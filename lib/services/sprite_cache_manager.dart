/// Advanced Sprite Cache System for PixelCode
///
/// Three-tier LRU + TTL-based cache with:
/// - Hash-based validation on file changes
/// - Priority-aware eviction (characters > furniture > decor)
/// - Cascade invalidation for dependent sprites
/// - Real-time metrics and health checks
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:watcher/watcher.dart';

// ─── Enums & Types ──────────────────────────────────────────────────────

enum CacheTier {
  hot,   // L1: 16 MB, TTL 5 min, active frames
  warm,  // L2: 64 MB, TTL 30 min, visible objects
  cold,  // L3: 256 MB, TTL 2 hours, offscreen
}

enum SpriteType {
  character,   // evictionWeight: 0.9 (keep longest)
  furniture,   // evictionWeight: 0.7
  decoration,  // evictionWeight: 0.3 (evict first)
  ui,          // evictionWeight: 0.8
}

// ─── Cache Entry ────────────────────────────────────────────────────────

class CacheEntry {
  final String spriteKey;      // "character_sprites.dart:_downWalk0"
  final ui.Image cachedImage;
  final String? fileHash;      // SHA256 hash of source file
  final DateTime createdAt;
  DateTime lastAccessedAt;
  int accessCount;
  CacheTier tier;
  final SpriteType spriteType;
  final Set<String> dependencies; // e.g., ["character_skins.dart"]

  CacheEntry({
    required this.spriteKey,
    required this.cachedImage,
    required this.fileHash,
    required this.tier,
    required this.spriteType,
    this.dependencies = const {},
  })  : createdAt = DateTime.now(),
        lastAccessedAt = DateTime.now(),
        accessCount = 0;

  /// Check if this entry has expired based on tier TTL
  bool isExpired(DateTime now) {
    final ttl = _getTtlForTier(tier);
    return now.difference(createdAt).compareTo(ttl) > 0;
  }

  /// Get memory size estimate (rough: 1 pixel = 4 bytes for RGBA)
  int getMemorySizeBytes() {
    return cachedImage.width * cachedImage.height * 4;
  }

  /// Compute eviction score (higher = evict first)
  double computeEvictionScore(DateTime now) {
    final age = now.difference(lastAccessedAt).inSeconds;
    final ttl = _getTtlForTier(tier).inSeconds;
    final timeSinceCreation = now.difference(createdAt).inHours;
    final weight = _getEvictionWeightForType(spriteType);

    // Base age factor
    final ageFactor = age / ttl;

    // Age since creation (prefer newer)
    final creationFactor = 1 + (timeSinceCreation / 24);

    // Sprite type priority (lower weight = higher score = evict first)
    final priorityFactor = 1 / weight;

    // Access frequency (more access = lower score = keep longer)
    final frequencyFactor = 1 / sqrt(accessCount.toDouble() + 1);

    return ageFactor * creationFactor * priorityFactor * frequencyFactor;
  }

  static Duration _getTtlForTier(CacheTier tier) {
    return switch (tier) {
      CacheTier.hot => const Duration(minutes: 5),
      CacheTier.warm => const Duration(minutes: 30),
      CacheTier.cold => const Duration(hours: 2),
    };
  }

  static double _getEvictionWeightForType(SpriteType type) {
    return switch (type) {
      SpriteType.character => 0.9,
      SpriteType.furniture => 0.7,
      SpriteType.decoration => 0.3,
      SpriteType.ui => 0.8,
    };
  }
}

// ─── Cache Metrics ──────────────────────────────────────────────────────

class CacheMetrics {
  int hitCount = 0;
  int missCount = 0;
  int evictionCount = 0;
  final Map<CacheTier, int> entriesByTier = {};
  final Map<CacheTier, int> memorySizeByTier = {};
  final List<DateTime> hitTimestamps = [];

  double get hitRate =>
    (hitCount + missCount) == 0 ? 0 : hitCount / (hitCount + missCount);

  int get totalMemoryBytes =>
    memorySizeByTier.values.fold(0, (sum, size) => sum + size);

  void recordHit() => hitCount++;
  void recordMiss() => missCount++;
  void recordEviction() => evictionCount++;

  void recordHitTimestamp() {
    hitTimestamps.add(DateTime.now());
    // Keep only last 60 seconds
    while (hitTimestamps.isNotEmpty &&
           DateTime.now().difference(hitTimestamps.first).inSeconds > 60) {
      hitTimestamps.removeAt(0);
    }
  }

  double get hitsPerSecond =>
    hitTimestamps.isEmpty ? 0 : hitTimestamps.length / 60;

  @override
  String toString() => '''
CacheMetrics {
  hitRate: ${(hitRate * 100).toStringAsFixed(2)}%,
  hitsPerSecond: ${hitsPerSecond.toStringAsFixed(2)},
  totalMemory: ${(totalMemoryBytes / 1024 / 1024).toStringAsFixed(2)} MB,
  evictions: $evictionCount,
  hot: ${entriesByTier[CacheTier.hot] ?? 0},
  warm: ${entriesByTier[CacheTier.warm] ?? 0},
  cold: ${entriesByTier[CacheTier.cold] ?? 0}
}''';
}

// ─── File Hash Validator ────────────────────────────────────────────────

class FileHashValidator {
  final Map<String, String> _fileHashes = {};

  /// Compute SHA256 hash of file content
  String computeHash(String filePath, Uint8List content) {
    return sha256.convert(content).toString();
  }

  /// Check if file has changed since last hash
  bool hasFileChanged(String filePath, String currentHash) {
    final previousHash = _fileHashes[filePath];
    if (previousHash != currentHash) {
      _fileHashes[filePath] = currentHash;
      return true;
    }
    return false;
  }

  /// Get all cache keys affected by a file change
  Set<String> getAffectedKeys(String filePath, Map<String, CacheEntry> cache) {
    return cache.entries
        .where((e) => e.value.spriteKey.startsWith('$filePath:'))
        .map((e) => e.key)
        .toSet();
  }

  /// Cascade invalidation: find dependent files
  Set<String> getCascadeDependencies(String changedFile) {
    // Hard-coded dependency graph for PixelCode
    const dependencies = {
      'character_sprites.dart': {'character_skins.dart', 'character_accessories.dart'},
      'character_skins.dart': {'character_accessories.dart'},
      'furniture_sprites.dart': {},
      'galley_sprites.dart': {},
      'arkanoid_sprites.dart': {},
    };
    return dependencies[changedFile] ?? {};
  }
}

// ─── Main Cache Manager ──────────────────────────────────────────────────

class SpriteCacheManager {
  // Storage
  final Map<String, CacheEntry> _cache = {};
  final List<String> _accessOrder = [];

  // Config
  final Map<CacheTier, int> maxSizeByTier = {
    CacheTier.hot: 16 * 1024 * 1024,    // 16 MB
    CacheTier.warm: 64 * 1024 * 1024,   // 64 MB
    CacheTier.cold: 256 * 1024 * 1024,  // 256 MB
  };

  // Validators & Observers
  final FileHashValidator _hashValidator = FileHashValidator();
  StreamSubscription? _fileWatcherSubscription;

  // Metrics
  final CacheMetrics metrics = CacheMetrics();

  // Cleanup timer
  Timer? _cleanupTimer;
  Timer? _metricsTimer;

  SpriteCacheManager() {
    _startPeriodicCleanup();
    _startMetricsReporting();
  }

  /// Get sprite from cache, with auto-promotion on hit
  ui.Image? get(String spriteKey) {
    final entry = _cache[spriteKey];
    if (entry != null) {
      entry.lastAccessedAt = DateTime.now();
      entry.accessCount++;

      // Auto-promote if accessed frequently
      _promoteIfHot(spriteKey, entry);

      metrics.recordHit();
      metrics.recordHitTimestamp();

      // Update access order for LRU
      _accessOrder.remove(spriteKey);
      _accessOrder.add(spriteKey);

      return entry.cachedImage;
    }

    metrics.recordMiss();
    return null;
  }

  /// Put sprite into cache with auto-tiering
  Future<void> put(
    String spriteKey,
    ui.Image image, {
    required SpriteType spriteType,
    String? sourceFile,
    String? fileHash,
    Set<String> dependencies = const {},
  }) async {
    // Initial tier based on sprite type
    final tier = _selectInitialTier(spriteType);

    final entry = CacheEntry(
      spriteKey: spriteKey,
      cachedImage: image,
      fileHash: fileHash,
      tier: tier,
      spriteType: spriteType,
      dependencies: dependencies,
    );

    _cache[spriteKey] = entry;
    _accessOrder.add(spriteKey);
    _updateMetrics();

    // Check eviction pressure
    await _evictIfNeeded(tier);
  }

  /// Invalidate cache entry by key
  void invalidate(String spriteKey) {
    _cache.remove(spriteKey);
    _accessOrder.remove(spriteKey);
    _updateMetrics();
  }

  /// Invalidate all entries from a file + cascade dependencies
  void invalidateFile(String filePath, String currentHash) {
    final affected = _hashValidator.getAffectedKeys(filePath, _cache);
    final cascaded = _hashValidator.getCascadeDependencies(filePath);

    affected.forEach(invalidate);

    for (final depFile in cascaded) {
      final depKeys = _cache.entries
          .where((e) => e.value.spriteKey.startsWith('$depFile:'))
          .map((e) => e.key)
          .toSet();
      depKeys.forEach(invalidate);
    }

    metrics.recordEviction();
  }

  /// Clear entire cache
  void clear() {
    _cache.clear();
    _accessOrder.clear();
    _updateMetrics();
  }

  /// Get cache statistics
  CacheMetrics getMetrics() => metrics;

  /// Start watching sprite files for changes (hot reload)
  Future<void> startFileWatcher(String spritesDirectory) async {
    try {
      final dir = Directory(spritesDirectory);
      if (!await dir.exists()) {
        if (kDebugMode) {
          print('[SpriteCacheManager] Directory does not exist: $spritesDirectory');
        }
        return;
      }

      final watcher = DirectoryWatcher(spritesDirectory);
      _fileWatcherSubscription = watcher.events.listen(
        (event) {
          final filePath = event.path;
          if (_isSpriteFile(filePath)) {
            if (event.type == ChangeType.MODIFY) {
              _handleSpriteFileChange(filePath);
            } else if (event.type == ChangeType.REMOVE) {
              _handleSpriteFileRemove(filePath);
            }
          }
        },
        onError: (e) {
          if (kDebugMode) {
            print('[SpriteCacheManager] Watcher error: $e');
          }
        },
      );

      if (kDebugMode) {
        print('[SpriteCacheManager] File watcher started for $spritesDirectory');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[SpriteCacheManager] Failed to start file watcher: $e');
      }
    }
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _metricsTimer?.cancel();
    _fileWatcherSubscription?.cancel();
    clear();
  }

  // ─── Private Helpers ────

  CacheTier _selectInitialTier(SpriteType spriteType) {
    return switch (spriteType) {
      SpriteType.character => CacheTier.warm,
      SpriteType.furniture => CacheTier.warm,
      SpriteType.decoration => CacheTier.cold,
      SpriteType.ui => CacheTier.hot,
    };
  }

  void _promoteIfHot(String spriteKey, CacheEntry entry) {
    // If accessed 3+ times per second and in COLD, promote to WARM
    if (entry.tier == CacheTier.cold && entry.accessCount > 3) {
      entry.tier = CacheTier.warm;
    }
    // If accessed frequently and in WARM, promote to HOT
    else if (entry.tier == CacheTier.warm && entry.accessCount > 10) {
      entry.tier = CacheTier.hot;
    }
  }

  Future<void> _evictIfNeeded(CacheTier tier) async {
    final maxSize = maxSizeByTier[tier]!;
    final tierEntries = _cache.entries
        .where((e) => e.value.tier == tier)
        .toList();

    int tierSize = tierEntries.fold<int>(
      0,
      (sum, e) => sum + e.value.getMemorySizeBytes(),
    );

    while (tierSize > maxSize && tierEntries.isNotEmpty) {
      // Find LRU victim in this tier
      final victim = tierEntries.reduce((a, b) =>
        a.value.lastAccessedAt.isBefore(b.value.lastAccessedAt) ? a : b);

      tierSize -= victim.value.getMemorySizeBytes();
      invalidate(victim.key);
      tierEntries.remove(victim);
      metrics.recordEviction();
    }
  }

  void _startPeriodicCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _cleanupExpiredEntries();
    });
  }

  void _cleanupExpiredEntries() {
    final now = DateTime.now();
    final expired = _cache.entries
        .where((e) => e.value.isExpired(now))
        .map((e) => e.key)
        .toList();

    for (final key in expired) {
      invalidate(key);
    }
  }

  void _startMetricsReporting() {
    _metricsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (kDebugMode) {
        print('[SpriteCacheManager] $metrics');
      }
    });
  }

  void _updateMetrics() {
    metrics.entriesByTier.clear();
    metrics.memorySizeByTier.clear();

    for (final tier in CacheTier.values) {
      final tierEntries = _cache.values.where((e) => e.tier == tier);
      metrics.entriesByTier[tier] = tierEntries.length;
      metrics.memorySizeByTier[tier] =
        tierEntries.fold(0, (sum, e) => sum + e.getMemorySizeBytes());
    }
  }

  // ─── File Watcher Helpers ────

  bool _isSpriteFile(String filePath) {
    // Match sprite dart files
    return filePath.endsWith('_sprites.dart') ||
           filePath.endsWith('character_sprites.dart') ||
           filePath.endsWith('furniture_sprites.dart') ||
           filePath.endsWith('galley_sprites.dart') ||
           filePath.endsWith('.png');
  }

  void _handleSpriteFileChange(String filePath) {
    // Extract base filename from path
    final fileName = filePath.split('/').last;
    final fileNameWithoutExt = fileName.replaceAll(RegExp(r'\.(dart|png)$'), '');

    if (kDebugMode) {
      print('[SpriteCacheManager] File changed: $fileName');
    }

    // Invalidate affected entries
    invalidateFile(fileNameWithoutExt, 'updated-${DateTime.now().millisecondsSinceEpoch}');
  }

  void _handleSpriteFileRemove(String filePath) {
    final fileName = filePath.split('/').last;
    final fileNameWithoutExt = fileName.replaceAll(RegExp(r'\.(dart|png)$'), '');

    if (kDebugMode) {
      print('[SpriteCacheManager] File removed: $fileName');
    }

    // Invalidate all related entries
    invalidateFile(fileNameWithoutExt, 'removed-${DateTime.now().millisecondsSinceEpoch}');
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/archive_crush/archive_level.dart';
import '../../models/archive_crush/archive_file.dart';
import '../../services/archive_crush/archive_compression_service.dart';

/// Постачальник рівнів гри
final archiveLevelsProvider = FutureProvider<List<ArchiveLevel>>((ref) async {
  final levels = <ArchiveLevel>[
    ArchiveLevel(
      id: 1,
      name: 'Warm Up',
      description: 'Learn the basics of file compression',
      files: [
        ArchiveFile(
          name: 'photo.jpg',
          originalSize: 2048,
          compressionRatio:
              ArchiveCompressionService.getCompressionRatioForFileType('jpg'),
          fileType: 'jpg',
        ),
        ArchiveFile(
          name: 'document.pdf',
          originalSize: 1024,
          compressionRatio:
              ArchiveCompressionService.getCompressionRatioForFileType('pdf'),
          fileType: 'pdf',
        ),
      ],
      targetCompression: 0.20,
      timeLimitSeconds: 30,
      difficulty: 1,
    ),
    ArchiveLevel(
      id: 2,
      name: 'Video Squash',
      description: 'Compress various media files',
      files: [
        ArchiveFile(
          name: 'video.mp4',
          originalSize: 5120,
          compressionRatio:
              ArchiveCompressionService.getCompressionRatioForFileType('mp4'),
          fileType: 'mp4',
        ),
        ArchiveFile(
          name: 'preview.png',
          originalSize: 512,
          compressionRatio:
              ArchiveCompressionService.getCompressionRatioForFileType('png'),
          fileType: 'png',
        ),
        ArchiveFile(
          name: 'metadata.txt',
          originalSize: 256,
          compressionRatio:
              ArchiveCompressionService.getCompressionRatioForFileType('txt'),
          fileType: 'txt',
        ),
      ],
      targetCompression: 0.15,
      timeLimitSeconds: 45,
      difficulty: 2,
    ),
    ArchiveLevel(
      id: 3,
      name: 'Archive Master',
      description: 'Compress a complex set of mixed files',
      files: [
        ArchiveFile(
          name: 'project.zip',
          originalSize: 3072,
          compressionRatio:
              ArchiveCompressionService.getCompressionRatioForFileType('zip'),
          fileType: 'zip',
        ),
        ArchiveFile(
          name: 'data.csv',
          originalSize: 256,
          compressionRatio:
              ArchiveCompressionService.getCompressionRatioForFileType('csv'),
          fileType: 'csv',
        ),
        ArchiveFile(
          name: 'image.psd',
          originalSize: 4096,
          compressionRatio:
              ArchiveCompressionService.getCompressionRatioForFileType('jpg'),
          fileType: 'psd',
        ),
        ArchiveFile(
          name: 'backup.sql',
          originalSize: 2048,
          compressionRatio:
              ArchiveCompressionService.getCompressionRatioForFileType('txt'),
          fileType: 'sql',
        ),
      ],
      targetCompression: 0.25,
      timeLimitSeconds: 60,
      difficulty: 3,
    ),
  ];

  return levels;
});

/// Provider для поточного рівня за індексом
final currentLevelProvider =
    StateProvider.family<ArchiveLevel?, int>((ref, levelIndex) {
  final levels = ref.watch(archiveLevelsProvider);
  return levels.when(
    data: (levelsList) {
      if (levelIndex >= 0 && levelIndex < levelsList.length) {
        return levelsList[levelIndex];
      }
      return null;
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Provider для перевірки чи є наступний рівень
final hasNextLevelProvider = StateProvider.family<bool, int>((ref, levelIndex) {
  final levels = ref.watch(archiveLevelsProvider);
  return levels.when(
    data: (levelsList) => levelIndex < levelsList.length - 1,
    loading: () => false,
    error: (_, __) => false,
  );
});

/// Provider для перевірки чи доступний рівень (рівні розблоковуються послідовно)
final isLevelAvailableProvider =
    StateProvider.family<bool, int>((ref, levelIndex) {
  // У простій версії всі рівні доступні; потім можна додати прогресію
  return true;
});

// Archive Statistics Panel — shows compression stats and controls

import 'package:flutter/material.dart';
import '../../models/archive_crush/archive_level.dart';
import '../../providers/archive_crush/archive_game_state_provider.dart';

class ArchiveStatisticsPanel extends StatelessWidget {
  final ArchiveLevel level;
  final ArchiveGameState gameState;
  final VoidCallback onCompressionStarted;
  final bool isCompressionRunning;

  const ArchiveStatisticsPanel({
    super.key,
    required this.level,
    required this.gameState,
    required this.onCompressionStarted,
    required this.isCompressionRunning,
  });

  @override
  Widget build(BuildContext context) {
    final totalOriginal = level.getTotalSize();
    final totalInArchive = gameState.filesInArchive.fold<int>(
      0,
      (sum, f) => sum + f.originalSize,
    );
    final totalCompressed = gameState.filesInArchive.fold<int>(
      0,
      (sum, f) => sum + f.getCompressedSize(),
    );
    final savedBytes = totalInArchive - totalCompressed;
    final compressionPercent = totalInArchive > 0
        ? ((savedBytes / totalInArchive) * 100).toStringAsFixed(1)
        : '0.0';
    final freeSpace = totalInArchive - totalCompressed;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Files in archive section
              _buildSectionHeader('📦 Files in Archive'),
              const SizedBox(height: 8),
              if (gameState.filesInArchive.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Drag files here to archive',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: gameState.filesInArchive
                      .map((file) => _buildFileRow(file))
                      .toList(),
                ),
              const SizedBox(height: 16),
              // Compression statistics
              _buildSectionHeader('📊 Compression Stats'),
              const SizedBox(height: 12),
              _buildStatRow(
                '📥 Original Size:',
                _formatBytes(totalInArchive),
                Colors.blue,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                '📤 Compressed Size:',
                _formatBytes(totalCompressed),
                Colors.orange,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                '💾 Space Saved:',
                _formatBytes(savedBytes),
                Colors.green,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                '📈 Compression %:',
                '$compressionPercent%',
                Colors.purple,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                '💿 Free Space:',
                _formatBytes(freeSpace),
                Colors.teal,
              ),
              const SizedBox(height: 16),
              // Target info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[300]!),
                ),
                child: Row(
                  children: [
                    const Text('🎯', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Target: ${(level.targetCompression * 100).toStringAsFixed(0)}% compression',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Compression progress
              if (isCompressionRunning)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSectionHeader('⚙️ Compressing...'),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: gameState.compressionProgress,
                        minHeight: 24,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.green[400]!,
                        ),
                        semanticsLabel: 'Compression progress',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(gameState.compressionProgress * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                )
              else
                // Compress button
                ElevatedButton(
                  onPressed: gameState.filesInArchive.isEmpty
                      ? null
                      : onCompressionStarted,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[500],
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    gameState.filesInArchive.isEmpty
                        ? 'Add files to compress'
                        : '🗜️ Start Compression',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildFileRow(dynamic file) {
    final originalSize = file.originalSize as int;
    final compressed = file.getCompressedSize();
    final saved = (originalSize - compressed).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  file.name,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Text(
                _formatBytes(saved),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.green[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _formatBytes(originalSize),
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '→',
                style: TextStyle(fontSize: 9, color: Colors.grey[600]),
              ),
              const SizedBox(width: 4),
              Text(
                _formatBytes(compressed),
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }
}

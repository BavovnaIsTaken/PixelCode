import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/archive_crush/archive_file.dart';
import '../../models/archive_crush/archive_level.dart';

/// Сервіс для керування ZIP-архівами та компресією файлів
class ArchiveCompressionService {
  static final ArchiveCompressionService _instance =
      ArchiveCompressionService._internal();

  factory ArchiveCompressionService() {
    return _instance;
  }

  ArchiveCompressionService._internal();

  /// Додає файли до архіву та розраховує компресію
  /// Реально не створює ZIP, а рахує метрики для анімації
  int calculateCompressedSize(List<ArchiveFile> files) {
    int totalSize = 0;
    for (final file in files) {
      final compressedSize = file.getCompressedSize();
      totalSize += compressedSize;
    }
    return totalSize;
  }

  /// Розраховує рівень компресії (0.0 - 1.0)
  double calculateCompressionRatio(
    List<ArchiveFile> files,
    double compressionProgress, // 0.0 - 1.0
  ) {
    if (files.isEmpty) return 0.0;

    int originalSize = files.fold(0, (sum, f) => sum + f.originalSize);
    if (originalSize == 0) return 0.0;

    // Середня компресія всіх файлів
    double totalCompressed = 0;
    for (final file in files) {
      final targetCompressed =
          file.originalSize * (1 - file.compressionRatio);
      totalCompressed +=
          targetCompressed * compressionProgress + file.originalSize;
    }

    final ratio = 1.0 - (totalCompressed / originalSize);
    return ratio.clamp(0.0, 1.0);
  }

  /// Реально創ює ZIP архів файлів в системній тимчасовій папці
  /// Повертає path до файлу .zip
  Future<String> createArchive(
    List<ArchiveFile> files,
    ArchiveLevel level,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final zipPath = '${tempDir.path}/archive_crush_level_${level.id}_$timestamp.zip';

      final encoder = ZipEncoder();
      final archive = Archive();

      // Додає фіктивні файли до архіву (вони не існують реально, це просто для демонстрації)
      for (final file in files) {
        final content = List<int>.filled(file.getCompressedSize(), 0);
        archive.addFile(ArchiveFile(file.name, content.length, content));
      }

      final bytes = encoder.encode(archive);
      if (bytes != null) {
        final zipFile = File(zipPath);
        await zipFile.writeAsBytes(bytes);
        return zipPath;
      }
      throw Exception('Failed to encode archive');
    } catch (e) {
      throw Exception('Failed to create archive: $e');
    }
  }

  /// Розпаковує ZIP архів в тимчасову папку
  /// Повертає список файлів що розпаковані
  Future<List<File>> extractArchive(String zipPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final extractPath =
          '${tempDir.path}/archive_crush_extract_${DateTime.now().millisecondsSinceEpoch}';

      final extractDir = Directory(extractPath);
      if (!extractDir.existsSync()) {
        extractDir.createSync(recursive: true);
      }

      final zipFile = File(zipPath);
      if (!zipFile.existsSync()) {
        throw Exception('ZIP file not found: $zipPath');
      }

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final extractedFiles = <File>[];
      for (final file in archive) {
        if (!file.isFile) continue;

        final filePath = '$extractPath/${file.name}';
        final fileToCreate = File(filePath);

        // Створює батьківські директорії якщо необхідно
        await fileToCreate.parent.create(recursive: true);

        final outFile = await fileToCreate.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
        extractedFiles.add(outFile);
      }

      return extractedFiles;
    } catch (e) {
      throw Exception('Failed to extract archive: $e');
    }
  }

  /// Видаляє архів та всі його розпаковані файли
  Future<void> cleanupArchive(String zipPath) async {
    try {
      final zipFile = File(zipPath);
      if (zipFile.existsSync()) {
        await zipFile.delete();
      }
    } catch (e) {
      print('Error cleaning up archive: $e');
    }
  }

  /// Розраховує розмір файлу з врахуванням компресії
  /// Симулює реальну компресію на основі типу файлу
  static double getCompressionRatioForFileType(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return 0.15; // зображення не стискуються добре (вже стиснені)
      case 'pdf':
        return 0.35;
      case 'txt':
      case 'csv':
      case 'json':
      case 'xml':
        return 0.75; // текстові файли стискуються добре
      case 'mp4':
      case 'avi':
      case 'mov':
        return 0.05; // відео не стискується (вже стиснене)
      case 'zip':
      case 'rar':
      case '7z':
        return 0.03; // архіви не стискуються
      case 'exe':
      case 'dll':
        return 0.45;
      default:
        return 0.5; // типова компресія
    }
  }
}

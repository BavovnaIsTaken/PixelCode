/// Всі асети для гри про архівацію
///
/// Містить піксельарт іконки, спрайти, кнопки, фони та анімації
///
/// ### Файлові іконки
/// - [FileIcon] — базова іконка файлу
/// - [AnimatedFileIcon] — анімована іконка з дебаунс ефектом
/// - [FileType] — enum для типів файлів (text, image, music, video)
///
/// ### Архівні контейнери
/// - [ArchivePainter] — статична іконка архіву з ZIP символом
/// - [AnimatedArchiveBox] — архівна коробка з анімацією відкриття/закриття молнії
///
/// ### UI Елементи
/// - [ArchiveGameButton] — піксельарт кнопка (Упакувати, Розпакувати, тощо)
/// - [CompressionProgressBar] — шкала прогресу компресії з процентами
/// - [StatisticsWidget] — блок статистики (кількість файлів, розмір, економія)
/// - [FileSizeIndicator] — мініатюрний індикатор розміру файлу
///
/// ### Анімації
/// - [FileToArchiveAnimation] — файл летить в архів
/// - [CompressionAnimation] — архів зменшується (анімація процесу)
/// - [ExtractionAnimation] — архів розривається, файли вилітають
/// - [ArrowToArchiveAnimation] — стрілки вказують на архів
/// - [RadialRaysAnimation] — промені енергії, що вилітають з архіву
/// - [FileAbsorptionAnimation] — файл зменшується та щезає
///
/// ### Звукові ефекти
/// - [ArchiveGameAudio] — синтез звукових ефектів (архівування, розпакування, успіх)
///   - `.playArchiveSound()` — шипіння + щоклики при архівуванні
///   - `.playExtractSound()` — вирівування + розривання при розпаковуванні
///   - `.playSuccessSound()` — дин/chime при успіху
///   - `.playErrorSound()` — гудіння при помилці
///   - `.playClickSound()` — клацання для кнопок
/// - [AudioPresets] — попередньо задані параметри
/// - Extensions: `.archiveQuick()`, `.extractQuick()`, `.successQuick()`

export 'file_icons.dart';
export 'folder_archive.dart';
export 'buttons.dart';
export 'level_backgrounds.dart';
export 'archive_animations.dart';
export 'audio_effects.dart';

// Колорова палітра гри
class ArchiveGameColors {
  // Яскраві, контрастні кольори для школярів
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color primaryOrange = Color(0xFFFF9800);
  static const Color primaryRed = Color(0xFFF44336);
  static const Color accentYellow = Color(0xFFFFEB3B);
  static const Color accentPink = Color(0xFFE91E63);
  static const Color accentPurple = Color(0xFF9C27B0);

  // Нейтральні
  static const Color darkText = Color(0xFF212121);
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color borderColor = Color(0xFF757575);

  // Фікс для ColorImport
  static const Color _placeholder = Color(0xFFFFFFFF);
}

// Re-export Color для зручності
export 'package:flutter/material.dart' show Color;

// Константи для анімацій
class ArchiveGameAnimations {
  static const Duration fastAnimation = Duration(milliseconds: 300);
  static const Duration standardAnimation = Duration(milliseconds: 500);
  static const Duration slowAnimation = Duration(milliseconds: 1000);
  static const Duration archiveAnimation = Duration(milliseconds: 1500);
  static const Duration extractAnimation = Duration(seconds: 2);
}

// Стилі тексту
class ArchiveGameTextStyles {
  static const TextStyle heading = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: ArchiveGameColors.darkText,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: Color(0xFFFFFFFF),
  );

  static const TextStyle bodyText = TextStyle(
    fontSize: 12,
    color: ArchiveGameColors.darkText,
  );
}

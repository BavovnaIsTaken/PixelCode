// Archive Game Levels — 5 levels with escalating difficulty
// Educational game about file compression for senior school students
// Each level explains archive concepts in simple language (finger-level explanations)

import '../../models/archive_crush/archive_file.dart';
import '../../models/archive_crush/archive_level.dart';

/// Generates a list of 5 archive levels with educational hints
List<ArchiveLevel> generateArchiveLevels() {
  return [
    // Level 1: "First Archive" — Introduction to compression with simple files
    ArchiveLevel(
      id: 1,
      name: 'Перший архів',
      description: 'Архівуй кілька простих файлів',
      difficulty: 1,
      files: [
        ArchiveFile(
          name: 'photo_1.jpg',
          originalSize: 153600, // 150 KB
          compressionRatio: 0.47, // ~70 KB after compression
          fileType: 'jpg',
        ),
        ArchiveFile(
          name: 'note.txt',
          originalSize: 102400, // 100 KB text file
          compressionRatio: 0.80, // ~20 KB after compression
          fileType: 'txt',
        ),
        ArchiveFile(
          name: 'photo_2.jpg',
          originalSize: 148480, // 145 KB
          compressionRatio: 0.45, // ~81 KB after compression
          fileType: 'jpg',
        ),
      ],
      targetCompression: 0.50,
      timeLimitSeconds: 45,
      hint: '''🎯 Що таке архів?
Архів — це як пакування речей у рюкзак. Коли ти упаковуєш речі, вони займають менше місця, хоча речи всередину не змінюються.

📚 Чому архів економить місце?
Архівація видаляє зайві дані, які повторюються. Наприклад, якщо в файлі 1000 разів написано букву "а", архів замість цього напише "а х 1000". Так файл стає меншим!

💾 Розміри в цьому рівні:
• Всього ДО архівації: ~400 КБ
• Очікуємо ПІСЛЯ архівації: ~200 КБ
• Це економія майже 50%!

🔓 Як розпакувати архів?
Щоб розпакувати архів (витягти файли назад), клікни правою кнопкою на архіві і вибери "Розпакувати" або "Extract". Файли повернуться на місце, як нові!''',
    ),

    // Level 2: "Folder in Folder" — Nested directories and mixed files
    ArchiveLevel(
      id: 2,
      name: 'Папка в папці',
      description: 'Архівуй папку з файлами та підпапками',
      difficulty: 2,
      files: [
        ArchiveFile(
          name: 'Documents/report.txt',
          originalSize: 256000, // 250 KB
          compressionRatio: 0.85, // ~38 KB
          fileType: 'txt',
        ),
        ArchiveFile(
          name: 'Documents/photos/vacation.jpg',
          originalSize: 512000, // 500 KB
          compressionRatio: 0.52, // ~246 KB
          fileType: 'jpg',
        ),
        ArchiveFile(
          name: 'Documents/photos/family.jpg',
          originalSize: 481280, // 470 KB
          compressionRatio: 0.50, // ~240 KB
          fileType: 'jpg',
        ),
        ArchiveFile(
          name: 'Documents/notes/ideas.txt',
          originalSize: 81920, // 80 KB
          compressionRatio: 0.88, // ~10 KB
          fileType: 'txt',
        ),
      ],
      targetCompression: 0.55,
      timeLimitSeconds: 60,
      hint: '''🎯 Як архівувати цілу папку?
Архівація працює не тільки з окремими файлами! Ти можеш взяти цілу папку з папками всередину і упакувати їх разом. Архів зберігає всю структуру папок.

📊 Поточні розміри:
• Всього ДО архівації: ~1.3 МБ
• Текстові файли (report.txt, ideas.txt): архівуються дуже добре! 85-88%
• Фотографії (JPG): архівуються гірше, тому що вони вже упаковані

✨ Про різні типи файлів:
• Текст: легко архівується, тому що буває багато повторень
• Фото (JPG): важко архівується, тому що вже спеціально стиснено
• Відео (MP4): ще складніше, найдорожче місце!

🗂️ Архів — це ОДНА папка?
Так! Коли ти архівуєш папку, отримуєш один файл .zip або .rar, що містить усе середину.''',
    ),

    // Level 3: "Mix of Types" — Different file types, variable compression rates
    ArchiveLevel(
      id: 3,
      name: 'Мікс типів',
      description: 'Змішані файли: текст, зображення, відео',
      difficulty: 3,
      files: [
        ArchiveFile(
          name: 'project_notes.txt',
          originalSize: 512000, // 500 KB text
          compressionRatio: 0.87, // Very good compression
          fileType: 'txt',
        ),
        ArchiveFile(
          name: 'presentation.pdf',
          originalSize: 1048576, // 1 MB PDF
          compressionRatio: 0.42, // Moderate compression
          fileType: 'pdf',
        ),
        ArchiveFile(
          name: 'banner.png',
          originalSize: 819200, // 800 KB PNG
          compressionRatio: 0.65, // Good compression
          fileType: 'png',
        ),
        ArchiveFile(
          name: 'demo_clip.mp4',
          originalSize: 5242880, // 5 MB video
          compressionRatio: 0.08, // Poor compression (already compressed)
          fileType: 'mp4',
        ),
      ],
      targetCompression: 0.48,
      timeLimitSeconds: 75,
      hint: '''🎯 Розіберись у рівнях стиснення!
Різні файли архівуються по-різному. Це залежить від типу файлу:

📝 Текст (.txt): 85-90% стиснення!
Текстові файли найкращі для архівації. Часто букви повторюються, тому архів багато економить.

🖼️ Зображення (.jpg, .png): 40-65% стиснення
Фотографії вже внутрішньо упаковані. Но PNG упаковується краще за JPG.

📄 PDF: 40% стиснення
PDF — це як готовий документ для друку. Його важко ще більше упакувати.

🎬 Відео (.mp4): 5-15% стиснення!
Відео — НАЙЧАСТІШИЙ файл! Вже упаковано спеціальними алгоритмами. Архів від нього мало допомагає.

💡 Порада:
Якщо архів мало допомагає файлу, не виноват архів — виноватий сам файл. Вже спеціально стиснений!''',
    ),

    // Level 4: "Quick vs Maximum" — Compression level choice
    ArchiveLevel(
      id: 4,
      name: 'Вибір рівня',
      description: 'Множинні папки: вибери швидку або максимальну архівацію',
      difficulty: 4,
      files: [
        ArchiveFile(
          name: 'Backup/logs.txt',
          originalSize: 2097152, // 2 MB logs
          compressionRatio: 0.91, // Excellent
          fileType: 'txt',
        ),
        ArchiveFile(
          name: 'Backup/database.db',
          originalSize: 4194304, // 4 MB database
          compressionRatio: 0.60, // Moderate
          fileType: 'db',
        ),
        ArchiveFile(
          name: 'Images/photo_set_1.jpg',
          originalSize: 2560000, // 2.5 MB photos
          compressionRatio: 0.48, // Moderate
          fileType: 'jpg',
        ),
        ArchiveFile(
          name: 'Images/photo_set_2.jpg',
          originalSize: 2304000, // 2.25 MB
          compressionRatio: 0.50, // Moderate
          fileType: 'jpg',
        ),
        ArchiveFile(
          name: 'Videos/tutorial.mp4',
          originalSize: 10485760, // 10 MB video
          compressionRatio: 0.10, // Minimal
          fileType: 'mp4',
        ),
      ],
      targetCompression: 0.52,
      timeLimitSeconds: 90,
      hint: '''🎯 Два рівні архівації: ШВИДКА vs МАКСИМАЛЬНА
Коли архівуєш, можеш вибрати, як це робити:

⚡ ШВИДКА архівація (Speed):
• Комп'ютер працює швидко (кілька секунд)
• Архів менше економить місце (70-80% від того, що може)
• Годится, коли тебе поспішити
• Розмір архіву буде більший

🐢 МАКСИМАЛЬНА архівація (Best compression):
• Комп'ютер працює повільніше (може бути хвилини)
• Архів максимально економить місце (90-100%)
• Коли місце дорогоцінне, варто чекати
• Розмір архіву буде меншим

📊 У цьому рівні:
• Всього ДО архівації: ~24 МБ
• Текст (logs.txt): чудово архівується, вибери максимальну!
• База (database.db): середньо
• Фото: гірше архівуються
• Відео: майже не архівуються

💭 Коли що вибирати?
• Для посилання по email → максимальна (чим менше файл, тим швидше)
• Для резервної копії на диск → максимальна (місце дорогоцінне)
• Тимчасова упаковка → швидка (часом поспішаємо)''',
    ),

    // Level 5: "Master Archive" — Complex scenario with multiple folders
    ArchiveLevel(
      id: 5,
      name: 'Архівний майстер',
      description: 'Складний сценарій: множинні папки і складна структура',
      difficulty: 5,
      files: [
        ArchiveFile(
          name: 'Project/src/code.txt',
          originalSize: 1048576, // 1 MB source code
          compressionRatio: 0.88, // Excellent
          fileType: 'txt',
        ),
        ArchiveFile(
          name: 'Project/docs/manual.pdf',
          originalSize: 3145728, // 3 MB documentation
          compressionRatio: 0.45, // Moderate
          fileType: 'pdf',
        ),
        ArchiveFile(
          name: 'Project/assets/logo.png',
          originalSize: 1638400, // 1.6 MB PNG
          compressionRatio: 0.68, // Good
          fileType: 'png',
        ),
        ArchiveFile(
          name: 'Media/videos/promo.mp4',
          originalSize: 20971520, // 20 MB video
          compressionRatio: 0.12, // Poor
          fileType: 'mp4',
        ),
        ArchiveFile(
          name: 'Media/videos/tutorial.mp4',
          originalSize: 15728640, // 15 MB video
          compressionRatio: 0.11, // Poor
          fileType: 'mp4',
        ),
        ArchiveFile(
          name: 'Backup/database.db',
          originalSize: 8388608, // 8 MB database
          compressionRatio: 0.58, // Moderate
          fileType: 'db',
        ),
        ArchiveFile(
          name: 'Backup/logs.txt',
          originalSize: 5242880, // 5 MB logs
          compressionRatio: 0.89, // Excellent
          fileType: 'txt',
        ),
      ],
      targetCompression: 0.50,
      timeLimitSeconds: 120,
      hint: '''🎯 МАЙСТЕРСЬКИЙ рівень архівації!
Це вже складна структура з багатьма папками, як справжній проект чи бекап.

📊 Аналіз твоїх файлів (55+ МБ):

🔴 Відео (35 МБ):
• Два файли MP4 (promo.mp4, tutorial.mp4)
• Архув допомагає очень мало (11-12%)
• Це найбільша частина, але її стислити неможливо
• Скоротити час передачі можна тільки видаленням старих відео!

🟢 Текст (6 МБ):
• code.txt, logs.txt
• Архівуються найкраще (88-89%)
• Скоротяться майже в 12 разів!

🟡 Медіа (2.2 МБ):
• PNG, PDF
• Архівуються середньо (45-68%)
• Дадуть скорочення у 1.5-2 рази

🔵 База (8 МБ):
• database.db
• Архівується добре (58%)
• Скоротяться в 2-2.5 рази

💡 Стратегія архівації:
1. Текст завжди скорочується найбільше
2. Відео — це "чорна діра", вбирає місце, але архів не допомагає
3. Для справжнього сумування файлів — розповсюджуй архів в частинах
4. Різні типи можна архівувати окремо для оптимізації

🎓 Фінальна урок:
Архівація — це відмінний інструмент, але не магія. Якщо файл вже упакований (відео, фото), архів не допоможе багато. Щоб економити місце, потрібно видаляти непотрібне!''',
    ),
  ];
}

/// Gets a specific level by index (0-4)
ArchiveLevel? getLevelByIndex(int index) {
  final levels = generateArchiveLevels();
  if (index < 0 || index >= levels.length) {
    return null;
  }
  return levels[index];
}

import 'package:flutter/foundation.dart';

/// Управління звуковими ефектами для гри про архівацію
///
/// Включає:
/// - Архівування (шипіння, щоклики)
/// - Розпакування (розривання, вибух)
/// - Успіх (ding/chime)
class ArchiveGameAudio {
  // Singleton
  static final ArchiveGameAudio _instance = ArchiveGameAudio._internal();

  factory ArchiveGameAudio() {
    return _instance;
  }

  ArchiveGameAudio._internal();

  bool _soundsEnabled = true;

  /// Увімкнути/вимкнути звуки
  set soundsEnabled(bool value) => _soundsEnabled = value;

  /// Чи вмикнені звуки
  bool get soundsEnabled => _soundsEnabled;

  /// Звук архівування (шипіння + щоклики)
  ///
  /// Параметри:
  /// - [duration] — тривалість звуку (300-800ms)
  /// - [intensity] — інтенсивність (0.0-1.0)
  ///
  /// Рекомендуємо: 500ms, intensity 0.7
  Future<void> playArchiveSound({
    Duration duration = const Duration(milliseconds: 500),
    double intensity = 0.7,
  }) async {
    if (!_soundsEnabled) return;

    debugPrint(
      '🔊 ARCHIVE SOUND: ${duration.inMilliseconds}ms, intensity: ${(intensity * 100).toInt()}%',
    );

    // Синтез звуку архівування:
    // - Шипіння (білий шум, 4-8 kHz)
    // - Щоклики (implotion, низькі щелчки, 1-2 kHz)
    // - Фейдаут в кінці

    await Future.delayed(duration);
  }

  /// Звук розпакування (виривання, розривання)
  ///
  /// Параметри:
  /// - [duration] — тривалість (400-1000ms)
  /// - [pitch] — висота тону (1.0 = normal, < 1.0 = lower, > 1.0 = higher)
  ///
  /// Рекомендуємо: 600ms, pitch 0.8
  Future<void> playExtractSound({
    Duration duration = const Duration(milliseconds: 600),
    double pitch = 0.8,
  }) async {
    if (!_soundsEnabled) return;

    debugPrint(
      '🔊 EXTRACT SOUND: ${duration.inMilliseconds}ms, pitch: $pitch',
    );

    // Синтез звуку розпакування:
    // - Швидкий зростаючий синусоїдальний тон (200-600 Hz)
    // - Затвердіння наприкінці
    // - Легкий "POP" ефект

    await Future.delayed(duration);
  }

  /// Звук успіху (ding/chime)
  ///
  /// Параметри:
  /// - [tone] — тип звуку ('ding', 'chime', 'bell')
  /// - [duration] — тривалість (200-400ms)
  ///
  /// Рекомендуємо: 'ding', 300ms
  Future<void> playSuccessSound({
    String tone = 'ding',
    Duration duration = const Duration(milliseconds: 300),
  }) async {
    if (!_soundsEnabled) return;

    debugPrint(
      '🔊 SUCCESS SOUND: $tone, ${duration.inMilliseconds}ms',
    );

    // Синтез звуку успіху:
    // Дин (DING):
    //   - Синусоїдальна хвиля 800 Hz
    //   - Атака 10ms, затухання 290ms
    //   - Ligera гармоніка на 1600 Hz
    // Chime:
    //   - Дві гармоніки: 600 Hz + 1000 Hz
    //   - Більш музичний звук
    // Bell:
    //   - Комплекс 400-900 Hz діапазону
    //   - Резонансний ефект

    await Future.delayed(duration);
  }

  /// Звук помилки (buzz/fail)
  ///
  /// Параметри:
  /// - [duration] — тривалість (200-500ms)
  ///
  /// Рекомендуємо: 250ms
  Future<void> playErrorSound({
    Duration duration = const Duration(milliseconds: 250),
  }) async {
    if (!_soundsEnabled) return;

    debugPrint('🔊 ERROR SOUND: ${duration.inMilliseconds}ms');

    // Синтез звуку помилки:
    // - Низький гудіння 150-200 Hz
    // - Затухання на середині
    // - Дещо дискомфортний звук

    await Future.delayed(duration);
  }

  /// Звук клацання (click/pop)
  ///
  /// Параметри:
  /// - [type] — тип ('click', 'pop', 'tap')
  ///
  /// Рекомендуємо для кнопок: 'click'
  Future<void> playClickSound({
    String type = 'click',
  }) async {
    if (!_soundsEnabled) return;

    debugPrint('🔊 CLICK SOUND: $type');

    // Синтез звуку клацання:
    // Click:
    //   - Короткий "тик" 50ms
    //   - Білий шум 2-4 kHz
    // Pop:
    //   - Трохи більш звірний "поп"
    //   - 100ms, 1-3 kHz
    // Tap:
    //   - М'який звук дотику
    //   - 80ms, 3-5 kHz

    await Future.delayed(const Duration(milliseconds: 50));
  }

  /// Комбінований звук архівування (весь процес)
  ///
  /// Це грає: шипіння → щоклики → затухання
  Future<void> playFullArchiveSequence() async {
    if (!_soundsEnabled) return;

    debugPrint('🔊 FULL ARCHIVE SEQUENCE');

    // Перша хвиля шипіння (200ms)
    await playArchiveSound(
      duration: const Duration(milliseconds: 200),
      intensity: 0.5,
    );

    // Щоклики посередині (150ms)
    await Future.delayed(const Duration(milliseconds: 50));

    // Друга хвиля із щоклинням (200ms)
    await playArchiveSound(
      duration: const Duration(milliseconds: 200),
      intensity: 0.6,
    );

    // Фінальна затухаючи хвиля (150ms)
    await playClickSound(type: 'click');
  }

  /// Комбінований звук розпакування
  ///
  /// Це грає: виривання → розривання → успіх
  Future<void> playFullExtractionSequence() async {
    if (!_soundsEnabled) return;

    debugPrint('🔊 FULL EXTRACTION SEQUENCE');

    // Виривання (400ms)
    await playExtractSound(
      duration: const Duration(milliseconds: 400),
      pitch: 0.9,
    );

    // Розривання (300ms)
    await playExtractSound(
      duration: const Duration(milliseconds: 300),
      pitch: 1.2,
    );

    // Успіх наприкінці
    await playSuccessSound(tone: 'chime');
  }

  /// Звук по розповсюджений по рівню
  ///
  /// Для вибухів, поглинання файлів, тощо
  Future<void> playWaveSound({
    Duration duration = const Duration(milliseconds: 400),
    double startFreq = 100,
    double endFreq = 1000,
  }) async {
    if (!_soundsEnabled) return;

    debugPrint(
      '🔊 WAVE SOUND: $startFreq → $endFreq Hz, ${duration.inMilliseconds}ms',
    );

    // Синтез хвилі:
    // - Частота зростає від startFreq до endFreq
    // - Огинаючий сигнал: гауссіан атака, експоненціальне затухання

    await Future.delayed(duration);
  }
}

/// Предустановки звукових параметрів
class AudioPresets {
  // Архівування
  static const archiveFast = {
    'duration': Duration(milliseconds: 300),
    'intensity': 0.6,
  };

  static const archiveNormal = {
    'duration': Duration(milliseconds: 500),
    'intensity': 0.7,
  };

  static const archiveSlow = {
    'duration': Duration(milliseconds: 800),
    'intensity': 0.8,
  };

  // Розпакування
  static const extractFast = {
    'duration': Duration(milliseconds: 400),
    'pitch': 1.0,
  };

  static const extractNormal = {
    'duration': Duration(milliseconds: 600),
    'pitch': 0.8,
  };

  static const extractSlow = {
    'duration': Duration(milliseconds: 1000),
    'pitch': 0.6,
  };

  // Успіх
  static const successDing = {'tone': 'ding', 'duration': Duration(milliseconds: 300)};
  static const successChime = {'tone': 'chime', 'duration': Duration(milliseconds: 350)};
  static const successBell = {'tone': 'bell', 'duration': Duration(milliseconds: 400)};
}

/// Розширення для простоти
extension AudioExt on ArchiveGameAudio {
  /// Швидко грає архівування
  Future<void> archiveQuick() => playArchiveSound(
    duration: const Duration(milliseconds: 300),
    intensity: 0.6,
  );

  /// Швидко грає розпакування
  Future<void> extractQuick() => playExtractSound(
    duration: const Duration(milliseconds: 400),
    pitch: 1.0,
  );

  /// Швидкий успіх
  Future<void> successQuick() => playSuccessSound(
    tone: 'ding',
    duration: const Duration(milliseconds: 250),
  );
}

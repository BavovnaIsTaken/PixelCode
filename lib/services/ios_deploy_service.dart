import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Сервіс для побудови та встановлення iOS білку на пристрої через мережу.
class IOSDeployService {
  static const _flutterCmd = 'flutter';
  static const _iosDeployCmd = 'ios-deploy';

  /// Отримує список доступних пристроїв iOS в мережі.
  /// Повертає список кортежів (ім'я пристрою, IP-адреса).
  Future<List<(String name, String ip)>> discoverDevices() async {
    try {
      // Спробуємо використати arp для пошуку iOS пристроїв
      // Шукаємо пристрої від Apple за MAC адресою
      final result = await Process.run(
        'arp',
        ['-a'],
      ).timeout(
        const Duration(seconds: 5),
      );

      if (result.exitCode == 0) {
        final devices = <(String, String)>[];
        final lines = result.stdout.toString().split('\n');

        for (final line in lines) {
          // Шукаємо Apple пристрої за MAC адресою (apple, iphone, ipad)
          if (line.toLowerCase().contains('apple') ||
              line.toLowerCase().contains('iphone') ||
              line.toLowerCase().contains('ipad')) {
            // Парсимо IP адресу з рядка
            final ipMatch = RegExp(r'\(([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\)');
            final match = ipMatch.firstMatch(line);

            if (match != null) {
              final ip = match.group(1)!;
              final name = line.split(' ').first;
              devices.add((name, ip));
            }
          }
        }
        return devices;
      }
    } catch (e) {
      // arp може не бути доступна на всіх системах
    }

    // Спробуємо ping на типові IP адреси в локальній мережі як альтернатива
    return _scanLocalNetwork();
  }

  /// Сканує локальну мережу для пошуку живих хостів
  Future<List<(String name, String ip)>> _scanLocalNetwork() async {
    final devices = <(String, String)>[];

    try {
      // Отримуємо локальний IP
      final hostname = await InternetAddress.lookup(InternetAddress.loopbackIPv4.host);
      if (hostname.isEmpty) return devices;

      // Отримуємо мережу з localhost
      final localIp = await _getLocalIP();
      if (localIp == null) return devices;

      // Отримуємо перші три октети для сканування
      final parts = localIp.split('.');
      if (parts.length != 4) return devices;

      final network = '${parts[0]}.${parts[1]}.${parts[2]}';

      // Скануємо 254 адреси в мережі (це може бути повільно)
      // Обмежимо до 20 спроб для швидкості
      final futures = <Future<bool>>[];
      for (int i = 1; i <= 20; i++) {
        final ip = '$network.$i';
        if (ip != localIp) {
          futures.add(_pingHost(ip));
        }
      }

      final results = await Future.wait(futures, eagerError: false);
      for (int i = 0; i < results.length; i++) {
        if (results[i]) {
          devices.add(('Device $i', '$network.${i + 1}'));
        }
      }
    } catch (e) {
      // Ігноруємо помилки при сканування
    }

    return devices;
  }

  /// Отримує локальну IP адресу
  Future<String?> _getLocalIP() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('127.')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      // Ігноруємо помилки
    }
    return null;
  }

  /// Перевіряє, чи доступна хост адреса
  Future<bool> _pingHost(String ip) async {
    try {
      final result = await InternetAddress.lookup(ip).timeout(
        const Duration(milliseconds: 500),
      );
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Будує iOS білк для мережевого розгортання.
  Future<String?> buildIOSApp({
    required void Function(String) onProgress,
    required void Function(String) onError,
  }) async {
    try {
      onProgress('Підготовка до побудови iOS білку...');
      onProgress('Команда: flutter build ios --release');

      // Запускаємо flutter build ios
      final process = await Process.start(
        _flutterCmd,
        ['build', 'ios', '--release'],
      );

      // Читаємо вивід в режимі реального часу
      final stdoutStream = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final stderrStream = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      unawaited(stdoutStream.forEach((line) {
        if (line.trim().isNotEmpty) {
          onProgress(line.trim());
        }
      }));

      unawaited(stderrStream.forEach((line) {
        if (line.trim().isNotEmpty) {
          onError(line.trim());
        }
      }));

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        onError('Помилка при побудові білку. Код виходу: $exitCode');
        return null;
      }

      onProgress('iOS білк успішно побудований!');

      // Повертаємо шлях до білку
      final buildDir = Directory(
        '${Directory.current.path}/build/ios/iphoneos/Runner.app',
      );

      if (await buildDir.exists()) {
        onProgress('Шлях до білку: ${buildDir.path}');
        return buildDir.path;
      }

      // Спробуємо альтернативну директорію
      final altBuildDir = Directory(
        '${Directory.current.path}/build/ios/Release-iphoneos/Runner.app',
      );

      if (await altBuildDir.exists()) {
        onProgress('Шлях до білку: ${altBuildDir.path}');
        return altBuildDir.path;
      }

      onError('Директорія білку не знайдена');
      return null;
    } catch (e) {
      onError('Помилка при побудові: $e');
      return null;
    }
  }

  /// Встановлює білк на iOS пристрій через мережу.
  /// Потребує ios-deploy для бути встановленою: brew install ios-deploy
  Future<bool> deployToDevice({
    required String ipAddress,
    required String appPath,
    required void Function(String) onProgress,
    required void Function(String) onError,
  }) async {
    try {
      // Перевіряємо, чи існує білк
      final appFile = File(appPath);
      if (!await appFile.exists()) {
        // Спробуємо знайти його як директорію
        final appDir = Directory(appPath);
        if (!await appDir.exists()) {
          onError('Білк не знайдено за шляхом: $appPath');
          return false;
        }
      }

      onProgress('Підключення до пристрою з IP: $ipAddress...');
      onProgress('Команда: ios-deploy --bundle=$appPath --id=$ipAddress');

      // ios-deploy дозволяє встановити білк через мережу
      final process = await Process.start(
        _iosDeployCmd,
        [
          '--bundle=$appPath',
          '--id=$ipAddress',
          '--verbose',
          '--justlaunch',
        ],
      );

      // Читаємо вивід
      final stdoutStream = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final stderrStream = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      unawaited(stdoutStream.forEach((line) {
        if (line.trim().isNotEmpty) {
          onProgress(line.trim());
        }
      }));

      unawaited(stderrStream.forEach((line) {
        if (line.trim().isNotEmpty) {
          onError(line.trim());
        }
      }));

      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        onProgress('Додаток успішно встановлено і запущено на пристрої!');
        return true;
      } else {
        onError('Помилка при встановленні. Код виходу: $exitCode');
        return false;
      }
    } catch (e) {
      onError('Помилка при встановленні: $e');
      return false;
    }
  }

  /// Запускає повний процес: побудова + встановлення.
  Future<bool> buildAndDeploy({
    required String ipAddress,
    required void Function(String) onProgress,
    required void Function(String) onError,
  }) async {
    // Крок 1: Побудова
    final appPath = await buildIOSApp(
      onProgress: onProgress,
      onError: onError,
    );

    if (appPath == null) {
      onError('Побудова не вдалася. Перевірте логи вище.');
      return false;
    }

    onProgress('');
    onProgress('===============================================');
    onProgress('Білк готовий. Розпочинаємо встановлення...');
    onProgress('===============================================');
    onProgress('');

    // Крок 2: Встановлення
    return deployToDevice(
      ipAddress: ipAddress,
      appPath: appPath,
      onProgress: onProgress,
      onError: onError,
    );
  }

  /// Перевіряє, чи встановлено необхідні інструменти.
  Future<(bool hasIOSDeploy, bool hasFlutter)> checkDependencies() async {
    bool hasIOSDeploy = false;
    bool hasFlutter = false;

    try {
      // Перевіримо ios-deploy
      final result = await Process.run(_iosDeployCmd, ['--version'])
          .timeout(const Duration(seconds: 5));
      hasIOSDeploy = result.exitCode == 0;
    } catch (e) {
      hasIOSDeploy = false;
    }

    try {
      // Перевіримо flutter
      final flutterResult = await Process.run(_flutterCmd, ['--version'])
          .timeout(const Duration(seconds: 5));
      hasFlutter = flutterResult.exitCode == 0;
    } catch (e) {
      hasFlutter = false;
    }

    return (hasIOSDeploy, hasFlutter);
  }
}

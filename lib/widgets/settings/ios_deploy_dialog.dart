library;

import 'package:flutter/material.dart';

import '../../services/ios_deploy_service.dart';

/// Діалог для встановлення iOS білку на локальне пристрій через мережу.
Future<void> showIOSDeployDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _IOSDeployDialog(),
  );
}

class _IOSDeployDialog extends StatefulWidget {
  const _IOSDeployDialog();

  @override
  State<_IOSDeployDialog> createState() => _IOSDeployDialogState();
}

class _IOSDeployDialogState extends State<_IOSDeployDialog> {
  late final _service = IOSDeployService();
  final _ipController = TextEditingController();
  final _logsBuffer = <String>[];

  bool _isLoading = false;
  bool _isDeploying = false;
  bool _success = false;
  String? _lastError;
  List<(String name, String ip)> _discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    _checkDependencies();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _checkDependencies() async {
    setState(() => _isLoading = true);
    final (hasIOSDeploy, hasFlutter) = await _service.checkDependencies();

    if (!hasIOSDeploy) {
      _addLog('ПОМИЛКА: ios-deploy не встановлено!');
      _addLog('Встановіть ios-deploy: brew install ios-deploy');
      setState(() => _lastError = 'ios-deploy не встановлено');
    } else if (!hasFlutter) {
      _addLog('ПОМИЛКА: flutter не встановлено!');
      _addLog('Перевірте встановлення Flutter');
      setState(() => _lastError = 'flutter не встановлено');
    } else {
      _addLog('Інструменти готові до роботи');
      _addLog('- Flutter: OK');
      _addLog('- ios-deploy: OK');
      _addLog('');
      _discoverDevices();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _discoverDevices() async {
    _addLog('Пошук пристроїв в мережі...');
    setState(() => _isLoading = true);

    try {
      final devices = await _service.discoverDevices();
      setState(() => _discoveredDevices = devices);
      if (devices.isEmpty) {
        _addLog('Пристрої не знайдені. Введіть IP адресу вручну.');
      } else {
        _addLog('Знайдено ${devices.length} пристрої(їв)');
        for (final (name, ip) in devices) {
          _addLog('  - $name (IP: $ip)');
        }
      }
    } catch (e) {
      _addLog('ПОМИЛКА при пошуку: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _startDeploy() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      _addLog('ПОМИЛКА: Введіть IP адресу пристрою');
      setState(() => _lastError = 'IP адреса не введена');
      return;
    }

    _logsBuffer.clear();
    setState(() {
      _isDeploying = true;
      _success = false;
      _lastError = null;
    });

    _addLog('Запуск процесу побудови та встановлення...');
    _addLog('IP пристрою: $ip');
    _addLog('');

    final result = await _service.buildAndDeploy(
      ipAddress: ip,
      onProgress: _addLog,
      onError: (msg) {
        _addLog('[ПОМИЛКА] $msg');
      },
    );

    setState(() {
      _isDeploying = false;
      _success = result;
      if (!result) {
        _lastError = 'Помилка при встановленні додатку';
      }
    });
  }

  void _addLog(String message) {
    setState(() {
      _logsBuffer.add(message);
      if (_logsBuffer.length > 1000) {
        _logsBuffer.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 800),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_iphone,
                    color: Color(0xFF00C0D1),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Розгортання iOS на локальний пристрій',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(
              color: Color(0xFF2A2A30),
              height: 1,
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Input section
                    if (!_isDeploying) ...[
                      Text(
                        'IP-адреса пристрою',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ipController,
                        enabled: !_isDeploying,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'наприклад: 192.168.1.100',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0E0E11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF00C0D1),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          prefixIcon: const Icon(
                            Icons.router,
                            color: Color(0xFF00C0D1),
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Discovered devices (if any)
                    if (_discoveredDevices.isNotEmpty && !_isDeploying) ...[
                      Text(
                        'Знайдені пристрої в мережі',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          children: [
                            for (int i = 0;
                                i < _discoveredDevices.length;
                                i++) ...[
                              InkWell(
                                onTap: _discoveredDevices[i].$2 != 'unknown'
                                    ? () => _ipController.text =
                                        _discoveredDevices[i].$2
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.devices,
                                        color: const Color(0xFF00C0D1),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _discoveredDevices[i].$1,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (_discoveredDevices[i].$2 !=
                                                'unknown')
                                              Text(
                                                _discoveredDevices[i].$2,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.35),
                                                  fontSize: 11,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (i < _discoveredDevices.length - 1)
                                Divider(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  height: 1,
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Logs section
                    Text(
                      'Лог операцій',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 300,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E0E11),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final log in _logsBuffer)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  log,
                                  style: TextStyle(
                                    color: log.contains('[ПОМИЛКА]')
                                        ? const Color(0xFFFF6B6B)
                                        : log.isEmpty
                                            ? Colors.transparent
                                            : Colors.white.withValues(
                                                alpha: 0.6),
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            if (_logsBuffer.isEmpty)
                              Text(
                                'Тут з\'являться повідомлення про процес...',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Error message
                    if (_lastError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFEF4444),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _lastError!,
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Success message
                    if (_success) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF4ADE80).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              color: Color(0xFF4ADE80),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Встановлення завершено успішно!',
                                style: TextStyle(
                                  color: Color(0xFF4ADE80),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!_isDeploying && !_success)
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _discoverDevices,
                      icon: Icon(
                        Icons.refresh,
                        size: 16,
                        color: _isLoading
                            ? Colors.white.withValues(alpha: 0.2)
                            : const Color(0xFF00C0D1),
                      ),
                      label: Text(
                        'Оновити',
                        style: TextStyle(
                          color: _isLoading
                              ? Colors.white.withValues(alpha: 0.2)
                              : const Color(0xFF00C0D1),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _isLoading
                              ? Colors.white.withValues(alpha: 0.1)
                              : const Color(0xFF00C0D1).withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _isDeploying ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Закрити',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed:
                        _isDeploying || _ipController.text.trim().isEmpty
                            ? null
                            : _startDeploy,
                    icon: _isDeploying
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                Colors.black.withValues(alpha: 0.7),
                              ),
                            ),
                          )
                        : const Icon(Icons.phone_iphone, size: 16),
                    label: Text(_isDeploying ? 'Розгортання...' : 'Розгорнути'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _isDeploying ||
                              _ipController.text.trim().isEmpty
                          ? const Color(0xFF00C0D1).withValues(alpha: 0.3)
                          : const Color(0xFF00C0D1),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

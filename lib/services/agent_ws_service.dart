/// WebSocket client that connects to the PixelCode Node.js server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/agent_message.dart';

class AgentWsService {
  static const _defaultUrl = 'ws://localhost:9720';

  WebSocket? _ws;
  final _messageController = StreamController<ServerMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  bool _isConnected = false;
  Timer? _reconnectTimer;

  Stream<ServerMessage> get messages => _messageController.stream;
  Stream<bool> get connectionStatus => _connectionController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect({String url = _defaultUrl}) async {
    try {
      _ws = await WebSocket.connect(url);
      _isConnected = true;
      _connectionController.add(true);
      _reconnectTimer?.cancel();

      _ws!.listen(
        (data) {
          try {
            final msg = ServerMessage.fromJson(data as String);
            _messageController.add(msg);
          } catch (e) {
            _messageController.add(ErrorMessage(message: 'Parse error: $e'));
          }
        },
        onDone: () {
          _isConnected = false;
          _connectionController.add(false);
          _scheduleReconnect(url);
        },
        onError: (e) {
          _isConnected = false;
          _connectionController.add(false);
          _scheduleReconnect(url);
        },
      );
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      _scheduleReconnect(url);
    }
  }

  void sendMessage(String content) {
    _send({'type': 'send_message', 'content': content});
  }

  void interrupt() {
    _send({'type': 'interrupt'});
  }

  void getStatus() {
    _send({'type': 'get_status'});
  }

  void _send(Map<String, dynamic> msg) {
    if (_ws != null && _isConnected) {
      _ws!.add(jsonEncode(msg));
    }
  }

  void _scheduleReconnect(String url) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () => connect(url: url));
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await _ws?.close();
    await _messageController.close();
    await _connectionController.close();
  }
}

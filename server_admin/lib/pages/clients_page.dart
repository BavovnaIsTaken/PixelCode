import 'package:flutter/material.dart';
import '../admin_client.dart';
import '../theme.dart';

class ClientsPage extends StatelessWidget {
  const ClientsPage({
    super.key,
    required this.clients,
    required this.serverRunning,
  });

  final List<ConnectedClientInfo> clients;
  final bool serverRunning;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PixelCard(
          title: 'Connected devices  (${clients.length})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!serverRunning)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Server is offline.',
                    style: TextStyle(color: PixelPalette.textMed),
                  ),
                )
              else if (clients.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'No devices connected.',
                    style: TextStyle(color: PixelPalette.textMed),
                  ),
                )
              else
                for (var i = 0; i < clients.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _ClientRow(client: clients[i]),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client});

  final ConnectedClientInfo client;

  IconData get _icon => switch (client.platform) {
        'macos' || 'linux' || 'windows' => Icons.desktop_mac_outlined,
        'ios'     => Icons.phone_iphone,
        'android' => Icons.phone_android,
        'web'     => Icons.language,
        _         => Icons.devices_other,
      };

  String get _displayName {
    if (client.deviceName.isNotEmpty) return client.deviceName;
    return switch (client.platform) {
      'ios'     => 'iPhone',
      'android' => 'Android',
      'macos'   => 'Mac',
      'linux'   => 'Linux',
      'windows' => 'Windows',
      'web'     => 'Web',
      _         => 'Device',
    };
  }

  String get _durationLabel {
    final diff = DateTime.now().difference(client.connectedAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PixelPalette.surfaceDim,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PixelPalette.border),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 16, color: PixelPalette.textMed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: PixelPalette.textHigh),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: client.isLocal
                              ? PixelPalette.success
                              : PixelPalette.accent,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        client.isLocal ? 'LOCAL' : 'REMOTE',
                        style: pixelFont(
                          size: 7,
                          color: client.isLocal
                              ? PixelPalette.success
                              : PixelPalette.accent,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${client.platform} · ${client.clientId.substring(0, client.clientId.length < 8 ? client.clientId.length : 8)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'Menlo',
                    color: PixelPalette.textLow,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _durationLabel,
            style: const TextStyle(
                fontSize: 11, color: PixelPalette.textMed),
          ),
        ],
      ),
    );
  }
}

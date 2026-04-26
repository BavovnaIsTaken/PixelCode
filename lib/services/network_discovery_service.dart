/// Bonjour-based discovery of PixelCode servers on the local network.
///
/// Uses the `bonsoir` package, which wraps Apple's NetService/NWBrowser on
/// iOS/macOS and Android's NsdManager — so iOS's Local Network permission
/// (see NSBonjourServices in Info.plist) applies correctly. Raw multicast
/// would otherwise require the `com.apple.developer.networking.multicast`
/// entitlement, which Apple grants only on request.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

/// Server-published discovery metadata. The server returns this from
/// `GET /metadata.json` so a LAN-discovered client can learn its public
/// Tailscale Funnel URL and create a session profile that works off-LAN too.
class ServerMetadata {
  final String hostname;
  final List<String> localIps;
  final int port;
  final String? tunnelUrl;

  const ServerMetadata({
    required this.hostname,
    required this.localIps,
    required this.port,
    this.tunnelUrl,
  });

  factory ServerMetadata.fromJson(Map<String, dynamic> json) => ServerMetadata(
        hostname: json['hostname'] as String? ?? '',
        localIps: ((json['localIps'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        port: json['port'] as int? ?? 9720,
        tunnelUrl: (json['tunnelUrl'] as String?)?.trim().isEmpty == true
            ? null
            : json['tunnelUrl'] as String?,
      );
}

/// Fetch `/metadata.json` from a discovered LAN server. Short timeout — this
/// is a best-effort lookup; callers fall back to the plain LAN host on null.
Future<ServerMetadata?> fetchServerMetadata({
  required String host,
  required int port,
  Duration timeout = const Duration(milliseconds: 1500),
  void Function(String)? onLog,
}) async {
  void log(String msg) {
    debugPrint('[metadata] $msg');
    onLog?.call('[metadata] $msg');
  }

  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final uri = Uri.parse('http://$host:$port/metadata.json');
    log('GET $uri');
    final req = await client.getUrl(uri).timeout(timeout);
    final resp = await req.close().timeout(timeout);
    if (resp.statusCode != 200) {
      log('non-200: ${resp.statusCode}');
      return null;
    }
    final body = await resp.transform(utf8.decoder).join().timeout(timeout);
    final json = jsonDecode(body) as Map<String, dynamic>;
    final meta = ServerMetadata.fromJson(json);
    log('tunnelUrl=${meta.tunnelUrl ?? "(none)"}');
    return meta;
  } catch (e) {
    log('failed: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}

class DiscoveredServer {
  final String name;
  final String host;
  final int port;

  const DiscoveredServer({
    required this.name,
    required this.host,
    required this.port,
  });

  @override
  String toString() => '$name ($host:$port)';

  @override
  bool operator ==(Object other) =>
      other is DiscoveredServer && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Scans the local network for PixelCode servers advertising `_pixelcode._tcp`.
/// Yields each server as it is resolved; closes after [timeout].
Stream<DiscoveredServer> discoverServers({
  Duration timeout = const Duration(seconds: 10),
  void Function(String)? onLog,
}) async* {
  void log(String msg) {
    debugPrint('[mDNS] $msg');
    onLog?.call('[mDNS] $msg');
  }

  log('Starting discovery for _pixelcode._tcp (timeout: ${timeout.inSeconds}s)');
  final discovery = BonsoirDiscovery(type: '_pixelcode._tcp');
  await discovery.ready;
  await discovery.start();
  log('Discovery started');

  final controller = StreamController<DiscoveredServer>();
  final seen = <String>{};

  final sub = discovery.eventStream!.listen((event) {
    final host = event.service is ResolvedBonsoirService
        ? (event.service as ResolvedBonsoirService).host
        : "?";
    log('event: ${event.type} service=${event.service?.name} host=$host');
    final service = event.service;
    if (service == null) return;

    if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
      service.resolve(discovery.serviceResolver);
    } else if (event.type ==
        BonsoirDiscoveryEventType.discoveryServiceResolved) {
      if (service is! ResolvedBonsoirService) return;
      // Bonsoir returns an absolute DNS name with a trailing dot (e.g.
      // "host.local.") which iOS mDNS can't resolve — strip it.
      final host = service.host?.replaceAll(RegExp(r'\.+$'), '');
      if (host == null || host.isEmpty) return;
      final key = '$host:${service.port}';
      if (seen.add(key)) {
        log('→ emitted: ${service.name} @ $host:${service.port}');
        controller.add(DiscoveredServer(
          name: service.name,
          host: host,
          port: service.port,
        ));
      }
    }
  });

  final timer = Timer(timeout, () {
    if (!controller.isClosed) controller.close();
  });

  try {
    yield* controller.stream;
  } finally {
    timer.cancel();
    await sub.cancel();
    await discovery.stop();
    if (!controller.isClosed) await controller.close();
  }
}

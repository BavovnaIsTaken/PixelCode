/// Bonjour-based discovery of PixelCode servers on the local network.
///
/// Uses the `bonsoir` package, which wraps Apple's NetService/NWBrowser on
/// iOS/macOS and Android's NsdManager — so iOS's Local Network permission
/// (see NSBonjourServices in Info.plist) applies correctly. Raw multicast
/// would otherwise require the `com.apple.developer.networking.multicast`
/// entitlement, which Apple grants only on request.
library;

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

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
      final host = service.host;
      if (host == null) return;
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

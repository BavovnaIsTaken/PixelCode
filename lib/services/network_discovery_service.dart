/// mDNS-based discovery of PixelCode servers on the local network.
library;

import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

/// A single discovered PixelCode server.
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

/// Scans the local network for PixelCode servers advertising via mDNS.
///
/// The server publishes itself as `_pixelcode._tcp.local.`.
/// Returns a stream that emits each server as it is found.
/// The stream closes after [timeout] (default 5 s) or when manually cancelled.
Stream<DiscoveredServer> discoverServers({
  Duration timeout = const Duration(seconds: 5),
}) async* {
  final client = MDnsClient();
  await client.start();

  const serviceType = '_pixelcode._tcp.local';
  final seen = <String>{};

  try {
    // Phase 1: collect PTR records (service instances).
    await for (final PtrResourceRecord ptr in client
        .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(serviceType))
        .timeout(timeout, onTimeout: (_) {})) {
      // Phase 2: resolve SRV → hostname + port.
      await for (final SrvResourceRecord srv in client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
          .timeout(const Duration(seconds: 2), onTimeout: (_) {})) {
        // Phase 3: resolve A record → IP address.
        await for (final IPAddressResourceRecord ip in client
            .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target))
            .timeout(const Duration(seconds: 2), onTimeout: (_) {})) {
          final host = ip.address.address;
          final key = '$host:${srv.port}';
          if (seen.add(key)) {
            // Strip trailing dot and strip service suffix from display name.
            final rawName = ptr.domainName;
            final suffix = '.$serviceType';
            final name = rawName.endsWith(suffix)
                ? rawName.substring(0, rawName.length - suffix.length)
                : rawName;
            yield DiscoveredServer(name: name, host: host, port: srv.port);
          }
        }
      }
    }
  } finally {
    client.stop();
  }
}

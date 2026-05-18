/// Pull-based provider over the server's `usage_baselines` snapshot.
///
/// The daily-control surface (`Settings → Usage Baselines` tab) calls
/// [refresh] when it opens, asks the server for a freshly computed report,
/// and renders whatever lands. The provider never speculates — every value
/// you see was computed on the server side by [analyze] over the on-disk
/// `usage_log.jsonl`.
///
/// Why a notifier instead of a stream: the snapshot is expensive enough
/// (linear in usage_log size) that we don't push it unsolicited; pull-on-open
/// keeps the WS quiet for users who never look at the tab. The outlier-
/// warning consumer that lands later can layer a stream on top without
/// touching this contract.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'ws_provider.dart';

class UsageBaselinesState {
  /// Most recent server snapshot. `null` until the first reply arrives.
  final UsageBaselinesMessage? report;

  /// True between [refresh] and the matching `usage_baselines` reply.
  final bool loading;

  /// When the local view-state was last updated — drives "stale > 1h" hints
  /// in the UI so the user can tell whether they're looking at fresh data.
  final DateTime? lastRefreshAt;

  const UsageBaselinesState({
    this.report,
    this.loading = false,
    this.lastRefreshAt,
  });

  UsageBaselinesState copyWith({
    UsageBaselinesMessage? report,
    bool? loading,
    DateTime? lastRefreshAt,
  }) =>
      UsageBaselinesState(
        report: report ?? this.report,
        loading: loading ?? this.loading,
        lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
      );
}

class UsageBaselinesNotifier extends Notifier<UsageBaselinesState> {
  StreamSubscription<ServerMessage>? _msgSub;

  @override
  UsageBaselinesState build() {
    final ws = ref.watch(wsServiceProvider);
    _msgSub?.cancel();
    _msgSub = ws.messages.listen((msg) {
      if (msg is UsageBaselinesMessage) {
        state = state.copyWith(
          report: msg,
          loading: false,
          lastRefreshAt: DateTime.now(),
        );
      }
    });
    ref.onDispose(() => _msgSub?.cancel());
    return const UsageBaselinesState();
  }

  /// Ask the server for a fresh snapshot. Idempotent — back-to-back calls
  /// are fine; the next reply just overwrites the previous one.
  void refresh() {
    state = state.copyWith(loading: true);
    ref.read(wsServiceProvider).getUsageBaselines();
  }
}

final usageBaselinesProvider =
    NotifierProvider<UsageBaselinesNotifier, UsageBaselinesState>(
  UsageBaselinesNotifier.new,
);

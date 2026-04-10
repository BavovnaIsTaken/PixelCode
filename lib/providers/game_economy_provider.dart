/// Riverpod provider for the game economy — currency, hiring, skills, office.
///
/// Listens to server messages to award гримні on task completion.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../models/game_economy.dart';
import '../services/game_persistence_service.dart';
import 'agent_provider.dart';
import 'settings_provider.dart';

class GameEconomyNotifier extends Notifier<GameState> {
  StreamSubscription<ServerMessage>? _sub;
  StreamSubscription<bool>? _connSub;
  Timer? _saveTimer;
  Timer? _passiveIncomeTimer;

  @override
  GameState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final loaded = GamePersistenceService.load(prefs);

    // Listen for task completions to award grymni
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);

    // Send game state to server on (re)connect
    _connSub?.cancel();
    _connSub = ws.connectionStatus.listen((connected) {
      if (connected) _syncToServer();
    });

    // Passive income: 10₲ per minute while connected
    _passiveIncomeTimer?.cancel();
    _passiveIncomeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _passiveIncome(),
    );

    ref.onDispose(() {
      _sub?.cancel();
      _connSub?.cancel();
      _saveTimer?.cancel();
      _passiveIncomeTimer?.cancel();
    });

    return loaded;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      final prefs = ref.read(sharedPrefsProvider);
      GamePersistenceService.save(prefs, state);
    });
  }

  /// Send current game state to the server so it knows which agents
  /// are hired, their hardware (→ model), and skill levels (→ prompt).
  void _syncToServer() {
    final gs = state;
    final hiredAgents = gs.hiredAgentIds;
    final agentHardware = <String, int>{};
    final agentSkills = <String, Map<String, int>>{};

    for (final entry in gs.agents.entries) {
      if (!entry.value.isHired) continue;
      agentHardware[entry.key] = entry.value.hardware.index;
      agentSkills[entry.key] = {
        for (final s in entry.value.skills.entries)
          s.key.index.toString(): s.value,
      };
    }

    ref.read(wsServiceProvider).setGameState(
      hiredAgents: hiredAgents,
      agentHardware: agentHardware,
      agentSkills: agentSkills,
    );
  }

  void _onMessage(ServerMessage msg) {
    if (msg is ResultMessage) {
      _onTaskCompleted(msg);
    }
  }

  void _onTaskCompleted(ResultMessage msg) {
    // Award 50-200₲ per completed task
    final rng = Random();
    final base = 50 + rng.nextInt(151);
    // Bonus for clean execution (no high cost = simpler task)
    final bonus = msg.costUsd < 0.1 ? 50 : 0;
    final earned = base + bonus;

    state = state.copyWith(
      grymni: state.grymni + earned,
      totalEarned: state.totalEarned + earned,
    );
    _scheduleSave();
  }

  void _passiveIncome() {
    final agents = ref.read(agentsProvider);
    final hasActiveAgents = agents.values.any((a) => a.isActive);
    if (!hasActiveAgents) return;

    // 10₲ per minute while agents are working
    state = state.copyWith(
      grymni: state.grymni + 10,
      totalEarned: state.totalEarned + 10,
    );
    _scheduleSave();
  }

  // ─── Hiring ────────────────────────────────────────────────────────────

  bool canHire(String agentId) {
    final agent = state.agents[agentId];
    if (agent == null || agent.isHired) return false;
    if (!state.canHireMore) return false;
    final catalog = catalogFor(agentId);
    if (catalog == null) return false;
    return state.grymni >= catalog.hireCost;
  }

  void hireAgent(String agentId) {
    if (!canHire(agentId)) return;
    final catalog = catalogFor(agentId)!;
    final cost = catalog.hireCost;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[agentId] = updated[agentId]!.copyWith(isHired: true);

    state = state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      agents: updated,
    );
    _scheduleSave();
    _syncToServer();
  }

  void fireAgent(String agentId) {
    final agent = state.agents[agentId];
    if (agent == null || !agent.isHired) return;
    // Can't fire starter agents
    final catalog = catalogFor(agentId);
    if (catalog != null && catalog.startsHired) return;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[agentId] = updated[agentId]!.copyWith(isHired: false);

    // Refund 50% of hire cost
    final refund = (catalog?.hireCost ?? 0) ~/ 2;

    state = state.copyWith(
      grymni: state.grymni + refund,
      agents: updated,
    );

    // If the fired agent was selected, switch to manager
    if (ref.read(selectedAgentProvider) == agentId) {
      ref.read(selectedAgentProvider.notifier).state = 'manager';
    }

    _scheduleSave();
    _syncToServer();
  }

  // ─── Skills ────────────────────────────────────────────────────────────

  bool canUpgradeSkill(String agentId, SkillType skill) {
    final agent = state.agents[agentId];
    if (agent == null || !agent.isHired) return false;
    final currentLevel = agent.skills[skill] ?? 1;
    if (currentLevel >= 10) return false;
    return state.grymni >= skill.upgradeCost(currentLevel);
  }

  void upgradeSkill(String agentId, SkillType skill) {
    if (!canUpgradeSkill(agentId, skill)) return;
    final agent = state.agents[agentId]!;
    final currentLevel = agent.skills[skill] ?? 1;
    final cost = skill.upgradeCost(currentLevel);

    final newSkills = Map<SkillType, int>.from(agent.skills);
    newSkills[skill] = currentLevel + 1;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[agentId] = agent.copyWith(skills: newSkills);

    state = state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      agents: updated,
    );
    _scheduleSave();
    _syncToServer();
  }

  // ─── Hardware ──────────────────────────────────────────────────────────

  bool canUpgradeHardware(String agentId) {
    final agent = state.agents[agentId];
    if (agent == null || !agent.isHired) return false;
    final next = agent.hardware.nextTier;
    if (next == null) return false;
    return state.grymni >= next.cost;
  }

  void upgradeHardware(String agentId) {
    if (!canUpgradeHardware(agentId)) return;
    final agent = state.agents[agentId]!;
    final next = agent.hardware.nextTier!;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[agentId] = agent.copyWith(hardware: next);

    state = state.copyWith(
      grymni: state.grymni - next.cost,
      totalSpent: state.totalSpent + next.cost,
      agents: updated,
    );
    _scheduleSave();
    _syncToServer();
  }

  // ─── Office ────────────────────────────────────────────────────────────

  bool canUpgradeOffice() {
    final next = state.officeLevel.nextLevel;
    if (next == null) return false;
    return state.grymni >= next.upgradeCost;
  }

  void upgradeOffice() {
    if (!canUpgradeOffice()) return;
    final next = state.officeLevel.nextLevel!;
    final cost = next.upgradeCost;

    state = state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      officeLevel: next,
    );
    _scheduleSave();
    _syncToServer();
  }

  // ─── Donations ─────────────────────────────────────────────────────────

  void purchaseDonation(DonationPackage package) {
    // Stub: always "successful payment"
    state = state.copyWith(
      grymni: state.grymni + package.grymni,
      totalEarned: state.totalEarned + package.grymni,
    );
    _scheduleSave();
  }

  // ─── Cheat / debug ────────────────────────────────────────────────────

  void addGrymni(int amount) {
    state = state.copyWith(
      grymni: state.grymni + amount,
      totalEarned: state.totalEarned + amount,
    );
    _scheduleSave();
  }
}

final gameEconomyProvider =
    NotifierProvider<GameEconomyNotifier, GameState>(
  GameEconomyNotifier.new,
);

/// Convenience: list of hired agent IDs.
final hiredAgentIdsProvider = Provider<List<String>>((ref) {
  return ref.watch(gameEconomyProvider).hiredAgentIds;
});

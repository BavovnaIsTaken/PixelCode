/// Riverpod provider for the game economy — currency, hiring, skills, office.
///
/// Listens to server messages to award гримні on task completion.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../models/app_theme.dart';
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
    // Stamp the state as locally mutated so cross-device sync can apply
    // last-write-wins. Done synchronously so _syncToServer (which may run
    // right after) sees the bumped timestamp.
    state = state.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      final prefs = ref.read(sharedPrefsProvider);
      GamePersistenceService.save(prefs, state);
    });
  }

  /// Save locally without bumping updatedAt or syncing back to the server
  /// (used when applying remote state to avoid infinite broadcast loops).
  void _scheduleSaveOnly() {
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
      fullState: gs.encode(),
      stateUpdatedAt: gs.updatedAt,
    );
  }

  void _onMessage(ServerMessage msg) {
    if (msg is ResultMessage) {
      _onTaskCompleted(msg);
    } else if (msg is GameStateSyncMessage) {
      _onGameStateSync(msg);
    } else if (msg is DungeonCompleteMessage) {
      _onDungeonComplete(msg);
    }
  }

  /// Apply game state received from another device via the server.
  /// Last-write-wins: only accept if the remote timestamp is strictly newer
  /// than our local one. If ours is newer, push it back so the server (and
  /// every other client) converges on our version instead.
  void _onGameStateSync(GameStateSyncMessage msg) {
    try {
      final remote = GameState.decode(msg.fullState);
      final remoteTs = msg.stateUpdatedAt != 0 ? msg.stateUpdatedAt : remote.updatedAt;
      if (remoteTs > state.updatedAt) {
        state = remote.copyWith(updatedAt: remoteTs);
        _scheduleSaveOnly();
      } else if (remoteTs < state.updatedAt) {
        _syncToServer();
      }
      // ts == local → no-op (echo of our own write)
    } catch (_) {
      // Ignore malformed sync messages
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

  /// Returns true if the agent has BOTH enough XP (from dungeons) AND grymni to level up.
  bool canUpgradeSkill(String agentId, SkillType skill) {
    final agent = state.agents[agentId];
    if (agent == null || !agent.isHired) return false;
    final currentLevel = agent.skills[skill] ?? 1;
    if (currentLevel >= 10) return false;
    final hasGrymni = state.grymni >= skill.upgradeCost(currentLevel);
    final currentXp = agent.skillXp[skill] ?? 0;
    final hasXp = currentXp >= agent.xpForNextLevel(skill);
    return hasGrymni && hasXp;
  }

  /// True when the XP gate is already met but grymni is insufficient.
  bool hasXpButNotGrymni(String agentId, SkillType skill) {
    final agent = state.agents[agentId];
    if (agent == null || !agent.isHired) return false;
    final currentLevel = agent.skills[skill] ?? 1;
    if (currentLevel >= 10) return false;
    final currentXp = agent.skillXp[skill] ?? 0;
    return (currentXp >= agent.xpForNextLevel(skill)) &&
        state.grymni < skill.upgradeCost(currentLevel);
  }

  void upgradeSkill(String agentId, SkillType skill) {
    if (!canUpgradeSkill(agentId, skill)) return;
    final agent = state.agents[agentId]!;
    final currentLevel = agent.skills[skill] ?? 1;
    final cost = skill.upgradeCost(currentLevel);
    final threshold = agent.xpForNextLevel(skill);
    final currentXp = agent.skillXp[skill] ?? 0;

    final newSkills = Map<SkillType, int>.from(agent.skills);
    newSkills[skill] = currentLevel + 1;

    // Carry over excess XP to the next level
    final newXp = Map<SkillType, int>.from(agent.skillXp);
    newXp[skill] = (currentXp - threshold).clamp(0, 999);

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[agentId] = agent.copyWith(skills: newSkills, skillXp: newXp);

    state = state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      agents: updated,
    );
    _scheduleSave();
    _syncToServer();
  }

  /// Accumulate XP from a dungeon run. Never auto-levels — player must spend grymni to level up.
  void _onDungeonComplete(DungeonCompleteMessage msg) {
    final agent = state.agents[msg.agentId];
    if (agent == null) return;
    final skill = SkillType.values[msg.skillType.clamp(0, SkillType.values.length - 1)];
    final newXp = Map<SkillType, int>.from(agent.skillXp);
    newXp[skill] = ((agent.skillXp[skill] ?? 0) + msg.xpEarned).clamp(0, 9999);

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[msg.agentId] = agent.copyWith(skillXp: newXp);
    state = state.copyWith(agents: updated);
    _scheduleSave();
  }

  /// Send a dungeon challenge to the server for the given agent + skill.
  void startDungeon(String agentId, SkillType skill, int difficulty) {
    ref.read(wsServiceProvider).startDungeon(
      agentId: agentId,
      skillType: skill.index,
      difficulty: difficulty.clamp(1, 3),
    );
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

  // ─── Nickname ──────────────────────────────────────────────────────────

  /// Change the player's nickname. Returns true on success, false if
  /// the player can't afford it.
  bool changeNickname(String newNickname) {
    final trimmed = newNickname.trim();
    if (trimmed.isEmpty || trimmed == state.nickname) return false;

    final cost = state.nextNicknameChangeCost;
    if (cost > 0 && state.grymni < cost) return false;

    state = state.copyWith(
      nickname: trimmed,
      nicknameChangesUsed: state.nicknameChangesUsed + 1,
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
    );
    _scheduleSave();
    _syncToServer();
    return true;
  }

  /// Regenerate a random game-style nickname (counts as a change).
  bool randomizeNickname() {
    final seed = DateTime.now().microsecondsSinceEpoch;
    return changeNickname(generateGameNickname(seed));
  }

  // ─── Cosmetics ────────────────────────────────────────────────────────

  bool ownsCosmetic(String cosmeticId) =>
      state.ownedCosmetics.contains(cosmeticId);

  bool canPurchaseCosmetic(String cosmeticId) {
    if (ownsCosmetic(cosmeticId)) return false;
    final item = cosmeticById(cosmeticId);
    if (item == null) return false;
    return state.grymni >= item.cost;
  }

  void purchaseCosmetic(String cosmeticId) {
    if (!canPurchaseCosmetic(cosmeticId)) return;
    final item = cosmeticById(cosmeticId)!;

    final owned = Set<String>.from(state.ownedCosmetics)..add(cosmeticId);
    state = state.copyWith(
      grymni: state.grymni - item.cost,
      totalSpent: state.totalSpent + item.cost,
      ownedCosmetics: owned,
    );
    _scheduleSave();
    _syncToServer();
  }

  void equipCosmetic(String cosmeticId) {
    if (!ownsCosmetic(cosmeticId)) return;
    final item = cosmeticById(cosmeticId);
    if (item == null) return;

    final equipped = Map<int, String>.from(state.equippedCosmetics);
    equipped[item.type.index] = cosmeticId;
    state = state.copyWith(equippedCosmetics: equipped);
    _scheduleSave();
    _syncToServer();
  }

  void unequipCosmetic(CosmeticType type) {
    final equipped = Map<int, String>.from(state.equippedCosmetics);
    equipped.remove(type.index);
    state = state.copyWith(equippedCosmetics: equipped);
    _scheduleSave();
    _syncToServer();
  }

  // ─── Themes ────────────────────────────────────────────────────────────

  bool ownsTheme(String themeId) {
    // All standard (free) themes are always owned.
    final def = themeById(themeId);
    if (def != null && def.isFree) return true;
    return state.themeState.ownedThemes.contains(themeId);
  }

  bool canPurchaseTheme(String themeId) {
    if (ownsTheme(themeId)) return false;
    final def = themeById(themeId);
    if (def == null) return false;
    return state.grymni >= def.cost;
  }

  void purchaseTheme(String themeId) {
    if (!canPurchaseTheme(themeId)) return;
    final def = themeById(themeId)!;

    final owned = Set<String>.from(state.themeState.ownedThemes)..add(themeId);
    state = state.copyWith(
      grymni: state.grymni - def.cost,
      totalSpent: state.totalSpent + def.cost,
      themeState: state.themeState.copyWith(ownedThemes: owned),
    );
    _scheduleSave();
    _syncToServer();
  }

  void activateTheme(String themeId) {
    if (!ownsTheme(themeId)) return;
    state = state.copyWith(
      themeState: state.themeState.copyWith(activeThemeId: themeId),
    );
    _scheduleSave();
    _syncToServer();
  }

  void customizeTheme(String themeId, ThemeCustomization customization) {
    if (!ownsTheme(themeId)) return;
    final def = themeById(themeId);
    if (def == null || !def.isCustomizable) return;

    final customs = Map<String, ThemeCustomization>.from(
        state.themeState.customizations);
    if (customization.isEmpty) {
      customs.remove(themeId);
    } else {
      customs[themeId] = customization;
    }
    state = state.copyWith(
      themeState: state.themeState.copyWith(customizations: customs),
    );
    _scheduleSave();
    _syncToServer();
  }

  // ─── Furniture ────────────────────────────────────────────────────────

  bool ownsFurniture(String itemId) =>
      state.ownedFurniture.contains(itemId);

  bool canPurchaseFurniture(String itemId) {
    if (ownsFurniture(itemId)) return false;
    final item = furnitureById(itemId);
    if (item == null) return false;
    return state.grymni >= item.cost;
  }

  void purchaseFurniture(String itemId) {
    if (!canPurchaseFurniture(itemId)) return;
    final item = furnitureById(itemId)!;

    final owned = Set<String>.from(state.ownedFurniture)..add(itemId);
    state = state.copyWith(
      grymni: state.grymni - item.cost,
      totalSpent: state.totalSpent + item.cost,
      ownedFurniture: owned,
    );
    _scheduleSave();
    _syncToServer();
  }

  void placeFurniture(String itemId, int col, int row) {
    if (!ownsFurniture(itemId)) return;
    final placed = List<FurniturePlacement>.from(state.placedFurniture)
      ..add(FurniturePlacement(itemId: itemId, col: col, row: row));
    state = state.copyWith(placedFurniture: placed);
    _scheduleSave();
    _syncToServer();
  }

  void removePlacedFurniture(int index) {
    if (index < 0 || index >= state.placedFurniture.length) return;
    final placed = List<FurniturePlacement>.from(state.placedFurniture)
      ..removeAt(index);
    state = state.copyWith(placedFurniture: placed);
    _scheduleSave();
    _syncToServer();
  }

  void moveFurniture(int index, int newCol, int newRow) {
    if (index < 0 || index >= state.placedFurniture.length) return;
    final old = state.placedFurniture[index];
    final placed = List<FurniturePlacement>.from(state.placedFurniture);
    placed[index] = FurniturePlacement(
      itemId: old.itemId,
      col: newCol,
      row: newRow,
    );
    state = state.copyWith(placedFurniture: placed);
    _scheduleSave();
    _syncToServer();
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

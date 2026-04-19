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

  /// Agents currently running work, tracked locally from ws messages so
  /// passive income can decide when to pay out without reading agentsProvider
  /// (which would create a provider cycle).
  final Set<String> _activeAgentIds = {};

  @override
  GameState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final loaded = GamePersistenceService.load(prefs);

    // Listen for task completions to award grymni
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);

    // Send game state to server on (re)connect — but ONLY if we have real
    // persisted state. A fresh client (updatedAt == 0) must wait for the
    // server's push, otherwise its default 500₲ state would race against and
    // clobber another device's accumulated progress.
    _connSub?.cancel();
    _connSub = ws.connectionStatus.listen((connected) {
      if (connected && state.updatedAt > 0) _syncToServer();
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

  /// Send current game state to the server.
  ///
  /// Serializes every hired instance into the `instances` map the server
  /// expects (instanceId → { roleType, nickname, hardware, skills }).
  void _syncToServer() {
    final gs = state;
    final instances = <String, Map<String, dynamic>>{};

    for (final entry in gs.agents.entries) {
      final a = entry.value;
      instances[entry.key] = {
        'roleType': a.roleType,
        'nickname': a.nickname,
        'hardware': a.hardware.index,
        'skills': {
          for (final s in a.skills.entries) s.key.index.toString(): s.value,
        },
      };
    }

    ref.read(wsServiceProvider).setGameState(
          instances: instances,
          fullState: gs.encode(),
          stateUpdatedAt: gs.updatedAt,
        );
  }

  void _onMessage(ServerMessage msg) {
    _trackActivity(msg);
    if (msg is ResultMessage) {
      _onTaskCompleted(msg);
    } else if (msg is GameStateSyncMessage) {
      _onGameStateSync(msg);
    } else if (msg is DungeonCompleteMessage) {
      _onDungeonComplete(msg);
    }
  }

  /// Mirror the subset of AgentsNotifier's active/idle logic needed to decide
  /// whether passive income should be paid, without crossing provider
  /// boundaries.
  void _trackActivity(ServerMessage msg) {
    switch (msg) {
      case AgentStatusMessage(:final agentId, :final status):
        if (status == AgentStatus.idle) {
          _activeAgentIds.remove(agentId);
        } else {
          _activeAgentIds.add(agentId);
        }
      case SubagentStartMessage(:final agentId):
        _activeAgentIds.add(agentId);
      case TaskDispatchedMessage(:final agentId):
        _activeAgentIds.add(agentId);
      case ToolUseMessage(:final agentId):
        _activeAgentIds.add(agentId);
      case SubagentStopMessage(:final agentId):
        _activeAgentIds.remove(agentId);
      case SubagentResultMessage(:final agentId):
        _activeAgentIds.remove(agentId);
      case ResultMessage():
        _activeAgentIds.remove('manager');
      default:
        break;
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
    _syncToServer();
  }

  void _passiveIncome() {
    if (_activeAgentIds.isEmpty) return;

    // 10₲ per minute while agents are working
    state = state.copyWith(
      grymni: state.grymni + 10,
      totalEarned: state.totalEarned + 10,
    );
    _scheduleSave();
    _syncToServer();
  }

  // ─── Hiring ────────────────────────────────────────────────────────────

  /// Whether a NEW instance of [roleType] can currently be hired.
  ///
  /// Checks: role exists in catalog, office has free room, singleton roles
  /// aren't already filled, and the player can afford it.
  bool canHire(String roleType) {
    final role = roleCatalogFor(roleType);
    if (role == null) return false;
    if (!state.canHireMore) return false;
    if (role.singleton && state.roleCount(roleType) >= 1) return false;
    return state.grymni >= role.hireCost;
  }

  /// Hire a new instance of [roleType]. Auto-generates instanceId + nickname.
  /// Returns the new instanceId on success, or null if hiring isn't allowed.
  String? hireAgent(String roleType) {
    if (!canHire(roleType)) return null;
    final role = roleCatalogFor(roleType)!;
    final cost = role.hireCost;

    final instanceId = nextInstanceId(roleType, state.agents.keys);
    final ordinal = state.roleCount(roleType) + 1;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[instanceId] = AgentGameData(
      instanceId: instanceId,
      roleType: roleType,
      nickname: defaultNicknameFor(role, ordinal),
      hardware: HardwareTier.oldLaptop,
      skills: {for (final s in SkillType.values) s: 1},
    );

    state = state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      agents: updated,
    );
    _scheduleSave();
    _syncToServer();
    return instanceId;
  }

  /// Fire a specific instance by instanceId. Refunds 50% of the role's hire cost.
  void fireAgent(String instanceId) {
    final agent = state.agents[instanceId];
    if (agent == null) return;

    final role = roleCatalogFor(agent.roleType);
    // Keep at least one manager around so the team can still coordinate.
    if (role != null && role.singleton && state.roleCount(agent.roleType) <= 1) {
      return;
    }

    final updated = Map<String, AgentGameData>.from(state.agents)
      ..remove(instanceId);

    final refund = (role?.hireCost ?? 0) ~/ 2;

    state = state.copyWith(
      grymni: state.grymni + refund,
      agents: updated,
    );

    // If the fired instance was selected, switch back to a manager instance.
    if (ref.read(selectedAgentProvider) == instanceId) {
      final managers = state.instancesOfRole('manager');
      ref.read(selectedAgentProvider.notifier).state =
          managers.isNotEmpty ? managers.first.instanceId : 'manager';
    }

    _scheduleSave();
    _syncToServer();
  }

  /// Rename an instance's nickname. Free within the game (no currency cost).
  void renameInstance(String instanceId, String newNickname) {
    final agent = state.agents[instanceId];
    final trimmed = newNickname.trim();
    if (agent == null || trimmed.isEmpty || trimmed == agent.nickname) return;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[instanceId] = agent.copyWith(nickname: trimmed);

    state = state.copyWith(agents: updated);
    _scheduleSave();
    _syncToServer();
  }

  // ─── Skills ────────────────────────────────────────────────────────────

  /// Returns true if the agent has BOTH enough XP (from dungeons) AND grymni to level up.
  bool canUpgradeSkill(String instanceId, SkillType skill) {
    final agent = state.agents[instanceId];
    if (agent == null) return false;
    final currentLevel = agent.skills[skill] ?? 1;
    if (currentLevel >= 10) return false;
    final hasGrymni = state.grymni >= skill.upgradeCost(currentLevel);
    final currentXp = agent.skillXp[skill] ?? 0;
    final hasXp = currentXp >= agent.xpForNextLevel(skill);
    return hasGrymni && hasXp;
  }

  /// True when the XP gate is already met but grymni is insufficient.
  bool hasXpButNotGrymni(String instanceId, SkillType skill) {
    final agent = state.agents[instanceId];
    if (agent == null) return false;
    final currentLevel = agent.skills[skill] ?? 1;
    if (currentLevel >= 10) return false;
    final currentXp = agent.skillXp[skill] ?? 0;
    return (currentXp >= agent.xpForNextLevel(skill)) &&
        state.grymni < skill.upgradeCost(currentLevel);
  }

  void upgradeSkill(String instanceId, SkillType skill) {
    if (!canUpgradeSkill(instanceId, skill)) return;
    final agent = state.agents[instanceId]!;
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
    updated[instanceId] = agent.copyWith(skills: newSkills, skillXp: newXp);

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
    _syncToServer();
  }

  /// Send a dungeon challenge to the server for the given agent instance + skill.
  void startDungeon(String instanceId, SkillType skill, int difficulty) {
    ref.read(wsServiceProvider).startDungeon(
      agentId: instanceId,
      skillType: skill.index,
      difficulty: difficulty.clamp(1, 3),
    );
  }

  // ─── Hardware ──────────────────────────────────────────────────────────

  bool canUpgradeHardware(String instanceId) {
    final agent = state.agents[instanceId];
    if (agent == null) return false;
    final next = agent.hardware.nextTier;
    if (next == null) return false;
    return state.grymni >= next.cost;
  }

  void upgradeHardware(String instanceId) {
    if (!canUpgradeHardware(instanceId)) return;
    final agent = state.agents[instanceId]!;
    final next = agent.hardware.nextTier!;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[instanceId] = agent.copyWith(hardware: next);

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
    if (next.isWipComingSoon) return false;
    return state.grymni >= next.upgradeCost;
  }

  void upgradeOffice() {
    if (!canUpgradeOffice()) return;
    final next = state.officeLevel.nextLevel!;
    if (next.isWipComingSoon) return;
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
    _syncToServer();
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

  // ─── Office rooms (Build Mode) ────────────────────────────────────────────

  bool canPlaceRoom(RoomType type) => state.grymni >= type.cost;
  int roomCount(RoomType type) =>
      state.placedRooms.where((r) => r.type == type).length;
  bool isRoomLimitReached(RoomType type) =>
      roomCount(type) >= type.maxPerOffice;

  void placeRoom(RoomType type, int col, int row) {
    if (!canPlaceRoom(type)) return;
    if (isRoomLimitReached(type)) return;
    final id = 'room_${DateTime.now().microsecondsSinceEpoch}';
    final rooms = List<PlacedRoom>.from(state.placedRooms)
      ..add(PlacedRoom(id: id, type: type, col: col, row: row));
    state = state.copyWith(
      grymni: state.grymni - type.cost,
      totalSpent: state.totalSpent + type.cost,
      placedRooms: rooms,
    );
    _scheduleSave();
    _syncToServer();
  }

  void removeRoom(String roomId) {
    final idx = state.placedRooms.indexWhere((r) => r.id == roomId);
    if (idx < 0) return;
    final room = state.placedRooms[idx];
    final rooms = List<PlacedRoom>.from(state.placedRooms)..removeAt(idx);
    state = state.copyWith(
      grymni: state.grymni + room.type.cost ~/ 2,
      placedRooms: rooms,
    );
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
    _syncToServer();
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

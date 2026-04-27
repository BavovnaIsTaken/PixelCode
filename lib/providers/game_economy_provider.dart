/// Riverpod provider for the game economy — currency, hiring, skills, office.
///
/// Listens to server messages to award гримні on task completion.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_level.dart';
import '../models/agent_message.dart';
import '../models/app_theme.dart';
import '../models/game_economy.dart';
import '../models/roster_catalog.dart';
import '../widgets/personalization/custom_agent_spawn_form.dart';
import '../services/game_persistence_service.dart';
import 'ws_provider.dart';
import 'deepseek_auth_provider.dart';
import 'kimi_auth_provider.dart';
import 'energy_provider.dart';
import 'settings_provider.dart';

class GameEconomyNotifier extends Notifier<GameState> {
  StreamSubscription<ServerMessage>? _sub;
  StreamSubscription<bool>? _connSub;
  Timer? _saveTimer;
  Timer? _syncTimer;
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
      _syncTimer?.cancel();
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
  /// Debounced to avoid hammering the server during rapid UI actions.
  void _syncToServer() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 500), () {
      final gs = state;
      final instances = <String, Map<String, dynamic>>{};

      for (final entry in gs.agents.entries) {
        final a = entry.value;
        instances[entry.key] = {
          'roleType': a.roleType,
          'nickname': a.nickname,
          'hardware': a.hardware.index,
          'provider': a.provider.index,
          'skills': {
            for (final s in a.skills.entries) s.key.index.toString(): s.value,
          },
        };
      }
      final deepseekKey = ref.read(deepseekAuthProvider).valueOrNull?.apiKey;
      final kimiKey = ref.read(kimiAuthProvider).valueOrNull?.apiKey;
      ref.read(wsServiceProvider).setGameState(
            instances: instances,
            fullState: gs.encode(),
            stateUpdatedAt: gs.updatedAt,
            deepseekApiKey: deepseekKey,
            kimiApiKey: kimiKey,
          );
    });
  }

  void _updateStateAndSync(GameState newState) {
    state = newState.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _scheduleSave();
    _syncToServer();
  }

  void _onMessage(ServerMessage msg) {
    _trackActivity(msg);
    if (msg is ResultMessage) {
      _onTaskCompleted(msg);
    } else if (msg is SubagentResultMessage) {
      _onSubagentResult(msg);
    } else if (msg is GameStateSyncMessage) {
      _onGameStateSync(msg);
    } else if (msg is DungeonCompleteMessage) {
      _onDungeonComplete(msg);
    }
  }

  /// Record a subagent's actual token usage into the Energy meter.
  /// Model tier is inferred from the agent's skill vector using the same
  /// capability score the server uses in [skillsToModel] — keeping client
  /// and server estimates aligned so the meter reflects reality.
  ///
  /// Token estimate from `costUsd`: at Sonnet-ish blended pricing,
  /// ~1 USD ≈ 200k tokens. Approximate but good enough for a budget signal.
  void _onSubagentResult(SubagentResultMessage msg) {
    final agent = state.agents[msg.agentId];
    if (agent == null || msg.costUsd <= 0) return;
    final model = capabilityModelForSkills(
      precision: agent.skills[SkillType.precision] ?? 1,
      creativity: agent.skills[SkillType.creativity] ?? 1,
      insight: agent.skills[SkillType.insight] ?? 1,
      reliability: agent.skills[SkillType.reliability] ?? 1,
      roleType: agent.roleType,
    );
    final tokens = (msg.costUsd * 200000).round();
    ref.read(energyProvider.notifier).recordTaskTokens(model, tokens);
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
      // Detect server-stored state that was serialized under an older schema.
      // decode() normalizes schemaVersion to current, but the raw JSON on the
      // server still holds the stale value — push a fresh copy up so future
      // connects don't keep re-sending the old blob to every client.
      final remoteIsStale = (jsonDecode(msg.fullState)
              as Map<String, dynamic>)['schemaVersion'] !=
          GameState.currentSchemaVersion;
      if (remoteTs > state.updatedAt) {
        state = remote.copyWith(updatedAt: remoteTs);
        _scheduleSaveOnly();
        if (remoteIsStale) _syncToServer();
      } else if (remoteTs < state.updatedAt) {
        _syncToServer();
      } else if (remoteIsStale) {
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

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni + earned,
      totalEarned: state.totalEarned + earned,
    ));
  }

  void _passiveIncome() {
    if (_activeAgentIds.isEmpty) return;

    // 10₲ per minute while agents are working
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni + 10,
      totalEarned: state.totalEarned + 10,
    ));
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
      provider: AgentProviderType.values[role.defaultProvider],
      skills: initialSkillsForRole(roleType),
    );

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      agents: updated,
    ));
    return instanceId;
  }

  /// Whether a curated roster character with [characterId] can be hired right
  /// now (catalog match + capacity + singleton + funds for `character.price`).
  bool canHireCharacter(String characterId) {
    final character = rosterCharacterById(characterId);
    if (character == null) return false;
    if (!state.canHireMore) return false;
    final role = roleCatalogFor(character.roleType);
    if (role == null) return false;
    if (role.singleton && state.roleCount(character.roleType) >= 1) {
      return false;
    }
    return state.grymni >= character.price;
  }

  /// Hire a curated roster character. Stats come from the character spec
  /// (not `initialSkillsForRole`), provider defaults to `character.defaultProvider`,
  /// and `characterId` is persisted on the resulting [AgentGameData] so the
  /// UI can render the named character on its roster card.
  ///
  /// Returns the new instanceId on success, or null if hiring isn't allowed.
  String? hireCharacter(String characterId) {
    if (!canHireCharacter(characterId)) return null;
    final character = rosterCharacterById(characterId)!;
    final cost = character.price;

    final instanceId = nextInstanceId(character.roleType, state.agents.keys);

    // Use the character's display name if it's the first instance of this
    // roster character; otherwise append an ordinal so duplicates remain
    // distinguishable in the UI ("Андрій 2").
    final existingForCharacter = state.agents.values
        .where((a) => a.characterId == character.id)
        .length;
    final nickname = existingForCharacter == 0
        ? character.name
        : '${character.name} ${existingForCharacter + 1}';

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[instanceId] = AgentGameData(
      instanceId: instanceId,
      roleType: character.roleType,
      nickname: nickname,
      hardware: HardwareTier.oldLaptop,
      provider: character.defaultProvider,
      skills: Map<SkillType, int>.from(character.statWeights),
      characterId: character.id,
    );

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      agents: updated,
    ));
    return instanceId;
  }

  /// Whether a custom agent with [data.selectedRole] can be spawned right now
  /// (capacity check + role exists + sufficient grymni).
  bool canSpawnCustomAgent(CustomAgentSpawnData data) {
    final role = roleCatalogFor(data.selectedRole);
    if (role == null) return false;
    if (!state.canHireMore) return false;
    if (role.singleton && state.roleCount(data.selectedRole) >= 1) return false;
    return state.grymni >= role.hireCost;
  }

  /// Spawn a fully custom agent from [data] (nickname, system prompt, role,
  /// personality preset, skill weights). Uses the role's standard hire cost.
  /// Returns the new instanceId on success, or null if spawning isn't allowed.
  String? spawnCustomAgent(CustomAgentSpawnData data) {
    if (!canSpawnCustomAgent(data)) return null;
    final role = roleCatalogFor(data.selectedRole)!;
    final cost = role.hireCost;

    final instanceId = nextInstanceId(data.selectedRole, state.agents.keys);
    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[instanceId] = AgentGameData(
      instanceId: instanceId,
      roleType: data.selectedRole,
      nickname: data.nickname.isEmpty
          ? defaultNicknameFor(role, state.roleCount(data.selectedRole) + 1)
          : data.nickname,
      hardware: HardwareTier.oldLaptop,
      provider: AgentProviderType.values[role.defaultProvider],
      skills: data.skillWeights,
      customSystemPrompt:
          data.systemPrompt.isEmpty ? null : data.systemPrompt,
      personalityPreset: data.personalityPreset,
    );

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      agents: updated,
    ));
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

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni + refund,
      agents: updated,
    ));
  }

  /// Rename an instance's nickname. Free within the game (no currency cost).
  void renameInstance(String instanceId, String newNickname) {
    final agent = state.agents[instanceId];
    final trimmed = newNickname.trim();
    if (agent == null || trimmed.isEmpty || trimmed == agent.nickname) return;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[instanceId] = agent.copyWith(nickname: trimmed);

    _updateStateAndSync(state.copyWith(agents: updated));
  }

  // ─── Skills ────────────────────────────────────────────────────────────

  /// Whether the given skill can be upgraded: below cap AND player can afford.
  bool canUpgradeSkill(String instanceId, SkillType skill) {
    final agent = state.agents[instanceId];
    if (agent == null) return false;
    final currentLevel = agent.skills[skill] ?? 1;
    if (currentLevel >= skillCap(agent.level)) return false;
    return state.grymni >= skill.upgradeCost(currentLevel);
  }

  /// Whether this skill is at the level-gated cap (blocked by agent level,
  /// not by gold). Callers can surface a "Рівень агент досягнуто" hint.
  bool isSkillCapped(String instanceId, SkillType skill) {
    final agent = state.agents[instanceId];
    if (agent == null) return false;
    return (agent.skills[skill] ?? 1) >= skillCap(agent.level);
  }

  void upgradeSkill(String instanceId, SkillType skill) {
    if (!canUpgradeSkill(instanceId, skill)) return;
    final agent = state.agents[instanceId]!;
    final currentLevel = agent.skills[skill] ?? 1;
    final cost = skill.upgradeCost(currentLevel);

    final newSkills = Map<SkillType, int>.from(agent.skills);
    newSkills[skill] = currentLevel + 1;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[instanceId] = agent.copyWith(skills: newSkills);

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      agents: updated,
    ));
  }

  /// Award XP to an agent, possibly triggering one or more level-ups.
  /// Carry-over XP is preserved. Returns the number of levels gained.
  int addXpToAgent(String instanceId, int xpGained) {
    final agent = state.agents[instanceId];
    if (agent == null || xpGained <= 0) return 0;
    if (agent.level >= maxAgentLevel) return 0;

    var level = agent.level;
    var xp = agent.xp + xpGained;
    var levelsGained = 0;

    while (level < maxAgentLevel && xp >= xpToNextLevel(level)) {
      xp -= xpToNextLevel(level);
      level += 1;
      levelsGained += 1;
    }

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[instanceId] = agent.copyWith(level: level, xp: xp);

    _updateStateAndSync(state.copyWith(agents: updated));
    return levelsGained;
  }

  /// Award a one-off crit bonus (100% of a typical task reward).
  /// Called when a task completes with a creativity crit.
  void awardCritBonus() {
    const bonus = 150;
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni + bonus,
      totalEarned: state.totalEarned + bonus,
    ));
  }

  /// Dungeon completion now awards agent-level XP (not per-skill XP).
  /// The server still reports `xpEarned` in the legacy per-skill scale (0-100+
  /// ballpark); we scale it down ×5 for the new agent-XP curve.
  void _onDungeonComplete(DungeonCompleteMessage msg) {
    if (state.agents[msg.agentId] == null) return;
    final gained = (msg.xpEarned ~/ 5).clamp(1, 999);
    addXpToAgent(msg.agentId, gained);
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

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - next.cost,
      totalSpent: state.totalSpent + next.cost,
      agents: updated,
    ));
  }

  // ─── Provider ──────────────────────────────────────────────────────────

  void setAgentProvider(String instanceId, AgentProviderType provider) {
    final agent = state.agents[instanceId];
    if (agent == null) return;

    final updated = Map<String, AgentGameData>.from(state.agents);
    updated[instanceId] = agent.copyWith(provider: provider);

    _updateStateAndSync(state.copyWith(agents: updated));
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

    // Reset expansion count — the new tier's expansion track is independent.
    // Drop any rooms/furniture that fall outside the new tier's base grid.
    final nextCols = next.baseCols;
    final nextRows = next.baseRows;
    final keptRooms = state.placedRooms
        .where((r) =>
            r.col >= 1 &&
            r.row >= 1 &&
            r.col + r.type.widthTiles <= nextCols - 1 &&
            r.row + r.type.heightTiles <= nextRows - 1)
        .toList();
    final keptFurniture = state.placedFurniture
        .where((p) => p.col < nextCols - 1 && p.row < nextRows - 1)
        .toList();

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      officeLevel: next,
      officeExpansions: 0,
      placedRooms: keptRooms,
      placedFurniture: keptFurniture,
    ));
  }

  /// Whether the player can afford and is eligible for the next expansion
  /// step at the current tier.
  bool canBuyOfficeExpansion() {
    final next = state.nextExpansion;
    if (next == null) return false;
    return state.grymni >= next.cost;
  }

  /// Buy the next expansion step at the current tier. No-op if the tier is
  /// already maxed out or the player can't afford it.
  void buyOfficeExpansion() {
    if (!canBuyOfficeExpansion()) return;
    final next = state.nextExpansion!;

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - next.cost,
      totalSpent: state.totalSpent + next.cost,
      officeExpansions: state.officeExpansions + 1,
    ));
  }

  // ─── Donations ─────────────────────────────────────────────────────────

  void purchaseDonation(DonationPackage package) {
    // Stub: always "successful payment"
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni + package.grymni,
      totalEarned: state.totalEarned + package.grymni,
    ));
  }

  // ─── Nickname ──────────────────────────────────────────────────────────

  /// Change the player's nickname. Returns true on success, false if
  /// the player can't afford it.
  bool changeNickname(String newNickname) {
    final trimmed = newNickname.trim();
    if (trimmed.isEmpty || trimmed == state.nickname) return false;

    final cost = state.nextNicknameChangeCost;
    if (cost > 0 && state.grymni < cost) return false;

    _updateStateAndSync(state.copyWith(
      nickname: trimmed,
      nicknameChangesUsed: state.nicknameChangesUsed + 1,
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
    ));
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
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - item.cost,
      totalSpent: state.totalSpent + item.cost,
      ownedCosmetics: owned,
    ));
  }

  void equipCosmetic(String cosmeticId) {
    if (!ownsCosmetic(cosmeticId)) return;
    final item = cosmeticById(cosmeticId);
    if (item == null) return;

    final equipped = Map<int, String>.from(state.equippedCosmetics);
    equipped[item.type.index] = cosmeticId;
    _updateStateAndSync(state.copyWith(equippedCosmetics: equipped));
  }

  void unequipCosmetic(CosmeticType type) {
    final equipped = Map<int, String>.from(state.equippedCosmetics);
    equipped.remove(type.index);
    _updateStateAndSync(state.copyWith(equippedCosmetics: equipped));
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
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - def.cost,
      totalSpent: state.totalSpent + def.cost,
      themeState: state.themeState.copyWith(ownedThemes: owned),
    ));
  }

  void activateTheme(String themeId) {
    if (!ownsTheme(themeId)) return;
    _updateStateAndSync(state.copyWith(
      themeState: state.themeState.copyWith(activeThemeId: themeId),
    ));
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
    _updateStateAndSync(state.copyWith(
      themeState: state.themeState.copyWith(customizations: customs),
    ));
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
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - item.cost,
      totalSpent: state.totalSpent + item.cost,
      ownedFurniture: owned,
    ));
  }

  void placeFurniture(String itemId, int col, int row) {
    if (!ownsFurniture(itemId)) return;
    final placed = List<FurniturePlacement>.from(state.placedFurniture)
      ..add(FurniturePlacement(itemId: itemId, col: col, row: row));
    _updateStateAndSync(state.copyWith(placedFurniture: placed));
  }

  void removePlacedFurniture(int index) {
    if (index < 0 || index >= state.placedFurniture.length) return;
    final placed = List<FurniturePlacement>.from(state.placedFurniture)
      ..removeAt(index);
    _updateStateAndSync(state.copyWith(placedFurniture: placed));
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
    _updateStateAndSync(state.copyWith(placedFurniture: placed));
  }

  // ─── Office rooms (Build Mode) ────────────────────────────────────────────

  bool canPlaceRoom(RoomType type) => state.grymni >= type.cost;
  int roomCount(RoomType type) =>
      state.placedRooms.where((r) => r.type == type).length;
  bool isRoomLimitReached(RoomType type) =>
      roomCount(type) >= type.maxPerOffice;

  void placeRoom(RoomType type, int col, int row, {int rotation = 0}) {
    if (!canPlaceRoom(type)) return;
    if (isRoomLimitReached(type)) return;
    final id = 'room_${DateTime.now().microsecondsSinceEpoch}';
    final rooms = List<PlacedRoom>.from(state.placedRooms)
      ..add(PlacedRoom(
          id: id, type: type, col: col, row: row, rotation: rotation));
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - type.cost,
      totalSpent: state.totalSpent + type.cost,
      placedRooms: rooms,
    ));
  }

  /// Final price (after the bundle discount) of a room template.
  int templateCost(RoomTemplate template) =>
      template.bundleCost(furnitureCatalog);

  bool canPlaceRoomTemplate(RoomTemplate template) {
    if (state.grymni < templateCost(template)) return false;
    if (isRoomLimitReached(template.baseRoom)) return false;
    return true;
  }

  /// Place a room template as one atomic transaction: deduct the bundle
  /// cost (single discounted price), spawn the base room, then drop in
  /// every furniture slot relative to the room's top-left corner. The
  /// included furniture items are also marked as owned so the player can
  /// later move or remove them via the Decor edit mode.
  void placeRoomTemplate(RoomTemplate template, int col, int row,
      {int rotation = 0}) {
    if (!canPlaceRoomTemplate(template)) return;
    final cost = templateCost(template);
    final roomId = 'room_${DateTime.now().microsecondsSinceEpoch}';
    final rooms = List<PlacedRoom>.from(state.placedRooms)
      ..add(PlacedRoom(
          id: roomId,
          type: template.baseRoom,
          col: col,
          row: row,
          rotation: rotation));

    final placed = List<FurniturePlacement>.from(state.placedFurniture);
    final owned = Set<String>.from(state.ownedFurniture);
    for (final slot in template.furniture) {
      // Slot offsets are stored relative to the unrotated room footprint.
      // For Stage 2 the placement is rotation-naive — when rotation lands
      // beyond 0° we still drop furniture at base offsets so the room is
      // valid; rotation-aware furniture layout is a follow-up.
      placed.add(FurniturePlacement(
        itemId: slot.furnitureId,
        col: col + slot.colOffset,
        row: row + slot.rowOffset,
      ));
      owned.add(slot.furnitureId);
    }

    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      placedRooms: rooms,
      placedFurniture: placed,
      ownedFurniture: owned,
    ));
  }

  void removeRoom(String roomId) {
    final idx = state.placedRooms.indexWhere((r) => r.id == roomId);
    if (idx < 0) return;
    final room = state.placedRooms[idx];
    final rooms = List<PlacedRoom>.from(state.placedRooms)..removeAt(idx);
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni + room.type.cost ~/ 2,
      placedRooms: rooms,
    ));
  }

  // ─── Wall / floor skin packs ──────────────────────────────────────────

  bool canPurchaseWallSkinPack(WallSkinPack pack) =>
      !state.ownedWallSkinPacks.contains(pack.id) &&
      state.grymni >= pack.cost;

  bool canPurchaseFloorSkinPack(FloorSkinPack pack) =>
      !state.ownedFloorSkinPacks.contains(pack.id) &&
      state.grymni >= pack.cost;

  void purchaseWallSkinPack(WallSkinPack pack) {
    if (!canPurchaseWallSkinPack(pack)) return;
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - pack.cost,
      totalSpent: state.totalSpent + pack.cost,
      ownedWallSkinPacks: {...state.ownedWallSkinPacks, pack.id},
    ));
  }

  void purchaseFloorSkinPack(FloorSkinPack pack) {
    if (!canPurchaseFloorSkinPack(pack)) return;
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - pack.cost,
      totalSpent: state.totalSpent + pack.cost,
      ownedFloorSkinPacks: {...state.ownedFloorSkinPacks, pack.id},
    ));
  }

  /// Apply (or reset) the wall skin on a single placed room.
  /// Pass [skinId] == [kWallSkinFreeId] or null to revert to tier default.
  void applyRoomWallSkin(String roomId, String? skinId) {
    final idx = state.placedRooms.indexWhere((r) => r.id == roomId);
    if (idx < 0) return;
    if (skinId != null &&
        skinId != kWallSkinFreeId &&
        !state.ownedWallSkinPacks.contains(skinId)) {
      return;
    }
    final rooms = List<PlacedRoom>.from(state.placedRooms);
    rooms[idx] = rooms[idx].copyWith(
      wallSkinId: skinId == kWallSkinFreeId ? null : skinId,
      clearWallSkin: skinId == null || skinId == kWallSkinFreeId,
    );
    _updateStateAndSync(state.copyWith(placedRooms: rooms));
  }

  /// Apply (or reset) the floor skin on a single placed room.
  void applyRoomFloorSkin(String roomId, String? skinId) {
    final idx = state.placedRooms.indexWhere((r) => r.id == roomId);
    if (idx < 0) return;
    if (skinId != null &&
        skinId != kFloorSkinFreeId &&
        !state.ownedFloorSkinPacks.contains(skinId)) {
      return;
    }
    final rooms = List<PlacedRoom>.from(state.placedRooms);
    rooms[idx] = rooms[idx].copyWith(
      floorSkinId: skinId == kFloorSkinFreeId ? null : skinId,
      clearFloorSkin: skinId == null || skinId == kFloorSkinFreeId,
    );
    _updateStateAndSync(state.copyWith(placedRooms: rooms));
  }

  // ─── Corridors ────────────────────────────────────────────────────────

  int corridorCostPerTile({bool wide = false}) => wide ? 90 : 50;

  int corridorCost(List<({int col, int row})> tiles, {bool wide = false}) =>
      tiles.length * corridorCostPerTile(wide: wide);

  bool canPlaceCorridor(List<({int col, int row})> tiles, {bool wide = false}) =>
      tiles.isNotEmpty && state.grymni >= corridorCost(tiles, wide: wide);

  void placeCorridor(
    List<({int col, int row})> tiles, {
    bool wide = false,
  }) {
    if (!canPlaceCorridor(tiles, wide: wide)) return;
    final cost = corridorCost(tiles, wide: wide);
    final id = 'corridor_${DateTime.now().microsecondsSinceEpoch}';
    final corridors = List<PlacedCorridor>.from(state.placedCorridors)
      ..add(PlacedCorridor(id: id, tiles: tiles, wide: wide));
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni - cost,
      totalSpent: state.totalSpent + cost,
      placedCorridors: corridors,
    ));
  }

  void removeCorridor(String corridorId) {
    final corridor = state.placedCorridors.firstWhere(
      (c) => c.id == corridorId,
      orElse: () => throw StateError('Corridor not found: $corridorId'),
    );
    final refund = (corridorCost(corridor.tiles, wide: corridor.wide) * 0.5).floor();
    _updateStateAndSync(state.removeCorridor(corridorId).copyWith(
      grymni: state.grymni + refund,
    ));
  }

  // ─── Cheat / debug ────────────────────────────────────────────────────

  void addGrymni(int amount) {
    _updateStateAndSync(state.copyWith(
      grymni: state.grymni + amount,
      totalEarned: state.totalEarned + amount,
    ));
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

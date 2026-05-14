# PixelCode — Roadmap та План Реалізації

> Високорівневе ТЗ і трекер прогресу. Базується на архітектурній стратегії з [STRATEGY.md](STRATEGY.md).
> Кожен пункт має статус і прив'язку до фази/кварталу.
>
> **Буфер на часові оцінки:** дати тут — "early estimate" для соло-розробника. Враховуй резерв часу для розчистки залежностей та неочікуваних проблем.

## Статуси

- `[DONE]` — реалізовано і працює
- `[WIP]` — в активній роботі
- `[PARTIAL]` — каркас є, треба завершити дроти
- `[TODO]` — заплановано, ще не почали
- `[FUTURE]` — після 2027, залежить від зовнішніх умов (залізо, моделі)

---

## A. Платформа і ядро (Foundation)

Базовий шар: процеси, транспорт, мережа, міжплатформеність. Здебільшого готовий.

| Компонент | Статус | Файли |
|---|---|---|
| Flutter cross-platform клієнт (macOS/Win/Linux/iOS/Android) | `[DONE]` | [pubspec.yaml](../pubspec.yaml) |
| Node.js + TypeScript сервер | `[DONE]` | [server/package.json](../server/package.json) |
| Server/client split (клієнт не спавнить сервер) | `[DONE]` | [server/src/server.ts](../server/src/server.ts) |
| Launcher daemon з respawn-on-75 | `[DONE]` | [server/src/launcher.ts](../server/src/launcher.ts) |
| `pixelcode-server` CLI | `[DONE]` | [server/bin/pixelcode-server.mjs](../server/bin/pixelcode-server.mjs) |
| Layered config (defaults → file → ENV → CLI) | `[DONE]` | [server/src/config.ts](../server/src/config.ts) |
| WebSocket transport | `[DONE]` | [server/src/server.ts](../server/src/server.ts), [lib/services/agent_ws_service.dart](../lib/services/agent_ws_service.dart) |
| mDNS/Bonjour LAN discovery | `[DONE]` | [lib/services/network_discovery_service.dart](../lib/services/network_discovery_service.dart) |
| Tailscale Funnel (OTA з будь-якої мережі) | `[DONE]` | [server/src/server.ts](../server/src/server.ts) |
| Real-time mirroring між пристроями | `[DONE]` | — |
| Shared SDK session між реконнектами | `[DONE]` | — |
| **PixelDock** (merged Launcher + admin app) — NavigationRail: DASH / SETUP / CONFIG / LOGS / CLIENTS; bearer SPAWN DAEMON; `launcher/` Flutter app видалено | `[DONE]` | 2026-05-09 — [server_admin/](../server_admin/) |
| **Kanban board persistence (per-project, atomic, debounced)** | `[DONE]` | 2026-05-02 — `~/.pixelcode/projects/{key}/board.json`, schema-versioned (v1 + v0 migration), atomic write (tmp+rename), debounced (250ms), tolerant loader з quarantine на corruption. Закриває P0 показстопер (раніше рестарт сервера витирав дошку). [server/src/board_persistence.ts](../server/src/board_persistence.ts), 14 unit-тестів |
| **Board sync — revision tracking + reconnect resync** | `[DONE]` | 2026-05-02 — monotonic `boardRevision` на кожній мутації; `board_get_state{since}` шле `board_state_unchanged` якщо клієнт current; tolerant payload validation (try/catch + isValidBoardColumn); client-side optimistic moves з auto-reconciliation. [server/src/server.ts](../server/src/server.ts), [lib/providers/task_board_provider.dart](../lib/providers/task_board_provider.dart). 7+11 нових тестів |
| **Roster validation + fire-mid-task cleanup + corrupt-state quarantine** | `[DONE]` | 2026-05-02 — `validateGameState` (unknown_role / manager_singleton / hardware/skill bounds / missing_api_key); `firedInstanceIds` для cleanup activeAgentTasks + `agent_fired` event; `classifyPersistedGameState` quarantines corrupt envelope замість silent re-broadcast garbage. [server/src/roster_validation.ts](../server/src/roster_validation.ts), 27 нових тестів |

**Що залишилось у цьому напрямку:** нічого критичного. Можна розглянути в майбутньому: cross-machine remote orchestration (WS-шар готовий, але UX-flow попереду); per-project broadcast scoping (наразі hypothetical — server один-на-PROJECT_CWD).

---

## B. Гра і економіка (Game Layer)

Поточний game loop працює end-to-end. Деякі бонуси/механіки ще не активні.

| Компонент | Статус | Файли |
|---|---|---|
| Hub-екран з анімованим пікселарт-офісом | `[DONE]` | [lib/widgets/canvas/](../lib/widgets/canvas/) |
| Z-sorted рендер 320×224, walk/type/read/idle анімації | `[DONE]` | [lib/widgets/canvas/pixel_office_painter.dart](../lib/widgets/canvas/pixel_office_painter.dart) |
| 6-тирова система спрайтів, 7 кадрів × 3 напрямки | `[DONE]` | [assets/characters/](../assets/characters/), [lib/widgets/canvas/pixel_sprites.dart](../lib/widgets/canvas/pixel_sprites.dart) |
| Меблі (столи, монітори, стільці, рослини) | `[DONE]` | [assets/furniture/](../assets/furniture/) |
| Hire/fire агентів за ролями (11 ролей: manager, tech-lead, coder, reviewer, tester, security, ui-ux-designer, llm-specialist, game-designer, strategy-keeper, character-artist) | `[DONE]` | [lib/widgets/](../lib/widgets/), [lib/models/game_economy.dart](../lib/models/game_economy.dart) |
| Kanban task board з drag-and-drop | `[DONE]` | [lib/widgets/board/task_board_panel.dart](../lib/widgets/board/task_board_panel.dart) |
| Real-time chat і activity feed | `[DONE]` | [lib/widgets/chat/](../lib/widgets/chat/) |
| Agent-level XP + skillCap progression | `[DONE]` | [lib/models/agent_level.dart](../lib/models/agent_level.dart) |
| 5-stat skill model (precision/insight/reliability/creativity/speed) | `[DONE]` | [lib/models/agent_level.dart](../lib/models/agent_level.dart) |
| Multi-tier model routing (Haiku/Sonnet/Opus) | `[DONE]` | [lib/models/agent_level.dart](../lib/models/agent_level.dart) |
| Grim currency + economy | `[DONE]` | [lib/models/game_economy.dart](../lib/models/game_economy.dart) |
| Office tiers (Garage → Campus) | `[DONE]` | — |
| Hardware upgrades (laptop → workstation) | `[DONE]` | — |
| Dungeon training з Haiku-суддею | `[DONE]` | [server/src/dungeon.ts](../server/src/dungeon.ts) |
| Task outcome rolls (bug/crit/incomplete) | `[DONE]` | [lib/services/task_outcome.dart](../lib/services/task_outcome.dart) |
| Energy meter (daily token meter) | `[DONE]` | [lib/widgets/energy/energy_meter.dart](../lib/widgets/energy/energy_meter.dart) |
| Quest line / quest persistence (Game Master mode foundation) | `[DONE]` | [server/src/quest/](../server/src/quest/), [lib/services/facilitator_output_persistence_service.dart](../lib/services/facilitator_output_persistence_service.dart) — data shapes + persistence + Game Master output + WS endpoint `facilitator_start` + client onboarding (picker→intake→kanban) wired (див. [Facilitator System](FACILITATOR_SYSTEM.md)); LLM-backed generators попереду |
| **Style picker UI** (вибір facilitator-а на старті проєкту) | `[DONE]` | [lib/screens/facilitator/facilitator_picker_screen.dart](../lib/screens/facilitator/facilitator_picker_screen.dart) + [lib/screens/facilitator/facilitator_intake_screen.dart](../lib/screens/facilitator/facilitator_intake_screen.dart) wired через [lib/widgets/facilitator/launch_facilitator_onboarding.dart](../lib/widgets/facilitator/launch_facilitator_onboarding.dart) у project selector |
| **Lexicon swap layer** (kanban labels через style.lexicon) | `[TODO]` | Q3 2026 |
| Shop panel (скіни, меблі, апгрейди) | `[DONE]` | [lib/widgets/shop/](../lib/widgets/shop/) |
| Multi-project / session profiles | `[DONE]` | [lib/models/session_profile.dart](../lib/models/session_profile.dart) |
| Easter eggs (Arkanoid, dungeon crawler) | `[DONE]` | [lib/widgets/easter_eggs/](../lib/widgets/easter_eggs/) |
| Arkanoid візуальний reskin під office-style | `[DONE]` | 2026-05-06 — Stage 1 (bg + bricks): фон → 16-px dark navy checker + vignette; cells 32×16 (13×8 grid збережено); 1-px cyan-rim силует-сепаратор. Stage 2a (powerups): pixel-art icon-glyph замість monospace-text у falling-pill; pill bumped 34×13 → 38×18; 8 кольорів узгоджено з skinDefault.clothes; HUD-chips і laser-bullet (cyan `#00C0D1`) синхронізовано. Stage 2b (glyph rescale): `_paintGlyph` рендерить `#` як 2×2 px (`scale=2.0`); bitmap-сітки 9×4..7 переписано → glyph занимає ~70-80% корисної площі pill-а. Stage 2c (collision feedback): brick hit-flash alpha 0.05 → 0.12; 2×2 px debris (4 normal, 8 blast) з 7-tick gravity-fall у кольорі brick-а; 2-px paddle rim flash на bounce (5 tick); gold pillars+wash+ring на sticky catch (6 tick); 3-frame fading ball-trail. Stage 3 (materials only — geometry preserved): зовнішня frame усіх 5 brick-типів → 4-шарна полірована плита (`#C8C8D8`/`#7A7A8C`/`#4A4A5A`/`#1A1A28` + L/R edges); внутрішні акценти переведено на crystal-shading через `_paintCrystalRect` (light/mid/dark slices + 1-px specular). Geometric silhouettes збережено: desk+monitor screen (8 row-tints з clothes), whiteboard sheet (ice + crack lines), trophy cup (citrine 3-row), server-rack shelves + 2×2 LED-кристали (cyan/red), safe = stone+steel-tint без кристала, central lock-stub `#1A1A28` + corner rivets. [lib/widgets/easter_eggs/arkanoid_game.dart](../lib/widgets/easter_eggs/arkanoid_game.dart) |
| Logo Path DSL (анімація логотипу) | `[DONE]` | [lib/services/logo_path_program.dart](../lib/services/logo_path_program.dart) |
| **Room adjacency bonuses** (Workstation↔Server Room і т.д.) | `[DONE]` | Per-pair engine: `areRoomsAdjacent` + `computeAdjacencyBonusPercent` — [lib/models/game_economy.dart](../lib/models/game_economy.dart). `_buildRoomEffects()` застосовує глобальні модифікатори + adjacency пари. Ghost overlay `+N%` / `−N%` label — [lib/widgets/canvas/pixel_office_painter.dart](../lib/widgets/canvas/pixel_office_painter.dart) + [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart). 23 нових тести. |
| **Break Room morale system** (+20% при відпочинку) | `[DONE]` | `seatRestMultiplier` — вбудовано у `_buildRoomEffects()`; breakRoom↔lounge synergy doubles multiplier |
| **Server Room cable proximity penalty** | `[DONE]` | `−5%` speed when serverRoom placed >8 tiles від всіх workstations — `_buildRoomEffects()` |
| **Manager Meeting Room dispatch boost** | `[TODO]` | Q2–Q3 2026 — adjacency pair обчислюється (`meetingRoom↔workstation → +5%`), hook до task-dispatch latency ще не зроблено |
| **Manager auto-dispatch MVP** (facilitator-tasks → агенти автоматично) | `[DONE]` | 2026-05-02 — `pickAssignee` deterministic: role match → load cap (MAX_AGENT_LOAD=2) → lowest load → highest skill → stable id tiebreak. Triggered after `board_seed_batch` для tasks з `taskType="facilitator"`. [server/src/auto_dispatcher.ts](../server/src/auto_dispatcher.ts), 17 нових тестів. **MVP без LLM** — smart LLM-routing залишається follow-up |
| **Agent workplace status** (`WorkplaceStatus.unassigned/assigned`; нові наймані агенти чекають у lobby-зоні без столу; `CharState.waiting`; `coding/testing/debugging` отримують `−0.25` success rate; Foreman показує desk-bubble; badge "Потрібен стіл" у Roster) | `[DONE]` | Q2 2026 — prerequisite для B.1 → D.1 integration; [lib/models/game_economy.dart](../lib/models/game_economy.dart), [lib/widgets/canvas/office_game_state.dart](../lib/widgets/canvas/office_game_state.dart), [lib/services/task_outcome.dart](../lib/services/task_outcome.dart) |
| **Diagnostics panel polish** | `[DONE]` | [lib/widgets/debug/](../lib/widgets/debug/) |
| **Game Designer hireable role** (мета-роль для дизайну механік/економіки/F2P-петель) | `[DONE]` | [server/src/agents.ts](../server/src/agents.ts), [lib/models/game_economy.dart](../lib/models/game_economy.dart). Поза-плановий додаток (рівень 2 за [STRATEGY §0](STRATEGY.md#0-реалістична-калібровка-станом-на-2026-04-26)); обґрунтування: meta-loop "гра дизайнить себе" + контент-хук. |
| **Strategy Keeper hireable role** ("Неповертайло" — reality-check голос проти drift від плану) | `[DONE]` | [server/src/agents.ts](../server/src/agents.ts), [lib/models/game_economy.dart](../lib/models/game_economy.dart). Поза-плановий додаток (рівень 2); обґрунтування: solo-dev needs скептика проти wishful thinking, інакше план дрейфує. |
| **Character Artist hireable role** ("Піксельмейстер" — створює нові спрайти, скін-палітри, NPC-концепти; 11-та і остання базова роль) | `[DONE]` | 2026-05-10 — [server/src/agents.ts](../server/src/agents.ts) (roleTemplate + roleCatalog + creative capability profile + 13 MCP tools у allowed list); [lib/models/game_economy.dart](../lib/models/game_economy.dart) (RoleCatalogEntry hire 500/salary 55, initialSkills 1/4/6/1/1, Color Soul passive); [lib/models/agent_level.dart](../lib/models/agent_level.dart) (isCreative includes character-artist); [lib/widgets/canvas/character_skins.dart](../lib/widgets/canvas/character_skins.dart) (8 skins × 1 new palette = 8 SkinPalette блоків); [lib/widgets/chat/](../lib/widgets/chat/) (5 switch updates: nickname/icon/color/gradient); [.claude/agents/character-artist.md](../.claude/agents/character-artist.md) (sub-agent definition with hard IP-provenance lock); 8 нових тестів (727 total). Передумова для D (Custom Agent Spawn) — повний 11-роль roster повинен існувати ДО UI custom-spawn-у. Передумова для E.2 (marketplace originality check). |
| **Pixel-art tooling for character-artist** (`add_character_skin` / `preview_skin_palette` / `diff_against_existing_palettes` MCP tools) | `[DONE]` | 2026-05-10 — [mcp-game-assets/src/tools/](../mcp-game-assets/src/tools/) (3 нових tool-и + 3 lib-модулі: color, skin_io, room_themes). 44 тести: hex parse, RGB Euclidean distance, WCAG contrast, balanced-paren Dart parser, idempotent insert, real-data smoke test проти `lib/widgets/canvas/character_skins.dart`. PNG render + animation strip — навмисно deferred до E.2 (require Flutter renderer integration). |
| **Permissions runtime invariant** (`permissionMode: "bypassPermissions"` обов'язковий для всіх SDK query() у `server/src/`) | `[DONE]` | 2026-05-10 — інваріант закріплено у [docs/STRATEGY.md](STRATEGY.md) §"Permissions runtime: bypass-by-default" і регресійному тесті [server/test/permissions_invariant.test.ts](../server/test/permissions_invariant.test.ts). 2 раніших drift-и (`acceptEdits` у `claude_backend.ts`, `facilitator/llm_generators.ts`) нормалізовано. Дизайнерські обмеження виражаються через `tools: [...]` allowlist, не через runtime-prompt-и. |
| **Done-column UX v2 — повна історія завершених задач** (compact card mode у колонці; stats-header `"N задач · X XP · avg Y хв"`; ліміт 20 + кнопка "Вся історія"; окремий Activity Log drawer на desktop / full-screen на mobile з групуванням за датою (Сьогодні/Вчора/тиждень/older); фільтри за агентом / outcome / роллю; сортування за completedAt/XP/тривалістю; текстовий пошук; **schema-міграція v6**: додати `completedAt: DateTime?` і `outcome: String?` поля в `TaskCard` + `board_persistence` migration v1→v2; виставляти `completedAt` у `moveTask → done` і `outcome` після rollOutcome) | `[TODO]` | Q3 2026 — дизайн ухвалено 2026-05-06 (ui-ux-designer): kanban Done = preview + spatial overview, повна історія = окремий Activity Log (Linear/Jira/GitHub паттерн). Передумова: `board_move_task → done` тепер flush-ить board.json синхронно (без 250ms debounce window) — [server/src/server.ts](../server/src/server.ts) `case "board_move_task"`/`"board_update_task"`. Файли: [lib/models/task_board.dart](../lib/models/task_board.dart), [lib/widgets/board/task_board_panel.dart](../lib/widgets/board/task_board_panel.dart), [lib/providers/task_board_provider.dart](../lib/providers/task_board_provider.dart), [server/src/board_persistence.ts](../server/src/board_persistence.ts), новий `lib/widgets/board/activity_log_panel.dart` |

### B.1 Build System v2 (Q2 2026)

Перебудова "каструбатого" rail+tray меню в єдиний build hub з drag-place ghost-preview, room templates, корідорами і per-room skin overrides. Дизайн затверджений (синтез ui-ux-designer + game-designer 2026-04-26): ліва NavigationRail на desktop / bottom sheet на mobile, NPC-будівельник як entry point, 1-finger placement + 2-finger pan на mobile, drag-A→B corridors. Заводиться двома етапами:

**Stage 1 — каркас (поточний цикл).**

| Компонент | Статус | Файли / Notes |
|---|---|---|
| Schema bump v5→v6 (PlacedRoom rotation, per-room wall/floor skin IDs, PlacedCorridor, RoomTemplate model, WallSkinPack/FloorSkinPack model, ownedWall/FloorSkinPacks sets) + soft additive migration v5→v6 | `[DONE]` | [lib/models/game_economy.dart](../lib/models/game_economy.dart), [lib/services/game_persistence_service.dart](../lib/services/game_persistence_service.dart) |
| Прибрати legacy `OfficePreset` / Presets категорію з UI + provider | `[DONE]` | модель, провайдер і `pixel_office_painter` зачищені; `build_picker_rail.dart` видалено |
| Foreman NPC polish (onboarding chevron + hover speech bubble "Збудуємо?" + persistence) | `[DONE]` | [lib/widgets/canvas/foreman_overlay_painter.dart](../lib/widgets/canvas/foreman_overlay_painter.dart), [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart). Foreman вже існував як entry point; додано onboarding cues + diegetic tooltip |
| Новий BuildMenu shell (NavigationRail desktop / bottom sheet mobile, 6 секцій: Rooms / Templates / Corridors / Walls / Floors / Decor) | `[DONE]` | [lib/widgets/canvas/build_menu.dart](../lib/widgets/canvas/build_menu.dart). Stage 1 видає тільки Rooms; решта секцій — placeholder "скоро у Stage 2" |
| BuildMenu mount: replaces ChatPanel у лівому 440dp слоті на десктопі (build state ⇒ `buildModeProvider`); мобільна форма лишається bottom-sheet поверх canvas | `[DONE]` | [lib/providers/build_mode_provider.dart](../lib/providers/build_mode_provider.dart), [lib/screens/hub/hub_screen.dart](../lib/screens/hub/hub_screen.dart). Канвас на десктопі більше не звужується — займає всю праву колонку повністю |
| Listener-based gesture layer (1-finger placement vs 2-finger pan, hover ghost, cursor variants, R/Shift+R rotate) | `[DONE]` | [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart). KeyboardListener (R/Shift+R rotate, Esc cancel); hover ghost via MouseRegion._updateBuildGhost; two-step tap placement |
| Room placement flow (drag-place, snap-to-grid, ghost color valid/invalid, place bar `[X][↺][↻][✓ ₲N]`, adjacency hints зеленою пунктиром у preview) | `[DONE]` | [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart). _PlaceBar float widget; ghostRotation у BuildModeState + rotateClockwise/CCW; rotation-aware _ghostIsValid; placeRoom приймає rotation |

**Stage 2 — контент і міграція (наступний цикл).**

| Компонент | Статус | Notes |
|---|---|---|
| Room Templates каталог (6–8 hardcode шт., snap-to-existing-edge placement, прозоре pricing breakdown `₲X = base + furniture − N%`) | `[DONE]` | 2026-05-11 — Stage 3a добив snap-to-edge follow-up; каталог розширено до 9 шаблонів, з них 3 нові work-focused (`tpl_starter_cube`, `tpl_deep_focus`, `tpl_team_hub`) у [lib/models/game_economy.dart](../lib/models/game_economy.dart). `placeRoomTemplate()` + UI секція + pricing breakdown — [lib/providers/game_economy_provider.dart](../lib/providers/game_economy_provider.dart), [lib/widgets/canvas/build_menu.dart](../lib/widgets/canvas/build_menu.dart) (`_TemplateCard`). Multi-room template (наприклад Open Space з 4 робочими місцями) лишається `[TODO]` у Stage 3b — потребує розширення `RoomTemplate.baseRoom` (singular) → multi-room layout. |
| Corridors (drag A→B, 1-tile @ ₲50/tile, 2-tile @ ₲90/tile + speed bonus, успадковує тему сусідньої кімнати) | `[DONE]` | Two-tap A→B placement, L-path via Map dedup, wide/narrow toggle (+3% speed), gold/orange tile render, anchor dot, `PlacedCorridor` model, `placeCorridor` + guards в провайдері, Corridors секція у BuildMenu з інструкцією. 14 нових тестів. Pathfinding (агенти реально ходять) — follow-up. |
| Wall/Floor skin packs (Classic Free default + 3 paid паки на старті, per-room swatch picker з live canvas preview) | `[DONE]` | `wallSkinPackCatalog` / `floorSkinPackCatalog` (4+4 паки) — [lib/models/game_economy.dart](../lib/models/game_economy.dart). `purchaseWallSkinPack/purchaseFloorSkinPack/applyRoomWallSkin/applyRoomFloorSkin` — [lib/providers/game_economy_provider.dart](../lib/providers/game_economy_provider.dart). Per-room `_themeForRoom()` у painter — [lib/widgets/canvas/pixel_office_painter.dart](../lib/widgets/canvas/pixel_office_painter.dart). Swatch picker + room selector у BuildMenu Walls/Floors — [lib/widgets/canvas/build_menu.dart](../lib/widgets/canvas/build_menu.dart). `selectedPlacedRoomId` у BuildModeState. 16 нових тестів (672 total). |
| Shop → BuildMenu furniture/plants migration (видалити таб `Меблі` з shop_panel, redirect deeplink, лишити tier upgrade у Shop) | `[DONE]` | [lib/widgets/canvas/build_decor_section.dart](../lib/widgets/canvas/build_decor_section.dart) + `BuildSection.decor` у [build_menu.dart](../lib/widgets/canvas/build_menu.dart). Shop тепер 5 табів, `shopTabFurniture` видалено, `shopTabDonation = 4` |
| Adjacency bonuses fully wired (live `+%` label на ghost preview) | `[DONE]` | `areRoomsAdjacent` + `computeAdjacencyBonusPercent` у game_economy.dart; `_buildRoomEffects()` з per-pair engine; ghost label у PixelOfficePainter + agent_canvas._adjacencyLabel(); 23 нових тести (656 total) |

**Залежності:** Stage 2 corridors залежать від pathfinding-системи "агенти реально ходять" (зараз `[TODO]` неявно — позначено в [office_design.md](office_design.md)). Якщо pathfinding ще не готовий до моменту stage 2, corridors поки що декоративні (без speed bonus), але візуально присутні.

**Stage 3a — швидке зручне масштабування (2026-05-11).** Дизайн затверджений синтезом game-designer + ui-ux-designer:

| Компонент | Статус | Файли |
|---|---|---|
| Rotation-aware snap (`footprintWidth/Height` для targets і ghost-а) | `[DONE]` | 2026-05-11 — [lib/widgets/canvas/snap_logic.dart](../lib/widgets/canvas/snap_logic.dart) (`snapGhostDistToRoom`), [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart) (`_updateBuildGhost` тепер передає `mode.ghostWidth/ghostHeight`). Раніше snap ламався при rotated target rooms. |
| Corridor snap (ghost прилипає до PlacedCorridor tile-ів; room-snap priority через `kCorridorSnapPenalty`) | `[DONE]` | 2026-05-11 — [lib/widgets/canvas/snap_logic.dart](../lib/widgets/canvas/snap_logic.dart) приймає `placedCorridors`, обчислює відстань до tile-anchor-а з 100.0 penalty щоб room-snap завжди вигравав tie. |
| Wall-to-door auto-creation (геометричний прохід на shared edge між кімнатами або між кімнатою і коридором) | `[DONE]` | 2026-05-11 — [lib/widgets/canvas/room_doors.dart](../lib/widgets/canvas/room_doors.dart) (`computeRoomDoors` + `RoomDoorSet`), [lib/widgets/canvas/room_sprites.dart](../lib/widgets/canvas/room_sprites.dart) (`_drawRoomBorder` per-tile segment skipping). Без data-моделі / migration — gap емерджентний з layout-у, removeRoom авто-закриває прохід. Безкоштовно (decision-friction вбиває snap-механіку). |
| Work-themed room templates (`tpl_starter_cube`, `tpl_deep_focus`, `tpl_team_hub`) | `[DONE]` | 2026-05-11 — [lib/models/game_economy.dart](../lib/models/game_economy.dart) (`roomTemplateCatalog`). 3 нові пресети з workstation/meetingRoom base + furniture з кулера/шафи/постера. |
| Тести Stage 3a | `[DONE]` | 2026-05-11 — [test/widgets/snap_logic_test.dart](../test/widgets/snap_logic_test.dart) (rotation-aware + corridor snap + room>corridor priority), [test/widgets/room_doors_test.dart](../test/widgets/room_doors_test.dart) (8 сценаріїв: isolated/flush/partial-overlap/rotated/corridor/wide-corridor), [test/models/room_template_test.dart](../test/models/room_template_test.dart) (нові 3 templates валідні). |

**Stage 3b — Room/Zone taxonomy + canvas-beyond-office (2026-05-11).** Дизайн затверджено синтезом game-designer + ui-ux-designer; реалізовано в одному раунді разом з тестами.

| Компонент | Статус | Файли |
|---|---|---|
| **Room/Zone taxonomy** (`enum RoomCategory { room, zone }` + `RoomTypeExt.category`; rooms = enclosed walls; zones = open feature areas) | `[DONE]` | 2026-05-11 — [lib/models/game_economy.dart](../lib/models/game_economy.dart). Workstation/breakRoom/meetingRoom/serverRoom/openSpace → Room; lounge/gym/cinema/pool/miniGolf → Zone. |
| **New RoomType `openSpace`** (4×3 з 4 робочими столами, ₲1200, max 3, Room category) | `[DONE]` | 2026-05-11 — `_drawOpenSpace` у [lib/widgets/canvas/room_sprites.dart](../lib/widgets/canvas/room_sprites.dart); 4 extra DeskStation у `_buildExtraStations` [lib/widgets/canvas/office_game_state.dart](../lib/widgets/canvas/office_game_state.dart). Bundle ціна (₲1200) на 25% дешевша за 4 × workstation (₲1600). |
| **Renaming + description polish** (Воркстейшн, Кімната відпочинку, Переговорна, Серверна, Опен-спейс, Рекреація замість Скейт-куток; описи переписані) | `[DONE]` | 2026-05-11 — [lib/models/game_economy.dart](../lib/models/game_economy.dart) `RoomTypeExt.nameUk` + `.description`. Enum identifier-и не чіпані щоб не зламати JSON-persisted `type.index`. |
| **Adjacency engine rewire** (zones receive-only через `_adjacencyContribution` guard; нові пари: openSpace↔meetingRoom +5%, openSpace↔workstation +5%, openSpace↔serverRoom +5%, breakRoom↔gym +5%; one-way breakRoom→lounge замість симетричної) | `[DONE]` | 2026-05-11 — [lib/models/game_economy.dart](../lib/models/game_economy.dart) `_adjacencyContribution`. ServerRoom isolation penalty тепер враховує openSpace як workstation-hub. 8 нових тестів. |
| **Buildable canvas-поза-офісом** (foundation grid +2 тайли буфер; tri-state ghost validity: valid/pendingExpand/invalid; amber ghost `#FFB020`; combined expand+place як одна транзакція у Place bar) | `[DONE]` | 2026-05-11 — `OfficeLevel.computeExpansionPlan` + `PendingExpansionPlan` model у [lib/models/game_economy.dart](../lib/models/game_economy.dart). `_drawFoundationBuffer` + amber ghost у [lib/widgets/canvas/pixel_office_painter.dart](../lib/widgets/canvas/pixel_office_painter.dart). `_GhostStatus` + `_ghostStatus` + `_bufferDims` у [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart). `placeRoom`/`placeRoomTemplate(expansionStepsToBuy:)` атомарна транзакція у [lib/providers/game_economy_provider.dart](../lib/providers/game_economy_provider.dart). Cap: 2 тайли буфер, clamped tier-max. |
| **Door management — close/open** (`PlacedRoom.closedDoors: Set<DoorTile>` + JSON migration soft-additive; `computeRoomDoors` фільтрує closed; `toggleDoor(roomId, col, row)` у provider) | `[DONE]` | 2026-05-11 — [lib/models/game_economy.dart](../lib/models/game_economy.dart) (`DoorTile typedef`, `closedDoors` поле, toJson omits empty, fromJson defaults to {}). [lib/widgets/canvas/room_doors.dart](../lib/widgets/canvas/room_doors.dart) субтракція closedDoors. `toggleDoor` validates border tile + within footprint. UI long-press → toggleDoor — follow-up. |
| **Build menu: Rooms/Zones sectioning + Zone badge + dashed zone-ghost** | `[DONE]` | 2026-05-11 — [lib/widgets/canvas/build_menu.dart](../lib/widgets/canvas/build_menu.dart) `_SectionLabel` headers + amber "Зона" pill у `_RoomCard`. Dashed border у painter `drawGhostRect(..., dashed: type.category == zone)`. |
| **Comprehensive tests for Stage 3b** | `[DONE]` | 2026-05-11 — [test/models/room_taxonomy_test.dart](../test/models/room_taxonomy_test.dart) (29 сценаріїв: category split, naming, openSpace economy, JSON roundtrip, adjacency rewire, expansion plan). [test/providers/expansion_placement_test.dart](../test/providers/expansion_placement_test.dart) (10 сценаріїв: combined transaction, multi-step, wallet guard, toggleDoor border/interior/footprint). [test/widgets/room_doors_test.dart](../test/widgets/room_doors_test.dart) розширено closedDoors filtering. Всі 886 тестів проходять. |

**Stage 3b — polish round (2026-05-11 same day).** Закриває UX feedback після першого захоплення Stage 3b:

| Компонент | Статус | Файли |
|---|---|---|
| **Bigger work rooms** (openSpace 4×3→**5×4 з 6 столами**, ₲1200→₲1800; новий `teamFloor` 7×5 з 12 столами, ₲4500, max 2) | `[DONE]` | 2026-05-11 — [lib/models/game_economy.dart](../lib/models/game_economy.dart) `RoomType.teamFloor` appended; size/cost/maxPerOffice tables; description оновлено. Game-designer call: 1 → 6 → 12 desk-ladder. |
| **Sprite rewrite** (`_drawDeskHall` shared painter для openSpace+teamFloor з configurable cols/rows + pod origins) | `[DONE]` | 2026-05-11 — [lib/widgets/canvas/room_sprites.dart](../lib/widgets/canvas/room_sprites.dart). `_kOpenSpacePodOrigins` (6 pods 3×2 grid), `_kTeamFloorPodOrigins` (12 pods 4×3 grid). Окремий sprite-функції видалено, тепер один `_drawDeskHall`. |
| **Extra DeskStations**: 6 для openSpace, 12 для teamFloor | `[DONE]` | 2026-05-11 — [lib/widgets/canvas/office_game_state.dart](../lib/widgets/canvas/office_game_state.dart) `_buildExtraStations`. Координати pod-ів синхронізовані з sprite origins. |
| **Adjacency hub set rewire** (workstation/openSpace/teamFloor як симетрична hub-група; новий guard `newType != existing && deskHubs.contains(existing)` запобігає self-pair) | `[DONE]` | 2026-05-11 — [lib/models/game_economy.dart](../lib/models/game_economy.dart) `_adjacencyContribution`. serverRoom isolation penalty тепер враховує всі 3 hub-типи. 5 нових тестів. |
| **Dynamic foundation buffer** (`max(kBuildBufferTiles=2, ghostWidth+1)`, capped tier max — тепер навіть teamFloor 7×5 може ghost-витиснутись за стіну і attach-итись) | `[DONE]` | 2026-05-11 — [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart) `_bufferDims` + `_ghostStatus` синхронізовані з тим самим helper. |
| **Beefed-up buffer visual + banner** (амбер `#FFB020` 22% wash + dark `#1A1410` base + `+` 2px crossbars + solid amber boundary line + top-canvas `_BuildBanner` widget "Тягни кімнату у золоту зону за стіною — офіс розшириться сам") | `[DONE]` | 2026-05-11 — [lib/widgets/canvas/pixel_office_painter.dart](../lib/widgets/canvas/pixel_office_painter.dart) `_drawFoundationBuffer`. `_BuildBanner` widget у [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart). Banner також показує fallback "Купи апгрейд офісу" коли buffer = 0. |
| **Pan-to-peek + grab cursor** (build-mode `InteractiveViewer.boundaryMargin: 160px` дозволяє драгати офіс щоб побачити foundation buffer; `SystemMouseCursors.grab`/`grabbing` без ghost, `cell` коли ghost валідний, `forbidden` коли invalid; графітовий `#13141A` backdrop у build mode; transform-reset на entry/exit) | `[DONE]` | 2026-05-11 — [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart) `Listener` + `MouseRegion(cursor:)` + `buildModeCursor` pure helper. Дизайн затверджено синтезом game-designer + ui-ux-designer (clean mode separation: drag = move ghost OR pan, not both; Escape для deselect). Тести: [test/widgets/build_mode_cursor_test.dart](../test/widgets/build_mode_cursor_test.dart) 7 сценаріїв. |

**Stage 3c — Ghost reason surfacing + doubled buffer (2026-05-12).** Закриває "мовчазний червоний ghost" feedback gap після proxy-user-тесту: дев сам не зміг інтуїтивно поставити кімнату, тому що `_ghostStatus` мав 4 invalid-причини і жодну не surface-ив. Архітектурна розвилка "fixed-tier shells vs free-form editor" обговорена з командою (strategy-keeper + game-designer + ui-ux-designer); консенсус — не пітнути, sunk cost 80% у free-form, фікс UX-feedback дешевший за pivot. Decision gate: тестуй з оновленим feedback; якщо все ще фрустраційно — Stage 4 ріже expansion і вводить fixed-tier shells.
| Компонент | Статус | Файли |
|---|---|---|
| **Doubled foundation buffer** (`kBuildBufferTiles: 2→4` — вільний простір навколо офісу де можна ghost-attach-ити нову кімнату; ghost не утискається до стіни, видно куди тулити) | `[DONE]` | 2026-05-12 — [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart) `kBuildBufferTiles` constant. Dynamic buffer (`max(4, ghostSize+1)`) лишається — це floor, не ceiling. |
| **Ghost invalid-reason surfacing** (`GhostInvalidReason` enum з 6 причинами: outOfBounds / overlap / blocked / tierCeiling / bufferOverrun / insufficientGrymni; `_GhostStatus.invalid(reason)` несе її через `_ghostStatus`; `_PlaceBar` показує reason-specific text замість generic "не вміщується") | `[DONE]` | 2026-05-12 — [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart) `GhostInvalidReason` enum + `ghostInvalidReasonLabel` pure helper. `_PlaceBar.invalidReason` plumb. Дизайн: actionable text ("потрібен апгрейд офісу", "не вистачає ₲", "занадто далеко — підсуньте ближче") замість мовчазного червоного rect. Тести: [test/widgets/ghost_invalid_reason_label_test.dart](../test/widgets/ghost_invalid_reason_label_test.dart) 8 сценаріїв включно з coverage guard (кожен enum має non-empty non-fallback label). |

**Stage 3c follow-up — defer-ed (Q3+ 2026).** Що навмисно не зайшло у Stage 3b/3c:

| Компонент | Статус | Notes |
|---|---|---|
| **Stage 4 decision gate — fixed-tier shells vs free-form** | `[TRIGGERED 2026-05-14]` | 2026-05-12 OPEN → 2026-05-14 TRIGGERED після playtest-у власника. Дві model-mismatch помилки підряд (клік на amber-buffer = "купую цю клітинку"; купівля = "ряд/стовбчик, а не тайл") підтвердили що per-row/col expansion не intuit-ується навіть автором механіки. Ріжемо expansion mechanic, фіксуємо canvas-grid per tier, залишаємо furniture+room-placement editor (Hex "IKEA, не Minecraft"). Implementation phases — Stage 4 нижче. |
| **Mobile build gestures** (long-press 200ms; edge-scroll; bottom sheet collapse) | `[TODO]` | Q3 2026 — на користувача немає сигналу про mobile use case зараз; defer-ed до coverage signal. |
| **Door management UI** (long-press на placedRoom → "Керувати проходами" → список дверей з close/open toggle) | `[TODO]` | Q3 2026 — data + provider toggleDoor готові у Stage 3b; треба тільки UI surface. |
| **Multi-room templates** ("Open Space"-style bundle з кількох кімнат як один template; `RoomTemplate.baseRoom` → multi-room layout) | `[TODO]` | Q4 2026 — openSpace як новий RoomType (Stage 3b) вирішує конкретний UX-кейс ("4 робочі столи в одній кімнаті") без model extension. Multi-room templates тільки якщо з'явиться кейс що не вкладається у single-room. |
| **BFS reachability validation** (заборонити isolated rooms) | `[TODO/N/A]` | 2026-05-11 — re-evaluated: при auto-door geometric model з Stage 3a кожна суміжна кімната автоматично reachable; для standalone first-room placement обмеження зайве. Може повернутись як explicit constraint якщо pathfinding system введе actual wall collision. |
| **Stage 5 — Sims-style lot terrain per tier** | `[FUTURE]` | Q4 2026 — кожен з 5 tier-ів отримує hand-crafted shell з immovable terrain (озеро, дерева, рельєф) + 1-2 pre-built кімнат як стартова "сцена". Гравець добудовує/перебудовує навколо. Pre-condition: Stage 4 [DONE] + раунд з game-designer (adjacency feasibility per terrain layout — щоб immovable features не блокували serverRoom isolation чи openSpace hub-pairing) + ui-ux-designer/Назар (5 lot-scene art-direction). НЕ запускати paralel зі Stage 4 — scope creep ризик. |

**Stage 4 — Fixed-tier shells (rip експансії, 2026-05-14).** План A після strategy-keeper audit: per-tier fixed grid, expansion mechanic видаляється повністю. Room placement, snap, doors, adjacency engine — переносяться без змін. Schema v5→v6 migration: legacy saves з `expansionsBought>0` колапсуються у tier max-grid + one-time grymni refund за вже куплені steps (щоб гравець не відчув втрату інвестиції).

| Компонент | Статус | Файли (очікувані) |
|---|---|---|
| **Model rip** (`OfficeExpansion` removed; `OfficeLevel.expansions` → видалити; `effectiveCols/Rows` → просто `gridCols/Rows = baseCols/baseRows`; `playableTiles` const per tier; `PendingExpansionPlan` + `computeExpansionPlan` видалити) | `[TODO]` | [lib/models/game_economy.dart](../lib/models/game_economy.dart) |
| **Provider rip** (`canBuyOfficeExpansion`, `buyOfficeExpansion`, `expansionStepsToBuy` параметр у `placeRoom`/`placeRoomTemplate` — все видалити; transaction спрощується до wallet-check + place) | `[TODO]` | [lib/providers/game_economy_provider.dart](../lib/providers/game_economy_provider.dart) |
| **Canvas rip** (`_drawFoundationBuffer`, amber buffer rendering, `_bufferDims`, `_BuildBanner` "тягни у золоту зону", `GhostInvalidReason.bufferOverrun`, hover/press buffer fields, `_tryBuyExpansionAtTap` — видалити; ghost або влазить у фіксовану сітку або outOfBounds) | `[TODO]` | [lib/widgets/canvas/agent_canvas.dart](../lib/widgets/canvas/agent_canvas.dart), [lib/widgets/canvas/pixel_office_painter.dart](../lib/widgets/canvas/pixel_office_painter.dart) |
| **Save schema v5→v6 migration** (drop `officeExpansions` поле; legacy saves: clamp existing placed rooms у новий fixed grid; furniture intact; one-time refund grymni за куплені expansion steps; написати migration test для save-у з `officeExpansions=3`) | `[TODO]` | [lib/models/game_economy.dart](../lib/models/game_economy.dart) `fromJson` |
| **Tier-upgrade dialog rework** (видалити "expansion progress" UI на tier card; tier upgrade = "розблоковує новий лот NxM"; copy-rewrite Hex) | `[TODO]` | [lib/widgets/canvas/office_upgrade_dialog.dart](../lib/widgets/canvas/office_upgrade_dialog.dart) |
| **Tier pricing rebalance** (раніше tier upgrade був дешевим бо expansion вибирався поступово; тепер tier-jump одразу = повний лот → tier 2/3 ціни треба переглянути з game-designer; не блокує rip) | `[TODO]` | [lib/models/game_economy.dart](../lib/models/game_economy.dart) `upgradeCost` |
| **Tests** (rip усіх `expansion_placement_test.dart` purchase сценаріїв; зберегти ghost-validity без bufferOverrun; додати migration test v5→v6 з refund перевіркою; адаптувати `room_taxonomy_test.dart` де згадується `computeExpansionPlan`) | `[TODO]` | [test/providers/expansion_placement_test.dart](../test/providers/expansion_placement_test.dart), [test/models/room_taxonomy_test.dart](../test/models/room_taxonomy_test.dart) |

**Залежності та risk-watch:**
- Phase D (Custom Agent Spawn) не залежить від expansion mechanic. Coupling строго локальний у canvas-layer + economy model.
- Stage 2 corridors / Stage 3a snap-and-doors / Stage 3b taxonomy — усі живуть без expansion. Pricing breakdown для room templates лишається.
- Tier pricing balance переглядається окремою сесією з game-designer **перед merge Stage 4** — заходимо у session з фіксованим грідом і дивимось чи tier-jump cost не задорогий/задешевий відносно нової "одразу повний лот" логіки.

---

## C. Агентна система і персоналізація

Бекенд персоналізації зібраний, UI попереду. Це фундамент для Custom Agent Spawn (D).

| Компонент | Статус | Файли |
|---|---|---|
| Per-agent profile cache | `[DONE]` | [server/src/profile_cache.ts](../server/src/profile_cache.ts) |
| Execution hooks (beforeDispatch / afterExecution / onError) | `[DONE]` | [server/src/hooks/executionHooks.ts](../server/src/hooks/executionHooks.ts) |
| Memory lifecycle (score / decay / capacity-tier eviction) | `[DONE]` | [server/src/memory_lifecycle.ts](../server/src/memory_lifecycle.ts) |
| Lesson extractor (pattern recognition + apply with eviction) | `[DONE]` | [server/src/lesson_extractor.ts](../server/src/lesson_extractor.ts) |
| Prompt cache manager (system prompt + learned-context) | `[DONE]` | [server/src/prompt_cache_manager.ts](../server/src/prompt_cache_manager.ts) |
| Agent context preparer | `[DONE]` | [server/src/agent_context.ts](../server/src/agent_context.ts) |
| Project context manager (cross-project profile migration) | `[DONE]` | [server/src/project_context_manager.ts](../server/src/project_context_manager.ts) |
| Trait memory | `[DONE]` | [server/src/trait_memory.ts](../server/src/trait_memory.ts), [lib/models/agent_trait.dart](../lib/models/agent_trait.dart) |
| Personalization orchestrator | `[DONE]` | [server/src/personalization.ts](../server/src/personalization.ts) |
| **Personalization UI** (показати lessons, дозволити edit, reset) | `[DONE]` | 2026-04-28 — `PersonalizationPanel` з per-trait delete + "Clear all" + consent toggle; entry point через "Пам'ять агента" іконку у _TeamRow (Roster tab). Провайдери wired до live WS stream. 11 нових тестів. |
| **Lessons history viewer** | `[DONE]` | 2026-04-28 — інтегровано у PersonalizationPanel: всі уроки по секціях Strengths/Weaknesses, frequency badges, category labels, sorted by frequency desc |
| **Topic affinity inspector** | `[TODO]` | Q3 2026 — server-side UserProfile.topicAffinities ще не surfaced через WS |
| **User consent flow** для запису lessons | `[DONE]` | 2026-04-28 — `learningConsentEnabled` toggle у PersonalizationPanel header + SharedPreferences persistence через `settingsProvider` |
| **Per-agent facilitator binding** (manager пам'ятає обраний style) | `[TODO]` | Q3 2026 |
| **Facilitator lessons namespace** (style-scoped lesson channel) | `[TODO]` | Q3 2026 |
| **Style switch flow** (UI для зміни facilitator з explanation) | `[TODO]` | Q4 2026 |
| **Agent busy/idle state + UI badge** (prerequisite для D — без нього team-dispatch + custom agents простоюють) | `[DONE]` | 2026-04-27 |

Дизайн — у [AGENT_PERSONALIZATION_SYSTEM.md](AGENT_PERSONALIZATION_SYSTEM.md), план — у [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md).

### C.1 Specialization & Accumulated Value (Q3 2026, паралельно з C)

**Стратегічна задача:** зробити "вирощений Lv10 агент > голий opus" відчутно для гравця. Personalization-шар (lessons / traits / project memory) уже накопичує знання server-side, але differentiation невидимий — це підважує value proposition vs raw API access (Cursor / Continue / Cody). Без цього шару Marketplace v1 (E) ризикує стати skin-store замість asset-trading. Запис після обговорення 2026-04-27.

| Компонент | Статус | ETA |
|---|---|---|
| **Specialization unlock mechanic** (після N task'ів одного topic → "Spec: Frontend" badge → +X% crit на тій категорії) | `[DONE]` | 2026-04-29 — 20-task threshold, +15% crit/spec capped at +30%; ★ badge in roster; 14 tests ([game_economy.dart](../lib/models/game_economy.dart), [game_economy_provider.dart](../lib/providers/game_economy_provider.dart), [task_outcome.dart](../lib/services/task_outcome.dart), [roster_tab.dart](../lib/widgets/shop/roster_tab.dart)) |
| **Lesson-driven roll bonus** (accumulated lessons → −X% incomplete rate на relevant task type) | `[DONE]` | 2026-04-29 — `lessonSuccessBonus()` + `lessonBonus` param in `rollOutcome`; +0.5%/lesson capped at +10% success; wired via `agentTraitsProvider` count in `task_progress_provider.dart`; 6 нових тестів ([task_outcome.dart](../lib/services/task_outcome.dart), [task_progress_provider.dart](../lib/providers/task_progress_provider.dart)) |
| **Trait-based response style surfacing** (trait badge у chat panel + agent card; видимі personality biases) | `[DONE]` | 2026-04-29 — `_TraitBadgesCard` (strengths green / weaknesses amber, emphasis-weight styling) у [agent_overview_tab.dart](../lib/widgets/roster/agent_overview_tab.dart); top-3 `_ChatHeaderTraitBadges` chips у [chat_panel.dart](../lib/widgets/chat/chat_panel.dart); 8 нових тестів |
| **Project memory depth bonus** (time-on-project → bonus to architectural reasoning rolls; свіжо найнятий tech-lead = generalist, 3-міс Богдан = знає проєкт) | `[DONE]` | 2026-05-01 — `projectMemoryDepthBonus()` (+1% crit per 5 tasks, capped +15% on `architecture` divergent tasks); wired via `totalTasksCompleted` count in `task_progress_provider.dart`; 6 нових тестів ([task_outcome.dart](../lib/services/task_outcome.dart)) |
| **Specialization badges на agent card** (поверх sprite — мікро-glyph; на roster card — окремий ряд badges) | `[DONE]` | 2026-04-29 — 2px amber glyph у `pixel_office_painter.dart` via `agentSpecializations` map; `_SpecializationBadgeRow` (Wrap of labeled pills) у roster_tab; `_SpecializationsCard` section у agent_overview_tab |
| **Lessons counter / topic affinity inspector** (UI yet to design — частина Personalization UI з C) | `[DONE]` | 2026-05-01 — `LessonCategory` enum (8 тем) + `TopicAffinityEntry` + `agentTopicAffinitiesProvider` (агрегує traits по category, сортує по total frequency); `_TopicAffinitiesSection` у PersonalizationPanel з `_TopicChip` (акцент green/red/gold за strengthCount vs weaknessCount); 5 нових тестів ([agent_trait.dart](../lib/models/agent_trait.dart), [agent_traits_provider.dart](../lib/providers/agent_traits_provider.dart), [personalization_panel.dart](../lib/widgets/personalization/personalization_panel.dart)) |
| **Telemetry: "grown vs raw" delta** (порівняння completion rate / crit rate Lv10 з accumulated context vs Lv10 без context — підтвердити що value реальний) | `[DONE]` | 2026-05-01 — Monte Carlo simulation: `AgentProfile` + `SimulationResult` + `GrowthDelta` + `simulateOutcomes` в [growth_telemetry.dart](../lib/services/growth_telemetry.dart); 8 тестів ([growth_telemetry_test.dart](../test/services/growth_telemetry_test.dart)) — completion delta +4–5% (lessons), crit delta +18–30% (specialization + project memory). Підтвердив що value > 10% threshold. |
| **Sub-agent thread-mirror split** (дзеркало активності суб-агента у чаті капітана не оновлює статус-індикатор капітана) | `[DONE]` | 2026-05-13 — Bug: capтан/фасилітатор показував `running: <команда>` ідентичну з суб-агентом (тех-лід) бо `subAgentMirrorToolUse` емітив `tool_use` з `agentId: managerId`, який `AgentsNotifier` обробляв як справжній статус. Fix: новий протокол-тип `subagent_thread_event` (server-side в [server/src/server.ts](../server/src/server.ts) + [server/src/protocol.ts](../server/src/protocol.ts)); клієнтський `SubagentThreadEventMessage` ([lib/models/agent_message.dart](../lib/models/agent_message.dart)) обробляється тільки `ChatNotifier` як thread status-bubble у чаті капітана, ніколи не торкається `AgentsNotifier` ([lib/providers/agent_provider.dart](../lib/providers/agent_provider.dart)). 2 нових тести (server contract type + client parser); existing mirror tests адаптовані. |
| **Conversational core loop** (facilitator team-reaction scene → dispatch → tech-lead digest з lesson capture → growth-surfacing) | `[DONE]` | 2026-05-08 — Закриває розрив "user пише задачу → команда обговорює → виконує → tech-lead тримає пульс". Components: 1) facilitator `team_reactions.ts` — Haiku call paralleled з seed, 2-3 in-character реакції стрімяться у chat як bubbles перед board fill, graceful failure → []; 2) `tech_lead_digest.ts` — bounded ring (50) + JSONL append-only persist, hook на `done`-transition в `board_move_task`/`board_update_task`, replay при boot, **топ-lesson агента (за frequency) snapshot-иться у entry → render-ить як "learned (strength): ..." у prompt** (backward-compat JSONL: legacy lines без поля replay-ять чисто); 3) digest injected в system prompt для tech-lead role через `buildOfficePrompt(..., techLeadDigest)` + new WS endpoint `get_tech_lead_pulse` + broadcast push на кожне completion; 4) live progress streaming verified end-to-end (existing `stream_event` → `assistant_text isPartial` path); 5) `TeamPulseStrip` widget на chat panel header — компактна стрічка останніх completion-ів, tooltip розкриває lesson context. 23 нових unit-тестів ([team_reactions.test.ts](../server/test/team_reactions.test.ts), [tech_lead_digest.test.ts](../server/test/tech_lead_digest.test.ts)) + 1 integration test ([conversational_core_loop.integration.test.ts](../server/test/integration/conversational_core_loop.integration.test.ts)) що викликає ті ж helper-и (`applyReactionsToChat`, `recordTaskCompletion`) що server.ts → handler/test drift неможливий. No new TS errors, flutter analyze clean. Files: [server/src/facilitator/team_reactions.ts](../server/src/facilitator/team_reactions.ts), [server/src/tech_lead_digest.ts](../server/src/tech_lead_digest.ts), [server/src/conversational_loop.ts](../server/src/conversational_loop.ts), [server/src/agents.ts](../server/src/agents.ts), [server/src/agent_runner.ts](../server/src/agent_runner.ts), [lib/widgets/team_pulse_strip.dart](../lib/widgets/team_pulse_strip.dart), [lib/providers/tech_lead_pulse_provider.dart](../lib/providers/tech_lead_pulse_provider.dart) |

**Залежності:**
- C.1 побудовано поверх існуючого personalization stack ([memory_lifecycle.ts](../server/src/memory_lifecycle.ts), [lesson_extractor.ts](../server/src/lesson_extractor.ts), [trait_memory.ts](../server/src/trait_memory.ts), [project_context_manager.ts](../server/src/project_context_manager.ts)) — нічого нового на server-side, тільки surface через game mechanics.
- Без C.1 → Marketplace v1 (E) торгує характерами без visible "trained value"; з C.1 → характер з 200 lessons + 2 specializations відрізняється від свіжо створеного, що = справжній asset.
- **Specialization mechanic може замінити необхідність обов'язкового tier upgrade** для creative ролей: Соня може лишитись на sonnet з +30% crit на дизайн = effectively opus у domain.

**Risk-watch:**
- Game mechanics що залежать від accumulated state може фруструвати new players ("моя команда слабка проти ветеранської"). Mitigation: cap specialization bonuses на reasonable максимумі (наприклад +30%), не x2.
- Telemetry мусить підтвердити що grown > raw API — інакше value proposition lie. Якщо delta < 10% — переглянути dispatch / context preparer.

---

## D. Custom Agent Spawn і агенти як активи

Перший крок до екосистеми. Не чекаємо локальних моделей — починаємо з prompt-level кастомізації.

| Компонент | Статус | ETA |
|---|---|---|
| **Custom Agent Spawn UI** — створення агента (system prompt, role bias, skill weights) | `[DONE]` | Q3 2026 |
| **Self-play в dungeon** — агент пробує задачу N разів, кращі attempts → memory | `[TODO]` | Q3 2026 |
| **Agent JSON export/import** — поділитися агентом як файлом | `[DONE]` | 2026-04-28 — `AgentBlueprint` + `AgentExportService` ([lib/services/agent_export_service.dart](../lib/services/agent_export_service.dart)); Export кнопка в agent_overview_tab; Import діалог (paste JSON) в roster_tab; 26 нових тестів |
| **Agent signature/identity** (унікальний ID, історія тренування) | `[TODO]` | Q3 2026 |
| **Personality presets** (templates для швидкого старту) | `[DONE]` | Q3 2026 |
| **Custom facilitator spawn** (user-defined persona_prompt + lexicon) | `[TODO]` | Q3 2027 |
| **Agent stats card** — для marketplace listing (XP, success rate, specializations); shareable з Roster v1 (D.1) | `[PARTIAL]` | 2026-05-08 — first signal landed: `agentCompletionCountProvider` derives recent-completion count per-agent з live `tech_lead_pulse` stream → `_RecentCompletionsBadge` поряд з Level chip у [agent_overview_tab.dart](../lib/widgets/roster/agent_overview_tab.dart). "Done X tasks" видно на профілі відразу. Не shareable card ще — тільки local surface. Повна marketplace card (success rate aggregation, lifetime stats, JSON export → image) залишається TODO до D.1 stats endpoint |
| **Discord/Reddit thread** — перший community trade ground (поза-аппка) | `[TODO]` | Q3 2026 |
| **Custom agent schema (CCGS-inspired)** — поля `description`, `tier` (reasoning/execution/bulk), `tools`, `maxTurns`, `disallowedTools`, `skills[]`; tier map-ує на provider через `roleCatalog` логіку; користувач вибирає tier, не модель | `[TODO]` | Q3 2026 |
| **Agent memory markdown export** — read-only debug-view на Agent Card: lessons → markdown; transparency win для custom agents | `[TODO]` | Q3 2026 |
| **Collaborative-mode default для custom agents** — нижча autonomy, явні confirmations при створенні; power-user override до autonomous | `[TODO]` | Q3 2026 |

**Залежності:** C (Personalization UI) має бути готова раніше, бо Custom Agent Spawn зливається з нею в одне UI.

### D.1 Curated Roster v1 (Q3 2026)

UX-rehearsal для Marketplace v1 — запечений roster named characters, де гравець наймає "Андрія, Code Specialist" замість абстрактної ролі. **Soft vendor-disclosure**: provider видно дрібним шрифтом з опцією свапу, але lore та name — character-first. Дизайн ухвалено [STRATEGY §Phase 1.5](STRATEGY.md#phase-15-curated-roster-v1-q3-2026); рішення зафіксовано 2026-04-27 (1C/2A/3A: soft firewall + sprite reuse + cosmetic-only monetization).

| Компонент | Статус | ETA |
|---|---|---|
| **Character data schema** (`name`, `portrait`, `statWeights`, `promptBias`, `defaultBackend`, `price`) | `[DONE]` | 2026-04-28 — [lib/models/roster_catalog.dart](../lib/models/roster_catalog.dart) |
| **Starter roster (7 characters)** — Андрій / Оля / Богдан / Тетяна / Дмитро / Соня / Максим; бюджет 18pt, max=7, min=1, spread≥4 (специфікація 2026-04-27) | `[DONE]` | 2026-04-28 — `rosterCatalog` у [lib/models/roster_catalog.dart](../lib/models/roster_catalog.dart) |
| **Capability formula review** — UI/UX-designer creativity-heavy (creativity weight=0.1) → haiku-locked. Або підняти creativity weight у formula, або role-specific override | `[DONE]` | 2026-04-28 — creative profile: `creativity: 0.35` у [server/src/agents.ts](../server/src/agents.ts):387–388 |
| **Roster catalog UI** (filter/sort cards: stats, ціна, role) — shareable component з Marketplace v1 stats-card | `[DONE]` | 2026-04-28 — `RosterTab` + `_RosterCharacterCard` + `_StatBars` + `_RoleFilterBar` у [lib/widgets/shop/roster_tab.dart](../lib/widgets/shop/roster_tab.dart) |
| **Hire-flow refactor** — role+provider абстракція → character picker; backward-compat з існуючим `AgentGameData.provider` | `[DONE]` | 2026-04-28 — `hireCharacter` / `canHireCharacter` у provider; `characterId` persisted на `AgentGameData` |
| **Soft vendor-disclosure styling** (`powered by X` дрібним шрифтом під portrait) + Anthropic/OpenAI brand guideline compliance | `[DONE]` | 2026-04-28 — `_VendorPill` у roster_tab.dart; Claude/DeepSeek/Gemini/Kimi color-coded badges |
| **Adjacency × stat interaction guard** — Server Room speed bonus + speed=7 character не повинні стакати без cap (diminishing returns) | `[DONE]` | 2026-04-28 — `kSpeedBonusCeiling = 1.35` + `clamp(0.9, kSpeedBonusCeiling)` у `_buildRoomEffects()` ([lib/widgets/canvas/office_game_state.dart](../lib/widgets/canvas/office_game_state.dart)); 3 нових тести |
| **Backend-swap UI** (advanced settings — змінити provider для найнятого character без втрати identity) | `[DONE]` | 2026-04-28 — `_BackendSwapCard` у [lib/widgets/roster/agent_overview_tab.dart](../lib/widgets/roster/agent_overview_tab.dart): 5 provider buttons з brand colors, ★ для recommended, ⚠ для auth-not-set; `setAgentProvider` wired; 3 нових тести |
| **Portrait pipeline: palette swaps + accessory overlays** на базі існуючого 8-skin × 9-class sprite system | `[TODO]` | Q3 2026 |
| **Roster telemetry hooks** (hire-rate per character, time-to-second-hire, retention rate, task success rate per role, backend-swap rate) | `[TODO]` | Q3 2026 (з L — Telemetry opt-in) |
| **Provider catalog single-source-of-truth** (versioning: DeepSeek V2/V3, model snapshots) | `[TODO]` | Q3 2026 |
| **Cosmetic shop slot для characters** (portrait variants, accessories, voice-stings — stats const) | `[TODO]` | Q4 2026 (з cosmetics shop в I) |

**Залежності:**
- D.1 — UX-rehearsal для Marketplace v1 (E). Stats-card компонент має бути shareable між обома, інакше double-work у Q4 2026.
- D (Custom Agent Spawn) і D.1 не competition: roster characters позиціонуються як "starting templates" → personalize через C → list на marketplace в E.
- Brand guideline review (Anthropic/OpenAI ToS) — перед launch, не в production.

**Risk-watch:**
- Soft firewall маркетинг-дисципліна: при описах характерів у social не валитись назад у "це Claude-агент"; характер описується через persona/stats.
- Балансування 5–7 hand-tuned characters може зжерти час D — старт з 5, додаткових 2 за результатом playtests.
- Cannibalize Custom Spawn: позиціонувати roster як templates для personalization, не final product.

---

## E. Marketplace v1

Інфраструктура торгівлі агентами. Поки агенти — JSON, але архітектура має бути готова для adapter weights пізніше.

| Компонент | Статус | ETA |
|---|---|---|
| **Marketplace catalog UI** (список агентів, filter, sort) | `[TODO]` | Q4 2026 |
| **Agent listing flow** (виставити свого агента) | `[TODO]` | Q4 2026 |
| **Agent quality score** (standardized dungeon challenges перед listing) | `[TODO]` | Q4 2026 |
| **Rating + review system** | `[TODO]` | Q4 2026 |
| **Anti-collusion logic** (один акаунт не торгує з собою) | `[TODO]` | Q4 2026 |
| **Marketplace backend** (server-side каталог, не P2P) | `[TODO]` | Q4 2026 |
| **Crowdsourced training data pool (opt-in)** | `[TODO]` | Q4 2026 |
| **Anonymization pipeline** для opt-in pool | `[TODO]` | Q4 2026 |
| **Agent merge mechanic v1** (для JSON-агентів — merge prompts/skills) | `[TODO]` | Q4 2026 |
| **Marketplace commission infra** (15–20% на угоду) | `[TODO]` | Q4 2026 |
| **Facilitator marketplace catalog** (style listings) | `[TODO]` | Q4 2026 |
| **Style quality signal** (token-spend / retention test on demo) | `[TODO]` | Q4 2026 |
| **Curated submission queue** (anti-edgelord moderation) | `[TODO]` | Q1 2027 |

---

## F. Backend Abstraction шар

Найважливіший архітектурний крок 2027. Виносимо все, що зараз зав'язано на Claude Agent SDK, за абстракцію.

| Компонент | Статус | ETA |
|---|---|---|
| **Gemini CLI integration foundation** (auth + provider routing) | `[PARTIAL]` | Q2 2026 — каркас є, agent routing попереду |
| **DeepSeek API integration** — `deepseek_backend.ts`, API-key linking у Settings, "втомлений" стан агентів; interim до AgentBackend abstraction | `[DONE]` | Q2 2026 |
| **`AgentBackend` interface** | `[TODO]` | Q1 2027 |
| **`ClaudeAgentSdkBackend`** (refactor існуючого коду) | `[TODO]` | Q1 2027 |
| **`OpenAgentBackend`** (для open-source agent frameworks) | `[TODO]` | Q1 2027 |
| **`LocalRuntimeBackend`** (Ollama / MLX / llama.cpp) | `[TODO]` | Q1 2027 |
| **`CustomBackend`** plugin loader | `[TODO]` | Q1 2027 |
| **Tier routing refactor** — Haiku/Sonnet/Opus → local-fast/local-quality/cloud | `[TODO]` | Q1 2027 |
| **Provider-agnostic session/tool-use abstraction** | `[TODO]` | Q1 2027 |
| **First non-Anthropic prototype** (Ollama + llama3.2:1b або phi4-mini) | `[TODO]` | Q1 2027 |
| **Dungeon judge на локальній моделі** (verify quality) | `[TODO]` | Q1 2027 |

**Чому критично:** marketplace (E) уже торгує агентами; без абстракції кожна одиниця — лише promptpack. З абстракцією агент стає повноцінним активом, що працює на будь-якому runtime.

**Тригер замість дати** (за [STRATEGY §0](STRATEGY.md#0-реалістична-калібровка-станом-на-2026-04-26) #3): починаємо роботу, **коли з'являється другий конкретний backend з реальним користувачем** — не за календарем. До тоді — Claude Agent SDK direct, без передчасної абстракції. Ціль "Q1 2027" вище — early estimate, який може зрушитись до Q2–Q3 2027 без втрати критичного шляху.

---

## G. Модельний шар (Foundation + Adapter)

Перший власний модельний артефакт. PixelCode Foundation Model — спільна база, поверх якої тренуються adapters.

| Компонент | Статус | ETA |
|---|---|---|
| **PixelCode Foundation Training Set** — 10K зразків від Cloud Opus | `[TODO]` | Q1 2027 |
| **Distillation pipeline v1** (cloud teacher → student data) | `[TODO]` | Q1 2027 |
| **PixelCode Foundation Model v1** (fine-tuned Llama 3.2 / Phi-4 / Qwen) | `[TODO]` | Q2 2027 |
| **Foundation Model distribution** (CDN, ~1–3GB download) | `[TODO]` | Q2 2027 |
| **Foundation Model versioning** | `[TODO]` | Q2 2027 |
| **LoRA adapter format spec** (стандартизований marketplace-сумісний) | `[TODO]` | Q3 2027 |
| **Adapter merge mechanic v2** (математичний weight averaging для LoRA) | `[TODO]` | Q3 2027 |
| **Foundation Model evaluation suite** (regression test перед release) | `[TODO]` | Q2 2027 |

---

## H. Тренування і Self-Distillation

Шар, що перевертає економіку. Self-distillation робить тренування майже безкоштовним.

| Компонент | Статус | ETA |
|---|---|---|
| **Cloud-shot training service** ($0.05–0.20 per adapter update) | `[TODO]` | Q2 2027 |
| **Cloud GPU вибір** (provider, billing, rate limiting) | `[TODO]` | Q2 2027 |
| **Training credits economy** (Grim → credits → GPU shots) | `[TODO]` | Q2 2027 |
| **Self-play training data collection** з dungeon | `[TODO]` | Q3 2026 (співпадає з D) |
| **AI judge v1** — Haiku-суддя як training signal generator | `[DONE]` | Перевикорис. з [server/src/dungeon.ts](../server/src/dungeon.ts) |
| **AI judge ensemble** (кілька судів для anti-reward-hacking) | `[TODO]` | Q3 2027 |
| **Reward hacking detection** | `[TODO]` | Q3 2027 |
| **Mode collapse safeguards** (diversification + cloud injection) | `[TODO]` | Q3 2027 |
| **On-device training (alpha)** — флагмани з NPU train-ops | `[FUTURE]` | Q4 2027 |
| **On-device self-distillation loop** (overnight while charging) | `[FUTURE]` | Q4 2027 |
| **Battery/thermal scheduler** (training only when plugged + cool) | `[FUTURE]` | Q4 2027 |
| **On-device training (mainstream)** — non-флагмани | `[FUTURE]` | 2028+ |
| **Community-driven Foundation updates** | `[FUTURE]` | 2028+ |

---

## I. Монетизація

Поетапне впровадження доходових потоків та лікензування. Деталі в Obsidian vault `~/Obsidian/PixelCode/STRATEGY.md` (pricing, unit economics, content strategy).

| Компонент | Статус | ETA |
|---|---|---|
| **Перехід на dual license** (PolyForm Noncommercial → особисте + комерційне) | `[TODO]` | Q4 2026 |
| **Pro tier subscription infrastructure** (auth, billing, entitlement check) | `[TODO]` | Q4 2026 |
| **Pro tier features** (cloud sync, unlimited projects, advanced analytics) | `[TODO]` | Q4 2026 |
| **Cosmetics shop** (скіни, меблі, теми) | `[TODO]` | Q4 2026 |
| **Cloud server (managed)** — для Pro tier | `[TODO]` | Q4 2026 |
| **Companion PWA** (моніторинг офісу з браузера) | `[TODO]` | Q4 2026 |
| **Marketplace commission infrastructure** | `[TODO]` | Q4 2026 |
| **B2B team license** (shared agent pools) | `[TODO]` | Q1 2027 |
| **Training credits economy** | `[TODO]` | Q2 2027 |
| **Grim packs** (real money → in-game currency) | `[TODO]` | Q3 2027 |
| **Premium agent listings** (marketplace promotion) | `[TODO]` | Q3 2027 |
| **Real money out infrastructure** (for top sellers) | `[TODO]` | Q3 2027 |
| **Юридичний review** (marketplace/trading регуляції) | `[TODO]` | **Q3 2026** (ДО marketplace launch) |

---

## J. Mobile деплой і дистрибуція

| Компонент | Статус | Файли |
|---|---|---|
| Silent iOS deploy через `xcrun devicectl` | `[DONE]` | [lib/services/ios_deploy_service.dart](../lib/services/ios_deploy_service.dart) |
| OTA iOS deploy через Tailscale Funnel | `[DONE]` | [server/src/server.ts](../server/src/server.ts) |
| Android deploy (повний) | `[DONE]` | [lib/services/android_deploy_service.dart](../lib/services/android_deploy_service.dart), [lib/providers/android_deploy_provider.dart](../lib/providers/android_deploy_provider.dart) |
| iOS signing flow + onboarding | `[DONE]` | [docs/iOS_DEPLOYMENT.md](iOS_DEPLOYMENT.md) |
| Android signing flow + onboarding | `[DONE]` | [server/src/health.ts](../server/src/health.ts) (`checkAndroidSigning`), [lib/widgets/settings/diagnostics_section.dart](../lib/widgets/settings/diagnostics_section.dart) |
| GitHub Releases для macOS артефактів | `[DONE]` | — |
| **App Store / Play Store presence** | `[TODO]` | Q4 2026 (після Pro tier infra) |

---

## K. Community і контент

Маркетинг і community building. Деталі в [STRATEGY.md §4](STRATEGY.md#4-контент-план-для-соцмереж).

| Канал | Статус | ETA |
|---|---|---|
| **GitHub presence** (README, CONTRIBUTING, LICENSE) | `[DONE]` | — |
| **X (Twitter) account** з активним постингом | `[TODO]` | Старт паралельно з alpha |
| **TikTok / Reels / Shorts** | `[TODO]` | Старт після першого polished demo |
| **YouTube канал** (1–2 відео/місяць) | `[TODO]` | Місяць 2 від старту contentу |
| **Reddit** (r/programming, r/FlutterDev, r/MachineLearning, r/gamedev) | `[TODO]` | Старт паралельно з X |
| **Discord server** | `[TODO]` | **Q1 2026** (community-фаза має початись раніше за marketplace, інакше liquidity-проблема — див. [STRATEGY §0](STRATEGY.md#0-реалістична-калібровка-станом-на-2026-04-26)) |
| **"Meet the breeders" series** | `[TODO]` | Q4 2026 (після Marketplace v1) |
| **"Agent battles" content format** | `[TODO]` | Q4 2026 |
| **LinkedIn presence (B2B)** | `[TODO]` | Q1 2027 |

---

## L. Інфраструктура підтримки

Щоб тримати якість і зрозуміти що відбувається.

| Компонент | Статус | ETA |
|---|---|---|
| Diagnostics panel (server health, deps, logs) | `[DONE]` | [lib/widgets/debug/](../lib/widgets/debug/) |
| Structured logging | `[DONE]` | — |
| Boot logs ring buffer | `[DONE]` | [server/src/launcher.ts](../server/src/launcher.ts) |
| **PixelDock + Launcher merge** (один додаток з NavigationRail: DASH / SETUP / CONFIG / LOGS / CLIENTS; sandbox вимкнено для Process.spawn; `SPAWN DAEMON` кнопка замінює "copy command") | `[DONE]` | 2026-05-09 — [server_admin/](../server_admin/); `launcher/` видалено |
| **PixelDock remote access — bearer token** (крок 1 з 3): middleware на `/launcher/*` і `/admin/api/*` — якщо запит не loopback, вимагає `Authorization: Bearer <token>`; token генерується при старті daemon або береться з `.env`; PixelDock UI: поле Token поряд з URL, зберігається у SharedPreferences; `LauncherClient` і `AdminClient` додають header | `[TODO]` | передумова для кроків 2–3 |
| **PixelDock remote access — configurable bind** (крок 2 з 3): `launcher.ts` приймає `--bind 0.0.0.0` (або env `LAUNCHER_BIND`); `isLoopback`-перевірка стає no-op коли token-режим увімкнено; за замовчуванням поведінка не змінюється (127.0.0.1) | `[TODO]` | після кроку 1 |
| **PixelDock remote access — Tailscale transport** (крок 3 з 3): daemon bind на Tailscale IP; iOS PixelDock build з полем remote URL + token → restart/stop сервера з iPhone через мобільний інтернет; `tailscaleUrl` вже є у `ServerStatus` | `[TODO]` | після кроку 2; Tailscale вже є у стеку |
| **PixelDock basic metrics on dashboard** — `metrics` block у `/admin/api/status`: RSS, heap used/total, CPU% (delta між poll-ами), queued tasks (`TaskQueue.size`), active sub-agents (`AgentRunner.getStatus().length`), Node version+platform; `_MetricsCard` під `_StatusCard` на DASH у PixelDock | `[DONE]` | 2026-05-11 — [server/src/admin.ts](../server/src/admin.ts), [server_admin/lib/pages/dashboard_page.dart](../server_admin/lib/pages/dashboard_page.dart) |
| **Telemetry / metrics opt-in** (anonymous usage stats) | `[TODO]` | Q3 2026 |
| **Crash reporting** (Sentry або власне) | `[TODO]` | Q3 2026 |
| **A/B test infra** (для UI-експериментів) | `[TODO]` | Q4 2026 |
| **Feature flags** | `[TODO]` | Q4 2026 |
| **Rate limiting / abuse prevention** на marketplace | `[TODO]` | Q4 2026 |
| **CI/CD pipeline** (build matrix для всіх платформ) | `[PARTIAL]` | Поточний стан — `flutter build` локально; потрібен GitHub Actions |
| **Automated test suite** (Flutter widget tests + server unit tests) | `[PARTIAL]` | Розширено 2026-05-02 — Production-ready core loop (8 work-packages) додав ~150 unit + 18 integration тестів: board persistence/sync/seed-batch, roster validation/cleanup/quarantine, LLM runner (timeout/retry/typed errors), auto-dispatcher, optimistic client board, facilitator UX. Integration tests у [server/test/integration/](../server/test/integration/) і [test/integration/](../test/integration/) ловлять регресії на стиках модулів. **+ 2026-05-02 captain orchestration loop** — 10 server-side scenarios у [server/test/integration/captain_orchestration.integration.test.ts](../server/test/integration/captain_orchestration.integration.test.ts) (decompose → workload-aware delegate → progress → done → blocker → restart) + 4 Flutter chat-flow scenarios у [test/integration/captain_chat_flow_test.dart](../test/integration/captain_chat_flow_test.dart) (split announcement, board snapshots, optimistic-move snapback, streaming chunk merge). Залишається: widget-tests на drag-and-drop, повний end-to-end через справжній in-process WS server |

---

## M. Facilitator System (стиль ведення розробки)

Facilitator — модальність взаємодії manager-агента, що визначає лексикон, ритм церемоній і output-формат (quest / sprint / milestone / mission / koan). Quest System стає одним з режимів (Game Master). Дизайн — у [FACILITATOR_SYSTEM.md](FACILITATOR_SYSTEM.md), Game Master режим — у [FACILITATOR_GAMEMASTER.md](FACILITATOR_GAMEMASTER.md).

| Компонент | Статус | Файли / ETA |
|---|---|---|
| **`FacilitatorStyle` schema** (persona_prompt, lexicon, ceremony, output_mapper) | `[DONE]` | [lib/models/facilitator_style.dart](../lib/models/facilitator_style.dart), [server/src/facilitator/types.ts](../server/src/facilitator/types.ts) |
| **`FacilitatorRunner` server-side** (intake, seed kanban, on-event ceremonies) | `[DONE]` | [server/src/facilitator/runner.ts](../server/src/facilitator/runner.ts) + WS endpoint `facilitator_start` готові; Mariya preset + i18n integration (v0.4.0) |
| **`FacilitatorOutput` interface** (toKanbanTasks/toCanonicalProgress) | `[DONE]` | [lib/models/facilitator_output.dart](../lib/models/facilitator_output.dart) |
| **Refactor: QuestLine → FacilitatorOutput impl** (Game Master mode) | `[DONE]` | [lib/models/quest_line.dart](../lib/models/quest_line.dart) |
| **Refactor: QuestPersistence → FacilitatorOutputPersistence** | `[DONE]` | [lib/services/facilitator_output_persistence_service.dart](../lib/services/facilitator_output_persistence_service.dart) |
| **Default styles MVP**: Game Master, Mariya (Amber), Drill Sergeant | `[DONE]` | [assets/facilitators/](../assets/facilitators/) |
| **`MissionBriefing` output format** (Drill Sergeant) | `[DONE]` | [lib/models/mission_briefing.dart](../lib/models/mission_briefing.dart), [server/src/facilitator/output_generator.ts](../server/src/facilitator/output_generator.ts) |
| **`MilestoneTree` output format** (Mariya) | `[DONE]` | [lib/models/milestone_tree.dart](../lib/models/milestone_tree.dart), [server/src/facilitator/output_generator.ts](../server/src/facilitator/output_generator.ts) |
| **Client integration** (picker → intake → WS `facilitator_start` → kanban seed) | `[DONE]` | [lib/services/facilitator_session_service.dart](../lib/services/facilitator_session_service.dart) + [lib/services/facilitator_onboarding.dart](../lib/services/facilitator_onboarding.dart) + [lib/widgets/facilitator/launch_facilitator_onboarding.dart](../lib/widgets/facilitator/launch_facilitator_onboarding.dart) — v0.4.0 додав localization bindings |
| **i18n integration** (English + Ukrainian across all facilitators) | `[DONE]` | v0.4.0 — see [lib/services/localization_service.dart](../lib/services/localization_service.dart) |
| **LLM-backed output generators** (заміна stub-ів через Anthropic SDK) | `[DONE]` | 2026-04-28 — `ClaudeQuestLineGenerator` / `ClaudeMissionBriefingGenerator` / `ClaudeMilestoneTreeGenerator` у [server/src/facilitator/llm_generators.ts](../server/src/facilitator/llm_generators.ts); CallerFn injectable для тестів; haiku (micro/small) + sonnet (medium/large); зареєстровано у server.ts при старті; 21 новий тест |
| **LLM pipeline robustness** (typed errors, timeout, retry, atomic seed) | `[DONE]` | 2026-05-02 — [server/src/facilitator/llm_runner.ts](../server/src/facilitator/llm_runner.ts) з `LLMGenerationError {kind: timeout/parse/rate_limit/auth/unknown}`, per-attempt 60s hard timeout, 1 retry на transient (5xx/429/ECONNRESET), parse/auth no-retry. `extractJson` повертає null замість silent fallthrough. `facilitator_error.code` typed на wire. Atomic `board_seed_batch` — none-or-all семантика, замінює N×board_create_task. 20+8+3 нових тестів |
| **Facilitator client UX polish** (typed-code aware UI + lost-style + 90s timeout) | `[DONE]` | 2026-05-02 — `FacilitatorErrorCode` enum + `FacilitatorSeedFailure.isRetryable`; default timeout 30s→90s (server WP4 has own retry); production шле `board_seed_batch` через `bindToWsService`; новий `lostFacilitatorStyleIdProvider` для prompt "стиль видалено" замість silent fallback. [lib/services/facilitator_session_service.dart](../lib/services/facilitator_session_service.dart), [lib/providers/active_facilitator_style_provider.dart](../lib/providers/active_facilitator_style_provider.dart). 18 нових тестів |
| **Hierarchical prompt safety** (style ≠ tech decisions; tech-lead veto) | `[TODO]` | Q3 2026 |
| **Default styles v2**: Scrum Master, Stoic Mentor | `[TODO]` | Q4 2026 |
| **`SprintBacklog` output format** (Scrum Master) | `[TODO]` | Q4 2026 |
| **`KoanEntry` output format** (Stoic Mentor) | `[TODO]` | Q4 2026 |
| **Style-aware ceremony engine** (standup/retro/journal/none) | `[TODO]` | Q4 2026 |
| **Suggest-switch heuristic** (sentiment-based fatigue detection) | `[TODO]` | Q1 2027 |

**Залежності:** Перетинається з C (style binding в personalization UI), B (kanban lexicon swap), E (marketplace path для community styles). Перевикористовує існуючі artifacts: [quest_line.dart](../lib/models/quest_line.dart), [scope_scorer.ts](../server/src/quest/scope_scorer.ts), [quest_persistence_service.dart](../lib/services/quest_persistence_service.dart).

---

## Залежності між напрямками

```
A (Foundation) ─────────────────────────────────────────────► все інше
B (Game Layer) ─┐
                ├──► D (Custom Spawn) ──► D.1 (Curated Roster) ──► E (Marketplace) ──► F (Backend abstraction)
C (Personalization) ─┘                                                                       │
                                                                    ▼
                                                              G (Foundation Model)
                                                                    │
                                                                    ▼
                                                              H (Training)
                                                                    │
                                                                    ▼
                                                              On-device training (FUTURE)

I (Monetization) — паралельно з E (Marketplace v1 потребує commission infra)
J (Mobile deploy) — паралельно, не блокує
K (Community) — паралельно, не блокує
L (Infra) — підтримує все
```

**Критичний шлях до 2027:**

```
C (Personalization UI) → D (Custom Agent Spawn) → D.1 (Curated Roster) → E (Marketplace v1)
  → F (AgentBackend abstraction) → G (Foundation Model) → H (Training)
```

---

## Орієнтовні зусилля (engineer-weeks)

Дуже грубо, для самооцінки. Один розробник full-time.

| Напрямок | Estimate |
|---|---|
| C — Personalization UI | 3–4 weeks |
| C.1 — Specialization & Accumulated Value (mechanics + UI) | 3–4 weeks |
| D — Custom Agent Spawn | 4–6 weeks |
| D.1 — Curated Roster v1 | 3–4 weeks (з ×1.5 буфером для portrait variations + balance) |
| E — Marketplace v1 | 6–8 weeks |
| F — Backend abstraction | 6–10 weeks |
| G — Foundation Model | 4–6 weeks (плюс GPU witty) |
| H — Training infra | 8–12 weeks |
| I — Monetization | 4–6 weeks |
| J — Android deploy завершення | 1–2 weeks |
| L — CI/CD + tests | 2–3 weeks |

**Сумарно до Q4 2027:** ~40–55 engineer-weeks для критичного шляху + monetization. Тобто реалістично — якщо є фокус і немає великих відволікань.

---

## Відкрані архітектурні питання

1. **Backend diversity — коли додаємо нові runtime крім Claude SDK?** Тригер замість дати: коли z'явиться другий конкретний backend з реальним користувачем.
2. **Foundation Model path** — self-build, партнерство чи open-source base?
3. **GPU provider для тренування** — infrastructure выбір визначить unit economics.
4. **On-device training arrival** — залежить від нового покоління NPU (train-ops, а не тільки inference).
5. **Community-driven Foundation updates** — як обновлюватить модель без централізованого сервера?

Деталі та бізнес-контекст див. у Obsidian vault `~/Obsidian/PixelCode/ROADMAP_internal.md`.

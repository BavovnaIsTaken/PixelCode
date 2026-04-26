# PixelCode Changelog

## [0.4.0] — 2026-04-26 (Alpha Release)

### Features
- **Internationalization (i18n)** — Added localization service with support for English and Ukrainian translations across all UI components
- **Facilitator System v1** — Integrated Mariya (Ukrainian PM) preset and localization bindings for all facilitators (Game Master, Drill Sergeant)
- **Build System v2 Stage 1** — New BuildMenu shell with schema v6 (PlacedRoom rotation, per-room wall/floor skins, PlacedCorridor, RoomTemplate model)
  - Foreman NPC polish with onboarding chevrons and diegetic tooltips
  - NavigationRail (desktop) / bottom sheet (mobile) UI
  - Foundation for room placement, templates, and corridor mechanics
- **Widget Test Helpers** — Comprehensive localization test utilities for Flutter widget tests

### Improvements
- Refactored facilitator system for multi-language support
- Improved onboarding flow for new projects via facilitator picker/intake
- Enhanced persistence layer for facilitator outputs (Game Master mode)
- Better handling of session persistence across facilitator styles

### Bug Fixes
- Fixed macOS app exit behavior — server launcher daemon now owns the process (no premature shutdown)
- Improved stability in facilitator output generation

### Known Limitations
- Build System v2 Stage 2 (room templates, corridors, wall/floor skins) pending for Q2–Q3 2026
- Agent Personalization UI (C) still pending — critical for Custom Agent Spawn
- Room adjacency bonuses framework exists but wiring incomplete
- Break Room morale system and Server Room penalties not yet implemented

### Roadmap Progress (§ via docs/ROADMAP.md)
- ✅ **B (Game Layer)** — Foundation complete; Stage 1 of Build System v2 done
- ✅ **M (Facilitator System)** — Mariya preset + i18n integration done
- 🔄 **C (Personalization)** — Backend ready, UI next (Q3 2026)
- 🔄 **D (Custom Agent Spawn)** — Blocked on C; targeting Q3 2026
- ⏳ **E–H (Marketplace, Backend abstraction, Foundation Model, Training)** — Q4 2026 onwards

### Contributors
- Danylo Oliinyk

---

## [0.3.0] — 2026-02-01 (Early Alpha)

### Features
- Initial PixelCode platform with Claude Agent SDK integration
- Pixel-art office hub with real-time agent visualization
- Kanban task board with drag-and-drop support
- Multi-tier model routing (Haiku/Sonnet/Opus) based on agent skill levels
- Grim currency economy and office tier progression
- Dungeon training with automated dungeon judge
- Real-time chat and activity feeds
- WebSocket transport with mDNS/Bonjour discovery
- Tailscale Funnel support for OTA deployment
- Cross-platform support (macOS, Windows, Linux, iOS, Android)

### Infrastructure
- Layered configuration system (defaults → file → ENV → CLI)
- Structured logging with boot ring buffer
- Diagnostics panel
- PixelDock admin application
- Easter eggs (Arkanoid, dungeon crawler)

---

For detailed roadmap and strategy context, see [docs/ROADMAP.md](docs/ROADMAP.md) and [docs/STRATEGY.md](docs/STRATEGY.md).

# Logo Settings Merge — Design

**Date:** 2026-04-21
**Status:** Approved (pending writing-plans handoff)

## Goal

Merge two settings categories — «Глітч-ефект» (`glitch`) and «Алгоритм логотипа» (`logoPath`) — into a single category called «Лого». Within the merged category, add a user-configurable animation duration for the shutdown icon flight, defaulting to the current hardcoded value (1100 ms) and kept in sync with the native window collapse timing.

## Non-Goals

- No changes to `_GlitchControls` content or behavior.
- No changes to `LogoPathEditor` content or DSL semantics.
- No changes to the zigzag fallback algorithm.
- No changes to the 400 ms native window collapse phase.

## Motivation

Both settings visually affect the same UI element (the app logo / shutdown icon). Two separate menu items fragmented an already-small surface. Merging gives users one mental model for "logo-related tweaks" and frees one slot in the settings rail.

The animation duration was previously buried as a magic number in [hub_screen.dart:62](lib/screens/hub/hub_screen.dart#L62) and again at [hub_screen.dart:261](lib/screens/hub/hub_screen.dart#L261). Exposing it turns it into a deliberate knob and forces the two call-sites to share a single source of truth.

## Design

### 1. Settings category taxonomy

In [settings_dialog.dart:147-162](lib/widgets/settings/settings_dialog.dart#L147-L162):

- Remove `glitch(Icons.auto_fix_high_outlined, 'Глітч-ефект')`.
- Remove `logoPath(Icons.code, 'Алгоритм логотипа')`.
- Add `logo(Icons.memory, 'Лого')` — single merged entry.

Switch in `_buildSection` collapses two cases into one; `_buildGlitch` and `_buildLogoPath` are replaced by a single `_buildLogo`.

### 2. Merged "Лого" section layout

`_buildLogo()` renders one top-level `_SectionHeader(title: 'Лого')` followed by two stacked sub-blocks. Each sub-block uses a smaller visual heading (reuse `_SectionHeader` or a local `_SubHeader` — whichever the plan picks to match existing style):

```
┌─ Лого ──────────────────────────
│
│  ── Глітч-ефект ─────────────
│  desc: "Налаштування візуального глітч-ефекту на логотипі."
│  _GlitchControls(...)                   // unchanged
│
│  (vertical spacer)
│
│  ── Алгоритм руху ──────────
│  desc: "Власна функція позиції логотипа під час анімації
│         вимкнення. Inputs: start, end, screenWidth,
│         screenHeight, t (0→1). Output: return Point(x, y)."
│  LogoPathEditor(...)                    // unchanged
│
│  ── Час анімації ───────────
│  desc: "Скільки триває політ іконки під час
│         вимкнення. Native collapse автоматично
│         підлаштовується."
│  Slider: 400–3000 ms, step 50, default 1100
│  [Reset to default] — visible only when value != null
└─
```

### 3. Persistent setting

In [settings_provider.dart](lib/providers/settings_provider.dart):

- **Constant:** `const int kDefaultLogoAnimationDurationMs = 1100;`
- **Field:** `final int? logoAnimationDurationMs;` on `AppSettings` (null ⇒ use default, same pattern as `logoPathScript`).
- **Key:** `_keyLogoAnimationDurationMs = 'settings_logo_animation_duration_ms'`.
- **`copyWith`:** sentinel pattern (identical to `logoPathScript`) so callers can set `null` to clear.
- **Hydration:** read `prefs.getInt(_keyLogoAnimationDurationMs)` in the provider's load path; coerce out-of-range values to `null` (defensive — in case of manual prefs edits).
- **Setter:** `Future<void> setLogoAnimationDurationMs(int? value)` — null removes the key; non-null clamps to 400–3000 before persisting and updating state.

### 4. Hub screen — single source of truth

In [hub_screen.dart](lib/screens/hub/hub_screen.dart):

- Controllers keep their current constructor defaults (1100 ms / 1500 ms) for the idle case — this avoids a read of `ref` before `initState` completes and keeps existing behavior if shutdown never fires.
- In `_triggerShutdown()`, before `_iconMoveCtrl.forward()` / `_shutdownCtrl.forward()`:
  ```
  final iconMs = ref.read(settingsProvider).logoAnimationDurationMs
                 ?? kDefaultLogoAnimationDurationMs;
  _iconMoveCtrl.duration  = Duration(milliseconds: iconMs);
  _shutdownCtrl.duration  = Duration(milliseconds: iconMs + 400);
  ```
- The hardcoded `Future<void>.delayed(const Duration(milliseconds: 1100))` at [hub_screen.dart:261](lib/screens/hub/hub_screen.dart#L261) becomes `Future<void>.delayed(Duration(milliseconds: iconMs))`.

Invariant: `_shutdownCtrl.duration == _iconMoveCtrl.duration + 400ms`. This preserves the existing sequence (icon flies → native window collapse begins → Flutter flash ends → terminate).

### 5. Slider UI component

Reuse the existing slider style used by `_GlitchControls` (so it matches visually). The component takes:
- current value (`int?`)
- `onChanged(int? value)` — new value, or `null` when user taps "Reset to default"
- hint text below: e.g. «1100 мс — дефолт».

Display:
- Slider fill driven by `(value ?? default)`.
- Numeric label to the right, e.g. `1100 мс`.
- Reset button inline, visible only when `value != null`.

### 6. Testing

- **Unit:** `AppSettings.copyWith` correctly round-trips `logoAnimationDurationMs` including the null-sentinel case (new field must not regress behavior of existing fields).
- **Unit:** `setLogoAnimationDurationMs`:
  - `null` → removes key from `SharedPreferences`.
  - `600` → persists `600` and updates state.
  - Out-of-range values clamped.
- **Integration (optional, if feasible without heavy setup):** rendering the merged settings section does not throw and exposes a slider with default value.

Animation-timing coupling in `_triggerShutdown` is intentionally not unit-tested — it's driven by `AnimationController` side effects and is better verified manually.

## Files Touched

| File | Change |
|------|--------|
| [lib/providers/settings_provider.dart](lib/providers/settings_provider.dart) | New field, key, constant, setter, hydration, copyWith |
| [lib/widgets/settings/settings_dialog.dart](lib/widgets/settings/settings_dialog.dart) | Category enum change; `_buildGlitch` + `_buildLogoPath` → `_buildLogo`; new duration slider |
| [lib/screens/hub/hub_screen.dart](lib/screens/hub/hub_screen.dart) | Read setting in `_triggerShutdown`, recompute both controller durations, replace hardcoded `Future.delayed` |
| `test/providers/settings_provider_test.dart` (or nearest existing) | Unit tests for the new setting |

## Risk & Rollback

- **Risk:** users who previously used only the glitch tab might be briefly confused by the rename. Low impact — the category icon change (`Icons.memory` or similar) + label «Лого» is self-evident.
- **Risk:** clamping at 3000 ms means shutdown can grow up to 3.4 s, which is noticeably slower. Acceptable — it's an explicit user choice.
- **Rollback:** revert commit; no migrations, no data loss. Existing `settings_glitch_*` and `settings_logo_path_script` keys are untouched.

## Open Questions

None remaining — variant A (coupled shutdown timing) approved.

# Gemini CLI Integration

## Overview

PixelCode now supports dual AI provider architecture with Claude Code and Gemini. The integration allows developers to hardcode agents to run on specific providers based on their strengths.

## Architecture

### Services Layer

#### `lib/services/gemini_auth_service.dart`
- Mirrors the Claude auth service pattern
- Wraps `gemini-cli` subprocess calls
- Provides:
  - `GeminiAuthStatus` — models login state, email, and project ID
  - `GeminiAuthService.checkStatus()` — runs `gemini-cli auth status`
  - `GeminiAuthService.login()` — opens browser for OAuth
  - `GeminiAuthService.logout()` — clears credentials

**Binary Detection:** Searches for `gemini-cli` on PATH (macOS/Linux only).

### Providers Layer

#### `lib/providers/gemini_auth_provider.dart`
- Riverpod `AsyncNotifierProvider<GeminiAuthNotifier, GeminiAuthStatus>`
- Methods:
  - `refresh()` — re-check auth status
  - `login()` — trigger OAuth flow
  - `logout()` — clear session

### UI Layer

#### `lib/widgets/settings/settings_dialog.dart` — Account Section
Updated `_AccountSection` now displays:
- **Claude auth** button: "Uvijty через claude.ai"
- **Gemini auth** button: "Uvijty через Google (gemini-cli)"
- Separate status indicators for each provider
- Login/logout handled independently

## Setup

### User: Link Google Account
1. Open Settings → Account
2. Click **"Uvijty через Google (gemini-cli)"**
3. Browser opens for Google OAuth
4. `gemini-cli` stores credentials locally
5. Status updates to show logged-in email

### Developer: Route Agents to Providers

Currently, agent routing is **developer-hardcoded**. Example pattern:

```dart
// In agent service/factory
const coderAgent = AgentConfig(
  name: 'Code Transformer',
  provider: AIProvider.claude,  // Explicitly Claude
  // ...
);

const designAgent = AgentConfig(
  name: 'UI Designer',
  provider: AIProvider.gemini,  // Use Gemini
  // ...
);
```

**Future:** Add agent capability matrix to determine optimal provider per task type.

## Files Added

- `lib/services/gemini_auth_service.dart` (133 lines)
- `lib/providers/gemini_auth_provider.dart` (37 lines)
- `test/services/gemini_auth_service_test.dart` (60 lines)
- `docs/GEMINI_INTEGRATION.md` (this file)

## Files Modified

- `lib/widgets/settings/settings_dialog.dart`
  - Added import: `gemini_auth_provider`
  - Refactored account section to show both providers
  - New methods: `_buildAuthSection()`, `_buildAuthProviderButton()`

## Testing

All auth service tests pass:
- ✓ GeminiAuthStatus JSON parsing
- ✓ Status initialization (logged-in, notLoggedIn)
- ✓ Binary detection (platform-aware)

Run:
```bash
flutter test test/services/gemini_auth_service_test.dart
```

## Next Steps

1. **Determine Gemini strengths** — LLM specialist should identify which agent types (vision, code, design) should default to Gemini
2. **Create AIProvider enum** — add provider selection to agent models
3. **Agent factory** — implement logic to select provider based on agent type + capabilities
4. **Testing** — integration tests for agent routing

## Known Limitations

- Windows support deferred (macOS/Linux only for now)
- Binary detection assumes standard PATH/extension location
- No credential storage (relies on `gemini-cli` local keychain)

/// Test helper to initialize localization for widget tests.
library;

import 'package:pixelcode/services/localization_service.dart';

/// Initialize localization service with test translations.
/// Must be called before running tests that depend on localization.
void initTestLocalization() {
  // Initialize with English for tests (more stable for snapshot tests)
  LocalizationService().initialize(initialLanguage: AppLanguage.en);
}

/// Localization service — manages UI string translations.
/// Supports language switching with persistence.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppLanguage {
  en,
  uk;

  String get code => name;

  String get displayName => switch (this) {
        AppLanguage.en => 'English',
        AppLanguage.uk => 'Українська',
      };
}

class LocalizationService {
  static final LocalizationService _instance = LocalizationService._internal();

  factory LocalizationService() => _instance;

  LocalizationService._internal();

  late AppLanguage _currentLanguage = AppLanguage.uk;
  late Map<String, Map<String, String>> _translations = {};

  AppLanguage get currentLanguage => _currentLanguage;

  Future<void> initialize({AppLanguage? initialLanguage}) async {
    _currentLanguage = initialLanguage ?? AppLanguage.uk;
    await _loadTranslations();
  }

  Future<void> _loadTranslations() async {
    try {
      final enJson = await rootBundle.loadString('assets/i18n/en.json');
      final ukJson = await rootBundle.loadString('assets/i18n/uk.json');

      _translations = {
        'en': (jsonDecode(enJson) as Map).cast<String, String>(),
        'uk': (jsonDecode(ukJson) as Map).cast<String, String>(),
      };
    } catch (e) {
      debugPrint('[Localization] Error loading translations: $e');
    }
  }

  String t(String key) {
    final lang = _currentLanguage.code;
    return _translations[lang]?[key] ?? key;
  }

  Future<void> setLanguage(AppLanguage language) async {
    _currentLanguage = language;
    // TODO: persist language preference to local storage
  }
}

final localization = LocalizationService();

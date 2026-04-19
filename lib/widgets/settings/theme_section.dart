/// Theme browser & customisation panel for the settings dialog.
///
/// Shows a grid of theme cards (standard + premium), lets the user
/// preview, purchase, activate and customise themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../providers/game_economy_provider.dart';

// ─── Main theme section ───────────────────────────────────────────────────

class ThemeSection extends ConsumerStatefulWidget {
  const ThemeSection({super.key});

  @override
  ConsumerState<ThemeSection> createState() => _ThemeSectionState();
}

class _ThemeSectionState extends ConsumerState<ThemeSection> {
  /// Theme currently selected for preview/customisation (may differ from
  /// the active theme while the user is browsing).
  String? _previewId;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameEconomyProvider);
    final economy = ref.read(gameEconomyProvider.notifier);
    final themeState = game.themeState;
    final activeId = themeState.activeThemeId;
    final previewId = _previewId ?? activeId;
    final previewDef = themeById(previewId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Standard themes ──────────────────────────────────────────
        _CategoryLabel(label: ThemeCategory.standard.label),
        const SizedBox(height: 10),
        _ThemeGrid(
          themes: standardThemes,
          activeId: activeId,
          previewId: previewId,
          ownedThemes: themeState.ownedThemes,
          onSelect: (id) => setState(() => _previewId = id),
          isOwned: economy.ownsTheme,
        ),

        const SizedBox(height: 20),

        // ── Premium themes ───────────────────────────────────────────
        _CategoryLabel(label: ThemeCategory.premium.label, isPremium: true),
        const SizedBox(height: 10),
        _ThemeGrid(
          themes: premiumThemes,
          activeId: activeId,
          previewId: previewId,
          ownedThemes: themeState.ownedThemes,
          onSelect: (id) => setState(() => _previewId = id),
          isOwned: economy.ownsTheme,
        ),

        // ── Seasonal themes (if any available) ───────────────────────
        if (availableSeasonalThemes().isNotEmpty) ...[
          const SizedBox(height: 20),
          _CategoryLabel(label: ThemeCategory.seasonal.label, isSeasonal: true),
          const SizedBox(height: 10),
          _ThemeGrid(
            themes: availableSeasonalThemes(),
            activeId: activeId,
            previewId: previewId,
            ownedThemes: themeState.ownedThemes,
            onSelect: (id) => setState(() => _previewId = id),
            isOwned: economy.ownsTheme,
          ),
        ],

        // ── Preview / Action area ────────────────────────────────────
        if (previewDef != null) ...[
          const SizedBox(height: 20),
          _ThemePreviewCard(
            theme: previewDef,
            isActive: previewId == activeId,
            isOwned: economy.ownsTheme(previewId),
            canAfford: game.grymni >= previewDef.cost,
            customization: themeState.customizations[previewId],
            onActivate: () {
              economy.activateTheme(previewId);
              setState(() => _previewId = null);
            },
            onPurchase: () {
              economy.purchaseTheme(previewId);
            },
            onCustomize: previewDef.isCustomizable &&
                    economy.ownsTheme(previewId)
                ? (c) => economy.customizeTheme(previewId, c)
                : null,
          ),
        ],
      ],
    );
  }
}

// ─── Category label ───────────────────────────────────────────────────────

class _CategoryLabel extends StatelessWidget {
  final String label;
  final bool isPremium;
  final bool isSeasonal;

  const _CategoryLabel({
    required this.label,
    this.isPremium = false,
    this.isSeasonal = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isPremium
                ? c.gold.withValues(alpha: 0.7)
                : isSeasonal
                    ? c.success.withValues(alpha: 0.7)
                    : c.textLow,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        if (isPremium) ...[
          const SizedBox(width: 6),
          Icon(Icons.auto_awesome, size: 12, color: c.gold.withValues(alpha: 0.5)),
        ],
        if (isSeasonal) ...[
          const SizedBox(width: 6),
          Icon(Icons.event, size: 12, color: c.success.withValues(alpha: 0.5)),
        ],
      ],
    );
  }
}

// ─── Theme grid ───────────────────────────────────────────────────────────

class _ThemeGrid extends StatelessWidget {
  final List<AppThemeDefinition> themes;
  final String activeId;
  final String previewId;
  final Set<String> ownedThemes;
  final ValueChanged<String> onSelect;
  final bool Function(String) isOwned;

  const _ThemeGrid({
    required this.themes,
    required this.activeId,
    required this.previewId,
    required this.ownedThemes,
    required this.onSelect,
    required this.isOwned,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final theme in themes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ThemeRow(
              theme: theme,
              isActive: theme.id == activeId,
              isSelected: theme.id == previewId,
              isOwned: isOwned(theme.id),
              onTap: () => onSelect(theme.id),
            ),
          ),
      ],
    );
  }
}

// ─── Individual theme row ─────────────────────────────────────────────────

class _ThemeRow extends StatelessWidget {
  final AppThemeDefinition theme;
  final bool isActive;
  final bool isSelected;
  final bool isOwned;
  final VoidCallback onTap;

  const _ThemeRow({
    required this.theme,
    required this.isActive,
    required this.isSelected,
    required this.isOwned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tc = theme.colors;
    final borderColor = isSelected
        ? tc.accent
        : isActive
            ? tc.accent.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.06);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          gradient: LinearGradient(
            colors: [
              tc.accent.withValues(alpha: isSelected ? 0.25 : 0.12),
              tc.background.withValues(alpha: isSelected ? 0.9 : 0.7),
            ],
            stops: const [0.0, 0.55],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // Color bar
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                color: tc.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            // Name
            Expanded(
              child: Text(
                theme.name,
                style: TextStyle(
                  color: isSelected
                      ? tc.accent
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            // Price badge (not owned)
            if (!isOwned && !theme.isFree) ...[
              Icon(Icons.lock_outline,
                  size: 11,
                  color: Colors.white.withValues(alpha: 0.35)),
              const SizedBox(width: 4),
              Text(
                '${theme.cost} ₲',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 4),
            ],
            // Active indicator
            if (isActive)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tc.accent,
                ),
              )
            else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

// ─── Theme preview card with actions ──────────────────────────────────────

class _ThemePreviewCard extends StatelessWidget {
  final AppThemeDefinition theme;
  final bool isActive;
  final bool isOwned;
  final bool canAfford;
  final ThemeCustomization? customization;
  final VoidCallback onActivate;
  final VoidCallback onPurchase;
  final ValueChanged<ThemeCustomization>? onCustomize;

  const _ThemePreviewCard({
    required this.theme,
    required this.isActive,
    required this.isOwned,
    required this.canAfford,
    required this.customization,
    required this.onActivate,
    required this.onPurchase,
    this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final resolved = resolveThemeColors(theme, customization);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                '${theme.emoji} ${theme.name}',
                style: TextStyle(
                  color: c.textHigh,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (theme.isPremium && !isOwned)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.gold.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${theme.cost} ₲',
                    style: TextStyle(
                      color: c.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Активна',
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Description
          Text(
            theme.description,
            style: TextStyle(color: c.textMedium, fontSize: 12),
          ),
          const SizedBox(height: 12),

          // Live preview strip
          _LivePreviewStrip(colors: resolved),
          const SizedBox(height: 14),

          // ── Customisation controls (premium, owned only) ──────────
          if (onCustomize != null) ...[
            _CustomizationPanel(
              theme: theme,
              customization: customization ?? const ThemeCustomization(),
              onChanged: onCustomize!,
            ),
            const SizedBox(height: 14),
          ],

          // ── Action button ──────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 40,
            child: _buildActionButton(context, c),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, ThemeColors c) {
    if (isActive) {
      // Already active
      return OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textLow,
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('Вже активна'),
      );
    }

    if (!isOwned) {
      // Need to purchase
      return FilledButton.icon(
        onPressed: canAfford ? onPurchase : null,
        icon: Icon(
          canAfford ? Icons.shopping_cart_outlined : Icons.lock_outline,
          size: 15,
        ),
        label: Text(canAfford ? 'Придбати за ${theme.cost} ₲' : 'Не вистачає ₲'),
        style: FilledButton.styleFrom(
          backgroundColor: canAfford ? c.gold : c.textLow.withValues(alpha: 0.2),
          foregroundColor: canAfford ? Colors.black : c.textLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    // Owned, can activate
    return FilledButton.icon(
      onPressed: onActivate,
      icon: const Icon(Icons.palette_outlined, size: 15),
      label: const Text('Активувати'),
      style: FilledButton.styleFrom(
        backgroundColor: theme.colors.accent,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ─── Live preview strip ───────────────────────────────────────────────────

class _LivePreviewStrip extends StatelessWidget {
  final ThemeColors colors;
  const _LivePreviewStrip({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Mini "surface card"
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(5),
              ),
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: colors.textHigh,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 3,
                    width: 28,
                    decoration: BoxDecoration(
                      color: colors.textMedium,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Mini "accent button"
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 20,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Mini colour indicators
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _miniDot(colors.gold),
              const SizedBox(height: 3),
              _miniDot(colors.success),
              const SizedBox(height: 3),
              _miniDot(colors.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniDot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
}

// ─── Customisation panel ──────────────────────────────────────────────────

class _CustomizationPanel extends StatelessWidget {
  final AppThemeDefinition theme;
  final ThemeCustomization customization;
  final ValueChanged<ThemeCustomization> onChanged;

  const _CustomizationPanel({
    required this.theme,
    required this.customization,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 13, color: c.textMedium),
              const SizedBox(width: 6),
              Text(
                'Кастомізація',
                style: TextStyle(
                  color: c.textMedium,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Accent colour ─────────────────────────────────────────
          if (theme.accentPalette.isNotEmpty) ...[
            Text(
              'Акцент',
              style: TextStyle(color: c.textLow, fontSize: 10),
            ),
            const SizedBox(height: 6),
            _ColorPicker(
              colors: theme.accentPalette,
              selectedIndex: customization.accentIndex,
              defaultColor: theme.colors.accent,
              onSelect: (i) => onChanged(ThemeCustomization(
                accentIndex: i,
                backgroundIndex: customization.backgroundIndex,
                highlightIndex: customization.highlightIndex,
              )),
            ),
            const SizedBox(height: 10),
          ],

          // ── Background shade ──────────────────────────────────────
          if (theme.backgroundShades.isNotEmpty) ...[
            Text(
              'Фон',
              style: TextStyle(color: c.textLow, fontSize: 10),
            ),
            const SizedBox(height: 6),
            _ColorPicker(
              colors: theme.backgroundShades,
              selectedIndex: customization.backgroundIndex,
              defaultColor: theme.colors.background,
              onSelect: (i) => onChanged(ThemeCustomization(
                accentIndex: customization.accentIndex,
                backgroundIndex: i,
                highlightIndex: customization.highlightIndex,
              )),
              isLarge: true,
            ),
            const SizedBox(height: 10),
          ],

          // ── Highlight tint ────────────────────────────────────────
          if (theme.highlightTints.isNotEmpty) ...[
            Text(
              'Виділення',
              style: TextStyle(color: c.textLow, fontSize: 10),
            ),
            const SizedBox(height: 6),
            _ColorPicker(
              colors: theme.highlightTints,
              selectedIndex: customization.highlightIndex,
              defaultColor: theme.colors.gold,
              onSelect: (i) => onChanged(ThemeCustomization(
                accentIndex: customization.accentIndex,
                backgroundIndex: customization.backgroundIndex,
                highlightIndex: i,
              )),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Colour picker row ───────────────────────────────────────────────────

class _ColorPicker extends StatelessWidget {
  final List<Color> colors;
  final int? selectedIndex;
  final Color defaultColor;
  final ValueChanged<int?> onSelect;
  final bool isLarge;

  const _ColorPicker({
    required this.colors,
    required this.selectedIndex,
    required this.defaultColor,
    required this.onSelect,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = isLarge ? 28.0 : 22.0;

    return Row(
      children: [
        // "Default" option
        GestureDetector(
          onTap: () => onSelect(null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: defaultColor,
              borderRadius: BorderRadius.circular(isLarge ? 6 : 4),
              border: Border.all(
                color: selectedIndex == null
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.15),
                width: selectedIndex == null ? 2 : 1,
              ),
            ),
            child: selectedIndex == null
                ? Center(
                    child: Icon(Icons.check, size: 12, color: Colors.white),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 6),
        // Custom options
        for (var i = 0; i < colors.length; i++) ...[
          GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: colors[i],
                borderRadius: BorderRadius.circular(isLarge ? 6 : 4),
                border: Border.all(
                  color: selectedIndex == i
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.15),
                  width: selectedIndex == i ? 2 : 1,
                ),
              ),
              child: selectedIndex == i
                  ? Center(
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: _contrastForeground(colors[i]),
                      ),
                    )
                  : null,
            ),
          ),
          if (i < colors.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  /// Pick black or white foreground depending on luminance.
  static Color _contrastForeground(Color bg) =>
      bg.computeLuminance() > 0.4 ? Colors.black : Colors.white;
}

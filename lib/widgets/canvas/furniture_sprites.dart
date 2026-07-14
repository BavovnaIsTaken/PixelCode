/// Text-sprite definitions for furniture and decoration shop icons.
///
/// All sprites are 8 columns wide, 10 rows tall (displayed at ×4 scale = 32×40 dp).
/// Color key namespace is separate from character sprites — same letter means
/// a different colour here. Resolver: [resolveFurnitureSpriteColor].
library;

import 'package:flutter/material.dart';

// ─── Colour resolver ────────────────────────────────────────────────────────

Color resolveFurnitureSpriteColor(String key) => switch (key) {
      // ── Existing furniture palette ──
      'd' => const Color(0xFF5C4033), // desk wood
      'k' => const Color(0xFF3E2B22), // desk edge / dark wood
      'm' => const Color(0xFF2A2A35), // monitor frame
      'g' => const Color(0xFF007A84), // monitor glow dim
      'G' => const Color(0xFF00C0D1), // accent cyan / glow bright
      // ── Plants ──
      'P' => const Color(0xFF2D5A1B), // plant dark green
      'p' => const Color(0xFF4A8A2C), // plant highlight green
      'V' => const Color(0xFF7B5E45), // pot terracotta
      'v' => const Color(0xFF5C4033), // pot shadow (= desk wood)
      // ── Metal / tech ──
      'B' => const Color(0xFF2A3448), // metal housing
      'T' => const Color(0xFF1C2230), // rack frame (darkest metal)
      'R' => const Color(0xFF00FF88), // LED on
      'r' => const Color(0xFF004422), // LED off
      // ── Kitchen / coffee ──
      'C' => const Color(0xFFD9B48F), // ceramic cup / warm beige
      'H' => const Color(0xFF8B4513), // coffee liquid / hot brown
      // ── Whiteboard ──
      'W' => const Color(0xFFE8ECF0), // whiteboard surface
      'w' => const Color(0xFF88BBEE), // marker line (meeting room blue)
      // ── Storage / shelves ──
      'S' => const Color(0xFF4A3728), // shelf wood (darker than desk)
      's' => const Color(0xFF2E2018), // shelf edge / shadow
      'N' => const Color(0xFF7C3AED), // book spine purple (reviewer)
      'n' => const Color(0xFF059669), // book spine green (coder)
      'O' => const Color(0xFFD97706), // book spine orange (manager)
      // ── Trophy ──
      'Y' => const Color(0xFFF59E0B), // trophy gold
      'y' => const Color(0xFFB45309), // gold shadow
      'Z' => const Color(0xFF3E2B22), // trophy base
      // ── Seating ──
      'A' => const Color(0xFF2563EB), // lounge fabric blue (ui-ux)
      'a' => const Color(0xFF1D4ED8), // lounge fabric shadow
      'F' => const Color(0xFFEC4899), // beanbag pink (tester)
      'f' => const Color(0xFFDB2777), // beanbag dark pink
      // ── Posters ──
      'X' => const Color(0xFF1A1A2E), // poster background (wall)
      'x' => const Color(0xFF00C0D1), // poster text / accent
      'z' => const Color(0xFF252540), // poster border
      // ── Water cooler ──
      'Q' => const Color(0xFFBFDBFE), // water light blue
      'q' => const Color(0xFF60A5FA), // water mid blue
      _ => Colors.transparent,
    };

// ─── Sprites (8 wide × 10 tall) ─────────────────────────────────────────────

const _plantSmall = [
  '...pp...',
  '..PPP...',
  '..PPP...',
  '.PPPPP..',
  '...PP...',
  '..VVVv..',
  '.VVVVVv.',
  '.VVVVVv.',
  '........',
  '........',
];

const _plantLarge = [
  '..pPp...',
  '.PPPPP..',
  'pPPPPPp.',
  '.PPPPP..',
  '..PPP...',
  '..VVVv..',
  '.VVVVVv.',
  '.VVVVVv.',
  '..VVVv..',
  '........',
];

const _posterMotivational = [
  'zXXXXXXz',
  'zX....Xz',
  'zX.xx.Xz',
  'zX.xx.Xz',
  'zX....Xz',
  'zX.xX.Xz',
  'zX.xX.Xz',
  'zX....Xz',
  'zXXXXXXz',
  '...kk...',
];

const _posterCode = [
  'zXXXXXXz',
  'zX.GG.Xz',
  'zX..G.Xz',
  'zX.GG.Xz',
  'zX....Xz',
  'zX.xG.Xz',
  'zX.xG.Xz',
  'zX....Xz',
  'zXXXXXXz',
  '...kk...',
];

const _waterCooler = [
  '..BBBB..',
  '.BBBBBB.',
  '.B.QQ.B.',
  '.B.QQ.B.',
  '.B.qq.B.',
  '.BBBBBB.',
  'BBBBBBBB',
  '..kBBk..',
  '...kk...',
  '........',
];

const _coffeeTableBasic = [
  '........',
  '........',
  'kkkkkkkk',
  'dddddddd',
  'dddddddd',
  'kk....kk',
  '.k....k.',
  '.k....k.',
  '........',
  '........',
];

const _coffeeTablePremium = [
  '........',
  '........',
  '.kkkkkk.',
  'kddddddk',
  'kddddddk',
  'kddddddk',
  '.kkkkkk.',
  '..k..k..',
  '........',
  '........',
];

const _coffeeTableDesigner = [
  '........',
  '........',
  '.GkkkGk.',
  'kGddddGk',
  'kGddddGk',
  'kGddddGk',
  '.GkkkGk.',
  '..k..k..',
  '........',
  '........',
];

const _oldDesk = [
  '........',
  '........',
  'kkkkkkkk',
  'kd....dk',
  'kd....dk',
  'kd....dk',
  '.k....k.',
  '.k....k.',
  '........',
  '........',
];

const _deskWorkstation = [
  '........',
  '..mmmm..',
  '..mGGm..',
  '..mggm..',
  '...mm...',
  'kkkkkkkk',
  'dddddddd',
  'dddddddd',
  'kk....kk',
  '.k....k.',
];

const _stool = [
  '........',
  '........',
  '........',
  '.dddddd.',
  '.dddddd.',
  '...kk...',
  '..k..k..',
  '.k....k.',
  '........',
  '........',
];

const _cardboardBoxesFixed = [
  '........',
  '..dddd..',
  '.ddkkddk',
  'kddddddk',
  'kddddddk',
  'kd....dk',
  'kddddddk',
  '........',
  '........',
  '........',
];

const _snackTableBasic = [
  '...CC...',
  '..CddC..',
  'kkkkkkkk',
  'dddddddd',
  'dddddddd',
  'kk....kk',
  '.k....k.',
  '.k....k.',
  '........',
  '........',
];

const _snackTableCandy = [
  '.FYCoYF.',
  '.CCCCCC.',
  'kkkkkkkk',
  'dddddddd',
  'dddddddd',
  'kk....kk',
  '.k....k.',
  '.k....k.',
  '........',
  '........',
];

const _snackTableBuffet = [
  'FYCCoYCF',
  'CCCCCCCC',
  'kkkkkkkk',
  'dddddddd',
  'dddddddd',
  'kkkkkkkk',
  'kk....kk',
  '.k....k.',
  '........',
  '........',
];

const _bookshelf = [
  'ssssssss',
  'SN.NO.nS',
  'SN.NO.nS',
  'SN.NO.nS',
  'ssssssss',
  'SO.Nn.NS',
  'SO.Nn.NS',
  'SO.Nn.NS',
  'ssssssss',
  's......s',
];

const _filingCabinet = [
  '.BBBBBB.',
  'BBBBBBBB',
  'BB....BB',
  'BBkkkkBB',
  'BB....BB',
  'BBkkkkBB',
  'BB....BB',
  'BBkkkkBB',
  'BBBBBBBB',
  'kBBBBBBk',
];

const _beanbag = [
  '..FFFF..',
  '.FFFFFF.',
  'FFFFFFFF',
  'FFFFFFFF',
  '.fFFFFf.',
  '..FFFF..',
  '...ff...',
  '........',
  '........',
  '........',
];

const _couchSmall = [
  '........',
  'AAAAAAAA',
  'AAAAAAAA',
  'aAAAAAAa',
  'aAAAAAAa',
  'aAAAAAAa',
  'AAAAAAAA',
  '.kAAAAk.',
  '.k....k.',
  '........',
];

// ─── Sprite map ──────────────────────────────────────────────────────────────

/// Maps furniture item id → text sprite.
const furnitureSpriteMap = <String, List<String>>{
  'plant_small': _plantSmall,
  'plant_large': _plantLarge,
  'poster_motivational': _posterMotivational,
  'poster_code': _posterCode,
  'water_cooler': _waterCooler,
  'coffee_table_basic': _coffeeTableBasic,
  'coffee_table_premium': _coffeeTablePremium,
  'coffee_table_designer': _coffeeTableDesigner,
  'old_desk': _oldDesk,
  'desk_workstation': _deskWorkstation,
  'stool': _stool,
  'cardboard_boxes': _cardboardBoxesFixed,
  'snack_table_basic': _snackTableBasic,
  'snack_table_candy': _snackTableCandy,
  'snack_table_buffet': _snackTableBuffet,
  'bookshelf': _bookshelf,
  'filing_cabinet': _filingCabinet,
  'beanbag': _beanbag,
  'couch_small': _couchSmall,
};

// ─── Widget ──────────────────────────────────────────────────────────────────

/// Pixel-art icon for a furniture item, 32×40 dp (8×10 at scale ×4).
/// Falls back to null if no sprite is registered for [itemId].
class FurnitureSpriteIcon extends StatelessWidget {
  final String itemId;
  final double scale;

  const FurnitureSpriteIcon({
    super.key,
    required this.itemId,
    this.scale = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    final sprite = furnitureSpriteMap[itemId];
    if (sprite == null) return const SizedBox.shrink();

    final w = (sprite.first.length * scale).ceilToDouble();
    final h = (sprite.length * scale).ceilToDouble();

    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(
        painter: _FurnitureSpritePainter(sprite: sprite, scale: scale),
      ),
    );
  }
}

class _FurnitureSpritePainter extends CustomPainter {
  final List<String> sprite;
  final double scale;

  const _FurnitureSpritePainter({required this.sprite, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (int row = 0; row < sprite.length; row++) {
      final line = sprite[row];
      for (int col = 0; col < line.length; col++) {
        final ch = line[col];
        if (ch == '.') continue;
        final color = resolveFurnitureSpriteColor(ch);
        if (color == Colors.transparent) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(
            col * scale,
            row * scale,
            scale + 0.5,
            scale + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FurnitureSpritePainter old) =>
      old.sprite != sprite || old.scale != scale;
}

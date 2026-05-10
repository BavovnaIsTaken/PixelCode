/// Character skin definitions — 8 palette themes for agent teams.
///
/// Each skin defines per-agent palettes (hair, skin, eye, clothes, etc.)
/// so agents remain visually distinct while sharing an overall aesthetic.
///
/// Skins:
///   1. Default — original PixelCode palettes
///   2. Casual — hoodies, relaxed streetwear
///   3. Corporate — dark suits, formal wear
///   4. Hacker — dark hoods, terminal green
///   5. Creative — bright, artistic, expressive
///   6. Retro — muted vintage / 80s tones
///   7. Cyberpunk — neon on black, chrome accents
///   8. Cozy — warm sweaters, autumn palette
library;

import 'package:flutter/material.dart';

import '../../models/resource_pack.dart';

// ─── Helper to build a skin's 7-agent palette map ───────────────────────────

const _agents = [
  'tech-lead',
  'manager',
  'coder',
  'reviewer',
  'tester',
  'security',
  'ui-ux-designer',
  'llm-specialist',
  'game-designer',
  'strategy-keeper',
  'character-artist',
];

Map<String, SkinPalette> _buildPalettes(List<SkinPalette> list) {
  assert(list.length == _agents.length);
  return {for (int i = 0; i < _agents.length; i++) _agents[i]: list[i]};
}

// ─── 1. Default ─────────────────────────────────────────────────────────────

final skinDefault = CharacterSkin(
  id: 'default',
  name: 'Стандарт',
  nameEn: 'Default',
  palettes: _buildPalettes(const [
    // tech-lead
    SkinPalette(
      hair: Color(0xFF1A1A2E), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF00C0D1),
      clothes: Color(0xFF00949F), pants: Color(0xFF2C3E50),
      boots: Color(0xFF1A1A1A),
    ),
    // manager
    SkinPalette(
      hair: Color(0xFF8B4513), skin: Color(0xFFD4A574),
      skinLight: Color(0xFFE8C49A), eye: Color(0xFFF59E0B),
      clothes: Color(0xFFD97706), pants: Color(0xFF44403C),
      boots: Color(0xFF292524),
    ),
    // coder
    SkinPalette(
      hair: Color(0xFF2D1B69), skin: Color(0xFFC68642),
      skinLight: Color(0xFFD4956B), eye: Color(0xFF10B981),
      clothes: Color(0xFF059669), pants: Color(0xFF1E293B),
      boots: Color(0xFF0F172A),
    ),
    // reviewer
    SkinPalette(
      hair: Color(0xFF4A1A6B), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF8B5CF6),
      clothes: Color(0xFF7C3AED), pants: Color(0xFF334155),
      boots: Color(0xFF1E293B),
    ),
    // tester
    SkinPalette(
      hair: Color(0xFFB91C1C), skin: Color(0xFFFDBCB4),
      skinLight: Color(0xFFFFD5CC), eye: Color(0xFFEC4899),
      clothes: Color(0xFFDB2777), pants: Color(0xFF374151),
      boots: Color(0xFF1F2937),
    ),
    // security
    SkinPalette(
      hair: Color(0xFF1F2937), skin: Color(0xFF8D5524),
      skinLight: Color(0xFFA0714B), eye: Color(0xFFEF4444),
      clothes: Color(0xFFDC2626), pants: Color(0xFF27272A),
      boots: Color(0xFF18181B),
    ),
    // ui-ux-designer
    SkinPalette(
      hair: Color(0xFFFF6B9D), skin: Color(0xFFF3D2C1),
      skinLight: Color(0xFFFBE8DC), eye: Color(0xFF3B82F6),
      clothes: Color(0xFF2563EB), pants: Color(0xFF3F3F46),
      boots: Color(0xFF27272A),
    ),
    // llm-specialist — neon violet
    SkinPalette(
      hair: Color(0xFF2A1B4D), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF9B59FF),
      clothes: Color(0xFF6C2BD9), pants: Color(0xFF1E1B2E),
      boots: Color(0xFF0F0E1A),
    ),
    // game-designer — gold blazer
    SkinPalette(
      hair: Color(0xFF4A3818), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFFFFD700),
      clothes: Color(0xFFCA8A04), pants: Color(0xFF3A2F1E),
      boots: Color(0xFF1A1408),
    ),
    // strategy-keeper — navy lighthouse-keeper, icy sky eye
    SkinPalette(
      hair: Color(0xFF1F2937), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF7DD3FC),
      clothes: Color(0xFF1E3A8A), pants: Color(0xFF1E293B),
      boots: Color(0xFF0F172A),
    ),
    // character-artist — copper hair, violet paint apron
    SkinPalette(
      hair: Color(0xFFC2410C), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFFFBBF24),
      clothes: Color(0xFF5B21B6), pants: Color(0xFF44403C),
      boots: Color(0xFF292524),
    ),
  ]),
);

// ─── 2. Casual — hoodies & jeans ────────────────────────────────────────────

final skinCasual = CharacterSkin(
  id: 'casual',
  name: 'Кежуал',
  nameEn: 'Casual',
  palettes: _buildPalettes(const [
    // tech-lead — teal hoodie
    SkinPalette(
      hair: Color(0xFF1A1A2E), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF00C0D1),
      clothes: Color(0xFF1A8A8A), pants: Color(0xFF3B5998),
      boots: Color(0xFF4A4A50),
    ),
    // manager — orange hoodie
    SkinPalette(
      hair: Color(0xFF8B4513), skin: Color(0xFFD4A574),
      skinLight: Color(0xFFE8C49A), eye: Color(0xFFF59E0B),
      clothes: Color(0xFFCC6600), pants: Color(0xFF4A5568),
      boots: Color(0xFF3A3A3A),
    ),
    // coder — dark green hoodie
    SkinPalette(
      hair: Color(0xFF2D1B69), skin: Color(0xFFC68642),
      skinLight: Color(0xFFD4956B), eye: Color(0xFF10B981),
      clothes: Color(0xFF1D6B45), pants: Color(0xFF2D3748),
      boots: Color(0xFF2A2A2A),
    ),
    // reviewer — purple zip-up
    SkinPalette(
      hair: Color(0xFF4A1A6B), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF8B5CF6),
      clothes: Color(0xFF5B3A8A), pants: Color(0xFF3B4A5C),
      boots: Color(0xFF363636),
    ),
    // tester — pink sweatshirt
    SkinPalette(
      hair: Color(0xFFB91C1C), skin: Color(0xFFFDBCB4),
      skinLight: Color(0xFFFFD5CC), eye: Color(0xFFEC4899),
      clothes: Color(0xFFA83279), pants: Color(0xFF4B5563),
      boots: Color(0xFF3D3D3D),
    ),
    // security — dark red flannel
    SkinPalette(
      hair: Color(0xFF1F2937), skin: Color(0xFF8D5524),
      skinLight: Color(0xFFA0714B), eye: Color(0xFFEF4444),
      clothes: Color(0xFF8B2020), pants: Color(0xFF333338),
      boots: Color(0xFF2A2A2A),
    ),
    // ui-ux — sky blue sweater
    SkinPalette(
      hair: Color(0xFFFF6B9D), skin: Color(0xFFF3D2C1),
      skinLight: Color(0xFFFBE8DC), eye: Color(0xFF3B82F6),
      clothes: Color(0xFF4488CC), pants: Color(0xFF3F4550),
      boots: Color(0xFF353535),
    ),
    // llm-specialist — purple hoodie
    SkinPalette(
      hair: Color(0xFF2A1B4D), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF9B59FF),
      clothes: Color(0xFF5B2EAF), pants: Color(0xFF2E2A48),
      boots: Color(0xFF1A1825),
    ),
    // game-designer — yellow hoodie
    SkinPalette(
      hair: Color(0xFF4A3818), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFFFFD700),
      clothes: Color(0xFFB58A1A), pants: Color(0xFF383028),
      boots: Color(0xFF2A2A2A),
    ),
    // strategy-keeper — navy hoodie
    SkinPalette(
      hair: Color(0xFF1F2937), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF7DD3FC),
      clothes: Color(0xFF1E40AF), pants: Color(0xFF334155),
      boots: Color(0xFF1E293B),
    ),
    // character-artist — paint-spattered indigo hoodie
    SkinPalette(
      hair: Color(0xFF92400E), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFFF59E0B),
      clothes: Color(0xFF4338CA), pants: Color(0xFF475569),
      boots: Color(0xFF1E293B),
    ),
  ]),
);

// ─── 3. Corporate — suits & ties ────────────────────────────────────────────

final skinCorporate = CharacterSkin(
  id: 'corporate',
  name: 'Корпоратив',
  nameEn: 'Corporate',
  palettes: _buildPalettes(const [
    // tech-lead — charcoal suit, teal tie
    SkinPalette(
      hair: Color(0xFF1A1A2E), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF00C0D1),
      clothes: Color(0xFF2C2C38), pants: Color(0xFF262630),
      boots: Color(0xFF0E0E10),
    ),
    // manager — navy suit, gold pocket square
    SkinPalette(
      hair: Color(0xFF8B4513), skin: Color(0xFFD4A574),
      skinLight: Color(0xFFE8C49A), eye: Color(0xFFF59E0B),
      clothes: Color(0xFF1C2340), pants: Color(0xFF18203A),
      boots: Color(0xFF0C0C14),
    ),
    // coder — dark grey suit, green accent
    SkinPalette(
      hair: Color(0xFF2D1B69), skin: Color(0xFFC68642),
      skinLight: Color(0xFFD4956B), eye: Color(0xFF10B981),
      clothes: Color(0xFF303036), pants: Color(0xFF28282E),
      boots: Color(0xFF101012),
    ),
    // reviewer — plum suit
    SkinPalette(
      hair: Color(0xFF4A1A6B), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF8B5CF6),
      clothes: Color(0xFF2E1C3E), pants: Color(0xFF261834),
      boots: Color(0xFF100C16),
    ),
    // tester — dark pink-grey suit
    SkinPalette(
      hair: Color(0xFFB91C1C), skin: Color(0xFFFDBCB4),
      skinLight: Color(0xFFFFD5CC), eye: Color(0xFFEC4899),
      clothes: Color(0xFF3A2030), pants: Color(0xFF321A28),
      boots: Color(0xFF140E14),
    ),
    // security — black suit, red tie
    SkinPalette(
      hair: Color(0xFF1F2937), skin: Color(0xFF8D5524),
      skinLight: Color(0xFFA0714B), eye: Color(0xFFEF4444),
      clothes: Color(0xFF1A1A1E), pants: Color(0xFF161618),
      boots: Color(0xFF0A0A0C),
    ),
    // ui-ux — slate blue suit
    SkinPalette(
      hair: Color(0xFFFF6B9D), skin: Color(0xFFF3D2C1),
      skinLight: Color(0xFFFBE8DC), eye: Color(0xFF3B82F6),
      clothes: Color(0xFF283848), pants: Color(0xFF222E3C),
      boots: Color(0xFF0E1218),
    ),
    // llm-specialist — deep violet suit
    SkinPalette(
      hair: Color(0xFF2A1B4D), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF9B59FF),
      clothes: Color(0xFF2A1F3D), pants: Color(0xFF221833),
      boots: Color(0xFF0E0A14),
    ),
    // game-designer — charcoal suit, gold tie
    SkinPalette(
      hair: Color(0xFF4A3818), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFFFFD700),
      clothes: Color(0xFF3A2E1A), pants: Color(0xFF302410),
      boots: Color(0xFF120E08),
    ),
    // strategy-keeper — deep navy 3-piece suit
    SkinPalette(
      hair: Color(0xFF1F2937), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF7DD3FC),
      clothes: Color(0xFF1E293B), pants: Color(0xFF0F172A),
      boots: Color(0xFF020617),
    ),
    // character-artist — gallery curator, deep purple suit
    SkinPalette(
      hair: Color(0xFF44403C), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFFB45309),
      clothes: Color(0xFF4C1D95), pants: Color(0xFF1F2937),
      boots: Color(0xFF0F172A),
    ),
  ]),
);

// ─── 4. Hacker — dark hoods, terminal green ─────────────────────────────────

final skinHacker = CharacterSkin(
  id: 'hacker',
  name: 'Хакер',
  nameEn: 'Hacker',
  palettes: _buildPalettes(const [
    // tech-lead
    SkinPalette(
      hair: Color(0xFF0A0A12), skin: Color(0xFFD0A888),
      skinLight: Color(0xFFE0BCA0), eye: Color(0xFF00FF88),
      clothes: Color(0xFF0E0E16), pants: Color(0xFF0C0C10),
      boots: Color(0xFF060608),
    ),
    // manager
    SkinPalette(
      hair: Color(0xFF1A1408), skin: Color(0xFFC09060),
      skinLight: Color(0xFFD0A878), eye: Color(0xFF00FF88),
      clothes: Color(0xFF12120A), pants: Color(0xFF0E0E08),
      boots: Color(0xFF080806),
    ),
    // coder
    SkinPalette(
      hair: Color(0xFF0A0820), skin: Color(0xFFB07838),
      skinLight: Color(0xFFC08C50), eye: Color(0xFF00FF44),
      clothes: Color(0xFF0A0A14), pants: Color(0xFF08080E),
      boots: Color(0xFF040408),
    ),
    // reviewer
    SkinPalette(
      hair: Color(0xFF140A20), skin: Color(0xFFD0A888),
      skinLight: Color(0xFFE0BCA0), eye: Color(0xFF00FFAA),
      clothes: Color(0xFF100E18), pants: Color(0xFF0C0A12),
      boots: Color(0xFF06060A),
    ),
    // tester
    SkinPalette(
      hair: Color(0xFF200808), skin: Color(0xFFE0A898),
      skinLight: Color(0xFFF0BCA8), eye: Color(0xFF00FF66),
      clothes: Color(0xFF141010), pants: Color(0xFF100C0C),
      boots: Color(0xFF080606),
    ),
    // security
    SkinPalette(
      hair: Color(0xFF080C10), skin: Color(0xFF7A4820),
      skinLight: Color(0xFF905C30), eye: Color(0xFFFF2200),
      clothes: Color(0xFF0C0C0E), pants: Color(0xFF08080A),
      boots: Color(0xFF040406),
    ),
    // ui-ux
    SkinPalette(
      hair: Color(0xFF301830), skin: Color(0xFFE0C0AA),
      skinLight: Color(0xFFF0D4BC), eye: Color(0xFF00CCFF),
      clothes: Color(0xFF0E0C14), pants: Color(0xFF0A080E),
      boots: Color(0xFF060408),
    ),
    // llm-specialist — neural net violet glow
    SkinPalette(
      hair: Color(0xFF14081E), skin: Color(0xFFD0A888),
      skinLight: Color(0xFFE0BCA0), eye: Color(0xFFBE6BFF),
      clothes: Color(0xFF100A18), pants: Color(0xFF0C0810),
      boots: Color(0xFF050308),
    ),
    // game-designer — terminal yellow on black
    SkinPalette(
      hair: Color(0xFF1A1408), skin: Color(0xFFD0A888),
      skinLight: Color(0xFFE0BCA0), eye: Color(0xFFFFFF00),
      clothes: Color(0xFF14120A), pants: Color(0xFF100E08),
      boots: Color(0xFF080604),
    ),
    // strategy-keeper — terminal cyan-blue on black
    SkinPalette(
      hair: Color(0xFF080A14), skin: Color(0xFFD0A888),
      skinLight: Color(0xFFE0BCA0), eye: Color(0xFF00CCFF),
      clothes: Color(0xFF0A1228), pants: Color(0xFF08101C),
      boots: Color(0xFF040810),
    ),
    // character-artist — glitch-art violet hood, magenta neon eye
    SkinPalette(
      hair: Color(0xFFA855F7), skin: Color(0xFFC0B8B0),
      skinLight: Color(0xFFD8D0C8), eye: Color(0xFFFF00FF),
      clothes: Color(0xFF1E1B4B), pants: Color(0xFF0F0E1F),
      boots: Color(0xFF050510),
    ),
  ]),
);

// ─── 5. Creative — bright, artistic ─────────────────────────────────────────

final skinCreative = CharacterSkin(
  id: 'creative',
  name: 'Креатив',
  nameEn: 'Creative',
  palettes: _buildPalettes(const [
    // tech-lead — electric blue jacket
    SkinPalette(
      hair: Color(0xFF00838F), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF00E5FF),
      clothes: Color(0xFF0097A7), pants: Color(0xFF455A64),
      boots: Color(0xFF263238),
    ),
    // manager — sunset orange
    SkinPalette(
      hair: Color(0xFFBF360C), skin: Color(0xFFD4A574),
      skinLight: Color(0xFFE8C49A), eye: Color(0xFFFF6D00),
      clothes: Color(0xFFFF8F00), pants: Color(0xFF4E342E),
      boots: Color(0xFF3E2723),
    ),
    // coder — lime green
    SkinPalette(
      hair: Color(0xFF1B5E20), skin: Color(0xFFC68642),
      skinLight: Color(0xFFD4956B), eye: Color(0xFF76FF03),
      clothes: Color(0xFF2E7D32), pants: Color(0xFF33691E),
      boots: Color(0xFF1B5E20),
    ),
    // reviewer — vivid violet
    SkinPalette(
      hair: Color(0xFF6A1B9A), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFFE040FB),
      clothes: Color(0xFF8E24AA), pants: Color(0xFF4A148C),
      boots: Color(0xFF311B92),
    ),
    // tester — hot magenta
    SkinPalette(
      hair: Color(0xFFAD1457), skin: Color(0xFFFDBCB4),
      skinLight: Color(0xFFFFD5CC), eye: Color(0xFFFF4081),
      clothes: Color(0xFFC2185B), pants: Color(0xFF880E4F),
      boots: Color(0xFF4A0028),
    ),
    // security — crimson red
    SkinPalette(
      hair: Color(0xFF212121), skin: Color(0xFF8D5524),
      skinLight: Color(0xFFA0714B), eye: Color(0xFFFF1744),
      clothes: Color(0xFFD50000), pants: Color(0xFF424242),
      boots: Color(0xFF212121),
    ),
    // ui-ux — ocean blue + coral
    SkinPalette(
      hair: Color(0xFFFF8A80), skin: Color(0xFFF3D2C1),
      skinLight: Color(0xFFFBE8DC), eye: Color(0xFF448AFF),
      clothes: Color(0xFF1565C0), pants: Color(0xFF0D47A1),
      boots: Color(0xFF0A2E6B),
    ),
    // llm-specialist — vivid amethyst
    SkinPalette(
      hair: Color(0xFF4527A0), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFFD500F9),
      clothes: Color(0xFF7B1FA2), pants: Color(0xFF311B92),
      boots: Color(0xFF1A0E55),
    ),
    // game-designer — sun yellow + bright gold
    SkinPalette(
      hair: Color(0xFFFFB300), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFFFFEA00),
      clothes: Color(0xFFFFB300), pants: Color(0xFF6E4D00),
      boots: Color(0xFF4A3000),
    ),
    // strategy-keeper — electric sky-blue jacket
    SkinPalette(
      hair: Color(0xFF0F172A), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF38BDF8),
      clothes: Color(0xFF0EA5E9), pants: Color(0xFF1E3A8A),
      boots: Color(0xFF1E40AF),
    ),
    // character-artist — full-rainbow expressionist
    SkinPalette(
      hair: Color(0xFFEC4899), skin: Color(0xFFF3D2C1),
      skinLight: Color(0xFFFBE8DC), eye: Color(0xFFFBBF24),
      clothes: Color(0xFFA855F7), pants: Color(0xFF14B8A6),
      boots: Color(0xFF1E293B),
    ),
  ]),
);

// ─── 6. Retro — muted 80s vintage ──────────────────────────────────────────

final skinRetro = CharacterSkin(
  id: 'retro',
  name: 'Ретро',
  nameEn: 'Retro',
  palettes: _buildPalettes(const [
    // tech-lead — faded teal
    SkinPalette(
      hair: Color(0xFF2E3830), skin: Color(0xFFD4B898),
      skinLight: Color(0xFFE4CCA8), eye: Color(0xFF6BADA8),
      clothes: Color(0xFF4A8A80), pants: Color(0xFF585850),
      boots: Color(0xFF3A3A34),
    ),
    // manager — mustard
    SkinPalette(
      hair: Color(0xFF5C3A14), skin: Color(0xFFC49870),
      skinLight: Color(0xFFD8AC84), eye: Color(0xFFC8A830),
      clothes: Color(0xFFA88A20), pants: Color(0xFF50483C),
      boots: Color(0xFF383028),
    ),
    // coder — olive drab
    SkinPalette(
      hair: Color(0xFF2A2850), skin: Color(0xFFB08048),
      skinLight: Color(0xFFC09460), eye: Color(0xFF68A060),
      clothes: Color(0xFF506840), pants: Color(0xFF404838),
      boots: Color(0xFF2C3028),
    ),
    // reviewer — dusty lavender
    SkinPalette(
      hair: Color(0xFF484060), skin: Color(0xFFD4B898),
      skinLight: Color(0xFFE4CCA8), eye: Color(0xFF8878A0),
      clothes: Color(0xFF6E6088), pants: Color(0xFF4C4858),
      boots: Color(0xFF343040),
    ),
    // tester — faded rose
    SkinPalette(
      hair: Color(0xFF804028), skin: Color(0xFFE8B8A0),
      skinLight: Color(0xFFF8CCB0), eye: Color(0xFFC07878),
      clothes: Color(0xFF985858), pants: Color(0xFF504848),
      boots: Color(0xFF383434),
    ),
    // security — army surplus
    SkinPalette(
      hair: Color(0xFF2C3028), skin: Color(0xFF7A5028),
      skinLight: Color(0xFF8C6438), eye: Color(0xFF986040),
      clothes: Color(0xFF586048), pants: Color(0xFF3C3830),
      boots: Color(0xFF282820),
    ),
    // ui-ux — periwinkle
    SkinPalette(
      hair: Color(0xFFA06880), skin: Color(0xFFE0C0A8),
      skinLight: Color(0xFFF0D4B8), eye: Color(0xFF6880B0),
      clothes: Color(0xFF5870A0), pants: Color(0xFF484858),
      boots: Color(0xFF303040),
    ),
    // llm-specialist — dusty mauve
    SkinPalette(
      hair: Color(0xFF483050), skin: Color(0xFFD4B898),
      skinLight: Color(0xFFE4CCA8), eye: Color(0xFF9078B8),
      clothes: Color(0xFF6A4878), pants: Color(0xFF403448),
      boots: Color(0xFF2C2434),
    ),
    // game-designer — mustard 70s
    SkinPalette(
      hair: Color(0xFF3A2818), skin: Color(0xFFD4B898),
      skinLight: Color(0xFFE4CCA8), eye: Color(0xFFC8A030),
      clothes: Color(0xFF8E7820), pants: Color(0xFF4A3E28),
      boots: Color(0xFF302820),
    ),
    // strategy-keeper — faded denim
    SkinPalette(
      hair: Color(0xFF2E3848), skin: Color(0xFFD4B898),
      skinLight: Color(0xFFE4CCA8), eye: Color(0xFF6B8AAB),
      clothes: Color(0xFF506888), pants: Color(0xFF485870),
      boots: Color(0xFF303848),
    ),
    // character-artist — 80s coral sunset, magenta blouse
    SkinPalette(
      hair: Color(0xFFFB7185), skin: Color(0xFFD4B898),
      skinLight: Color(0xFFE4CCA8), eye: Color(0xFFFFA94D),
      clothes: Color(0xFFA21CAF), pants: Color(0xFF5B21B6),
      boots: Color(0xFF1E1B4B),
    ),
  ]),
);

// ─── 7. Cyberpunk — neon on black ───────────────────────────────────────────

final skinCyberpunk = CharacterSkin(
  id: 'cyberpunk',
  name: 'Кіберпанк',
  nameEn: 'Cyberpunk',
  palettes: _buildPalettes(const [
    // tech-lead — cyan chrome
    SkinPalette(
      hair: Color(0xFF0A0A14), skin: Color(0xFFB8A088),
      skinLight: Color(0xFFC8B098), eye: Color(0xFF00FFFF),
      clothes: Color(0xFF00606A), pants: Color(0xFF101018),
      boots: Color(0xFF08080C),
    ),
    // manager — gold circuit
    SkinPalette(
      hair: Color(0xFF10100A), skin: Color(0xFFA88860),
      skinLight: Color(0xFFB89870), eye: Color(0xFFFFD700),
      clothes: Color(0xFF6A5A00), pants: Color(0xFF121210),
      boots: Color(0xFF080808),
    ),
    // coder — matrix green
    SkinPalette(
      hair: Color(0xFF080A10), skin: Color(0xFF9A7040),
      skinLight: Color(0xFFAA8050), eye: Color(0xFF00FF41),
      clothes: Color(0xFF003A10), pants: Color(0xFF0A0C0A),
      boots: Color(0xFF060806),
    ),
    // reviewer — neon violet
    SkinPalette(
      hair: Color(0xFF0C0818), skin: Color(0xFFB8A088),
      skinLight: Color(0xFFC8B098), eye: Color(0xFFBF00FF),
      clothes: Color(0xFF3A0060), pants: Color(0xFF0C0A14),
      boots: Color(0xFF060408),
    ),
    // tester — hot pink
    SkinPalette(
      hair: Color(0xFF1A0808), skin: Color(0xFFD8A898),
      skinLight: Color(0xFFE8BCA8), eye: Color(0xFFFF0080),
      clothes: Color(0xFF600030), pants: Color(0xFF12080C),
      boots: Color(0xFF080406),
    ),
    // security — danger red
    SkinPalette(
      hair: Color(0xFF0C0C0E), skin: Color(0xFF6A4020),
      skinLight: Color(0xFF7C5030), eye: Color(0xFFFF0000),
      clothes: Color(0xFF500000), pants: Color(0xFF0E0808),
      boots: Color(0xFF060404),
    ),
    // ui-ux — electric blue
    SkinPalette(
      hair: Color(0xFF300040), skin: Color(0xFFD8B8A0),
      skinLight: Color(0xFFE8CCB0), eye: Color(0xFF0088FF),
      clothes: Color(0xFF002C60), pants: Color(0xFF0A0A12),
      boots: Color(0xFF04040A),
    ),
    // llm-specialist — synth violet glow
    SkinPalette(
      hair: Color(0xFF1A0830), skin: Color(0xFFC8A088),
      skinLight: Color(0xFFD8B098), eye: Color(0xFFC000FF),
      clothes: Color(0xFF400070), pants: Color(0xFF0E0818),
      boots: Color(0xFF06030C),
    ),
    // game-designer — neon yellow on black
    SkinPalette(
      hair: Color(0xFF0A0A14), skin: Color(0xFFB8A088),
      skinLight: Color(0xFFC8B098), eye: Color(0xFFFFD800),
      clothes: Color(0xFF4A3800), pants: Color(0xFF0C0C12),
      boots: Color(0xFF040408),
    ),
    // strategy-keeper — neon ice-blue on black
    SkinPalette(
      hair: Color(0xFF060614), skin: Color(0xFFB8A088),
      skinLight: Color(0xFFC8B098), eye: Color(0xFF00DDFF),
      clothes: Color(0xFF001A40), pants: Color(0xFF0A0A1C),
      boots: Color(0xFF050A14),
    ),
    // character-artist — neon graffiti, cyan hair + hot pink neon eye
    SkinPalette(
      hair: Color(0xFF00FFFF), skin: Color(0xFFB8A0A8),
      skinLight: Color(0xFFC8B0B8), eye: Color(0xFFFF1493),
      clothes: Color(0xFF08081C), pants: Color(0xFF0A0A12),
      boots: Color(0xFF040408),
    ),
  ]),
);

// ─── 8. Cozy — warm sweaters, autumn palette ────────────────────────────────

final skinCozy = CharacterSkin(
  id: 'cozy',
  name: 'Затишок',
  nameEn: 'Cozy',
  palettes: _buildPalettes(const [
    // tech-lead — warm teal knit
    SkinPalette(
      hair: Color(0xFF1C2828), skin: Color(0xFFE8C0A0),
      skinLight: Color(0xFFF8D4B4), eye: Color(0xFF4ABEAA),
      clothes: Color(0xFF2A7A72), pants: Color(0xFF5A4A3A),
      boots: Color(0xFF3E3228),
    ),
    // manager — caramel cable-knit
    SkinPalette(
      hair: Color(0xFF6A3818), skin: Color(0xFFD8B080),
      skinLight: Color(0xFFE8C494), eye: Color(0xFFDEA030),
      clothes: Color(0xFFB07828), pants: Color(0xFF584838),
      boots: Color(0xFF3C3028),
    ),
    // coder — forest green wool
    SkinPalette(
      hair: Color(0xFF242050), skin: Color(0xFFC09050),
      skinLight: Color(0xFFD0A468), eye: Color(0xFF58B878),
      clothes: Color(0xFF2E6838), pants: Color(0xFF3E3A30),
      boots: Color(0xFF2A2820),
    ),
    // reviewer — plum cardigan
    SkinPalette(
      hair: Color(0xFF3A1850), skin: Color(0xFFE8C0A0),
      skinLight: Color(0xFFF8D4B4), eye: Color(0xFF9878C0),
      clothes: Color(0xFF604870), pants: Color(0xFF484040),
      boots: Color(0xFF302A30),
    ),
    // tester — berry knit
    SkinPalette(
      hair: Color(0xFF8A2018), skin: Color(0xFFF0C0B0),
      skinLight: Color(0xFFFCD4C4), eye: Color(0xFFD07088),
      clothes: Color(0xFFA04050), pants: Color(0xFF504040),
      boots: Color(0xFF382E2E),
    ),
    // security — charcoal wool
    SkinPalette(
      hair: Color(0xFF202830), skin: Color(0xFF8A5828),
      skinLight: Color(0xFFA06C3C), eye: Color(0xFFD05838),
      clothes: Color(0xFF484048), pants: Color(0xFF343030),
      boots: Color(0xFF222020),
    ),
    // ui-ux — powder blue angora
    SkinPalette(
      hair: Color(0xFFE07088), skin: Color(0xFFF0D0BC),
      skinLight: Color(0xFFFCE4D0), eye: Color(0xFF5888C0),
      clothes: Color(0xFF5878A8), pants: Color(0xFF484448),
      boots: Color(0xFF303034),
    ),
    // llm-specialist — lavender turtleneck
    SkinPalette(
      hair: Color(0xFF302048), skin: Color(0xFFE8C0A0),
      skinLight: Color(0xFFF8D4B4), eye: Color(0xFFA888D0),
      clothes: Color(0xFF6A4890), pants: Color(0xFF463848),
      boots: Color(0xFF2E2434),
    ),
    // game-designer — honey knit
    SkinPalette(
      hair: Color(0xFF6A4828), skin: Color(0xFFE8C0A0),
      skinLight: Color(0xFFF8D4B4), eye: Color(0xFFCFA040),
      clothes: Color(0xFF986818), pants: Color(0xFF4A3828),
      boots: Color(0xFF302418),
    ),
    // strategy-keeper — wool navy turtleneck
    SkinPalette(
      hair: Color(0xFF1C2030), skin: Color(0xFFE8C0A0),
      skinLight: Color(0xFFF8D4B4), eye: Color(0xFF88AAC8),
      clothes: Color(0xFF2A4068), pants: Color(0xFF4A4A5A),
      boots: Color(0xFF303040),
    ),
    // character-artist — autumn paint-stained sienna cardigan
    SkinPalette(
      hair: Color(0xFF8B3A1A), skin: Color(0xFFF0C0B0),
      skinLight: Color(0xFFFCD4C4), eye: Color(0xFFD2691E),
      clothes: Color(0xFFA0522D), pants: Color(0xFF4A3838),
      boots: Color(0xFF302828),
    ),
  ]),
);

// ─── All skins ──────────────────────────────────────────────────────────────

final allCharacterSkins = <CharacterSkin>[
  skinDefault,
  skinCasual,
  skinCorporate,
  skinHacker,
  skinCreative,
  skinRetro,
  skinCyberpunk,
  skinCozy,
];

CharacterSkin characterSkinById(String id) =>
    allCharacterSkins.firstWhere((s) => s.id == id, orElse: () => skinDefault);

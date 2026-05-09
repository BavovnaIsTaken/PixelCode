// Extract sprites from XQuest 1.3 binary files and output as Dart constants.
// Usage: dart run tools/extract_sprites.dart > output.txt

import 'dart:io';
import 'dart:typed_data';

List<int> parsePalette(String path) {
  final src = File(path).readAsStringSync();
  final nums = RegExp(r'\d+').allMatches(src).map((m) => int.parse(m.group(0)!)).toList();
  final palette = <int>[];
  for (var i = 2; i < nums.length - 2; i += 3) {
    final r = (nums[i] * 255 / 63).round().clamp(0, 255);
    final g = (nums[i + 1] * 255 / 63).round().clamp(0, 255);
    final b = (nums[i + 2] * 255 / 63).round().clamp(0, 255);
    palette.add((0xFF << 24) | (r << 16) | (g << 8) | b);
  }
  return palette;
}

class Sprite {
  final String name;
  final int width, height;
  final List<int> pixels; // palette indices
  Sprite(this.name, this.width, this.height, this.pixels);
}

Sprite? readBitmap(ByteData data, int offset, String name) {
  if (offset + 4 > data.lengthInBytes) return null;
  final width = data.getUint16(offset, Endian.little);
  final height = data.getUint16(offset + 2, Endian.little);
  if (width == 0 || height == 0 || width > 100 || height > 100) return null;
  final bmwidth = ((width - 1) ~/ 4 + 1) * 4;
  final dataSize = bmwidth * height;
  if (offset + 4 + dataSize > data.lengthInBytes) return null;
  final pixels = <int>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      pixels.add(data.getUint8(offset + 4 + y * bmwidth + x));
    }
  }
  return Sprite(name, width, height, pixels);
}

int bitmapSize(ByteData data, int offset) {
  if (offset + 4 > data.lengthInBytes) return 0;
  final width = data.getUint16(offset, Endian.little);
  final height = data.getUint16(offset + 2, Endian.little);
  if (width == 0 || height == 0 || width > 100 || height > 100) return 0;
  final bmwidth = ((width - 1) ~/ 4 + 1) * 4;
  return 4 + bmwidth * height;
}

void main() {
  final baseDir = 'xquest_1.3_src';
  final palette = parsePalette('$baseDir/palette.inc');
  final gfxBytes = File('$baseDir/xquest.gfx').readAsBytesSync();
  final gfx = ByteData.sublistView(gfxBytes);

  var offset = 0;
  final allSprites = <String, List<Sprite>>{};

  // Ship (24 frames)
  final ships = <Sprite>[];
  for (var i = 0; i < 24; i++) {
    final s = readBitmap(gfx, offset, 'ship_$i');
    if (s != null) { ships.add(s); offset += bitmapSize(gfx, offset); }
  }
  allSprites['ship'] = ships;

  // Missile
  final missile = readBitmap(gfx, offset, 'missile');
  if (missile != null) { allSprites['missile'] = [missile]; offset += bitmapSize(gfx, offset); }

  // Objects
  for (final name in ['crystal', 'mine', 'smart_bomb']) {
    final s = readBitmap(gfx, offset, name);
    if (s != null) { allSprites[name] = [s]; offset += bitmapSize(gfx, offset); }
  }

  // Enemy mine
  final emine = readBitmap(gfx, offset, 'enemy_mine');
  if (emine != null) { allSprites['enemy_mine'] = [emine]; offset += bitmapSize(gfx, offset); }

  // Enemies
  final knownFrames = [5, 5, 3, 3, 3, 3, 0, 3, 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5];
  final enemyNames = [
    'supercrystal', 'explosion', 'grunger', 'zippo', 'zinger', 'vince',
    'hibernator', 'miner', 'meeby', 'retaliator', 'terrier', 'doinger',
    'snipe', 'tribbler', 'tribble', 'buckshot', 'cluster', 'sticktight', 'repulsor'
  ];

  for (var i = 0; i < 19; i++) {
    final frames = <Sprite>[];
    for (var j = 0; j <= knownFrames[i]; j++) {
      final s = readBitmap(gfx, offset, '${enemyNames[i]}_$j');
      if (s != null) { frames.add(s); offset += bitmapSize(gfx, offset); }
    }
    allSprites[enemyNames[i]] = frames;
  }

  // Enemy missiles (6)
  for (var i = 1; i <= 6; i++) {
    final s = readBitmap(gfx, offset, 'emissile_$i');
    if (s != null) { allSprites['emissile_$i'] = [s]; offset += bitmapSize(gfx, offset); }
  }

  // PBM sprites
  for (final name in ['ship_icon', 'smart_icon', 'crystal_icon',
      'pu_shield', 'pu_aimed', 'pu_rapid', 'pu_multi', 'pu_ass', 'pu_heavy', 'pu_bounce']) {
    final s = readBitmap(gfx, offset, name);
    if (s != null) { allSprites[name] = [s]; offset += bitmapSize(gfx, offset); }
  }

  // Gates
  for (final name in ['left_gate', 'right_gate']) {
    final s = readBitmap(gfx, offset, name);
    if (s != null) { allSprites[name] = [s]; offset += bitmapSize(gfx, offset); }
  }
  for (final name in ['tl_corner', 'tr_corner', 'br_corner', 'bl_corner']) {
    final s = readBitmap(gfx, offset, name);
    if (s != null) { allSprites[name] = [s]; offset += bitmapSize(gfx, offset); }
  }
  final lgates = <Sprite>[];
  for (var i = 0; i < 6; i++) {
    final s = readBitmap(gfx, offset, 'lgate_$i');
    if (s != null) { lgates.add(s); offset += bitmapSize(gfx, offset); }
  }
  allSprites['lgate'] = lgates;
  final rgates = <Sprite>[];
  for (var i = 0; i < 6; i++) {
    final s = readBitmap(gfx, offset, 'rgate_$i');
    if (s != null) { rgates.add(s); offset += bitmapSize(gfx, offset); }
  }
  allSprites['rgate'] = rgates;

  // Now output Dart code
  // Output key sprites as Dart map of ARGB int lists

  // We want: ship (all 24), crystal, mine, smart_bomb, enemy_mine,
  // enemies (frame 0 for each used type), missile, power-up icons
  final output = StringBuffer();

  output.writeln('// Auto-generated from xquest.gfx — DO NOT EDIT');
  output.writeln('// Sprite data extracted from original XQuest 1.3 (1996)');
  output.writeln('import \'dart:ui\';');
  output.writeln('');

  // Ship frames
  output.writeln('// Ship sprite: 24 rotation frames, 16x16 each');
  output.writeln('const _ogShipFrames = <List<int>>[');
  for (var i = 0; i < ships.length; i++) {
    final s = ships[i];
    output.write('  // Frame $i\n  [');
    for (var j = 0; j < s.pixels.length; j++) {
      if (j % s.width == 0) output.write('\n    ');
      final idx = s.pixels[j];
      if (idx == 0) { output.write('0x00000000,'); }
      else if (idx < palette.length) { output.write('0x${palette[idx].toRadixString(16).padLeft(8, '0')},'); }
      else { output.write('0x00000000,'); }
    }
    output.writeln('\n  ],');
  }
  output.writeln('];');
  output.writeln('const _ogShipW = ${ships[0].width}, _ogShipH = ${ships[0].height};');
  output.writeln('');

  // Single sprites as named constants
  void outputSingle(String dartName, String key) {
    final frames = allSprites[key];
    if (frames == null || frames.isEmpty) return;
    final s = frames[0];
    output.writeln('const _og${dartName}W = ${s.width}, _og${dartName}H = ${s.height};');
    output.write('const _og$dartName = [');
    for (var j = 0; j < s.pixels.length; j++) {
      if (j % s.width == 0) output.write('\n  ');
      final idx = s.pixels[j];
      if (idx == 0) { output.write('0x00000000,'); }
      else if (idx < palette.length) { output.write('0x${palette[idx].toRadixString(16).padLeft(8, '0')},'); }
      else { output.write('0x00000000,'); }
    }
    output.writeln('\n];');
    output.writeln('');
  }

  outputSingle('Crystal', 'crystal');
  outputSingle('Mine', 'mine');
  outputSingle('SmartBomb', 'smart_bomb');
  outputSingle('EnemyMine', 'enemy_mine');
  outputSingle('Missile', 'missile');

  // Enemy sprites (frame 0 of each)
  final gameEnemies = ['grunger', 'zippo', 'zinger', 'retaliator', 'miner',
    'terrier', 'doinger', 'tribbler', 'tribble', 'vince', 'meeby', 'snipe',
    'buckshot', 'cluster', 'sticktight', 'repulsor', 'supercrystal'];

  output.writeln('// Enemy sprites (frame 0)');
  for (final name in gameEnemies) {
    final frames = allSprites[name];
    if (frames == null || frames.isEmpty) continue;
    final s = frames[0];
    final dartName = name[0].toUpperCase() + name.substring(1);
    output.writeln('const _og${dartName}W = ${s.width}, _og${dartName}H = ${s.height};');
    output.write('const _og$dartName = [');
    for (var j = 0; j < s.pixels.length; j++) {
      if (j % s.width == 0) output.write('\n  ');
      final idx = s.pixels[j];
      if (idx == 0) { output.write('0x00000000,'); }
      else if (idx < palette.length) { output.write('0x${palette[idx].toRadixString(16).padLeft(8, '0')},'); }
      else { output.write('0x00000000,'); }
    }
    output.writeln('\n];');
    output.writeln('');
  }

  // Explosion frames (for death animation)
  output.writeln('// Explosion: 6 frames');
  final explosions = allSprites['explosion'] ?? [];
  output.writeln('const _ogExplosionW = ${explosions.isEmpty ? 0 : explosions[0].width};');
  output.writeln('const _ogExplosionH = ${explosions.isEmpty ? 0 : explosions[0].height};');
  output.writeln('const _ogExplosionFrames = <List<int>>[');
  for (var i = 0; i < explosions.length; i++) {
    final s = explosions[i];
    output.write('  [');
    for (var j = 0; j < s.pixels.length; j++) {
      if (j % s.width == 0) output.write('\n    ');
      final idx = s.pixels[j];
      if (idx == 0) { output.write('0x00000000,'); }
      else if (idx < palette.length) { output.write('0x${palette[idx].toRadixString(16).padLeft(8, '0')},'); }
      else { output.write('0x00000000,'); }
    }
    output.writeln('\n  ],');
  }
  output.writeln('];');

  // Power-up icons
  for (final pu in ['pu_shield', 'pu_aimed', 'pu_rapid', 'pu_multi', 'pu_ass', 'pu_heavy', 'pu_bounce']) {
    final frames = allSprites[pu];
    if (frames == null || frames.isEmpty) continue;
    final dartName = pu.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join('');
    outputSingle(dartName, pu);
  }

  File('tools/xquest_sprites.dart').writeAsStringSync(output.toString());
  stderr.writeln('Written to tools/xquest_sprites.dart');
  stderr.writeln('Total sprites: ${allSprites.values.fold<int>(0, (s, l) => s + l.length)}');
  stderr.writeln('Offset consumed: $offset / ${gfxBytes.length}');
}

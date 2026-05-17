/**
 * Color utilities for the character-artist toolset.
 *
 * Two consumers:
 *   - palette diff (Euclidean RGB distance — fast, fine for "is this a clone of X" detection)
 *   - palette contrast vs room-theme floors (WCAG relative luminance ratio)
 *
 * Deliberately not pulling in a chroma/colorthief dependency — these
 * computations are stable, well-defined, and small enough to keep inline.
 */

export interface Rgb {
  r: number;
  g: number;
  b: number;
}

const HEX_RE = /^#([0-9A-Fa-f]{6})$/;

export function isValidHex(hex: string): boolean {
  return HEX_RE.test(hex);
}

export function parseHex(hex: string): Rgb {
  const m = HEX_RE.exec(hex);
  if (!m) {
    throw new Error(`Invalid hex color "${hex}". Expected format "#RRGGBB" (uppercase).`);
  }
  const v = parseInt(m[1], 16);
  return {
    r: (v >> 16) & 0xff,
    g: (v >> 8) & 0xff,
    b: v & 0xff,
  };
}

export function normalizeHex(hex: string): string {
  if (!isValidHex(hex)) throw new Error(`Invalid hex "${hex}"`);
  return "#" + hex.slice(1).toUpperCase();
}

/** Euclidean distance in RGB space, range 0 .. ~441.7. */
export function rgbDistance(a: Rgb, b: Rgb): number {
  const dr = a.r - b.r;
  const dg = a.g - b.g;
  const db = a.b - b.b;
  return Math.sqrt(dr * dr + dg * dg + db * db);
}

export function hexDistance(a: string, b: string): number {
  return rgbDistance(parseHex(a), parseHex(b));
}

/** WCAG 2.1 relative luminance for an sRGB color. */
export function relativeLuminance({ r, g, b }: Rgb): number {
  const channel = (v: number): number => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

/** WCAG contrast ratio between two colors (1..21). 4.5+ = body text, 3+ = large text / UI element. */
export function contrastRatio(a: Rgb, b: Rgb): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const [hi, lo] = la >= lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
}

export function contrastVerdict(ratio: number): "unreadable" | "borderline" | "readable" {
  if (ratio >= 4.5) return "readable";
  if (ratio >= 3) return "borderline";
  return "unreadable";
}

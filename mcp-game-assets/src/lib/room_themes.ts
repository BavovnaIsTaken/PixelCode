/**
 * Room theme floor colors per office tier — used for palette readability checks.
 *
 * Source of truth lives in lib/widgets/canvas/room_themes.dart. This file is a
 * frozen mirror that the contrast-checker tool reads at runtime. If the Dart
 * file changes, regenerate this list manually (or wire up a parser later).
 *
 * Both floor variants matter — characters walk on the checkerboard pattern,
 * so contrast must hold against the brighter of the two for a fair test.
 */

export interface RoomThemeFloor {
  tier: number;
  id: string;
  nameUk: string;
  floorDark: string;
  floorLight: string;
}

export const ROOM_THEME_FLOORS: ReadonlyArray<RoomThemeFloor> = [
  { tier: 1, id: "garage", nameUk: "Гараж", floorDark: "#141210", floorLight: "#181614" },
  { tier: 2, id: "smallOffice", nameUk: "Маленький офіс", floorDark: "#131318", floorLight: "#17171E" },
  { tier: 3, id: "modernOffice", nameUk: "Модерн офіс", floorDark: "#131320", floorLight: "#171728" },
  { tier: 4, id: "techHub", nameUk: "Тех хаб", floorDark: "#0C1418", floorLight: "#101A1E" },
  { tier: 5, id: "campus", nameUk: "Кампус", floorDark: "#161622", floorLight: "#1C1C2E" },
];

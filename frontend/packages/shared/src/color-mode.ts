/**
 * color-mode.ts - kept as a thin re-export of the palette module.
 * All color logic now lives in palette.ts (single source of truth).
 */
export {
  activityColor,
  applyFamily,
  type ColorFamily,
  type ColorScheme,
  categoryColor,
  DEFAULT_FAMILY,
  dotColor,
  FAMILIES,
  type FamilyDef,
  familyFor,
  gradientColor,
  isValidFamily,
  markerColor,
  type SchemePair,
  schemeFor,
  speedColor,
  typeColor,
} from './palette'

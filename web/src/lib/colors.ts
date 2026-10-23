import { type PartyGroup } from './parties'

export const MARGIN_BINS = [0.05, 0.1, 0.2, 0.3] as const
export const MARGIN_LABELS = ['<5', '5–10', '10–20', '20–30', '30+']

const RAMPS: Record<'REP' | 'DEM' | 'THIRD', string[]> = {
  REP: ['#F9D3D0', '#F1A19F', '#E36B72', '#CE2F3B', '#9E1B28'],
  DEM: ['#D3E3F6', '#9DBFEA', '#5F93D3', '#2563B5', '#163F7F'],
  THIRD: ['#F8E9A8', '#F2D970', '#E3B505', '#B88D00', '#8A6900'],
}
const MEASURE: Record<'FOR' | 'AGAINST', string[]> = {
  FOR: ['#CBE8E8', '#93CFD1', '#4FAFB5', '#17808A', '#0D5961'],
  AGAINST: ['#F3DCC4', '#E6B98A', '#D08F4F', '#B5651D', '#7F4311'],
}

export function binIndex(margin: number): number {
  const m = Math.abs(margin)
  let i = 0
  while (i < MARGIN_BINS.length && m >= MARGIN_BINS[i]) i++
  return i
}

export function leaderFill(group: PartyGroup, margin: number): string {
  const i = binIndex(margin)
  if (group === 'REP' || group === 'DEM' || group === 'THIRD') return RAMPS[group][i]
  if (group === 'FOR' || group === 'AGAINST') return MEASURE[group][i]
  return '#d9d9d9'
}

export const rampFor = (g: PartyGroup): string[] =>
  g === 'REP' || g === 'DEM' || g === 'THIRD' ? RAMPS[g] : g === 'FOR' || g === 'AGAINST' ? MEASURE[g] : []

export const NO_DATA = '#ececec'
/** Precinct polygons with no residents: a visible neutral so they never read as a rendering gap. */
export const NO_RESIDENTS = '#e6e4de'
/** Populated precincts without a result of their own (reported with another precinct). */
export const NO_PRECINCT_RESULT = '#e3e3e3'

/** Rating scale 0 (Solid D) .. 6 (Solid R). */
export const RATING_FILL = ['#163F7F', '#2563B5', '#8FB4E3', '#C4B8D9', '#F0A2A0', '#DB4A55', '#9E1B28']
export const RATING_TEXT = ['#fff', '#fff', '#12294a', '#2d2540', '#4a1210', '#fff', '#fff']

export function ratingIndex(label: string | undefined | null, scale: string[]): number {
  if (!label) return -1
  const norm = label
    .replace(/^safe/i, 'Solid')
    .replace(/^tilt/i, 'Lean')
    .replace(/toss[\s-]?up/i, 'Toss-up')
    .replace(/^likely/i, 'Likely')
  const i = scale.findIndex((s) => s.toLowerCase() === norm.toLowerCase())
  return i
}

/** Diverging fill for a signed margin (positive = R). Used for swing and trend maps. */
export function divergingFill(v: number, max = 0.15): string {
  const t = Math.min(1, Math.abs(v) / max)
  const ramp = v >= 0 ? RAMPS.REP : RAMPS.DEM
  return ramp[Math.min(4, Math.floor(t * 5))]
}

export const SEQUENTIAL = ['#eef3f9', '#cddcee', '#a5c0e0', '#789fcf', '#4a7bb8', '#2a5a96', '#17406f']
export function sequentialFill(t: number): string {
  return SEQUENTIAL[Math.min(SEQUENTIAL.length - 1, Math.max(0, Math.floor(t * SEQUENTIAL.length)))]
}

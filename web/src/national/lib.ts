import { RATING_FILL, RATING_TEXT } from '../lib/colors'
import type { SenateRace, SeatParty } from './types'

export const SEAT_HEX: Record<SeatParty, string> = { DEM: '#2563B5', REP: '#D6303A', IND: '#E3B505' }
export const SEAT_NAME: Record<SeatParty, string> = { DEM: 'Democratic', REP: 'Republican', IND: 'Independent' }
export const SEAT_LETTER: Record<SeatParty, string> = { DEM: 'D', REP: 'R', IND: 'I' }

/** Signed score: -3 Solid D ... 0 Toss-up ... +3 Solid R. Tilt counts as half a step. */
export function ratingScore(label: string | null | undefined): number | null {
  if (!label) return null
  const base = label.replace(/\s*\(flip\)$/i, '').trim()
  if (/^toss/i.test(base)) return 0
  const sign = /R$/.test(base) ? 1 : /D$/.test(base) ? -1 : 0
  if (!sign) return null
  if (/^tilt/i.test(base)) return 0.5 * sign
  if (/^lean/i.test(base)) return sign
  if (/^likely/i.test(base)) return 2 * sign
  return 3 * sign
}

export function consensusScore(race: SenateRace): number | null {
  const s = Object.values(race.ratings).map(ratingScore).filter((v): v is number => v != null)
  return s.length ? s.reduce((a, b) => a + b, 0) / s.length : null
}

/** Index on the shared seven-point scale (0 Solid D ... 6 Solid R). */
export function scoreIndex(score: number | null): number {
  if (score == null) return 3
  const a = Math.abs(score)
  const step = a < 0.25 ? 0 : a < 1.5 ? 1 : a < 2.5 ? 2 : 3
  return 3 + Math.sign(score) * step
}

export const INDEX_LABEL = ['Solid D', 'Likely D', 'Lean D', 'Toss-up', 'Lean R', 'Likely R', 'Solid R']
export const indexFill = (i: number) => RATING_FILL[i]
export const indexText = (i: number) => RATING_TEXT[i]

export const raceIndex = (race: SenateRace) => scoreIndex(consensusScore(race))

export function fmtLead(value: number, opponentParty: string, opponent: string): string {
  const v = Math.abs(value)
  if (v < 0.5) return 'Even'
  const label = value > 0 ? 'R' : opponentParty === 'DEM' ? 'D' : ((opponent ?? '').split(' ').pop() || 'I')
  return `${label}+${v.toFixed(1)}`
}

export const leadClass = (value: number, opponentParty: string): 'r' | 'd' | 'i' | '' =>
  Math.abs(value) < 0.5 ? '' : value > 0 ? 'r' : opponentParty === 'DEM' ? 'd' : 'i'

export interface SeatCounts {
  dHold: number; rHold: number; calledD: number; calledR: number; calledI: number
  ratedD: number; tossup: number; ratedR: number
}

export function seatCounts(not_up: { DEM: number; REP: number; IND: number }, races: SenateRace[]): SeatCounts {
  const open = races.filter((r) => !r.call)
  const idx = open.map(raceIndex)
  return {
    dHold: not_up.DEM + not_up.IND, rHold: not_up.REP,
    calledD: races.filter((r) => r.call?.winner_party === 'DEM').length,
    calledR: races.filter((r) => r.call?.winner_party === 'REP').length,
    calledI: races.filter((r) => r.call?.winner_party === 'IND').length,
    ratedD: idx.filter((i) => i < 3).length, tossup: idx.filter((i) => i === 3).length, ratedR: idx.filter((i) => i > 3).length,
  }
}

export const shortRating = (label: string | null): string => (label ? label.replace(/\s*\(flip\)$/i, '').replace('Tossup', 'Toss-up').replace(/^Safe/, 'Solid') : '–')

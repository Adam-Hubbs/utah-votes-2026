export type SeatParty = 'DEM' | 'REP' | 'IND'

export interface NatCandidate { name: string; party: string }

export interface NatPollAvg {
  n_polls: number
  last_poll_date?: string
  latest: { candidate_id: string; name: string; party: string; avg: number; lo: number; hi: number }[]
  /** REP minus the main opponent, in points (positive = Republican lead). */
  margin: { value: number; lo: number; hi: number; opponent: string; opponent_party: string } | null
}

export interface SenateRace {
  state: string
  state_name: string
  special: boolean
  incumbent: string
  incumbent_party: SeatParty
  open: boolean
  status_note: string | null
  candidates: NatCandidate[]
  poll_avg: NatPollAvg
  ratings: { cook: string | null; sabato: string | null; inside: string | null }
  tracker: boolean
}

export interface Composition { DEM: number; REP: number; IND: number }

export interface SourceNote { name: string; url: string; as_of: string }

export interface SenateFile {
  updated_at: string
  composition: { current: Composition; not_up: Composition; majority: number; vp_tiebreak: 'REP' | 'DEM'; note?: string }
  composition_source: SourceNote
  ratings_sources: { id: 'cook' | 'sabato' | 'inside'; name: string; as_of: string; url: string }[]
  ratings_via: string
  poll_method: string
  poll_note: string
  races: SenateRace[]
}

export interface HouseFile {
  updated_at: string
  composition: { current: Composition & { vacant: number }; majority: number; note?: string; source: SourceNote }
  ratings_tally: {
    via: string
    url: string
    sources: { id: 'cook' | 'sabato' | 'inside'; as_of: string; counts: Record<string, number> }[]
  }
  generic_ballot: { date: string; DEM: number; REP: number; margin: number; margin_lo: number; margin_hi: number; n_polls: number } | null
}

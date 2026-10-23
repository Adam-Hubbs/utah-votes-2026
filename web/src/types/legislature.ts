// Contracts for legislature.json and judges.json (see "State races" in ARCHITECTURE.md).

export interface LegSeat {
  district: number
  contest_id: string | null
  holder: string | null
  holder_party: string | null
  holder_since?: string | null
  vacant: boolean
  up: boolean
  incumbent_running: boolean | null
  running_for: string | null
  uncontested: boolean | null
  pres24_margin: number | null
  note?: string | null
}

export type PartyCounts = Record<string, number>

export interface LegChamber {
  seats: number
  majority: number
  supermajority: number
  current: PartyCounts
  holdovers: PartyCounts
  up_2026: PartyCounts
  vacant: number
  seats_list: LegSeat[]
}

export interface LegislatureFile {
  updated_at: string
  roster_source?: string
  chambers: { house: LegChamber; senate: LegChamber }
}

export interface JudgeInfo {
  judge: string
  title: string
  court: string
  court_level: 'supreme' | 'appeals' | 'district' | 'juvenile' | 'justice'
  jpec_recommendation: string | null
  jpec_score_summary: string | null
  appointing_governor: string | null
  appointed_year: number | null
}

export interface JudgesFile {
  updated_at: string
  jpec_source?: string
  judges: Record<string, JudgeInfo>
}

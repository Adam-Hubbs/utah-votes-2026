// Mirrors the data contracts in ARCHITECTURE.md. Fields marked optional are
// ones the front end tolerates being absent while the pipeline matures.

export type LiveMode = 'pre' | 'live' | 'final'
export type Party = string // REP | DEM | LIB | CON | IAP | UUP | GRN | FWD | NPA | UNA | OTH

export interface SiteConfig {
  current_election: string
  election_date: string
  polls_close_utc: string
  live_mode: LiveMode
  live_data_base?: string
  featured_contests: string[]
}

export interface IndexContest {
  contest_id: string
  name: string
  office: string
}

export interface IndexElection {
  election_id: string
  name: string
  date: string
  status: LiveMode
  precinct_geo: string | null
  cd_plan: string | null
  contests: IndexContest[]
}

export interface ResultsIndex {
  elections: IndexElection[]
}

export interface Turnout {
  ballots_counted: number
  registered: number
  expected_ballots: number
  expected_lo: number
  expected_hi: number
  pct_expected: number
}

export interface SummaryCandidate {
  candidate_id: string
  name: string
  party: Party | null
  incumbent: boolean
  votes: number
  pct: number
  winner: boolean
}

export interface Reporting {
  counties_reporting: number
  counties_total: number
  pct_expected: number
  pct_expected_lo: number
  pct_expected_hi: number
}

export interface ContestCall {
  candidate_id: string
  called_at: string
  by: string
}

export interface SummaryContest {
  contest_id: string
  name: string
  office: string
  district?: number | null
  type: 'candidate' | 'measure'
  featured?: boolean
  description?: string
  total_votes: number
  candidates: SummaryCandidate[]
  reporting: Reporting
  call: ContestCall | null
}

export interface ElectionSummary {
  election_id: string
  name: string
  date: string
  status: LiveMode
  updated_at: string
  source: string
  precinct_geo: string | null
  cd_plan: string | null
  turnout: Turnout
  contests: SummaryContest[]
}

export interface ContestCandidate {
  candidate_id: string
  name: string
  party: Party | null
}

export interface CountyResult {
  fips: string
  name: string
  votes: Record<string, number>
  total: number
  ballots_counted: number
  expected_ballots: number
  pct_expected: number
  pct_expected_lo: number
  pct_expected_hi: number
}

export interface PrecinctResult {
  precinct_id: string
  votes: Record<string, number>
  total: number
}

export interface ContestResults {
  contest_id: string
  election_id: string
  updated_at: string
  candidates: ContestCandidate[]
  counties: CountyResult[]
  precincts: PrecinctResult[]
}

export interface ModelCounty {
  fips: string
  registered: number
  counted: number
  expected_median: number
  expected_lo: number
  expected_hi: number
  pct_expected: number
  pct_expected_lo: number
  pct_expected_hi: number
  source: 'model' | 'reported_remaining' | 'final'
}

export interface ElectionModel {
  updated_at: string
  draws: number
  method: string
  statewide: {
    counted: number
    expected_median: number
    expected_lo: number
    expected_hi: number
    pct_expected: number
  }
  counties: ModelCounty[]
  history: { t: string; counted: number; expected_median: number }[]
}

export interface TimelinePoint {
  t: string
  votes: Record<string, number>
  total: number
}

export interface ElectionTimeline {
  contests: Record<string, TimelinePoint[]>
}

export interface BaselineEntry {
  election_id: string
  contest_id: string
  name: string
  votes: Record<string, number>
  total: number
  margin: number
}

export interface Baselines {
  method: string
  districts: Record<string, BaselineEntry[]>
}

export interface CountyTrendEntry {
  election_id: string
  contest_id: string
  name: string
  year: number
  margin: number // (REP - DEM) / two-party-or-total; positive = R lead
  turnout: number | null
}

export interface CountyTrends {
  // ASSUMPTION: contract only says "per county, per (election, contest)".
  counties: Record<string, CountyTrendEntry[]>
}

export interface PollResult {
  candidate_id: string
  name: string
  party: Party | null
  pct: number
}

export interface Poll {
  poll_id: string
  question_id: string
  contest_id: string
  stage: 'general' | 'primary'
  pollster: string
  sponsor: string | null
  start_date: string
  end_date: string
  sample_size: number | null
  population: string | null
  partisan: string | null
  internal: boolean
  url: string | null
  numeric_grade: number | null
  results: PollResult[]
}

export interface AveragePoint {
  date: string
  candidate_id: string
  avg: number
  lo: number
  hi: number
}

export interface AverageLatest {
  candidate_id: string
  name: string
  party: Party | null
  avg: number
  lo: number
  hi: number
}

export interface ContestAverage {
  n_polls: number
  latest: AverageLatest[]
  series: AveragePoint[]
}

export interface PollAverages {
  updated_at: string
  method: string
  contests: Record<string, ContestAverage>
}

export interface NationalSeriesPoint {
  date: string
  [key: string]: number | string
}

export interface NationalPolls {
  generic_ballot: { series: NationalSeriesPoint[]; latest: Record<string, number | string> }
  approval: { series: NationalSeriesPoint[]; latest: Record<string, number | string> }
}

export interface RatingSource {
  id: string
  name: string
  url?: string
}

export interface Ratings {
  updated_at: string
  sources: RatingSource[]
  ratings: Record<string, Record<string, string>>
  scale: string[]
  // Optional extras some pipelines include.
  forecasts?: Record<string, Record<string, number>>
}

export interface CandidateBio {
  candidate_id: string
  name: string
  party: Party | null
  incumbent: boolean
  bio?: string | null
  website?: string | null
}

export type CandidatesFile = Record<string, CandidateBio[]>

export interface Registration {
  REP: number
  DEM: number
  UNA: number
  OTH: number
  total: number
  as_of?: string
}

export interface DemographicUnit {
  id: string
  name: string
  population: number
  median_age: number | null
  pct_white_nh: number | null
  pct_hispanic: number | null
  pct_asian: number | null
  pct_black: number | null
  pct_bachelors_plus: number | null
  median_hh_income: number | null
  pct_under_18: number | null
  pct_65_plus: number | null
  pct_urban: number | null
  registration?: Registration
}

export interface Demographics {
  source: string
  units: DemographicUnit[]
}

export type DemographicKey = Exclude<keyof DemographicUnit, 'id' | 'name' | 'registration'>

export interface PlaceLabel {
  name: string
  lon: number
  lat: number
  rank: number
}

// ASSUMPTION: not in ARCHITECTURE.md. Optional `measures.json` supplying ballot-measure text.
export interface MeasureInfo {
  title: string
  summary: string
  for_means?: string
  against_means?: string
  source_url?: string
}
export type MeasuresFile = Record<string, MeasureInfo>

// ---- Needle (ARCHITECTURE.md "Needle"): margins are a-minus-b as proportions of all votes (0-1) ----
export interface NeedleInterval { median: number; lo50: number; hi50: number; lo90: number; hi90: number }
export interface NeedleShare { median: number; lo90: number; hi90: number }
export interface NeedleHistoryPoint {
  t: string
  pct_expected: number
  prob: Record<string, number>
  margin_median: number
  margin_lo90: number
  margin_hi90: number
}
export interface NeedleContest {
  stage: 'pre' | 'early' | 'live' | 'final'
  pct_expected: number
  pair: [string, string]
  prob: Record<string, number>
  capped?: boolean
  margin: NeedleInterval
  shares: Record<string, NeedleShare>
  prior?: { share_a: number; source: string }
  history?: NeedleHistoryPoint[]
}
export interface NeedleFile {
  updated_at: string
  draws: number
  method: string
  environment_shift_logit?: number
  contests: Record<string, NeedleContest>
}

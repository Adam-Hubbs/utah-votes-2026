import { useMemo } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useResultsIndex, useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { ContestExplorer } from '../components/ContestExplorer'
import { ContestSelect, ElectionSelect } from '../components/ElectionPicker'
import { Gate, Section, Unavailable } from '../components/Ui'
import { candidateColors } from '../lib/parties'
import { fmtPct } from '../lib/format'
import { useDocTitle } from '../lib/hooks'
import { flags } from '../data/base'
import type { ElectionSummary, IndexElection, SummaryContest } from '../types/data'

export function ResultsPage() {
  const { currentElection, config } = useSite()
  const params = useParams()
  const navigate = useNavigate()
  const index = useResultsIndex()
  const electionId = params.electionId ?? currentElection
  const summary = useSummary(electionId)
  const currentSummary = useSummary(currentElection)
  // index.json only lists past elections, so the current one is built from its summary.
  const elections = useMemo(() => {
    const past = index?.elections.filter((e) => e.election_id !== currentElection) ?? []
    if (!currentSummary) return past
    const current: IndexElection = {
      election_id: currentElection,
      name: flags.sim && !/simulat/i.test(currentSummary.name) ? `${currentSummary.name} (simulation)` : currentSummary.name,
      date: currentSummary.date, status: currentSummary.status, precinct_geo: currentSummary.precinct_geo, cd_plan: currentSummary.cd_plan,
      contests: currentSummary.contests.map((c) => ({ contest_id: c.contest_id, name: c.name, office: c.office })),
    }
    return [current, ...past]
  }, [index, currentSummary, currentElection])
  const election = elections.find((e) => e.election_id === electionId)
  const firstContest = config.featured_contests[0] ?? election?.contests[0]?.contest_id ?? ''
  const contestId = params.contestId ?? (election?.contests.some((c) => c.contest_id === firstContest) ? firstContest : election?.contests[0]?.contest_id) ?? firstContest
  useDocTitle('Results')

  const firstContestOf = (id: string) => {
    const cs = elections.find((e) => e.election_id === id)?.contests ?? []
    return (cs.find((c) => config.featured_contests.includes(c.contest_id)) ?? cs[0])?.contest_id
  }
  const go = (e: string, c: string) => navigate(`/results/${e}/${c}`)

  return (
    <div className="page">
      <header className="page-head">
        <div className="kicker">Results</div>
        <h1 className="headline sm">Election results</h1>
        <p className="dek">Pick an election and a contest. Past elections are shown on the districts and precincts in place at the time.</p>
      </header>
      <div className="selectors">
        <Gate data={index} what="The election list">
          {() => (
            <>
              <ElectionSelect elections={elections} value={electionId} onChange={(id) => go(id, firstContestOf(id) ?? contestId)} />
              <ContestSelect election={election} value={contestId} onChange={(c) => go(electionId, c)} />
            </>
          )}
        </Gate>
      </div>

      {contestId ? (
        <ContestExplorer key={`${electionId}/${contestId}`} electionId={electionId} contestId={contestId} />
      ) : <Unavailable what="Results" />}

      <Gate data={summary} what="">
        {(s) => <OtherContests summary={s} electionId={electionId} current={contestId} />}
      </Gate>
    </div>
  )
}

function OtherContests({ summary, electionId, current }: { summary: ElectionSummary; electionId: string; current: string }) {
  const featured = summary.contests.filter((c) => c.featured && c.contest_id !== current)
  if (!featured.length) return null
  return (
    <Section title="Other major contests">
      <div className="mini-grid">
        {featured.map((c) => <MiniContest key={c.contest_id} c={c} to={`/results/${electionId}/${c.contest_id}`} />)}
      </div>
    </Section>
  )
}

function MiniContest({ c, to }: { c: SummaryContest; to: string }) {
  const colors = candidateColors(c.candidates)
  const has = c.total_votes > 0
  const rank = (p: string | null) => (p === 'DEM' ? 0 : p === 'REP' ? 1 : 2)
  const shown = (has ? c.candidates : [...c.candidates].sort((a, b) => rank(a.party) - rank(b.party))).slice(0, 2)
  return (
    <Link to={to} className="mini-contest">
      <b>{c.name}</b>
      {shown.map((x) => (
        <div className="mini-line" key={x.candidate_id}><i style={{ background: colors[x.candidate_id] }} />{x.name}<span>{has ? fmtPct(x.pct) : '–'}</span></div>
      ))}
    </Link>
  )
}

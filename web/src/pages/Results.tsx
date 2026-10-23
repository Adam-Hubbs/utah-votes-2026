import { useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useResultsIndex, useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { ContestExplorer } from '../components/ContestExplorer'
import { ContestSelect, ElectionSelect } from '../components/ElectionPicker'
import { Gate, Section, Unavailable } from '../components/Ui'
import { CandidateRow } from '../components/CandidateRow'
import { ReportingMeter } from '../components/ReportingMeter'
import { candidateColors } from '../lib/parties'
import { MAPPABLE_OFFICES, OFFICE_LABEL } from '../lib/results'
import { fmtInt, fmtPct } from '../lib/format'
import { useDocTitle } from '../lib/hooks'
import type { ElectionSummary, SummaryContest } from '../types/data'
import { LastUpdated } from '../components/LastUpdated'

export function ResultsPage() {
  const { currentElection, config } = useSite()
  const params = useParams()
  const navigate = useNavigate()
  const index = useResultsIndex()
  const electionId = params.electionId ?? currentElection
  const election = index?.elections.find((e) => e.election_id === electionId)
  const summary = useSummary(electionId)
  const firstContest = config.featured_contests[0] ?? election?.contests[0]?.contest_id ?? ''
  const contestId = params.contestId ?? (election?.contests.some((c) => c.contest_id === firstContest) ? firstContest : election?.contests[0]?.contest_id) ?? firstContest
  useDocTitle('Results')

  const go = (e: string, c: string) => navigate(`/results/${e}/${c}`)
  const contestMeta = election?.contests.find((c) => c.contest_id === contestId)
  const listView = contestMeta ? !MAPPABLE_OFFICES.has(contestMeta.office) : false

  return (
    <div className="page">
      <header className="page-head">
        <div className="kicker">Results</div>
        <h1 className="headline sm">Election results</h1>
        <p className="dek">Pick an election and a contest. Past elections are shown on the districts and precincts in place at the time.</p>
      </header>
      <div className="selectors">
        <Gate data={index} what="The election list">
          {(i) => (
            <>
              <ElectionSelect elections={i.elections} value={electionId} onChange={(id) => go(id, i.elections.find((e) => e.election_id === id)?.contests[0]?.contest_id ?? contestId)} />
              <ContestSelect election={election} value={contestId} onChange={(c) => go(electionId, c)} />
            </>
          )}
        </Gate>
      </div>

      {listView ? (
        <Gate data={summary} what="Election summary">
          {(s) => <ContestList summary={s} office={contestMeta?.office ?? ''} electionId={electionId} />}
        </Gate>
      ) : contestId ? (
        <ContestExplorer key={`${electionId}/${contestId}`} electionId={electionId} contestId={contestId} />
      ) : <Unavailable what="Results" />}

      <Gate data={summary} what="">
        {(s) => !listView && <OtherContests summary={s} electionId={electionId} current={contestId} />}
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
  return (
    <Link to={to} className="mini-contest">
      <b>{c.name}</b>
      {c.candidates.slice(0, 2).map((x) => (
        <div className="mini-line" key={x.candidate_id}><i style={{ background: colors[x.candidate_id] }} />{x.name}<span>{has ? fmtPct(x.pct) : '–'}</span></div>
      ))}
    </Link>
  )
}

function ContestList({ summary, office, electionId }: { summary: ElectionSummary; office: string; electionId: string }) {
  const [q, setQ] = useState('')
  const [officeFilter, setOfficeFilter] = useState<string>(office)
  const offices = useMemo(() => [...new Set(summary.contests.filter((c) => !MAPPABLE_OFFICES.has(c.office)).map((c) => c.office))], [summary])
  const rows = useMemo(() => summary.contests.filter((c) => !MAPPABLE_OFFICES.has(c.office) && (officeFilter === 'all' || c.office === officeFilter)
    && (!q || `${c.name} ${c.candidates.map((x) => x.name).join(' ')}`.toLowerCase().includes(q.toLowerCase()))), [summary, q, officeFilter])
  return (
    <Section title="Legislative, school board and judicial contests" dek="Candidate-by-candidate totals. Search by district, candidate or judge.">
      <div className="list-toolbar">
        <input type="search" className="search" placeholder="Search contests or candidates" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Search contests" />
        <label className="select"><span className="select-label">Office</span>
          <select value={officeFilter} onChange={(e) => setOfficeFilter(e.target.value)}>
            <option value="all">All offices</option>
            {offices.map((o) => <option key={o} value={o}>{OFFICE_LABEL[o] ?? o}</option>)}
          </select>
        </label>
        <LastUpdated iso={summary.updated_at} status={summary.status} />
      </div>
      <div className="contest-list">
        {rows.map((c) => {
          const colors = candidateColors(c.candidates)
          const has = c.total_votes > 0
          return (
            <article key={c.contest_id} className="list-contest">
              <header><h3>{c.name}</h3><span className="muted">{OFFICE_LABEL[c.office] ?? c.office}</span></header>
              {c.candidates.map((x) => <CandidateRow key={x.candidate_id} compact name={x.name} party={x.party} candidateId={x.candidate_id} incumbent={x.incumbent} votes={has ? x.votes : undefined} pct={has ? x.pct : undefined} color={colors[x.candidate_id]} winner={x.winner} />)}
              {has && <div className="list-foot"><ReportingMeter pct={c.reporting.pct_expected} lo={c.reporting.pct_expected_lo} hi={c.reporting.pct_expected_hi} size="sm" /><span>{fmtInt(c.total_votes)} votes</span></div>}
            </article>
          )
        })}
        {!rows.length && <div className="unavailable">No contests match “{q}”.</div>}
      </div>
      <p className="note">Contests: {rows.length}. <Link to={`/results/${electionId}/${summary.contests[0]?.contest_id ?? ''}`}>Back to featured contests</Link></p>
    </Section>
  )
}

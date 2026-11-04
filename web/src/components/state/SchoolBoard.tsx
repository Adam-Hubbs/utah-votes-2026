import { Link } from 'react-router-dom'
import { PartyChip } from '../PartyChip'
import { ResultsBar } from '../ResultsBar'
import { fmtPct } from '../../lib/format'
import type { SummaryContest } from '../../types/data'

export function SchoolBoard({ contests, started }: { contests: SummaryContest[]; started: boolean }) {
  const boards = contests.filter((c) => c.office === 'school-board').sort((a, b) => (a.district ?? 0) - (b.district ?? 0))
  if (!boards.length) return <div className="unavailable">State School Board contests are not yet available.</div>
  return (
    <div className="sb-grid">
      {boards.map((c) => {
        const live = started && c.total_votes > 0
        const cands = [...c.candidates].sort((a, b) => b.votes - a.votes)
        const solo = cands.length === 1
        return (
          <article key={c.contest_id} className="sb-card">
            <h3><Link to={`/state/${c.contest_id}`}>District {c.district}</Link>{solo && <span className="tag">Unopposed</span>}</h3>
            <ul>
              {cands.map((x, i) => (
                <li key={x.candidate_id} className={live && i === 0 ? 'lead' : ''}>
                  <span><PartyChip party={x.party} /> {x.name}{x.winner ? ' ✓' : ''}</span>
                  {live && <b>{fmtPct(x.pct)}</b>}
                </li>
              ))}
            </ul>
            {live && !solo && <ResultsBar items={cands.map((x) => ({ candidate_id: x.candidate_id, name: x.name, party: x.party, pct: x.pct }))} height={8} />}
          </article>
        )
      })}
    </div>
  )
}

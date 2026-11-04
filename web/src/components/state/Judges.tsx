import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { useSite } from '../../data/site'
import { fmtPct } from '../../lib/format'
import type { SummaryContest } from '../../types/data'
import type { JudgeInfo, JudgesFile } from '../../types/legislature'

const LEVELS: { id: JudgeInfo['court_level']; title: string }[] = [
  { id: 'supreme', title: 'Utah Supreme Court' }, { id: 'appeals', title: 'Court of Appeals' }, { id: 'district', title: 'District courts' },
  { id: 'juvenile', title: 'Juvenile courts' }, { id: 'justice', title: 'Justice courts' },
]

interface Row {
  contest: SummaryContest
  info: JudgeInfo | null
  name: string
  yes: number
  no: number
  started: boolean
}

function status(r: Row, decided: boolean): { label: string; cls: string } {
  if (!r.started) return { label: 'Awaiting results', cls: 'pending' }
  const passing = r.yes > 0.5
  if (decided) return passing ? { label: 'Retained', cls: 'good' } : { label: 'Not retained', cls: 'bad' }
  return passing ? { label: 'On track to be retained', cls: 'track' } : { label: 'Below the 50% needed', cls: 'warn' }
}

const jpecClass = (rec: string | null): string => (rec == null ? 'none' : /retain/i.test(rec) && !/not/i.test(rec) ? 'good' : 'bad')

export function Judges({ contests, judges, started }: { contests: SummaryContest[]; judges: JudgesFile | null | undefined; started: boolean }) {
  const { mode } = useSite()
  const [q, setQ] = useState('')

  const rows = useMemo<Row[]>(() => contests.filter((c) => c.office === 'retention').map((c) => {
    const info = judges?.judges[c.contest_id] ?? null
    const yes = c.candidates.find((x) => x.candidate_id === 'yes')
    const no = c.candidates.find((x) => x.candidate_id === 'no')
    return {
      contest: c, info, started: started && c.total_votes > 0,
      name: info ? `${info.title} ${info.judge}` : c.name.replace(/^Retain /, '').replace(/\?$/, ''),
      yes: yes?.pct ?? 0, no: no?.pct ?? 0,
    }
  }), [contests, judges, started])

  if (!rows.length) return <div className="unavailable">Judicial retention contests are not yet available.</div>

  const needle = q.trim().toLowerCase()
  const shown = rows.filter((r) => !needle || `${r.name} ${r.info?.court ?? ''}`.toLowerCase().includes(needle))
  const groups = LEVELS.map((l) => ({ ...l, rows: shown.filter((r) => (r.info?.court_level ?? 'justice') === l.id) })).filter((g) => g.rows.length)
  const recommended = rows.filter((r) => r.info?.jpec_recommendation && jpecClass(r.info.jpec_recommendation) === 'good').length

  return (
    <div className="judges">
      <div className="selectors">
        <input className="search" type="search" placeholder="Search judge or court" aria-label="Search judges" value={q} onChange={(e) => setQ(e.target.value)} />
        <span className="note small inline">
          {rows.length} judges listed. The Judicial Performance Evaluation Commission recommended retention for {recommended} of them. A judge is retained with more than 50% yes.
        </span>
      </div>
      {groups.map((g) => (
        <div key={g.id} className="judge-group">
          <h3 className="judge-group-title">{g.title}</h3>
          <div className="table-wrap">
            <table className="data-table judge-table">
              <thead>
                <tr><th scope="col">Judge</th><th scope="col">Court</th><th scope="col">JPEC</th><th scope="col" className="right">Yes</th><th scope="col" className="bar-col">Yes / No</th><th scope="col">Status</th></tr>
              </thead>
              <tbody>
                {g.rows.map((r) => {
                  const st = status(r, mode === 'final' || r.contest.candidates.some((c) => c.winner))
                  return (
                    <tr key={r.contest.contest_id}>
                      <td><Link to={`/state/${r.contest.contest_id}`}><b>{r.name}</b></Link></td>
                      <td className="muted">{r.info?.court ?? '–'}</td>
                      <td>{r.info?.jpec_recommendation ? <span className={`chip jpec-${jpecClass(r.info.jpec_recommendation)}`} title="Judicial Performance Evaluation Commission recommendation">{r.info.jpec_recommendation}</span> : <span className="muted">–</span>}</td>
                      <td className="right"><b>{r.started ? fmtPct(r.yes) : '–'}</b></td>
                      <td className="bar-col">
                        <div className="yn-bar" role="img" aria-label={r.started ? `Yes ${fmtPct(r.yes)}, No ${fmtPct(r.no)}` : 'No votes counted yet'}>
                          {r.started && <><i className="yes" style={{ width: `${r.yes * 100}%` }} /><i className="no" style={{ width: `${r.no * 100}%` }} /></>}
                          <em />
                        </div>
                      </td>
                      <td><span className={`status status-${st.cls}`}>{st.label}</span></td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>
      ))}
      {!groups.length && <div className="unavailable">No judges match.</div>}
      {judges?.jpec_source && <p className="note small">{judges.jpec_source}</p>}
    </div>
  )
}

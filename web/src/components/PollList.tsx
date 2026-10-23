import type { Poll } from '../types/data'
import { fmtDateRange, fmtInt, parseDate } from '../lib/format'
import { candidateColors } from '../lib/parties'
import { lastName } from '../lib/results'

export function pollMargin(p: Poll): { text: string; sign: number } | null {
  const r = p.results.find((x) => x.party === 'REP')
  const d = p.results.find((x) => x.party === 'DEM')
  if (r && d) {
    const m = r.pct - d.pct
    return { text: Math.abs(m) < 0.05 ? 'Even' : `${m > 0 ? 'R' : 'D'}+${Math.abs(m).toFixed(1).replace(/\.0$/, '')}`, sign: Math.sign(m) }
  }
  const s = [...p.results].sort((a, b) => b.pct - a.pct)
  if (s.length >= 2) return { text: `${lastName(s[0].name)}+${(s[0].pct - s[1].pct).toFixed(1).replace(/\.0$/, '')}`, sign: 0 }
  return null
}

export const popLabel = (p: string | null): string => (p ? ({ rv: 'RV', lv: 'LV', a: 'Adults', v: 'Voters' } as Record<string, string>)[p.toLowerCase()] ?? p.toUpperCase() : '–')

export function LatestPolls({ polls, names, limit = 6 }: { polls: Poll[]; names: (id: string) => string; limit?: number }) {
  const rows = [...polls].sort((a, b) => parseDate(b.end_date).getTime() - parseDate(a.end_date).getTime()).slice(0, limit)
  return (
    <ul className="poll-list">
      {rows.map((p) => {
        const colors = candidateColors(p.results)
        const m = pollMargin(p)
        const top = [...p.results].sort((a, b) => b.pct - a.pct).slice(0, 2)
        return (
          <li key={p.poll_id + p.question_id}>
            <div className="pl-top">
              <b>{names(p.contest_id)}</b>
              <span className={`pl-margin${m ? (m.sign > 0 ? ' r' : m.sign < 0 ? ' d' : '') : ''}`}>{m?.text}</span>
            </div>
            <div className="pl-mid">
              {top.map((r) => <span key={r.candidate_id}><i style={{ background: colors[r.candidate_id] }} />{lastName(r.name)} {r.pct}%</span>)}
            </div>
            <div className="pl-sub">{p.pollster} · {fmtDateRange(p.start_date, p.end_date)} · {p.sample_size ? `${fmtInt(p.sample_size)} ${popLabel(p.population)}` : popLabel(p.population)}</div>
          </li>
        )
      })}
    </ul>
  )
}

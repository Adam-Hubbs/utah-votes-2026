import { useMemo } from 'react'
import type { ContestAverage, Poll } from '../types/data'
import { candidateColors } from '../lib/parties'
import { fmtDateRange, fmtInt, parseDate } from '../lib/format'
import { lastName } from '../lib/results'
import { PollChart, type TSeries } from './PollChart'
import { SortableTable, type Column } from './SortableTable'
import { PartyChip } from './PartyChip'
import { PollingAverage } from './PollingAverage'
import { pollMargin, popLabel } from './PollList'

interface Props {
  contestId: string
  avg?: ContestAverage
  polls: Poll[]
  height?: number
  stage?: 'general' | 'primary'
  showTable?: boolean
  today?: Date
}

export function PollTracker({ contestId, avg, polls, height = 340, stage = 'general', showTable = true, today }: Props) {
  const rows = useMemo(() => polls.filter((p) => p.contest_id === contestId && p.stage === stage), [polls, contestId, stage])

  const cands = useMemo(() => {
    const m = new Map<string, { candidate_id: string; name: string; party: string | null }>()
    for (const l of avg?.latest ?? []) m.set(l.candidate_id, l)
    for (const p of rows) for (const r of p.results) if (!m.has(r.candidate_id)) m.set(r.candidate_id, r)
    return [...m.values()]
  }, [avg, rows])
  const colors = useMemo(() => candidateColors(cands), [cands])

  const series: TSeries[] = useMemo(() => cands.map((c) => ({
    id: c.candidate_id, label: c.name, endLabel: lastName(c.name), color: colors[c.candidate_id],
    line: (avg?.series ?? []).filter((s) => s.candidate_id === c.candidate_id).map((s) => ({ x: parseDate(s.date), y: s.avg, lo: s.lo, hi: s.hi })),
    dots: rows.flatMap((p) => {
      const r = p.results.find((x) => x.candidate_id === c.candidate_id)
      return r ? [{ x: parseDate(p.end_date), y: r.pct, n: p.sample_size ?? 400, tip: `${p.pollster}, ${fmtDateRange(p.start_date, p.end_date)}: ${c.name} ${r.pct.toFixed(1)}%` }] : []
    }),
  })).sort((a, b) => (b.line[b.line.length - 1]?.y ?? 0) - (a.line[a.line.length - 1]?.y ?? 0)), [cands, colors, avg, rows])

  const nPolls = avg?.n_polls ?? rows.length
  const columns: Column<Poll>[] = [
    { key: 'date', header: 'Dates', sort: (p) => parseDate(p.end_date).getTime(), render: (p) => <span className="nowrap">{fmtDateRange(p.start_date, p.end_date)}</span> },
    {
      key: 'pollster', header: 'Pollster', sort: (p) => p.pollster,
      render: (p) => <div>{p.url ? <a href={p.url} target="_blank" rel="noreferrer">{p.pollster}</a> : p.pollster}{p.sponsor && <div className="sub">for {p.sponsor}</div>}{p.internal && <span className="tag">Internal</span>}</div>,
    },
    { key: 'n', header: 'Sample', align: 'right', sort: (p) => p.sample_size, render: (p) => <span className="num nowrap">{p.sample_size ? fmtInt(p.sample_size) : '–'} <span className="muted">{popLabel(p.population)}</span></span> },
    ...cands.map((c): Column<Poll> => ({
      key: `c-${c.candidate_id}`, align: 'right', className: 'cand-col',
      header: <span className="th-cand"><i style={{ background: colors[c.candidate_id] }} />{lastName(c.name)} <PartyChip party={c.party} id={c.candidate_id} /></span>,
      sort: (p) => p.results.find((r) => r.candidate_id === c.candidate_id)?.pct ?? null,
      render: (p) => { const r = p.results.find((x) => x.candidate_id === c.candidate_id); return <span className="num">{r ? r.pct.toFixed(1) : '–'}</span> },
    })),
    {
      key: 'margin', header: 'Margin', align: 'right', marginSort: { value: (p) => pollMargin(p)?.value ?? null },
      render: (p) => { const m = pollMargin(p); return m ? <span className={`margin-pill ${m.sign > 0 ? 'r' : m.sign < 0 ? 'd' : ''}`}>{m.text}</span> : '–' },
    },
  ]

  if (!cands.length) return <div className="unavailable">No {stage} polls yet for this contest.</div>
  return (
    <div className="poll-tracker">
      {avg && <PollingAverage avg={avg} polls={rows} />}
      {avg && avg.n_polls === 1 && <p className="poll-caption">One poll is not an average. Treat it with caution.</p>}
      <p className="poll-caption">These are poll numbers, not election results.</p>
      {series.some((x) => x.line.length > 0) && <PollChart series={series} height={height} marker={today ? { x: today, label: 'Today' } : undefined}
        yDomain={[0, Math.max(40, Math.ceil(Math.max(...series.flatMap((s) => [...s.line.map((p) => p.hi ?? p.y), ...(s.dots ?? []).map((d) => d.y)]), 0) / 10) * 10)]}
        hint={() => (nPolls === 1 ? 'Only one poll so far' : null)} ariaLabel={`Poll averages for ${contestId}`} />}
      {series.some((x) => x.line.length > 0) && <p className="chart-note">Dots are individual polls, sized by sample size. Lines are the weighted average with a shaded 95% uncertainty band.</p>}
      {showTable && (
        <SortableTable rows={rows} columns={columns} rowKey={(p) => p.poll_id + p.question_id} initialSort={{ key: 'date', dir: 'desc' }} caption="Individual polls" />
      )}
    </div>
  )
}

import { useMemo } from 'react'
import type { NeedleContest, SummaryCandidate } from '../types/data'
import { PollChart, type TSeries } from './PollChart'
import { fmtDay, fmtMT, fmtMTFull } from '../lib/format'
import { sideOf, signed } from '../lib/needle'

interface Props {
  needle: NeedleContest
  candidates: SummaryCandidate[]
}

/** Chance of winning and projected margin over time, in the same chart style as the poll tracker. */
const tick = (d: Date): string => (d.getHours() === 0 && d.getMinutes() === 0 ? fmtDay(d) : fmtMT(d))

export function NeedleHistory({ needle, candidates }: Props) {
  const [a, b] = needle.pair
  const sa = sideOf(a, candidates)
  const sb = sideOf(b, candidates)
  const hist = useMemo(() => needle.history ?? [], [needle.history])

  const chance = useMemo<TSeries[]>(() => [
    { id: a, label: sa.short, color: sa.color, line: hist.map((h) => ({ x: new Date(h.t), y: (h.prob[a] ?? 0.5) * 100 })) },
    { id: b, label: sb.short, color: sb.color, line: hist.map((h) => ({ x: new Date(h.t), y: (1 - (h.prob[a] ?? 0.5)) * 100 })) },
  ], [hist, a, b, sa.short, sb.short, sa.color, sb.color])

  const margin = useMemo<TSeries[]>(() => [
    { id: 'margin', label: `${sa.short} − ${sb.short}`, endLabel: 'margin', color: '#3b3b3b', line: hist.map((h) => ({ x: new Date(h.t), y: h.margin_median * 100, lo: h.margin_lo90 * 100, hi: h.margin_hi90 * 100 })) },
  ], [hist, sa.short, sb.short])

  const counted = useMemo(() => new Map(hist.map((h) => [new Date(h.t).getTime(), h.pct_expected])), [hist])
  const hint = (d: Date) => {
    const p = counted.get(d.getTime())
    return p == null ? null : `About ${Math.round(p * 100)}% of expected vote counted`
  }

  if (hist.length === 0) return <div className="unavailable">The history charts fill in as results come in.</div>

  const hi = Math.max(...hist.map((h) => h.margin_hi90 * 100), 5)
  const lo = Math.min(...hist.map((h) => h.margin_lo90 * 100), -5)
  const pad = Math.max(5, (hi - lo) * 0.1)

  return (
    <div className="needle-history">
      <div>
        <h3 className="subhead">Chance of winning</h3>
        <PollChart series={chance} height={230} yDomain={[0, 100]} yFormat={(v) => `${v}%`} valueFormat={(v) => `${v < 1 ? '<1' : v > 99 ? '>99' : Math.round(v)}%`}
          minSpanDays={0.05} xTickFormat={tick} tipDateFormat={fmtMTFull} hint={hint}
          ariaLabel={`Chance of winning over time: ${sa.name} versus ${sb.name}`} />
      </div>
      <div>
        <h3 className="subhead">Projected final margin <span className="muted">({sa.short} minus {sb.short}, with 90% range)</span></h3>
        <PollChart series={margin} height={230} yDomain={[Math.floor(lo - pad), Math.ceil(hi + pad)]} yFormat={(v) => signed(Math.round(v))} valueFormat={(v) => `${signed(Math.round(v))} pts`}
          minSpanDays={0.05} xTickFormat={tick} tipDateFormat={fmtMTFull} hint={hint}
          ariaLabel={`Projected final margin over time for ${sa.name} minus ${sb.name}`} />
      </div>
    </div>
  )
}

import { useMemo, useState } from 'react'
import { Segmented } from '../Ui'
import { barOrder, seatLabel, tally, type Bucket, type SeatState } from '../../lib/legislature'
import type { LegChamber } from '../../types/legislature'

interface Props {
  chamber: 'house' | 'senate'
  data: LegChamber
  states: SeatState[]
  started: boolean
}

const NAMES: Record<Bucket, string> = { DEM: 'Democrats', REP: 'Republicans', OTH: 'Other' }
const cls = (s: SeatState): string => `seat seat-${(s.bucket ?? 'none').toLowerCase()} st-${s.status}${s.flip ? ' flip' : ''}`

const seatTitle = (s: SeatState, chamber: 'house' | 'senate'): string => {
  const head = `${seatLabel(chamber)} ${s.seat.district}`
  if (s.leader) return `${head}: ${s.leader.name}${s.status === 'won' ? ' (called)' : ' leading'}${s.flip ? ', flip' : ''}`
  if (s.status === 'holdover') return `${head}: ${s.seat.holder ?? 'Vacant'} (not up in 2026)`
  if (s.status === 'vacant') return `${head}: vacant`
  if (s.status === 'untracked') return `${head}: contest not yet in results feed`
  return `${head}: ${s.seat.holder ?? 'Vacant'}${s.status === 'pending' ? ', no votes counted yet' : ''}`
}

/** Parliament-style arc: seats on concentric rows, filled left to right in the same order as the bar. */
function Arc({ ordered, chamber }: { ordered: SeatState[]; chamber: 'house' | 'senate' }) {
  const n = ordered.length
  const dots = useMemo(() => {
    const rows = n > 50 ? 5 : 3
    const r0 = 0.46
    const radii = Array.from({ length: rows }, (_, i) => r0 + (i * (1 - r0)) / (rows - 1))
    const sum = radii.reduce((a, b) => a + b, 0)
    const counts = radii.map((r) => Math.round((n * r) / sum))
    counts[rows - 1] += n - counts.reduce((a, b) => a + b, 0)
    const pts = radii.flatMap((r, ri) =>
      Array.from({ length: counts[ri] }, (_, k) => {
        const a = Math.PI * (1 - (counts[ri] === 1 ? 0.5 : k / (counts[ri] - 1)))
        return { a, r, x: Math.cos(a) * r, y: -Math.sin(a) * r }
      }),
    )
    pts.sort((p, q) => q.a - p.a || p.r - q.r)
    const spacing = (Math.PI * 1 * 1) / Math.max(...counts) // arc spacing on the outer row
    const rowGap = (1 - r0) / (rows - 1)
    return { pts, size: Math.min(spacing, rowGap) * 0.42 }
  }, [n])
  const W = 440, H = 238, R = 205
  return (
    <svg className="seat-arc" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`${seatLabel(chamber)} seats arranged in an arc`}>
      <defs>
        {(['dem', 'rep', 'oth'] as const).map((b) => (
          <pattern key={b} id={`arc-hold-${b}`} width="4" height="4" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <rect width="4" height="4" className={`pat-bg-${b}`} />
            <rect width="2" height="4" className={`pat-fg-${b}`} />
          </pattern>
        ))}
      </defs>
      {ordered.map((s, i) => {
        const p = dots.pts[i]
        const b = (s.bucket ?? 'none').toLowerCase()
        const fill = s.status === 'holdover' && s.bucket ? `url(#arc-hold-${b})` : undefined
        return (
          <circle key={s.seat.district} cx={W / 2 + p.x * R} cy={H - 14 + p.y * R} r={dots.size * R}
            className={cls(s)} style={fill ? { fill } : undefined}>
            <title>{seatTitle(s, chamber)}</title>
          </circle>
        )
      })}
    </svg>
  )
}

export function BalanceOfPower({ chamber, data, states, started }: Props) {
  const [view, setView] = useState<'bar' | 'arc'>('bar')
  const t = useMemo(() => tally(states), [states])
  const ordered = useMemo(() => barOrder(states), [states])
  const total = data.seats
  const secured = (b: Bucket): number => t[b].won + t[b].holdover + t[b].holder
  const leading = (b: Bucket): number => t[b].leading
  const undecided = t.none.pending + t.none.untracked
  const pct = (n: number): string => `${(n / total) * 100}%`

  const lead: Bucket | null = (() => {
    const cands = (['DEM', 'REP'] as Bucket[]).map((b) => ({ b, n: secured(b) + leading(b) })).sort((a, b) => b.n - a.n)
    return cands[0].n >= data.majority ? cands[0].b : null
  })()
  const headline = (() => {
    if (!started) {
      const r = t.total.REP, d = t.total.DEM
      return `${r >= data.majority ? 'Republicans' : 'Democrats'} hold a ${r >= data.supermajority ? 'supermajority' : 'majority'} today, ${Math.max(r, d)} of ${total} seats${data.vacant ? ` (${data.vacant} vacant)` : ''}.`
    }
    if (!lead) return 'Neither party has reached a majority yet.'
    const sec = secured(lead)
    const word = sec >= data.majority ? 'has secured' : 'is on track for'
    const sup = sec + leading(lead) >= data.supermajority ? `, including the ${data.supermajority}-seat two-thirds supermajority that can override a veto` : ''
    return `${NAMES[lead]} ${word} a majority${sup}.`
  })()

  const seatUp = !started ? `${Object.values(data.up_2026).reduce((a, b) => a + b, 0)} of ${total} seats are on the 2026 ballot` : null

  return (
    <div className="bop">
      <div className="bop-head">
        <div>
          <h3 className="bop-title">{seatLabel(chamber)}</h3>
          <p className="bop-sub">{headline}{seatUp ? ` ${seatUp}.` : ''}</p>
        </div>
        <Segmented<'bar' | 'arc'> label="Chart style" value={view} onChange={setView} options={[{ value: 'bar', label: 'Bar' }, { value: 'arc', label: 'Arc' }]} />
      </div>

      <div className="bop-nums">
        {(['DEM', 'OTH', 'REP'] as Bucket[]).filter((b) => b !== 'OTH' || t.total.OTH > 0).map((b) => (
          <div key={b} className={`bop-num bop-${b.toLowerCase()}`}>
            <div className="bop-n">{secured(b)}{leading(b) > 0 && <span className="bop-lead"> +{leading(b)} leading</span>}</div>
            <div className="bop-name">{b === 'OTH' ? 'Forward / other' : NAMES[b]}</div>
          </div>
        ))}
        {undecided > 0 && <div className="bop-num bop-none"><div className="bop-n">{undecided}</div><div className="bop-name">Not yet decided</div></div>}
      </div>

      {view === 'bar' ? (
        <div className="bar-frame">
          <div className="seat-bar" role="img" aria-label={`${seatLabel(chamber)} balance of power`}>
            {ordered.map((s) => <i key={s.seat.district} className={cls(s)} title={seatTitle(s, chamber)} />)}
          </div>
          <div className="bar-mark" style={{ left: '50%' }}><span>{data.majority} for majority</span></div>
          <div className="bar-mark sup" style={{ left: pct(data.supermajority) }}><span>{data.supermajority}</span></div>
          <div className="bar-mark sup" style={{ left: pct(total - data.supermajority) }}><span>{data.supermajority}</span></div>
        </div>
      ) : (
        <div className="arc-frame">
          <Arc ordered={ordered} chamber={chamber} />
          <div className="arc-center"><b>{data.majority}</b><span>for majority</span></div>
        </div>
      )}
      <p className="bop-foot">Two-thirds ({data.supermajority} seats) is enough to override the governor’s veto.</p>

      <Legend started={started} />
      {t.flips.length > 0 && (
        <p className="bop-flips"><b>Flips so far:</b> {t.flips.map((f) => `${seatLabel(chamber).replace('Utah ', '')} ${f.district} (${f.from === 'REP' ? 'R' : f.from === 'DEM' ? 'D' : 'Other'}→${f.to === 'REP' ? 'R' : f.to === 'DEM' ? 'D' : 'Other'})`).join(', ')}</p>
      )}
    </div>
  )
}

function Legend({ started }: { started: boolean }) {
  const items: { c: string; label: string }[] = started
    ? [
        { c: 'seat seat-dem st-won', label: 'Called' }, { c: 'seat seat-dem st-leading', label: 'Leading' },
        { c: 'seat seat-dem st-holdover', label: 'Not up in 2026' }, { c: 'seat seat-none st-pending', label: 'No result yet' },
        { c: 'seat seat-rep st-won flip', label: 'Flip from current holder' },
      ]
    : [
        { c: 'seat seat-dem st-holder', label: 'Current holder, seat up in 2026' }, { c: 'seat seat-dem st-holdover', label: 'Holdover, not on ballot' },
        { c: 'seat seat-none st-vacant', label: 'Vacant' },
      ]
  return (
    <div className="bop-legend" aria-label="Legend">
      {items.map((i) => <span key={i.label}><i className={i.c} /> {i.label}</span>)}
    </div>
  )
}

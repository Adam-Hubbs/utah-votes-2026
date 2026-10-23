import { useEffect, useMemo, useState } from 'react'
import { arc } from 'd3-shape'
import { interpolateRgbBasis } from 'd3-interpolate'
import type { NeedleContest, SummaryCandidate } from '../types/data'
import { useLocalState } from '../lib/hooks'
import { BAND_EDGES, BAND_NAMES, TICKS, jitterRange, needleText, probAToAngle, probToT, type Side } from '../lib/needle'
import type { PartyGroup } from '../lib/parties'
import { fmtMT } from '../lib/format'

const RAMPS: Record<PartyGroup, string[]> = {
  DEM: ['#f4f6f9', '#b9d0ee', '#5f93d3', '#2563b5', '#163f7f'],
  REP: ['#faf4f3', '#f4b7b3', '#e36b72', '#ce2f3b', '#9e1b28'],
  FOR: ['#f1f7f7', '#a9d9da', '#4fafb5', '#17808a', '#0d5961'],
  AGAINST: ['#f8f3ec', '#ecc9a0', '#d08f4f', '#b5651d', '#7f4311'],
  THIRD: ['#faf6e4', '#f2d970', '#e3b505', '#b88d00', '#8a6900'],
  NONE: ['#f4f4f4', '#cfcfcf', '#9a9a9a', '#6b6b6b', '#444'],
}

const W = 460
const CX = 230
const CY = 214
const R_OUT = 188
const R_IN = 130
const SLICES = 72

const polar = (r: number, angleDeg: number): [number, number] => {
  const a = (angleDeg * Math.PI) / 180
  return [CX + r * Math.sin(a), CY - r * Math.cos(a)]
}

const sliceArc = arc<{ s: number; e: number }>().innerRadius(R_IN).outerRadius(R_OUT).startAngle((d) => d.s).endAngle((d) => d.e)

/** Left = candidate a (or "for"), right = candidate b. Angle in degrees from vertical: -90 left end, +90 right end. */
const tToAngle = (t: number, side: 'left' | 'right'): number => (side === 'left' ? -90 * t : 90 * t)

export function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(() => (typeof window !== 'undefined' && window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)').matches : false))
  useEffect(() => {
    if (!window.matchMedia) return
    const q = window.matchMedia('(prefers-reduced-motion: reduce)')
    const on = () => setReduced(q.matches)
    q.addEventListener('change', on)
    return () => q.removeEventListener('change', on)
  }, [])
  return reduced
}

/** Jitter is on by default unless the visitor prefers reduced motion; an explicit choice is remembered. */
export function useJitterSetting(): [boolean, (v: boolean) => void] {
  const reduced = usePrefersReducedMotion()
  const [stored, setStored] = useLocalState<boolean | null>('needle-jitter', null)
  return [reduced ? false : (stored ?? true), (v) => setStored(v)]
}

function useNeedleAngle(c: NeedleContest, enabled: boolean): number {
  const pa = c.prob[c.pair[0]] ?? 0.5
  const base = probAToAngle(pa)
  const [angle, setAngle] = useState(base)
  const [lo, hi] = useMemo(() => jitterRange(c), [c])
  const live = enabled && c.stage !== 'pre' && c.stage !== 'final' && hi - lo > 1e-4
  useEffect(() => {
    if (!live) { setAngle(base); return }
    const pick = () => {
      const u = (Math.random() + Math.random()) / 2
      setAngle(probAToAngle(lo + u * (hi - lo)))
    }
    pick()
    const id = window.setInterval(pick, 1300)
    return () => window.clearInterval(id)
  }, [live, base, lo, hi])
  return live ? angle : base
}

interface Props {
  needle: NeedleContest
  candidates: SummaryCandidate[]
  title: string
  measure?: boolean
  compact?: boolean
  updatedAt?: string
  jitter?: boolean
  onToggleJitter?: (v: boolean) => void
}

export function Needle({ needle, candidates, title, measure = false, compact = false, updatedAt, jitter = true, onToggleJitter }: Props) {
  const text = needleText(needle, candidates, { measure, title })
  const left: Side = text.leader.id === needle.pair[0] ? text.leader : text.trailer
  const right: Side = text.leader.id === needle.pair[0] ? text.trailer : text.leader
  const pre = needle.stage === 'pre'
  const angle = useNeedleAngle(needle, jitter)

  const ramps = useMemo(() => ({ left: interpolateRgbBasis(RAMPS[left.group]), right: interpolateRgbBasis(RAMPS[right.group]) }), [left.group, right.group])
  const slices = useMemo(() => {
    const out: { d: string; fill: string }[] = []
    for (const side of ['left', 'right'] as const) {
      for (let i = 0; i < SLICES; i++) {
        const t0 = i / SLICES
        const t1 = (i + 1) / SLICES
        const a0 = (tToAngle(t0, side) * Math.PI) / 180
        const a1 = (tToAngle(t1, side) * Math.PI) / 180
        const [s, e] = side === 'left' ? [a1, a0] : [a0, a1]
        out.push({ d: sliceArc({ s, e }) ?? '', fill: ramps[side](Math.pow((t0 + t1) / 2, 0.8)) })
      }
    }
    return out
  }, [ramps])

  const bandNoun = (side: Side) => (measure ? (side.group === 'FOR' ? 'passes' : 'fails') : side.short)
  const aria = `${text.headline}. ${text.tossUp ? `${left.short} ${Math.round((needle.prob[left.id] ?? 0.5) * 100)} percent, ${right.short} ${Math.round((needle.prob[right.id] ?? 0.5) * 100)} percent. ` : ''}${text.marginText}. ${text.caption}.`

  const showLabels = !compact
  const viewH = compact ? 236 : 272
  const fadeOpacity = pre ? 0.4 : 1

  return (
    <figure className={`needle${compact ? ' needle-compact' : ''}${pre ? ' needle-pre' : ''}`} aria-label={`Win probability: ${title}`}>
      <svg viewBox={`0 ${compact ? 14 : 0} ${W} ${viewH - (compact ? 14 : 0)}`} role="img" aria-label={aria} className="needle-svg">
        <g opacity={fadeOpacity}>
          {slices.map((s, i) => <path key={i} d={s.d} transform={`translate(${CX},${CY})`} fill={s.fill} stroke={s.fill} strokeWidth={0.7} />)}
          {BAND_EDGES.slice(1, -1).flatMap((t) => (['left', 'right'] as const).map((side) => {
            const a = tToAngle(t, side)
            const [x0, y0] = polar(R_IN - 1, a)
            const [x1, y1] = polar(R_OUT + 1, a)
            return <line key={`${side}${t}`} x1={x0} y1={y0} x2={x1} y2={y1} className="needle-edge" />
          }))}
          {showLabels && BAND_NAMES.map((name, bi) => {
            const t0 = BAND_EDGES[bi]
            const t1 = BAND_EDGES[bi + 1]
            const rMid = (R_IN + R_OUT) / 2
            const sides = bi === 0 ? (['left'] as const) : (['left', 'right'] as const)
            return sides.map((side) => {
              const aStart = bi === 0 ? tToAngle(t1, 'left') : side === 'left' ? tToAngle(t1, 'left') : tToAngle(t0, 'right')
              const aEnd = bi === 0 ? tToAngle(t1, 'right') : side === 'left' ? tToAngle(t0, 'left') : tToAngle(t1, 'right')
              const [x0, y0] = polar(rMid, aStart)
              const [x1, y1] = polar(rMid, aEnd)
              const id = `needle-band-${bi}-${side}`
              const mid = (t0 + t1) / 2
              const dark = mid > 0.5
              return (
                <g key={id}>
                  <path id={id} d={`M${x0},${y0} A${rMid},${rMid} 0 0 1 ${x1},${y1}`} fill="none" />
                  <text className="needle-band-label" fill={dark ? '#fff' : '#2a2a2a'}>
                    <textPath href={`#${id}`} startOffset="50%" textAnchor="middle">{name}</textPath>
                  </text>
                </g>
              )
            })
          })}
          {showLabels && TICKS.flatMap((p) => (['left', 'right'] as const).map((side) => {
            const a = tToAngle(probToT(p), side)
            const [x0, y0] = polar(R_OUT, a)
            const [x1, y1] = polar(R_OUT + 7, a)
            const [tx, ty] = polar(R_OUT + 19, a)
            return (
              <g key={`${side}${p}`}>
                <line x1={x0} y1={y0} x2={x1} y2={y1} className="needle-tick" />
                <text x={tx} y={ty} textAnchor="middle" dominantBaseline="middle" className="needle-tick-label">{p === 0.99 ? '99%' : `${Math.round(p * 100)}%`}</text>
              </g>
            )
          }))}
          {showLabels && (() => {
            const [x0, y0] = polar(R_OUT, 0)
            const [x1, y1] = polar(R_OUT + 7, 0)
            const [tx, ty] = polar(R_OUT + 19, 0)
            return (
              <g>
                <line x1={x0} y1={y0} x2={x1} y2={y1} className="needle-tick" />
                <text x={tx} y={ty} textAnchor="middle" dominantBaseline="middle" className="needle-tick-label">50%</text>
              </g>
            )
          })()}
        </g>
        <g className="needle-pointer" style={{ transform: `rotate(${angle}deg)`, transformOrigin: `${CX}px ${CY}px` }} opacity={pre ? 0.35 : 1}>
          <polygon points={`${CX - 5},${CY} ${CX + 5},${CY} ${CX + 1.2},${CY - R_IN + 6} ${CX - 1.2},${CY - R_IN + 6}`} className="needle-blade" />
        </g>
        <circle cx={CX} cy={CY} r={compact ? 9 : 11} className="needle-hub" opacity={pre ? 0.5 : 1} />
        {!compact && (
          <>
            <text x={CX - R_OUT + 4} y={CY + 22} textAnchor="start" className="needle-side-label" fill={left.color}>{bandNoun(left)}</text>
            <text x={CX + R_OUT - 4} y={CY + 22} textAnchor="end" className="needle-side-label" fill={right.color}>{bandNoun(right)}</text>
          </>
        )}
      </svg>
      <figcaption className="needle-text">
        <div className={`needle-headline${text.tossUp ? ' toss' : ''}`}>
          {compact ? (
            <>
              <b className="needle-pct" style={{ color: text.tossUp ? undefined : text.leader.color }}>{text.tossUp ? 'Toss-up' : text.pctText}</b>
              {!text.tossUp && <span className="needle-who">{measure ? `${title} ${text.leader.group === 'FOR' ? 'passes' : 'fails'}` : text.leader.short}</span>}
            </>
          ) : (
            <span aria-live="polite">{text.headline}</span>
          )}
        </div>
        {!compact && text.tossUp && (
          <div className="needle-sub">
            {left.short} {Math.round((needle.prob[left.id] ?? 0.5) * 100)}% · {right.short} {Math.round((needle.prob[right.id] ?? 0.5) * 100)}% chance of winning
          </div>
        )}
        {!compact && !pre && <div className="needle-margin">{text.marginText}</div>}
        {compact && !pre && <div className="needle-margin sm">{text.marginText.replace('Projected margin: ', '')}</div>}
        {!compact && <div className={`needle-caption${pre ? ' strong' : ''}`}>{text.caption}{updatedAt && !pre ? ` · updated ${fmtMT(updatedAt)} MT` : ''}</div>}
        {compact && pre && <div className="needle-caption">Pre-election estimate</div>}
        {!compact && needle.stage !== 'pre' && needle.stage !== 'final' && onToggleJitter && (
          <button type="button" className="link-btn needle-jitter-btn" aria-pressed={!jitter} onClick={() => onToggleJitter(!jitter)}>
            {jitter ? 'Stop jitter' : 'Resume jitter'}
          </button>
        )}
      </figcaption>
    </figure>
  )
}

import { Link } from 'react-router-dom'
import type { NeedleContest } from '../types/data'
import { sideOf, signed, type NamedCandidate } from '../lib/needle'

interface Props {
  needle: NeedleContest
  candidates: NamedCandidate[]
  title: string
  measure?: boolean
  compact?: boolean
  /** Hide the "based on" note when the surrounding page already carries it. */
  showNote?: boolean
}

export const STAGE_LABEL: Record<NeedleContest['stage'], string> = {
  pre: 'Our forecast',
  early: 'Live projection of the final result',
  live: 'Live projection of the final result',
  final: 'Projection at the final count',
}

const inHundred = (p: number): string => (p >= 0.99 ? 'more than 99' : p <= 0.01 ? 'fewer than 1' : String(Math.round(p * 100)))

/** Our model's projection. Deliberately neutral-ink and boxed so it reads as neither a result nor a poll. */
export function ForecastSummary({ needle, candidates, title, measure = false, compact = false, showNote = true }: Props) {
  const [a, b] = needle.pair
  const pa = needle.prob[a] ?? 0.5
  const aLeads = pa >= 0.5
  const leader = sideOf(aLeads ? a : b, candidates)
  const trailer = sideOf(aLeads ? b : a, candidates)
  const p = aLeads ? pa : 1 - pa
  const m = needle.margin
  const lead = aLeads ? m.median : -m.median
  const lo90 = aLeads ? m.lo90 : -m.hi90
  const hi90 = aLeads ? m.hi90 : -m.lo90
  const lo50 = aLeads ? m.lo50 : -m.hi50
  const hi50 = aLeads ? m.hi50 : -m.lo50
  const pts = (v: number) => Math.round(v * 100)
  const tossUp = p < 0.6
  const verb = measure ? (leader.group === 'FOR' ? 'passes' : 'fails') : 'wins'
  const subject = measure ? title : leader.short
  const headline = tossUp ? `Toss-up: ${subject} ${verb} ${inHundred(p)} in 100` : `${subject} ${verb} ${inHundred(p)} in 100`
  const label = STAGE_LABEL[needle.stage]
  const live = needle.stage === 'early' || needle.stage === 'live'

  const domain = Math.max(0.2, Math.ceil(Math.max(Math.abs(lo90), Math.abs(hi90)) * 10) / 10)
  const pos = (v: number) => `${((v + domain) / (2 * domain)) * 100}%`
  const width = (x: number, y: number) => `${((y - x) / (2 * domain)) * 100}%`

  return (
    <div className={`forecast${compact ? ' compact' : ''}${live ? ' is-live' : ''}`}>
      <div className="forecast-tag">{label}<span> · model, not votes</span></div>
      <div className="forecast-head">{headline}</div>
      <div className="forecast-margin">
        Projected margin {leader.short} {signed(pts(lead))} pts
        <span> (90% range {signed(pts(lo90))} to {signed(pts(hi90))})</span>
      </div>
      {!compact && (
        <div className="forecast-track" role="img" aria-label={`Projected margin ${leader.short} ${signed(pts(lead))}, 50% range ${signed(pts(lo50))} to ${signed(pts(hi50))}, 90% range ${signed(pts(lo90))} to ${signed(pts(hi90))}`}>
          <div className="ft-axis" />
          <div className="ft-zero" style={{ left: '50%' }} />
          <div className="ft-90" style={{ left: pos(lo90), width: width(lo90, hi90) }} />
          <div className="ft-50" style={{ left: pos(lo50), width: width(lo50, hi50) }} />
          <div className="ft-med" style={{ left: pos(lead) }} />
          <div className="ft-ends"><span>{trailer.short} ahead</span><span>{leader.short} ahead</span></div>
        </div>
      )}
      {!compact && showNote && (
        <p className="forecast-note">
          {live ? 'Combines votes counted so far with the ballots still expected. ' : 'Based on the polling average, 2024 results in the new district and the national environment. '}
          Darker bar: 50% range. Lighter bar: 90% range. <Link to="/methodology">How the forecast works</Link>.
        </p>
      )}
    </div>
  )
}

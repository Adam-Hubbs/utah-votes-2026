import type { ReactNode } from 'react'
import { fmtInt, fmtPct } from '../lib/format'
import { PartyChip } from './PartyChip'

interface Props {
  name: string
  party: string | null
  candidateId?: string
  incumbent?: boolean
  votes?: number
  pct?: number
  color: string
  winner?: boolean
  maxPct?: number
  extra?: ReactNode
  compact?: boolean
}

export function CandidateRow({ name, party, candidateId, incumbent, votes, pct, color, winner, maxPct = 1, extra, compact }: Props) {
  return (
    <div className={`cand-row${winner ? ' winner' : ''}${compact ? ' compact' : ''}`}>
      <div className="cand-name">
        <span className="cand-swatch" style={{ background: color }} aria-hidden />
        <span className="cand-text">
          {name}
          {incumbent && <span className="inc" title="Incumbent"> (i)</span>}
        </span>
        <PartyChip party={party} id={candidateId} />
        {winner && (
          <span className="check" role="img" aria-label="Winner">
            <svg viewBox="0 0 16 16" width="14" height="14"><path d="M3 8.5l3.2 3.2L13 4.8" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" /></svg>
            <span>Winner</span>
          </span>
        )}
      </div>
      {pct != null && (
        <div className="cand-bar" aria-hidden>
          <div style={{ width: `${Math.min(100, (pct / (maxPct || 1)) * 100)}%`, background: color }} />
        </div>
      )}
      <div className="cand-num">
        {votes != null && <span className="cand-votes">{fmtInt(votes)}</span>}
        {pct != null && <span className="cand-pct">{fmtPct(pct)}</span>}
        {extra}
      </div>
    </div>
  )
}

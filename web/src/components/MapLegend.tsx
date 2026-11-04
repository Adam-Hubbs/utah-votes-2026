import { MARGIN_LABELS, rampFor } from '../lib/colors'
import type { PartyGroup } from '../lib/parties'

export function MarginLegend({ groups = ['DEM', 'REP', 'THIRD'], note }: { groups?: PartyGroup[]; note?: string }) {
  const names: Record<string, string> = { DEM: 'Democratic', REP: 'Republican', THIRD: 'Third party', FOR: 'For', AGAINST: 'Against' }
  return (
    <div className="legend" aria-label="Map legend">
      <div className="legend-title">Margin of victory{note ? ` · ${note}` : ''}</div>
      <div className="legend-rows">
        {groups.map((g) => (
          <div className="legend-row" key={g}>
            <span className="legend-name">{names[g]}</span>
            <span className="legend-ramp">
              {rampFor(g).map((c, i) => (
                <span key={c} className="legend-cell">
                  <i style={{ background: c }} />
                  <em>{MARGIN_LABELS[i]}</em>
                </span>
              ))}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}

export function PrecinctKey({ counting }: { counting: boolean }) {
  return (
    <div className="legend legend-precinct" aria-label="Precinct map key">
      <div className="legend-hatch"><i className="key-empty" /> No residents, so no votes cast</div>
      <div className="legend-hatch"><i className="key-missing" /> No precinct-level result (may be counted with a neighbouring precinct)</div>
      {counting && <div className="legend-hatch"><i className="key-pending" /> Not yet reported</div>}
    </div>
  )
}

export function ContinuousLegend({ colors, lo, hi, title }: { colors: string[]; lo: string; hi: string; title: string }) {
  return (
    <div className="legend">
      <div className="legend-title">{title}</div>
      <div className="legend-continuous">
        <span>{lo}</span>
        <span className="legend-bar" style={{ background: `linear-gradient(90deg, ${colors.join(',')})` }} />
        <span>{hi}</span>
      </div>
    </div>
  )
}

import { Link } from 'react-router-dom'
import { useHouse, useSenate } from './hooks'
import './national.css'

export function NationalTicker() {
  const senate = useSenate()
  const house = useHouse()
  if (!senate) return null

  const cur = senate.composition.current
  const d = cur.DEM + cur.IND
  const gb = house?.generic_ballot
  const lead = gb ? (gb.margin < -0.05 ? `D+${Math.abs(gb.margin).toFixed(1)}` : gb.margin > 0.05 ? `R+${gb.margin.toFixed(1)}` : 'Even') : null
  const body = (
    <>
      <span className="tk-group"><b>Current Senate</b> {cur.REP >= d ? <span className="r">R {cur.REP}–{d}</span> : <span className="d">D {d}–{cur.REP}</span>} · {senate.races.length} races</span>
      {lead && <span className="tk-group tk-hide-xs">Generic ballot <b className={lead[0] === 'D' ? 'd' : 'r'}>{lead}</b></span>}
    </>
  )
  return (
    <div className="ticker" role="complementary" aria-label="National summary">
      <div className="wrap">
        <Link to="/national" className="ticker-link">
          <span className="tk-label">National</span>
          {body}
          <span className="tk-arrow" aria-hidden>→</span>
        </Link>
      </div>
    </div>
  )
}

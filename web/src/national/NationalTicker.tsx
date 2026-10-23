import { Link } from 'react-router-dom'
import { useSite } from '../data/site'
import { useHouse, useSenate } from './hooks'
import './national.css'

export function NationalTicker() {
  const { mode } = useSite()
  const senate = useSenate()
  const house = useHouse()
  if (!senate) return null

  const st = senate.tally
  const calls = st.DEM_won + st.REP_won + st.IND_won + (house ? house.tally.DEM_won + house.tally.REP_won + house.tally.IND_won : 0)
  const election = mode !== 'pre' || calls > 0

  let body
  if (election) {
    const ht = house?.tally
    body = (
      <>
        <span className="tk-group"><b>Senate</b> <span className="d">D {st.DEM_won}</span> · <span className="r">R {st.REP_won}</span>{st.IND_won > 0 && <> · I {st.IND_won}</>} · {st.uncalled} uncalled</span>
        {ht && <span className="tk-group"><b>House</b> <span className="d">D {ht.DEM_won}</span> · <span className="r">R {ht.REP_won}</span> · {ht.uncalled} uncalled</span>}
      </>
    )
  } else {
    const cur = senate.composition.current
    const d = cur.DEM + cur.IND
    const gb = house?.generic_ballot
    const lead = gb ? (gb.margin < -0.05 ? `D+${Math.abs(gb.margin).toFixed(1)}` : gb.margin > 0.05 ? `R+${gb.margin.toFixed(1)}` : 'Even') : null
    body = (
      <>
        <span className="tk-group"><b>Senate</b> {cur.REP >= d ? <span className="r">R {cur.REP}–{d}</span> : <span className="d">D {d}–{cur.REP}</span>} · {senate.races.length} races</span>
        {lead && <span className="tk-group tk-hide-xs">Generic ballot <b className={lead[0] === 'D' ? 'd' : 'r'}>{lead}</b></span>}
      </>
    )
  }
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

import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import type { Feature, Geometry } from 'geojson'
import { ChoroplethMap } from '../ChoroplethMap'
import { MarginLegend } from '../MapLegend'
import { useGeo } from '../../data/hooks'
import { useSite } from '../../data/site'
import { NO_DATA, leaderFill } from '../../lib/colors'
import { partyGroup } from '../../lib/parties'
import { fmtMargin, fmtPct } from '../../lib/format'
import { seatLabel, type SeatState } from '../../lib/legislature'

type F = Feature<Geometry, Record<string, unknown>>

const PRE_FILL = { REP: '#E36B72', DEM: '#5F93D3', OTH: '#E3B505' } as const
const HOLDOVER = '#d4d4d0'

// Salt Lake / Davis / Utah County core, where most districts are too small to click on a statewide map.
const WASATCH: F = {
  type: 'Feature', properties: {},
  geometry: { type: 'Polygon', coordinates: [[[-112.16, 40.05], [-112.16, 41.12], [-111.62, 41.12], [-111.62, 40.05], [-112.16, 40.05]]] },
}

export function LegislatureMap({ chamber, states, started }: { chamber: 'house' | 'senate'; states: SeatState[]; started: boolean }) {
  const geo = useGeo(chamber === 'house' ? 'state_house' : 'state_senate')
  const navigate = useNavigate()
  const { currentElection } = useSite()
  const byDistrict = useMemo(() => new Map(states.map((s) => [s.seat.district, s])), [states])
  const stateOf = (f: F): SeatState | undefined => byDistrict.get(Number(f.properties?.district))

  const fill = (f: F): string => {
    const s = stateOf(f)
    if (!s) return NO_DATA
    if (s.status === 'holdover') return HOLDOVER
    if (started) return s.leader ? leaderFill(partyGroup(s.leader.party, s.leader.candidate_id), s.margin) : NO_DATA
    return s.bucket ? PRE_FILL[s.bucket] : NO_DATA
  }
  const hatch = (f: F): boolean => {
    const s = stateOf(f)
    return !!s && started && s.status !== 'holdover' && s.status !== 'untracked' && s.pctCounted < 0.5
  }
  const tooltip = (f: F) => {
    const s = stateOf(f)
    const d = Number(f.properties?.district)
    if (!s) return <div className="tt-title">{seatLabel(chamber)} {d}</div>
    const holder = s.seat.vacant ? 'Vacant' : `${s.seat.holder ?? '—'}${s.seat.holder_party ? ` (${s.seat.holder_party[0]})` : ''}`
    return (
      <div>
        <div className="tt-title">{seatLabel(chamber)} {d}</div>
        <div className="tt-row"><span>Current</span><b>{holder}</b></div>
        {s.status === 'holdover' && <div className="tt-muted">Not on the 2026 ballot</div>}
        {s.status !== 'holdover' && started && s.leader && (
          <>
            <div className="tt-row"><span>{s.status === 'won' ? 'Winner' : 'Leading'}</span><b>{s.leader.name} ({s.leader.party?.[0] ?? '–'}) {fmtPct(s.leader.pct)}</b></div>
            <div className="tt-muted">Est. {fmtPct(s.pctCounted, 0)} counted{s.flip ? ' · flip' : ''}</div>
          </>
        )}
        {s.status !== 'holdover' && started && !s.leader && <div className="tt-muted">{s.status === 'untracked' ? 'Contest not yet in results feed' : 'No votes counted yet'}</div>}
        {s.status !== 'holdover' && !started && (
          <>
            <div className="tt-row"><span>2024 president</span><b>{fmtMargin(s.seat.pres24_margin)}</b></div>
            {s.seat.uncontested && <div className="tt-muted">Unopposed</div>}
            {s.seat.up && !s.seat.vacant && s.seat.incumbent_running === false && <div className="tt-muted">Incumbent not running</div>}
          </>
        )}
        {s.seat.contest_id && <div className="tt-muted">Click for the race page</div>}
      </div>
    )
  }
  const open = (f: F | null) => {
    const s = f ? stateOf(f) : undefined
    if (s?.seat.contest_id) navigate(`/results/${currentElection}/${s.seat.contest_id}`)
  }

  if (geo === undefined) return <div className="map-placeholder">Loading map…</div>
  if (geo === null) return <div className="unavailable">District map not yet available.</div>
  const features = geo.features as F[]

  return (
    <div>
      <div className="leg-maps">
        <figure className="leg-map">
          <figcaption>Statewide</figcaption>
          <ChoroplethMap features={features} idOf={(f) => String(f.properties?.district)} fill={fill} hatch={hatch} tooltip={tooltip} onSelect={open}
            strokeWidth={0.6} zoomable={false} aspect={1.1} maxHeight={520} ariaLabel={`Map of Utah ${chamber} districts`} />
        </figure>
        <figure className="leg-map">
          <figcaption>Wasatch Front</figcaption>
          <ChoroplethMap features={features} fitTo={[WASATCH]} idOf={(f) => String(f.properties?.district)} fill={fill} hatch={hatch} tooltip={tooltip} onSelect={open}
            strokeWidth={0.8} zoomable aspect={1.1} maxHeight={520} ariaLabel={`Map of ${chamber} districts along the Wasatch Front`} />
        </figure>
      </div>
      {started ? <MarginLegend hatchNote note="leader" /> : (
        <div className="legend">
          <div className="legend-title">Current holder&rsquo;s party</div>
          <div className="legend-swatches">
            <span><i style={{ background: PRE_FILL.REP }} /> Republican</span>
            <span><i style={{ background: PRE_FILL.DEM }} /> Democratic</span>
            <span><i style={{ background: PRE_FILL.OTH }} /> Other</span>
            {chamber === 'senate' && <span><i style={{ background: HOLDOVER }} /> Not up in 2026</span>}
            <span><i style={{ background: NO_DATA }} /> Vacant</span>
          </div>
        </div>
      )}
    </div>
  )
}

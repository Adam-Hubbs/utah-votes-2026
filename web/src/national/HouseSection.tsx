import { PollChart } from '../components/PollChart'
import { Section } from '../components/Ui'
import { RATING_FILL } from '../lib/colors'
import { fmtDay, parseDate } from '../lib/format'
import type { NationalPolls, NationalSeriesPoint } from '../types/data'
import type { HouseFile } from './types'
import { SEAT_HEX } from './lib'

const SRC_NAME = { cook: 'Cook Political Report', sabato: "Sabato's Crystal Ball", inside: 'Inside Elections' }
const seriesOf = (s: NationalSeriesPoint[], key: string) => s.map((p) => ({ x: parseDate(String(p.date)), y: Number(p[key]) }))

function ratingSegments(counts: Record<string, number>) {
  const g = (k: string) => counts[k] ?? 0
  return [
    { label: 'Solid D', n: g('Solid D'), i: 0 }, { label: 'Likely D', n: g('Likely D'), i: 1 },
    { label: 'Lean/Tilt D', n: g('Lean D') + g('Tilt D'), i: 2 }, { label: 'Toss-up', n: g('Toss-up'), i: 3 },
    { label: 'Lean/Tilt R', n: g('Lean R') + g('Tilt R'), i: 4 }, { label: 'Likely R', n: g('Likely R'), i: 5 }, { label: 'Solid R', n: g('Solid R'), i: 6 },
  ]
}

export function RatingsTally({ house }: { house: HouseFile }) {
  return (
    <div className="ratings-tally">
      {house.ratings_tally.sources.map((s) => {
        const segs = ratingSegments(s.counts)
        const d = segs.slice(0, 3).reduce((a, x) => a + x.n, 0)
        const r = segs.slice(4).reduce((a, x) => a + x.n, 0)
        return (
          <div key={s.id} className="rt-row">
            <div className="rt-head"><b>{SRC_NAME[s.id]}</b><span className="muted">as of {fmtDay(s.as_of)}</span>
              <span className="rt-sum"><span className="d">D {d}</span> · Toss-up {segs[3].n} · <span className="r">R {r}</span></span></div>
            <div className="seat-bar" role="img" aria-label={`${SRC_NAME[s.id]}: ${segs.map((x) => `${x.label} ${x.n}`).join(', ')}`}>
              {segs.filter((x) => x.n > 0).map((x) => (
                <div key={x.label} style={{ flex: x.n, background: RATING_FILL[x.i], color: x.i === 2 || x.i === 3 || x.i === 4 ? '#222' : '#fff' }} title={`${x.label}: ${x.n}`}>{x.n >= 14 && <span>{x.n}</span>}</div>
              ))}
              <i className="seat-line" style={{ left: `${(218 - 0.5) / 435 * 100}%` }} aria-hidden />
            </div>
          </div>
        )
      })}
      <div className="balance-key">
        {['Solid D', 'Likely D', 'Lean D', 'Toss-up', 'Lean R', 'Likely R', 'Solid R'].map((l, i) => <span key={l}><i style={{ background: RATING_FILL[i] }} /> {l}</span>)}
      </div>
      <p className="note small">Line marks 218 seats. Inside Elections' "Tilt" ratings are grouped with Lean. Counts are from <a href={house.ratings_tally.url} target="_blank" rel="noreferrer">{house.ratings_tally.via}</a>; seats not listed as competitive by any outlet are counted Solid.</p>
    </div>
  )
}

export function HouseSection({ house, national }: { house: HouseFile; national: NationalPolls | null | undefined }) {
  const c = house.composition.current
  const gb = house.generic_ballot
  const lead = gb ? (gb.margin < -0.05 ? `D+${Math.abs(gb.margin).toFixed(1)}` : gb.margin > 0.05 ? `R+${gb.margin.toFixed(1)}` : 'Even') : null
  return (
    <>
      <Section title="U.S. House" dek="All 435 seats are up. Control hinges on a few dozen competitive districts, plus the new maps in several states.">
        <div className="two-col eq">
          <div>
            <h3 className="subhead">Generic congressional ballot{lead && <span className={`gb-lead ${lead[0] === 'D' ? 'd' : 'r'}`}> {lead}</span>}</h3>
            {national ? (
              <>
                <PollChart height={240} ariaLabel="Generic ballot average" yDomain={[35, 55]}
                  series={[
                    { id: 'DEM', label: 'Democrats', endLabel: 'Dem.', color: '#2563B5', line: seriesOf(national.generic_ballot.series, 'DEM') },
                    { id: 'REP', label: 'Republicans', endLabel: 'Rep.', color: '#D6303A', line: seriesOf(national.generic_ballot.series, 'REP') },
                  ]} />
                {gb && <p className="note small">{gb.n_polls} polls, as of {fmtDay(gb.date)}. Margin band {gb.margin_lo.toFixed(1)} to {gb.margin_hi.toFixed(1)} (negative = Democratic lead).</p>}
              </>
            ) : <div className="unavailable">National polling not yet available.</div>}
          </div>
          <div>
            <h3 className="subhead">Current House</h3>
            <div className="seat-bar" role="img" aria-label={`House today: Democrats ${c.DEM}, independent ${c.IND}, Republicans ${c.REP}, vacant ${c.vacant}`}>
              <div style={{ flex: c.DEM, background: SEAT_HEX.DEM, color: '#fff' }}><span>{c.DEM}</span></div>
              <div style={{ flex: c.IND, background: SEAT_HEX.IND }} title="Independent" />
              <div style={{ flex: c.vacant, background: '#ccc' }} title="Vacant" />
              <div style={{ flex: c.REP, background: SEAT_HEX.REP, color: '#fff' }}><span>{c.REP}</span></div>
              <i className="seat-line" style={{ left: `${(218 - 0.5) / 435 * 100}%` }} aria-hidden />
            </div>
            <p className="note small">Democrats {c.DEM} · Republicans {c.REP} · Independent {c.IND} · Vacant {c.vacant}. {house.composition.majority} needed for a majority. {house.composition.note} (<a href={house.composition.source.url} target="_blank" rel="noreferrer">{house.composition.source.name}</a>, as of {fmtDay(house.composition.source.as_of)}.)</p>
          </div>
        </div>
      </Section>
      <Section title="House race ratings" dek="Seats in each category, by three prognosticators.">
        <RatingsTally house={house} />
      </Section>
    </>
  )
}

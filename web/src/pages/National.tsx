import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useNational } from '../data/hooks'
import { Gate, Section, Segmented } from '../components/Ui'
import { PollTracker } from '../components/PollTracker'
import { LastUpdated } from '../components/LastUpdated'
import { useDocTitle } from '../lib/hooks'
import { BalanceBar } from '../national/BalanceBar'
import { HouseSection } from '../national/HouseSection'
import { useHouse, useSenate, useSenatePolls } from '../national/hooks'
import { MapLegend, TileMap } from '../national/TileMap'
import { RaceDetail, SenateTable } from '../national/SenateTable'
import '../national/national.css'

export function NationalPage() {
  useDocTitle('National')
  const senate = useSenate()
  const house = useHouse()
  const polls = useSenatePolls()
  const national = useNational()
  const [selected, setSelected] = useState<string | null>(null)
  const [trackerState, setTrackerState] = useState<string | null>(null)

  const race = senate?.races.find((r) => r.state === selected) ?? null
  const trackers = senate?.races.filter((r) => r.tracker && polls?.averages[`senate-${r.state}`]) ?? []
  const tState = trackerState ?? trackers[0]?.state ?? null

  return (
    <div className="page national">
      <header className="page-head">
        <div className="kicker">National</div>
        <h1 className="headline sm">The U.S. Senate and House</h1>
        <p className="dek">
          Utah has no Senate race this year, and our focus stays on <Link to="/results">Utah’s races</Link>. This page tracks the national contests that decide control of Congress.
 It shows pre-election context only (current composition, race ratings and poll averages); we do not report national results.
        </p>
      </header>

      <Section title="Control of the Senate" aside={senate && <LastUpdated iso={senate.updated_at} />}>
        <Gate data={senate} what="Senate data">{(s) => <BalanceBar senate={s} />}</Gate>
      </Section>

      <Section title="2026 Senate races" dek="One tile per state; 35 seats are up, including special elections in Florida and Ohio. Select a state for details.">
        <Gate data={senate} what="Senate races">
          {(s) => (
            <div className="two-col map-cols">
              <div>
                <TileMap races={s.races} selected={selected} onSelect={(st) => setSelected(selected === st ? null : st)} />
                <MapLegend />
              </div>
              <div>
                {race ? <RaceDetail race={race} senate={s} /> : (
                  <div className="race-detail empty">
                    <p>Select a state on the map or a row in the table for the candidates, poll average and ratings.</p>
                    <p className="note small">Poll averages weight each poll by recency, sample size and pollster quality, using the New York Times poll database. Ratings are from Cook Political Report, Sabato’s Crystal Ball and Inside Elections.</p>
                  </div>
                )}
              </div>
            </div>
          )}
        </Gate>
      </Section>

      <Section title="Race table">
        <Gate data={senate} what="Senate races">{(s) => <SenateTable senate={s} selected={selected} onSelect={(st) => setSelected(st)} />}</Gate>
        {senate && (
          <p className="note small">
            Ratings sources: {senate.ratings_sources.map((r) => `${r.name} (${r.as_of})`).join(', ')}, via {senate.ratings_via}. Seat counts: <a href={senate.composition_source.url} target="_blank" rel="noreferrer">{senate.composition_source.name}</a>.
            {' '}Poll margin is the Republican against the leading opponent. {senate.poll_note}
          </p>
        )}
      </Section>

      {senate && polls && trackers.length > 0 && tState && (
        <Section title="Closest Senate races: poll trackers" dek="The eight most competitive races with recent polling."
          aside={<Segmented label="Race" value={tState} onChange={setTrackerState} options={trackers.map((r) => ({ value: r.state, label: r.state }))} />}>
          <h3 className="subhead">{senate.races.find((r) => r.state === tState)?.state_name}</h3>
          <PollTracker contestId={`senate-${tState}`} avg={polls.averages[`senate-${tState}`]} polls={polls.polls} today={new Date()} height={300} />
        </Section>
      )}

      <Gate data={house} what="House data">{(h) => <HouseSection house={h} national={national} />}</Gate>

      <p className="note small">Not affiliated with any news organization. Unofficial national tallies; see <Link to="/methodology">methodology</Link> for how Utah’s own results are produced.</p>
    </div>
  )
}

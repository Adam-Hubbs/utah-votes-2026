import { useMemo, useState } from 'react'
import { useJudges, useLegislature } from '../data/legislature'
import { useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { BalanceOfPower } from '../components/state/BalanceOfPower'
import { LegislatureMap } from '../components/state/LegislatureMap'
import { RaceTable } from '../components/state/RaceTable'
import { Judges } from '../components/state/Judges'
import { SchoolBoard } from '../components/state/SchoolBoard'
import { LastUpdated } from '../components/LastUpdated'
import { Gate, Section, Segmented } from '../components/Ui'
import { seatStates } from '../lib/legislature'
import { useDocTitle } from '../lib/hooks'
import type { SummaryContest } from '../types/data'
import '../styles/state.css'

export function StatePage() {
  useDocTitle('State races')
  const { mode, currentElection } = useSite()
  const summary = useSummary(currentElection)
  const leg = useLegislature()
  const judges = useJudges()
  const [mapChamber, setMapChamber] = useState<'house' | 'senate'>('house')

  const contests = useMemo<SummaryContest[]>(() => summary?.contests ?? [], [summary])
  const byId = useMemo(() => new Map(contests.map((c) => [c.contest_id, c])), [contests])
  const started = mode !== 'pre' && contests.some((c) => c.office.startsWith('state-') && c.total_votes > 0)

  const states = useMemo(() => {
    if (!leg) return null
    return {
      house: seatStates('house', leg.chambers.house, byId, started),
      senate: seatStates('senate', leg.chambers.senate, byId, started),
    }
  }, [leg, byId, started])

  return (
    <div className="page state-page">
      <header className="page-head">
        <div className="kicker">Utah · State races</div>
        <h1 className="headline sm">The Legislature, judges and school board</h1>
        <p className="dek">
          {started
            ? 'Which party controls each chamber, race by race. A seat counts as won only once results are official; until then it is shown as leading.'
            : 'All 75 House seats and 15 of 29 Senate seats are on the ballot, along with judicial retention and the State School Board.'}
          {started && <> <LastUpdated iso={summary?.updated_at} /></>}
        </p>
      </header>

      <Section title="Balance of power" dek="A majority passes bills; two-thirds of each chamber can override the governor’s veto.">
        <Gate data={leg} what="Legislature data">
          {(d) => states && (
            <div className="bop-grid">
              <BalanceOfPower chamber="house" data={d.chambers.house} states={states.house} started={started} />
              <BalanceOfPower chamber="senate" data={d.chambers.senate} states={states.senate} started={started} />
            </div>
          )}
        </Gate>
      </Section>

      <Section title="District maps" dek="Click a district for the race page. Most districts are small and packed along the Wasatch Front, so the second map zooms in there."
        aside={<Segmented<'house' | 'senate'> label="Chamber" value={mapChamber} onChange={setMapChamber} options={[{ value: 'house', label: 'House' }, { value: 'senate', label: 'Senate' }]} />}>
        {states ? <LegislatureMap chamber={mapChamber} states={states[mapChamber]} started={started} /> : <Gate data={leg} what="Legislature data">{() => null}</Gate>}
      </Section>

      <Section title="Legislative races" dek="Every seat on the ballot. The 2024 presidential margin shows how each district voted at the top of the ticket.">
        {states ? <RaceTable states={[...states.house, ...states.senate]} started={started} /> : <Gate data={leg} what="Legislature data">{() => null}</Gate>}
        <p className="note small">Seats whose contest is missing from the results feed (a few Weber County races) are listed without candidates.</p>
      </Section>

      <Section title="Judicial retention" dek="Voters decide whether each judge stays on the bench.">
        <Judges contests={contests} judges={judges} started={started} />
      </Section>

      <Section title="State School Board" dek="Seven of the board’s 15 seats are up.">
        <SchoolBoard contests={contests} started={started} />
      </Section>
    </div>
  )
}

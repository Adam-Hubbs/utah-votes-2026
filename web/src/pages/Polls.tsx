import { useMemo, useState } from 'react'
import { useAverages, useNational, usePolls, useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { Gate, Section, Segmented } from '../components/Ui'
import { PollTracker } from '../components/PollTracker'
import { PollChart } from '../components/PollChart'
import { parseDate } from '../lib/format'
import { useDocTitle } from '../lib/hooks'
import type { NationalSeriesPoint } from '../types/data'

const house = (n: number) => `us-house-${n}`

export function PollsPage() {
  useDocTitle('Polls')
  const { currentElection } = useSite()
  const polls = usePolls()
  const averages = useAverages()
  const national = useNational()
  const summary = useSummary(currentElection)
  const [contest, setContest] = useState(house(1))
  const ids = useMemo(() => {
    const s = new Set<string>([...Object.keys(averages?.contests ?? {}), ...(polls ?? []).filter((p) => p.stage !== 'primary').map((p) => p.contest_id)])
    return [...s].sort()
  }, [averages, polls])
  const nameOf = (id: string) => summary?.contests.find((c) => c.contest_id === id)?.name ?? id.replace('us-house-', 'U.S. House District ').replace('amendment-', 'Amendment ')
  const primaryContests = useMemo(() => [...new Set((polls ?? []).filter((p) => p.stage === 'primary').map((p) => p.contest_id))].sort(), [polls])

  return (
    <div className="page">
      <header className="page-head">
        <div className="kicker">Polls</div>
        <h1 className="headline sm">Poll tracker</h1>
        <p className="dek">Every public poll of Utah’s 2026 races, combined into a running average. Few races are polled often, so averages here can rest on a handful of surveys.</p>
      </header>

      <Section title="General election" aside={
        <Segmented label="Contest" value={contest} onChange={setContest} options={ids.map((id) => ({ value: id, label: id.replace('us-house-', 'District ').replace('amendment-', 'Amend. ') }))} />
      }>
        <h3 className="subhead">{nameOf(contest)}</h3>
        <Gate data={polls} what="Polls">
          {(p) => <PollTracker contestId={contest} avg={averages?.contests[contest]} polls={p} today={new Date()} />}
        </Gate>
      </Section>

      {primaryContests.length > 0 && (
        <Section title="Primary polls" dek="Surveys taken before the June primaries, kept separate from the general election average.">
          {primaryContests.map((id) => (
            <div key={id} className="primary-block">
              <h3 className="subhead">{nameOf(id)}</h3>
              <Gate data={polls} what="Polls">{(p) => <PollTracker contestId={id} stage="primary" polls={p} showTable height={200} />}</Gate>
            </div>
          ))}
        </Section>
      )}

      <Section title="National context" dek="Utah’s races are shaped partly by the national mood.">
        <Gate data={national} what="National polling">
          {(n) => (
            <div className="two-col eq">
              <div>
                <h3 className="subhead">Generic congressional ballot</h3>
                <PollChart height={250} ariaLabel="Generic ballot average" yDomain={[35, 55]}
                  series={[
                    { id: 'DEM', label: 'Democrats', endLabel: 'Dem.', color: '#2563B5', line: seriesOf(n.generic_ballot.series, 'DEM') },
                    { id: 'REP', label: 'Republicans', endLabel: 'Rep.', color: '#D6303A', line: seriesOf(n.generic_ballot.series, 'REP') },
                  ]} />
              </div>
              <div>
                <h3 className="subhead">Trump approval</h3>
                <PollChart height={250} ariaLabel="Presidential approval average" yDomain={[35, 60]}
                  series={[
                    { id: 'approve', label: 'Approve', color: '#17808A', line: seriesOf(n.approval.series, 'approve') },
                    { id: 'disapprove', label: 'Disapprove', color: '#B5651D', line: seriesOf(n.approval.series, 'disapprove') },
                  ]} />
              </div>
            </div>
          )}
        </Gate>
      </Section>
    </div>
  )
}

const seriesOf = (s: NationalSeriesPoint[], key: string) => s.map((p) => ({ x: parseDate(String(p.date)), y: Number(p[key]) }))

import { Link, useParams } from 'react-router-dom'
import { ContestExplorer } from '../components/ContestExplorer'
import { Gate, Unavailable } from '../components/Ui'
import { useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { useDocTitle } from '../lib/hooks'
import { OFFICE_LABEL } from '../lib/results'

export function StateRacePage() {
  const { contestId = '' } = useParams()
  const { currentElection } = useSite()
  const summary = useSummary(currentElection)
  const contest = summary?.contests.find((c) => c.contest_id === contestId)
  useDocTitle(contest?.name ?? 'State race')

  return (
    <div className="page">
      <Link to="/state" className="more">← All state races</Link>
      <Gate data={summary} what="Election summary">
        {() => contest ? (
          <>
            <header className="page-head">
              <div className="kicker">{OFFICE_LABEL[contest.office] ?? 'State race'} · 2026 General Election</div>
              <h1 className="headline sm">{contest.name}</h1>
              {contest.description && <p className="dek">{contest.description}</p>}
            </header>
            <ContestExplorer key={contestId} electionId={currentElection} contestId={contestId} />
          </>
        ) : <Unavailable what="This race" />}
      </Gate>
    </div>
  )
}

import { Link } from 'react-router-dom'
import { useNeedle, useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { Needle, useJitterSetting } from './Needle'
import { NeedleHistory } from './NeedleHistory'
import { Section } from './Ui'
import type { NeedleContest, SummaryCandidate, SummaryContest } from '../types/data'

/** Full needle plus history for one contest; renders nothing unless the pipeline published a needle for it. */
export function NeedlePanel({ electionId, contestId, headingId = 'needle', title = 'Who is likely to win' }: { electionId: string; contestId: string; headingId?: string; title?: string }) {
  const needle = useNeedle(electionId)
  const summary = useSummary(electionId)
  const [jitter, setJitter] = useJitterSetting()
  const nc = needle?.contests[contestId]
  const contest = summary?.contests.find((c) => c.contest_id === contestId)
  if (!nc || !contest) return null
  const live = nc.stage !== 'pre'
  return (
    <Section id={headingId} title={title} dek={live ? 'Our model’s projection of the final result from votes counted so far and the ballots still expected. This is not the count.' : undefined}>
      <div className="needle-panel">
        <Needle needle={nc} candidates={contest.candidates} title={contest.name} measure={contest.type === 'measure'} updatedAt={needle?.updated_at} jitter={jitter} onToggleJitter={setJitter} />
        {live && (
          <div className="needle-panel-history">
            <NeedleHistory needle={nc} candidates={contest.candidates} />
          </div>
        )}
      </div>
      <p className="note">Not a call: the projection treats the count so far as informative but not final, and Utah’s late ballots can differ. Probabilities are shown no higher than “&gt;99%” or lower than “&lt;1%”. <Link to="/methodology">How the needle works</Link>.</p>
    </Section>
  )
}

export interface StripItem { contest: SummaryContest; needle: NeedleContest }

/** Row of compact needles for the featured contests, shown at the top of the results page while counting. */
export function NeedleStrip({ electionId, featured }: { electionId: string; featured: string[] }) {
  const needle = useNeedle(electionId)
  const summary = useSummary(electionId)
  const { mode } = useSite()
  if (mode === 'pre' || !needle || !summary) return null
  const items = featured.map((id) => ({ contest: summary.contests.find((c) => c.contest_id === id), needle: needle.contests[id] }))
    .filter((i): i is StripItem => !!i.contest && !!i.needle && i.needle.stage !== 'pre')
  if (!items.length) return null
  return (
    <Section title="Needles" dek="Chance of winning, updated with every count." className="needle-strip-section">
      <div className="needle-strip">
        {items.map(({ contest, needle: nc }) => (
          <Link key={contest.contest_id} to={`/results/${electionId}/${contest.contest_id}`} className="needle-strip-item">
            <b>{contest.name.replace('U.S. House District ', 'District ').replace('Constitutional ', '')}</b>
            <CompactNeedle nc={nc} candidates={contest.candidates} title={contest.name.replace('Constitutional ', '')} measure={contest.type === 'measure'} />
          </Link>
        ))}
      </div>
    </Section>
  )
}

export function CompactNeedle({ nc, candidates, title, measure }: { nc: NeedleContest; candidates: SummaryCandidate[]; title: string; measure: boolean }) {
  const [jitter] = useJitterSetting()
  return <Needle needle={nc} candidates={candidates} title={title} measure={measure} compact jitter={jitter} />
}

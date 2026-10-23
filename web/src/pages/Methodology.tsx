import { Link } from 'react-router-dom'
import { useAverages, useModel, useNeedle, useRatings } from '../data/hooks'
import { useSite } from '../data/site'
import { useDocTitle } from '../lib/hooks'
import { fmtDayYear } from '../lib/format'

export function MethodologyPage() {
  useDocTitle('Methodology')
  const { currentElection } = useSite()
  const averages = useAverages()
  const model = useModel(currentElection)
  const needle = useNeedle(currentElection)
  const ratings = useRatings()
  return (
    <div className="page prose-page">
      <header className="page-head">
        <div className="kicker">Methodology</div>
        <h1 className="headline sm">How this site works</h1>
        <p className="dek">What the numbers mean, where they come from, and when they update.</p>
      </header>

      <article className="prose">
        <h2>Poll averages</h2>
        <p>Poll averages combine every public Utah poll found in The New York Times poll database for a given race. Newer polls and polls with larger samples count for more, and each poll’s weight fades over a few weeks. The shaded band around each line is a 95% uncertainty range that widens when there are few polls or they are old.</p>
        <p>Many Utah races are polled only a handful of times, so we say so: a chart marked “Based on 1 poll” is that poll and nothing more. Primary polls are kept separate from general election polls, and the dots on each chart are the individual surveys, sized by sample size.</p>
        {averages && <p className="callout-small"><b>Current averaging method:</b> {averages.method} <span className="muted">(updated {fmtDayYear(averages.updated_at)})</span></p>}

        <h2>Race ratings</h2>
        <p>Ratings are collected from independent forecasters. Each source uses its own words (Safe, Solid, Likely, Lean, Toss-up); we map them onto one seven-point scale from Solid Democratic to Solid Republican. The consensus is the average position of the sources, rounded to the nearest category.{ratings ? ` Sources: ${ratings.sources.map((s) => s.name).join(', ')}.` : ''}</p>

        <h2>Estimating how much vote is left</h2>
        <p>Utah votes almost entirely by mail, and counties report in batches over about two weeks. A precinct “reporting” therefore says little about how much of the vote is in. Instead we estimate the share of the <em>expected</em> final vote that has been counted.</p>
        <p>A Bayesian model predicts each county’s final number of ballots from its registration, past turnout and the ballots already counted, and simulates thousands of plausible outcomes. The percent shown is the median; the range is a 90% interval from the simulations. Statewide totals are the sum across simulated counties, so they are more certain than any single county. Estimates are least reliable early in the night and in small counties.</p>
        <p>The model is a guide, not a call. Late-arriving ballots can differ in partisanship from those counted first, and the site does not project winners except where a result has been called and labelled.</p>
        {model && <p className="callout-small"><b>Current model:</b> {model.method}</p>}

        <h2>Data sources</h2>
        <ul>
          <li><b>Results:</b> Utah Lieutenant Governor’s Office, electionresults.utah.gov, including precinct-level files.</li>
          <li><b>Polls:</b> The New York Times polling database.</li>
          <li><b>Demographics:</b> U.S. Census Bureau, American Community Survey 5-year estimates (2020–2024).</li>
          <li><b>Boundaries:</b> Utah Geospatial Resource Center (UGRC) and U.S. Census Bureau TIGER/Line.</li>
          <li><b>Ratings:</b> Cook Political Report, Sabato’s Crystal Ball, Inside Elections and others as listed on the <Link to="/forecasts">forecasts page</Link>.</li>
        </ul>

        <h2>Boundary changes</h2>
        <p>In November 2025 a court-ordered map replaced Utah’s 2022–2024 congressional districts and created a Salt Lake County–based district. The numbering also changed, so 2024 “District 1” and 2026 “District 1” are different places.</p>
        <p>Precinct lines are redrawn every cycle, so each election uses its own precinct map and we never join results across years by name. To show how past elections would have gone under the new lines, 2020 Census blocks are assigned to precincts and to districts, and each precinct’s votes are split among districts in proportion to voting-age population. These estimates carry error where a precinct straddles a district line. Precinct-to-precinct swing between 2024 and 2026 will be published after the election.</p>

        <h2>Update schedule</h2>
        <ul>
          <li><b>Before the election:</b> polls and ratings refresh when new data is published, usually daily.</li>
          <li><b>Election night:</b> results, the turnout model and the vote timeline refresh about every three minutes; this page checks for new data every minute.</li>
          <li><b>After election night:</b> county canvasses continue for roughly two weeks, with updates every 30 minutes until certification.</li>
        </ul>
        <h2>The needle: chance of winning</h2>
        <p>The needle projects the <em>final</em> result of each U.S. House race, each amendment and each legislative contest. It is not a call and it does not use the percent counted alone: counted votes are exact, and the ballots still to come are simulated 5,000 times (2,500 for legislative contests).</p>
        <ul>
          <li><b>Before votes arrive</b> the starting estimate blends the poll average with a fundamentals baseline: 2024 presidential results re-assigned to the 2026 precincts, nudged by how far the national generic ballot has moved since 2024 (damped by half for Utah). Legislative contests and amendments have no polls, so they use the baseline (legislature) or a deliberately wide range around 50% (amendments). The needle is shown faded until results arrive.</li>
          <li><b>As precincts report</b>, each counted precinct is compared with its 2024 baseline. Those differences show how this contest is running relative to 2024 in each county and statewide; the more precincts are in, the less the starting estimate matters. For amendments the model learns how support varies with a precinct’s 2024 partisanship from the precincts already counted.</li>
          <li><b>Remaining ballots</b> per county come from the expected-vote model above (a lognormal fitted to its 90% range, with a shared statewide factor). The lean of those ballots is what has been counted in the same precinct and county, plus an uncertain shift for late-counted ballots, which in Utah can differ from the first batches. We did not have historical timing data to estimate that shift, so it is a wide assumption, not a measurement.</li>
          <li><b>Back-test:</b> replaying 2024 at 25%, 50%, 75% and 90% counted, the model’s 90% range for the final margin contained the actual margin 85–93% of the time when late ballots behaved as assumed, and 72–74% of the time in a harsher scenario with larger, biased late shifts and worse ballot-count estimates. Treat early-night ranges as optimistic.</li>
          <li><b>Probabilities</b> are never shown above “&gt;99%” or below “&lt;1%”. The needle jitters within the 50% range of the projected margin, as a reminder of that uncertainty; you can stop it with “Stop jitter”, and it stays still if your device asks for reduced motion.</li>
        </ul>
        {needle && <p className="callout-small"><b>Current needle model:</b> {needle.method}</p>}

        <p className="muted">Results are unofficial until certified by the state.</p>
      </article>
    </div>
  )
}

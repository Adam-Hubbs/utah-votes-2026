import { Link } from 'react-router-dom'
import { useAverages, useModel, useRatings } from '../data/hooks'
import { useSite } from '../data/site'
import { useDocTitle } from '../lib/hooks'
import { fmtDayYear } from '../lib/format'

export function MethodologyPage() {
  useDocTitle('Methodology')
  const { currentElection } = useSite()
  const averages = useAverages()
  const model = useModel(currentElection)
  const ratings = useRatings()
  return (
    <div className="page prose-page">
      <header className="page-head">
        <div className="kicker">Methodology</div>
        <h1 className="headline sm">How this site works</h1>
        <p className="dek">What the numbers mean, where they come from, and when they update.</p>
      </header>

      <article className="prose">
        <h2>Polls, forecast and results are different things</h2>
        <ul>
          <li><b>Polling average:</b> what surveys say. It is not a vote count and not a prediction by itself.</li>
          <li><b>Our forecast:</b> a model’s pre-election projection of the final result, built from the polling average, 2024 results re-assigned to the new districts and the national environment. It is shown as a chance of winning and a projected margin with a range.</li>
          <li><b>Results:</b> only counted votes. We do not publish live win probabilities or projected margins during the count.</li>
        </ul>

        <h2>Poll averages</h2>
        <p>Poll averages combine every public Utah poll found in The New York Times poll database for a given race. Newer polls and polls with larger samples count for more, and each poll’s weight fades over a few weeks. The shaded band around each line is a 95% uncertainty range that widens when there are few polls or they are old. Many Utah races are polled only a handful of times, so we say so: an average marked “Based on 1 poll” is that poll and nothing more. Primary polls are kept separate from general election polls.</p>
        {averages && <p className="callout-small"><b>Current averaging method:</b> {averages.method} <span className="muted">(updated {fmtDayYear(averages.updated_at)})</span></p>}

        <h2>Race ratings</h2>
        <p>Ratings are collected from independent forecasters. Each source uses its own words (Safe, Solid, Likely, Lean, Toss-up); we map them onto one seven-point scale from Solid Democratic to Solid Republican. The consensus is the average position of the sources, rounded to the nearest category.{ratings ? ` Sources: ${ratings.sources.map((s) => s.name).join(', ')}.` : ''}</p>

        <h2>Legislative race ratings</h2>
        <p>Each state House and Senate race gets a pre-election rating from the forecast model’s win probability for the favourite: Safe at 97% or higher, Likely at 85–97%, Lean at 65–85%, and Toss-up below 65% (checked against 2018–2024 results and kept: in held-out back-tests no seat rated above 95% lost; the evidence for the Lean and Toss-up bands is thin, with only a handful of close seats). Races with a single candidate are Uncontested. Where the model has no forecast, we use the absolute 2024 presidential margin in the district instead: 20 points or more is Safe, 10–20 Likely, 5–10 Lean and under 5 a Toss-up. Hovering a rating shows which source was used. The rating is fixed before votes are counted and does not change on election night.</p>

        <h2>Estimating how much vote is left</h2>
        <p>Utah votes almost entirely by mail, and counties report in batches over about two weeks. A precinct “reporting” therefore says little about how much of the vote is in. Instead we estimate the share of the <em>expected</em> final vote that has been counted.</p>
        <p>A Bayesian model predicts each county’s final number of ballots from its registration, past turnout and the ballots already counted, and simulates thousands of plausible outcomes. The percent shown is the median; the range is a 90% interval from the simulations. Statewide totals are the sum across simulated counties, so they are more certain than any single county. Estimates are least reliable early on. We checked the model against archived Utah results from 2016 to 2022: counting was slower than most people expect, with only about 70% of the final vote in a day after the polls closed and most of the rest arriving over the following week. Small counties finish on election night while the largest lag. Until about 36 hours after the polls close (or while the 90% range is wider than 25 points) the site therefore shows the share counted as a rounded range, such as “about 55–80%”, instead of a single number.</p>
        <p>The model is a guide, not a call. Late-arriving ballots can differ in partisanship from those counted first, and the site does not project winners.</p>
        <h2>Winners and “leading”</h2>
        <p>We do not make race calls. Winners are marked automatically once results are official: when the Lieutenant Governor’s office reports the election results as final, the top vote-getter (the top candidates, where several seats are open) is marked the winner, and a measure or judicial retention is decided by whether it clears its threshold (more than 50% yes). Until then, candidates are shown as leading. The national page shows pre-election context only (ratings and polls), not results.</p>
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
        <h2>Our pre-election forecast: chance of winning</h2>
        <p>Before votes were counted we published a chance of winning and a projected margin for each U.S. House race and legislative contest. That forecast is frozen as of Election Day and is not updated with results. We do not publish live win probabilities or projected margins during the count.</p>
        <ul>
          <li><b>The estimate</b> blends the poll average with a fundamentals baseline: 2024 presidential results re-assigned to the 2026 precincts, nudged by how far the national generic ballot has moved since 2024 (damped by half for Utah). Legislative contests have no polls, so they use the baseline, adjusted using 2018–2024 results: the Democratic share in the baseline runs high where a Republican is the incumbent, slightly low where a Democrat is, and non-Democratic challengers (unaffiliated, Forward, Libertarian, Constitution) get less than the Democratic baseline. Amendments have no public polling, so before votes arrive we show no forecast. U.S. House races assume about 5% to 7% of votes go to minor candidates, based on 2016–2024 results.</li>
          <li><b>Probabilities</b> are never shown above “&gt;99%” or below “&lt;1%”.</li>
        </ul>

        <p className="muted">Results are unofficial until certified by the state.</p>
      </article>
    </div>
  )
}

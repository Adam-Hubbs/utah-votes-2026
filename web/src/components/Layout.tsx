import { Link, NavLink } from 'react-router-dom'
import type { ReactNode } from 'react'
import { useSite } from '../data/site'
import { flags } from '../data/base'
import { Countdown } from './LastUpdated'
import { fmtDayYear } from '../lib/format'
import { NationalTicker } from '../national/NationalTicker'

const NAV = [
  { to: '/', label: 'Overview', end: true },
  { to: '/results', label: 'Results' },
  { to: '/forecasts', label: 'Forecasts' },
  { to: '/race/us-house-1', label: 'Races', match: '/race' },
  { to: '/state', label: 'State races' },
  { to: '/polls', label: 'Polls' },
  { to: '/history', label: 'History' },
  { to: '/demographics', label: 'Demographics' },
  { to: '/national', label: 'National' },
  { to: '/methodology', label: 'Methodology' },
]

export function LiveBanner() {
  const { mode, config } = useSite()
  if (mode === 'live') {
    return (
      <div className="banner banner-live" role="status">
        <div className="wrap">
          <span className="live-dot" aria-hidden /> <b>LIVE</b>
          <span>Election night results are updating automatically.{flags.sim ? ' This is a simulation.' : ''}</span>
        </div>
      </div>
    )
  }
  if (mode === 'pre') {
    return (
      <div className="banner" role="status">
        <div className="wrap">
          <span>Election Day is {fmtDayYear(config.election_date)}.</span>
          <span>Polls close in <Countdown target={config.polls_close_utc} /></span>
        </div>
      </div>
    )
  }
  return (
    <div className="banner" role="status"><div className="wrap"><span>Final results. Counting is complete.</span></div></div>
  )
}

export function Layout({ children }: { children: ReactNode }) {
  return (
    <>
      <a href="#main" className="skip-link">Skip to content</a>
      <LiveBanner />
      <header className="site-header">
        <div className="wrap header-inner">
          <Link to="/" className="brand" aria-label="Utah Votes 2026 home">
            <span className="brand-mark" aria-hidden>
              <svg viewBox="0 0 32 32" width="26" height="26"><rect width="32" height="32" rx="6" fill="#121212" /><path d="M9 8h6v9a2 2 0 0 0 4 0V8h4v9a6 6 0 0 1-12 0z" fill="#fff" /></svg>
            </span>
            <span className="brand-name">Utah Votes <span>2026</span></span>
          </Link>
          <nav className="nav" aria-label="Primary">
            {NAV.map((n) => (
              <NavLink key={n.to} to={n.to} end={n.end} className={({ isActive }) => (isActive || (n.match && window.location.hash.includes(n.match)) ? 'active' : '')}>
                {n.label}
              </NavLink>
            ))}
          </nav>
        </div>
      </header>
      <NationalTicker />
      <main id="main" className="wrap main">{children}</main>
      <footer className="site-footer">
        <div className="wrap">
          <div className="footer-cols">
            <div>
              <div className="brand-name small">Utah Votes <span>2026</span></div>
              <p>Election-night results, our forecast, race ratings and poll averages for Utah. Independent and non-partisan.</p>
            </div>
            <div>
              <h4>Data</h4>
              <p>Results: Utah Lieutenant Governor / electionresults.utah.gov. Polls: The New York Times. Demographics: U.S. Census Bureau ACS. Boundaries: UGRC.</p>
            </div>
            <div>
              <h4>Note</h4>
              <p>Results are unofficial until certified. Utah counts mail ballots for about two weeks. <Link to="/methodology">How we estimate what is left to count</Link>.</p>
            </div>
          </div>
          {flags.mock && <p className="mock-flag">Showing mock data (?mock=1).</p>}
        </div>
      </footer>
    </>
  )
}

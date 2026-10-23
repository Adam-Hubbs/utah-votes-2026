import { fmtCountdown, timeAgo } from '../lib/format'
import { useSite } from '../data/site'

export function LastUpdated({ iso, showRefresh = true }: { iso?: string | null; showRefresh?: boolean }) {
  const { mode, now, nextRefreshMs, paused, setPaused, refreshNow } = useSite()
  if (!iso) return null
  const secs = Math.ceil(nextRefreshMs / 1000)
  const next = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`
  return (
    <div className="last-updated" aria-live="off">
      <span>Updated {timeAgo(iso, now)}</span>
      {showRefresh && mode === 'live' && (
        <>
          <span className="sep">·</span>
          <span>{paused ? 'auto-refresh paused' : `next update in ${next}`}</span>
          <button type="button" className="link-btn" onClick={() => setPaused(!paused)} aria-pressed={paused}>
            {paused ? 'Resume' : 'Pause'}
          </button>
          <button type="button" className="link-btn" onClick={refreshNow}>Refresh</button>
        </>
      )}
    </div>
  )
}

export function Countdown({ target }: { target: string }) {
  const { now } = useSite()
  const ms = new Date(target).getTime() - now
  if (ms <= 0) return <span>Polls are closed</span>
  return <span className="countdown">{fmtCountdown(ms)}</span>
}

import { fmtPct } from '../lib/format'

interface Props {
  pct: number
  lo?: number
  hi?: number
  label?: string
  size?: 'sm' | 'md'
  showText?: boolean
}

/** Progress bar for "estimated share of expected vote counted" with an uncertainty band. */
export function ReportingMeter({ pct, lo, hi, label = 'Est. expected vote counted', size = 'md', showText = true }: Props) {
  const hasBand = lo != null && hi != null && hi > lo
  const text = hasBand && size === 'md' ? `${fmtPct(pct, 0)} (${fmtPct(lo, 0)}–${fmtPct(hi, 0)})` : fmtPct(pct, 0)
  return (
    <div className={`meter meter-${size}`}>
      <div className="meter-track" role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(pct * 100)}>
        {hasBand && <div className="meter-band" style={{ left: `${lo * 100}%`, width: `${(hi - lo) * 100}%` }} />}
        <div className="meter-fill" style={{ width: `${Math.min(100, pct * 100)}%` }} />
      </div>
      {showText && <span className="meter-text">{text}</span>}
    </div>
  )
}

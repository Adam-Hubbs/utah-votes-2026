import { useState } from 'react'
import { fmtPct } from '../lib/format'
import { roughRange, useIsRough } from '../lib/reporting'
import { TooltipHeader, TooltipNote } from './Tooltip'

interface Props {
  pct: number
  lo?: number
  hi?: number
  label?: string
  size?: 'sm' | 'md'
  showText?: boolean
}

/** Why early estimates are wide; shown on hover or keyboard focus of the "?" next to any rough estimate. */
export function RoughTip() {
  const [open, setOpen] = useState(false)
  return (
    <span className="rough-tip" onMouseEnter={() => setOpen(true)} onMouseLeave={() => setOpen(false)}>
      <button type="button" className="rough-btn" aria-label="Why is this a range?" aria-expanded={open} onFocus={() => setOpen(true)} onBlur={() => setOpen(false)}>?</button>
      {open && (
        <span className="tooltip rough-pop" role="tooltip">
          <TooltipHeader title="Rough estimate" subtitle="early counts" />
          <TooltipNote>Utah counts ballots for about two weeks. In 2018, 2020 and 2022 only about 70% of the final vote was counted a day after the polls closed, and the share varies a lot by county. Until more is counted we cannot tell slow counting from high turnout, so the estimate is shown as a range.</TooltipNote>
        </span>
      )}
    </span>
  )
}

/** Text for an "estimated share of expected vote counted": a rounded range while the estimate is rough, a point once it is not. */
export function PctExpectedText({ pct, lo, hi, prefix = '', bare = false }: { pct: number; lo?: number; hi?: number; prefix?: string; bare?: boolean }) {
  const rough = useIsRough(lo, hi)
  if (rough && lo != null && hi != null) return <>{bare ? '' : 'About '}{roughRange(lo, hi)}<RoughTip /></>
  return <>{prefix}{prefix ? ' ' : ''}{fmtPct(pct, 0)}</>
}

/** Progress bar for "estimated share of expected vote counted" with an uncertainty band. */
export function ReportingMeter({ pct, lo, hi, label = 'Est. expected vote counted', size = 'md', showText = true }: Props) {
  const hasBand = lo != null && hi != null && hi > lo
  const rough = useIsRough(lo, hi)
  const text = rough && hasBand ? `~${roughRange(lo, hi)}` : hasBand && size === 'md' ? `${fmtPct(pct, 0)} (${fmtPct(lo, 0)}–${fmtPct(hi, 0)})` : fmtPct(pct, 0)
  return (
    <div className={`meter meter-${size}${rough ? ' meter-rough' : ''}`}>
      <div className="meter-track" role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(pct * 100)} aria-valuetext={rough && hasBand ? `about ${roughRange(lo, hi)}` : undefined}>
        {hasBand && <div className="meter-band" style={{ left: `${lo * 100}%`, width: `${(hi - lo) * 100}%` }} />}
        {!rough && <div className="meter-fill" style={{ width: `${Math.min(100, pct * 100)}%` }} />}
        {rough && hasBand && <div className="meter-fill" style={{ width: `${Math.min(100, lo * 100)}%` }} />}
      </div>
      {showText && <span className="meter-text">{text}</span>}
    </div>
  )
}

import { fmtInt, fmtPct } from '../lib/format'
import { useLayoutEffect, useRef, useState, type ReactNode } from 'react'

interface Props {
  x: number
  y: number
  bounds: { width: number; height: number }
  children: ReactNode
}

/** Positioned inside a `position: relative` container; flips to stay within bounds. */
export function Tooltip({ x, y, bounds, children }: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const [size, setSize] = useState({ w: 200, h: 80 })
  useLayoutEffect(() => {
    const r = ref.current?.getBoundingClientRect()
    if (r) setSize({ w: r.width, h: r.height })
  }, [children])
  const gap = 14
  const edge = 4
  let left = x + gap
  if (left + size.w > bounds.width - edge) left = x - gap - size.w
  left = Math.min(Math.max(edge, left), Math.max(edge, bounds.width - size.w - edge))
  let top = y - size.h - gap
  if (top < edge) top = y + gap
  top = Math.min(Math.max(edge, top), Math.max(edge, bounds.height - size.h - edge))
  return (
    <div ref={ref} className="tooltip" role="tooltip" style={{ left, top }}>
      {children}
    </div>
  )
}

export function TooltipHeader({ title, subtitle }: { title: ReactNode; subtitle?: ReactNode }) {
  return (
    <div className="tt-head">
      <span className="tt-title">{title}</span>
      {subtitle != null && <span className="tt-sub">{subtitle}</span>}
    </div>
  )
}

interface RowProps {
  label: ReactNode
  value: ReactNode
  color?: string
  /** Muted trailing detail such as a vote count. */
  detail?: ReactNode
}

export function TooltipRow({ label, value, color, detail }: RowProps) {
  return (
    <div className={`tt-row${color ? ' has-dot' : ''}${detail != null ? ' has-detail' : ''}`}>
      {color && <i style={{ background: color }} />}
      <span className="tt-label">{label}</span>
      <b className="tt-value">{value}</b>
      {detail != null && <em>{detail}</em>}
    </div>
  )
}

export function TooltipNote({ children }: { children: ReactNode }) {
  return <div className="tt-muted">{children}</div>
}

export function TooltipFoot({ children }: { children: ReactNode }) {
  return <div className="tt-foot">{children}</div>
}

const MAJOR_CANDIDATES_SHOWN = 4

/** The leading candidates in a map unit, each with vote share and votes. Share and total always count every candidate, including those not listed. */
export function TooltipCandidates({ candidates, colors }: { candidates: { id: string; name: string; votes: number }[]; colors: Record<string, string> }) {
  const total = candidates.reduce((sum, c) => sum + c.votes, 0)
  const shown = [...candidates].sort((a, b) => b.votes - a.votes).slice(0, MAJOR_CANDIDATES_SHOWN)
  return (
    <>
      {shown.map((c) => (
        <TooltipRow key={c.id} color={colors[c.id] ?? '#999'} label={c.name} value={fmtPct(total ? c.votes / total : 0)} detail={fmtInt(c.votes)} />
      ))}
      <TooltipFoot><span>Total votes</span><b>{fmtInt(total)}</b></TooltipFoot>
    </>
  )
}

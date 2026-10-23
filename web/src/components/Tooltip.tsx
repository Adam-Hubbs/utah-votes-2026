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

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
  let left = x + gap
  if (left + size.w > bounds.width - 4) left = x - gap - size.w
  left = Math.max(4, left)
  let top = y - size.h - gap
  if (top < 4) top = Math.min(y + gap, bounds.height - size.h - 4)
  return (
    <div ref={ref} className="tooltip" role="tooltip" style={{ left, top }}>
      {children}
    </div>
  )
}

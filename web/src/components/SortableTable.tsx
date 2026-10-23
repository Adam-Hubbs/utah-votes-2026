import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'

export type MarginMode = 'closest' | 'left' | 'right'

/** Signed margin column: positive values are Republican (or For), negative are Democratic (or Against). */
export interface MarginSort<T> {
  value: (row: T) => number | null
  kind?: 'party' | 'measure'
}

const MARGIN_LABELS: Record<NonNullable<MarginSort<unknown>['kind']>, Record<MarginMode, string>> = {
  party: { closest: 'Closest', left: 'Most Democratic', right: 'Most Republican' },
  measure: { closest: 'Closest', left: 'Most Against', right: 'Most For' },
}

export interface Column<T> {
  key: string
  header: ReactNode
  render: (row: T) => ReactNode
  sort?: (row: T) => number | string | null
  marginSort?: MarginSort<T>
  align?: 'left' | 'right' | 'center'
  className?: string
  title?: string
}

interface Props<T> {
  rows: T[]
  columns: Column<T>[]
  rowKey: (row: T) => string
  initialSort?: { key: string; dir: 'asc' | 'desc' }
  onRowClick?: (row: T) => void
  activeKey?: string | null
  caption?: string
  maxHeight?: number
  empty?: ReactNode
}

export function SortableTable<T>({ rows, columns, rowKey, initialSort, onRowClick, activeKey, caption, maxHeight, empty }: Props<T>) {
  const [sort, setSort] = useState<{ key: string; dir: 'asc' | 'desc'; mode?: MarginMode } | null>(initialSort ?? null)
  const sorted = useMemo(() => {
    if (!sort) return rows
    const col = columns.find((c) => c.key === sort.key)
    let f = col?.sort
    let dir = sort.dir === 'asc' ? 1 : -1
    if (col?.marginSort) {
      const v = col.marginSort.value
      const mode = sort.mode ?? 'closest'
      f = mode === 'closest' ? (r: T) => { const x = v(r); return x == null ? null : Math.abs(x) } : v
      dir = mode === 'right' ? -1 : 1
    }
    if (!f) return rows
    return [...rows].sort((a, b) => {
      const va = f(a), vb = f(b)
      if (va == null && vb == null) return 0
      if (va == null) return 1
      if (vb == null) return -1
      return (typeof va === 'string' ? va.localeCompare(String(vb)) : (va as number) - (vb as number)) * dir
    })
  }, [rows, sort, columns])

  return (
    <div className="table-wrap" style={maxHeight ? { maxHeight } : undefined}>
      <table className="data-table">
        {caption && <caption className="sr-only">{caption}</caption>}
        <thead>
          <tr>
            {columns.map((c) => {
              const active = sort?.key === c.key
              if (c.marginSort) {
                return (
                  <th key={c.key} scope="col" className={`${c.align ?? 'left'} ${c.className ?? ''}`} title={c.title}
                    aria-sort={active ? (sort?.mode === 'right' ? 'descending' : 'ascending') : 'none'}>
                    <MarginHeader header={c.header} kind={c.marginSort.kind ?? 'party'} mode={active ? (sort?.mode ?? 'closest') : null}
                      onPick={(mode) => setSort({ key: c.key, dir: mode === 'right' ? 'desc' : 'asc', mode })} />
                  </th>
                )
              }
              return (
                <th key={c.key} scope="col" className={`${c.align ?? 'left'} ${c.className ?? ''}`} title={c.title}
                  aria-sort={active ? (sort?.dir === 'asc' ? 'ascending' : 'descending') : c.sort ? 'none' : undefined}>
                  {c.sort ? (
                    <button type="button" className="th-btn" onClick={() => setSort(active && sort ? { key: c.key, dir: sort.dir === 'asc' ? 'desc' : 'asc' } : { key: c.key, dir: rows.length > 0 && typeof c.sort?.(rows[0]) === 'string' ? 'asc' : 'desc' })}>
                      {c.header}
                      <span className={`sort-ind${active ? ' on' : ''}`} aria-hidden>{active ? (sort?.dir === 'asc' ? '▲' : '▼') : '↕'}</span>
                    </button>
                  ) : c.header}
                </th>
              )
            })}
          </tr>
        </thead>
        <tbody>
          {sorted.map((r) => {
            const k = rowKey(r)
            return (
              <tr key={k} className={`${activeKey === k ? 'active' : ''}${onRowClick ? ' clickable' : ''}`}
                onClick={onRowClick ? () => onRowClick(r) : undefined}
                tabIndex={onRowClick ? 0 : undefined}
                onKeyDown={onRowClick ? (e) => { if (e.key === 'Enter') onRowClick(r) } : undefined}>
                {columns.map((c) => <td key={c.key} className={`${c.align ?? 'left'} ${c.className ?? ''}`}>{c.render(r)}</td>)}
              </tr>
            )
          })}
          {!sorted.length && <tr><td colSpan={columns.length} className="empty-cell">{empty ?? 'No rows.'}</td></tr>}
        </tbody>
      </table>
    </div>
  )
}

function MarginHeader({ header, kind, mode, onPick }: { header: ReactNode; kind: 'party' | 'measure'; mode: MarginMode | null; onPick: (m: MarginMode) => void }) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLSpanElement>(null)
  const labels = MARGIN_LABELS[kind]
  useEffect(() => {
    if (!open) return
    const close = (e: Event) => { if (!ref.current?.contains(e.target as Node)) setOpen(false) }
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('pointerdown', close)
    document.addEventListener('keydown', esc)
    return () => { document.removeEventListener('pointerdown', close); document.removeEventListener('keydown', esc) }
  }, [open])
  return (
    <span className="margin-head" ref={ref}>
      <button type="button" className="th-btn" aria-haspopup="menu" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
        {header}
        <span className={`sort-ind${mode ? ' on' : ''}`} aria-hidden>{mode ? '▾' : '↕'}</span>
      </button>
      {mode && <span className="margin-mode">{labels[mode]}</span>}
      {open && (
        <div className="margin-menu" role="menu">
          {(['closest', 'left', 'right'] as const).map((m) => (
            <button key={m} type="button" role="menuitemradio" aria-checked={mode === m} className={mode === m ? 'on' : ''} onClick={() => { onPick(m); setOpen(false) }}>
              <span className="check-mark" aria-hidden>{mode === m ? '✓' : ''}</span>{labels[m]}
            </button>
          ))}
        </div>
      )}
    </span>
  )
}

import { useMemo, useState, type ReactNode } from 'react'

export interface Column<T> {
  key: string
  header: ReactNode
  render: (row: T) => ReactNode
  sort?: (row: T) => number | string | null
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
  const [sort, setSort] = useState(initialSort ?? null)
  const sorted = useMemo(() => {
    if (!sort) return rows
    const col = columns.find((c) => c.key === sort.key)
    if (!col?.sort) return rows
    const f = col.sort
    const dir = sort.dir === 'asc' ? 1 : -1
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

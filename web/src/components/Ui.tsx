import type { ReactNode } from 'react'
import type { Loaded } from '../data/hooks'

export function Unavailable({ what = 'Data' }: { what?: string }) {
  return <div className="unavailable">{what} not yet available.</div>
}

export function Loading() {
  return <div className="loading" aria-busy="true"><span className="skeleton" style={{ width: '40%' }} /><span className="skeleton" style={{ width: '70%' }} /><span className="skeleton" style={{ width: '55%' }} /></div>
}

/** Renders children once data is loaded; otherwise a loading or "not available" state. */
export function Gate<T>({ data, what, children }: { data: Loaded<T>; what?: string; children: (d: T) => ReactNode }) {
  if (data === undefined) return <Loading />
  if (data === null) return <Unavailable what={what} />
  return <>{children(data)}</>
}

export function Section({ title, dek, id, aside, children, className = '' }: { title?: ReactNode; dek?: ReactNode; id?: string; aside?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`section ${className}`} id={id} aria-labelledby={id ? `${id}-h` : undefined}>
      {(title || aside) && (
        <header className="section-head">
          <div>
            {title && <h2 id={id ? `${id}-h` : undefined} className="section-title">{title}</h2>}
            {dek && <p className="section-dek">{dek}</p>}
          </div>
          {aside && <div className="section-aside">{aside}</div>}
        </header>
      )}
      {children}
    </section>
  )
}

export function Segmented<T extends string>({ options, value, onChange, label }: { options: { value: T; label: string; disabled?: boolean }[]; value: T; onChange: (v: T) => void; label: string }) {
  return (
    <div className="segmented" role="group" aria-label={label}>
      {options.map((o) => (
        <button key={o.value} type="button" disabled={o.disabled} className={o.value === value ? 'on' : ''} aria-pressed={o.value === value} onClick={() => onChange(o.value)}>
          {o.label}
        </button>
      ))}
    </div>
  )
}

export function Select({ value, onChange, children, label, id }: { value: string; onChange: (v: string) => void; children: ReactNode; label: string; id?: string }) {
  return (
    <label className="select">
      <span className="select-label">{label}</span>
      <select id={id} value={value} onChange={(e) => onChange(e.target.value)}>{children}</select>
    </label>
  )
}

export function Stat({ label, value, sub }: { label: string; value: ReactNode; sub?: ReactNode }) {
  return (
    <div className="stat">
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      {sub && <div className="stat-sub">{sub}</div>}
    </div>
  )
}

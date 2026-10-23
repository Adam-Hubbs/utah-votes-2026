import type { DemographicUnit } from '../types/data'
import { DEMO_VARS, valueOf } from '../lib/demo'

export function DemoCompare({ unit, state, unitLabel, color = 'var(--ink)' }: { unit: DemographicUnit; state: DemographicUnit | undefined; unitLabel: string; color?: string }) {
  const vars = DEMO_VARS.filter((v) => v.key !== 'population')
  return (
    <div className="demo-compare" role="table" aria-label={`${unitLabel} compared with Utah`}>
      <div className="dc-head" role="row"><span role="columnheader" /><span role="columnheader">{unitLabel}</span><span role="columnheader">Utah</span></div>
      {vars.map((v) => {
        const a = valueOf(unit, v.key)
        const b = state ? valueOf(state, v.key) : null
        if (a == null) return null
        const scaleMax = v.pct ? Math.max(a, b ?? 0, 0.5) * (a > 0.5 || (b ?? 0) > 0.5 ? 1 : 1) : Math.max(a, b ?? 0) * 1.1
        return (
          <div className="dc-row" role="row" key={v.key}>
            <span className="dc-label" role="rowheader">{v.label}</span>
            <span className="dc-val" role="cell">
              <b>{v.fmt(a)}</b>
              <span className="dc-track"><i style={{ width: `${(a / scaleMax) * 100}%`, background: color }} />{b != null && <u style={{ left: `${(b / scaleMax) * 100}%` }} title={`Utah ${v.fmt(b)}`} />}</span>
            </span>
            <span className="dc-state" role="cell">{b != null ? v.fmt(b) : '–'}</span>
          </div>
        )
      })}
    </div>
  )
}

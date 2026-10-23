import type { DemographicKey, DemographicUnit } from '../types/data'
import { fmtDollar, fmtInt, fmtPct } from './format'

export interface DemoVar {
  key: DemographicKey
  label: string
  fmt: (v: number) => string
  /** Axis hint: proportions are 0-1. */
  pct: boolean
}

const pct = (v: number) => fmtPct(v, 1)

export const DEMO_VARS: DemoVar[] = [
  { key: 'population', label: 'Population', fmt: fmtInt, pct: false },
  { key: 'median_age', label: 'Median age', fmt: (v) => v.toFixed(1), pct: false },
  { key: 'pct_white_nh', label: 'White, non-Hispanic', fmt: pct, pct: true },
  { key: 'pct_hispanic', label: 'Hispanic or Latino', fmt: pct, pct: true },
  { key: 'pct_asian', label: 'Asian', fmt: pct, pct: true },
  { key: 'pct_black', label: 'Black', fmt: pct, pct: true },
  { key: 'pct_bachelors_plus', label: 'Bachelor’s degree or higher', fmt: pct, pct: true },
  { key: 'median_hh_income', label: 'Median household income', fmt: fmtDollar, pct: false },
  { key: 'pct_under_18', label: 'Under age 18', fmt: pct, pct: true },
  { key: 'pct_65_plus', label: 'Age 65 and older', fmt: pct, pct: true },
  { key: 'pct_urban', label: 'Urban population', fmt: pct, pct: true },
]

export const demoVar = (key: DemographicKey): DemoVar => DEMO_VARS.find((v) => v.key === key) ?? DEMO_VARS[0]

export const valueOf = (u: DemographicUnit, key: DemographicKey): number | null => {
  const v = u[key]
  return typeof v === 'number' ? v : null
}

import { timeFormat } from 'd3-time-format'

export const fmtInt = (n: number | null | undefined): string =>
  n == null || Number.isNaN(n) ? '–' : Math.round(n).toLocaleString('en-US')

export const fmtCompact = (n: number): string => {
  if (n >= 1e6) return `${(n / 1e6).toFixed(n >= 1e7 ? 0 : 2).replace(/\.?0+$/, '')}M`
  if (n >= 1e4) return `${Math.round(n / 1e3)}K`
  if (n >= 1e3) return `${(n / 1e3).toFixed(1).replace(/\.0$/, '')}K`
  return String(Math.round(n))
}

/** Proportion (0-1) as a percentage string. */
export const fmtPct = (p: number | null | undefined, digits = 1): string =>
  p == null || Number.isNaN(p) ? '–' : `${(p * 100).toFixed(digits)}%`

/** Value already on a 0-100 scale. */
export const fmtPts = (v: number | null | undefined, digits = 0): string =>
  v == null || Number.isNaN(v) ? '–' : `${v.toFixed(digits)}%`

export const fmtDollar = (n: number | null | undefined): string =>
  n == null ? '–' : `$${Math.round(n).toLocaleString('en-US')}`

/** Margin as proportion; positive = Republican lead. */
export const fmtMargin = (m: number | null | undefined, digits = 1): string => {
  if (m == null || Number.isNaN(m)) return '–'
  const v = Math.abs(m * 100)
  if (v < 0.05) return 'Even'
  return `${m > 0 ? 'R' : 'D'}+${v.toFixed(digits)}`
}

const dayFmt = timeFormat('%b %-d')
const dayYearFmt = timeFormat('%b %-d, %Y')
const timeFmt = timeFormat('%-I:%M %p')

export const parseDate = (s: string): Date => {
  // Date-only strings are parsed as local noon to avoid off-by-one display.
  return /^\d{4}-\d{2}-\d{2}$/.test(s) ? new Date(`${s}T12:00:00`) : new Date(s)
}
export const fmtDay = (s: string | Date): string => dayFmt(typeof s === 'string' ? parseDate(s) : s)
export const fmtDayYear = (s: string | Date): string => dayYearFmt(typeof s === 'string' ? parseDate(s) : s)
export const fmtTime = (s: string | Date): string => timeFmt(typeof s === 'string' ? parseDate(s) : s)

export const fmtDateRange = (a: string, b: string): string =>
  a === b ? fmtDay(a) : `${fmtDay(a)}–${parseDate(a).getMonth() === parseDate(b).getMonth() ? parseDate(b).getDate() : fmtDay(b)}`

export const timeAgo = (iso: string, now = Date.now()): string => {
  const s = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000))
  if (s < 45) return 'just now'
  const m = Math.round(s / 60)
  if (m < 60) return `${m} min ago`
  const h = Math.round(m / 60)
  if (h < 36) return `${h} hr ago`
  return `${Math.round(h / 24)} days ago`
}

export const fmtCountdown = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000))
  const d = Math.floor(s / 86400)
  const h = Math.floor((s % 86400) / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  return d > 0 ? `${d}d ${h}h ${m}m` : `${h}h ${String(m).padStart(2, '0')}m ${String(sec).padStart(2, '0')}s`
}

export const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v))

export const ordinal = (n: number): string => {
  const s = ['th', 'st', 'nd', 'rd']
  const v = n % 100
  return n + (s[(v - 20) % 10] ?? s[v] ?? s[0])
}

const mtTime = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'America/Denver' })
const mtDay = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', timeZone: 'America/Denver' })
/** Election-night clock times are always shown in Utah time. */
export const fmtMT = (d: Date | string): string => mtTime.format(typeof d === 'string' ? new Date(d) : d)
export const fmtMTFull = (d: Date | string): string => `${mtDay.format(typeof d === 'string' ? new Date(d) : d)} MT`

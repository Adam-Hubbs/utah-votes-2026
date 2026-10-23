// Data-source switching: `?mock=1` (or VITE_DATA_BASE=mock/data) serves mock data;
// `?sim=1` swaps the 2026 general election for the simulated election night.
export interface Flags {
  mock: boolean
  sim: boolean
  mode: 'pre' | 'live' | 'final' | null
}

const KEY = 'utah-votes-flags'

function readParams(): URLSearchParams {
  const merged = new URLSearchParams(window.location.search)
  const hashQuery = window.location.hash.split('?')[1]
  if (hashQuery) new URLSearchParams(hashQuery).forEach((v, k) => merged.set(k, v))
  return merged
}

function load(): Flags {
  let stored: Partial<Flags> = {}
  try {
    stored = JSON.parse(sessionStorage.getItem(KEY) ?? '{}') as Partial<Flags>
  } catch {
    stored = {}
  }
  const p = readParams()
  const pick = (name: string, prev: boolean | undefined): boolean => (p.has(name) ? p.get(name) !== '0' : (prev ?? false))
  const modeParam = p.get('mode')
  const flags: Flags = {
    mock: pick('mock', stored.mock),
    sim: pick('sim', stored.sim),
    mode: modeParam === 'pre' || modeParam === 'live' || modeParam === 'final' ? modeParam : modeParam === '0' ? null : (stored.mode ?? null),
  }
  try {
    sessionStorage.setItem(KEY, JSON.stringify(flags))
  } catch {
    /* storage may be unavailable; flags still work for this page load */
  }
  return flags
}

export const flags: Flags = load()

export const dataBase = (): string => {
  const env = import.meta.env.VITE_DATA_BASE as string | undefined
  const base = flags.mock ? 'mock/data' : (env ?? 'data')
  return base.replace(/\/$/, '')
}

export const resolveElectionId = (id: string): string => (flags.sim && id === '2026-general' ? '2026-sim' : id)

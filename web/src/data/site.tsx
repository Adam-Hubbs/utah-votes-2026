import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { LiveMode, SiteConfig } from '../types/data'
import { getJson } from './api'
import { flags, resolveElectionId } from './base'

export const REFRESH_MS = 60_000

const FALLBACK: SiteConfig = {
  current_election: '2026-general', election_date: '2026-11-03', polls_close_utc: '2026-11-04T03:00:00Z', live_mode: 'pre',
  featured_contests: ['us-house-1', 'us-house-2', 'us-house-3', 'us-house-4', 'amendment-a', 'amendment-b'],
}

interface SiteState {
  config: SiteConfig
  configLoaded: boolean
  mode: LiveMode
  currentElection: string // canonical id, e.g. 2026-general
  currentElectionData: string // id actually fetched (2026-sim with ?sim=1)
  tick: number
  now: number
  paused: boolean
  setPaused: (p: boolean) => void
  nextRefreshMs: number
  refreshNow: () => void
}

const Ctx = createContext<SiteState | null>(null)

export function SiteProvider({ children }: { children: ReactNode }) {
  const [config, setConfig] = useState<SiteConfig>(FALLBACK)
  const [configLoaded, setConfigLoaded] = useState(false)
  const [tick, setTick] = useState(0)
  const [now, setNow] = useState(Date.now())
  const [paused, setPaused] = useState(false)
  const lastTick = useRef(Date.now())

  const mode: LiveMode = flags.sim ? (flags.mode ?? 'live') : (flags.mode ?? config.live_mode)

  useEffect(() => {
    let alive = true
    void getJson<SiteConfig>('config.json', { live: true }).then((c) => {
      if (!alive) return
      if (c) setConfig({ ...FALLBACK, ...c })
      setConfigLoaded(true)
    })
    return () => { alive = false }
  }, [tick])

  useEffect(() => {
    const id = window.setInterval(() => {
      const t = Date.now()
      setNow(t)
      if (mode === 'live' && !paused && t - lastTick.current >= REFRESH_MS) {
        lastTick.current = t
        setTick((n) => n + 1)
      }
    }, 1000)
    return () => window.clearInterval(id)
  }, [mode, paused])

  const refreshNow = useCallback(() => {
    lastTick.current = Date.now()
    setTick((n) => n + 1)
  }, [])

  const value = useMemo<SiteState>(() => ({
    config, configLoaded, mode, currentElection: config.current_election, currentElectionData: resolveElectionId(config.current_election),
    tick, now, paused, setPaused, nextRefreshMs: Math.max(0, REFRESH_MS - (now - lastTick.current)), refreshNow,
  }), [config, configLoaded, mode, tick, now, paused, refreshNow])

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useSite(): SiteState {
  const v = useContext(Ctx)
  if (!v) throw new Error('SiteProvider missing')
  return v
}

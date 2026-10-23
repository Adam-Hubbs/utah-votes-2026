import { useEffect, useState } from 'react'
import { getJson } from '../data/api'
import { flags } from '../data/base'
import { useSite } from '../data/site'
import type { Loaded } from '../data/hooks'
import type { ContestAverage, Poll } from '../types/data'
import type { HouseFile, SenateFile } from './types'

function useNationalJson<T>(file: string): Loaded<T> {
  const { tick, mode } = useSite()
  const live = mode === 'live'
  const rel = `national/${flags.sim ? 'sim/' : ''}${file}`
  const dep = live ? tick : 0
  const [state, setState] = useState<{ rel: string; data: Loaded<T> }>({ rel, data: undefined })
  useEffect(() => {
    let alive = true
    void getJson<T>(rel, { live }).then((d) => {
      if (!alive) return
      setState((prev) => ({ rel, data: d ?? (prev.rel === rel && live ? prev.data : null) }))
    })
    return () => { alive = false }
  }, [rel, live, dep])
  return state.rel === rel ? state.data : undefined
}

export const useSenate = () => useNationalJson<SenateFile>('senate.json')
export const useHouse = () => useNationalJson<HouseFile>('house.json')
export const useSenatePolls = () => useNationalJson<{ polls: Poll[]; averages: Record<string, ContestAverage> }>('senate_polls.json')

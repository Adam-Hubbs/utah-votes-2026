import { useEffect, useState } from 'react'
import { getJson } from './api'
import type { Loaded } from './hooks'
import type { JudgesFile, LegislatureFile } from '../types/legislature'

function useStatic<T>(rel: string): Loaded<T> {
  const [data, setData] = useState<Loaded<T>>(undefined)
  useEffect(() => {
    let alive = true
    void getJson<T>(rel).then((d) => alive && setData(d))
    return () => { alive = false }
  }, [rel])
  return data
}

export const useLegislature = () => useStatic<LegislatureFile>('legislature.json')
export const useJudges = () => useStatic<JudgesFile>('judges.json')

import { useEffect, useState } from 'react'
import { feature } from 'topojson-client'
import type { Feature, FeatureCollection, Geometry } from 'geojson'
import type { Topology } from 'topojson-specification'
import { getJson } from './api'
import { resolveElectionId } from './base'
import { useSite } from './site'
import type {
  Baselines, CandidatesFile, MeasuresFile, ContestResults, CountyTrends, Demographics, ElectionModel, ElectionSummary, ElectionTimeline,
  NationalPolls, PlaceLabel, Poll, PollAverages, Ratings, ResultsIndex,
} from '../types/data'

/** undefined = loading, null = unavailable, otherwise the data. */
export type Loaded<T> = T | null | undefined

function useJson<T>(rel: string | null, live = false): Loaded<T> {
  const { tick } = useSite()
  const [state, setState] = useState<{ rel: string | null; data: Loaded<T> }>({ rel, data: undefined })
  const dep = live ? tick : 0
  useEffect(() => {
    if (!rel) return
    let alive = true
    void getJson<T>(rel, { live }).then((d) => {
      if (!alive) return
      // Keep the last good payload when a live refresh fails transiently.
      setState((prev) => ({ rel, data: d ?? (prev.rel === rel && live ? prev.data : null) }))
    })
    return () => { alive = false }
  }, [rel, live, dep])
  if (!rel) return null
  return state.rel === rel ? state.data : undefined
}

const resultsPath = (election: string, file: string) => `results/${resolveElectionId(election)}/${file}`

export const useResultsIndex = () => useJson<ResultsIndex>('results/index.json')

/** Live-refreshing only for the current election while it is in live mode (or the simulation). */
function useIsLive(election: string): boolean {
  const { mode, currentElection } = useSite()
  return mode === 'live' && election === currentElection
}

export const useSummary = (election: string | null) => {
  const live = useIsLive(election ?? '')
  return useJson<ElectionSummary>(election ? resultsPath(election, 'summary.json') : null, live)
}
export const useContestResults = (election: string | null, contest: string | null) => {
  const live = useIsLive(election ?? '')
  return useJson<ContestResults>(election && contest ? resultsPath(election, `contests/${contest}.json`) : null, live)
}
export const useModel = (election: string | null) => {
  const live = useIsLive(election ?? '')
  return useJson<ElectionModel>(election ? resultsPath(election, 'model.json') : null, live)
}
export const useTimeline = (election: string | null) => {
  const live = useIsLive(election ?? '')
  return useJson<ElectionTimeline>(election ? resultsPath(election, 'timeline.json') : null, live)
}

export const usePolls = () => useJson<Poll[]>('polls/polls.json')
export const useAverages = () => useJson<PollAverages>('polls/averages.json')
export const useNational = () => useJson<NationalPolls>('polls/national.json')
export const useRatings = () => useJson<Ratings>('ratings.json')
export const useCandidates = () => useJson<CandidatesFile>('candidates.json')
export const useDemographics = (kind: 'counties' | 'cd2026' | 'state') => useJson<Demographics>(`demographics/${kind}.json`)
export const useBaselines = (plan: 'cd2026' | 'cd2022') => useJson<Baselines>(`history/${plan}_baselines.json`)
export const useCountyTrends = () => useJson<CountyTrends>('history/county_trends.json')
export const useMeasures = () => useJson<MeasuresFile>('measures.json')
export const usePlaces = () => useJson<PlaceLabel[]>('geo/places.json')

export type Geo<P = Record<string, unknown>> = FeatureCollection<Geometry, P>
export type Feat<P = Record<string, unknown>> = Feature<Geometry, P>

const geoCache = new Map<string, Promise<Geo | null>>()

function loadGeo(file: string, object: string): Promise<Geo | null> {
  const key = `${file}:${object}`
  let p = geoCache.get(key)
  if (!p) {
    p = getJson<Topology>(`geo/${file}.topo.json`).then((t) => {
      const obj = t?.objects?.[object]
      if (!t || !obj) return null
      return feature(t, obj) as unknown as Geo
    })
    geoCache.set(key, p)
  }
  return p
}

const GEO_OBJECTS: Record<string, string> = {
  counties: 'counties', cd2026: 'districts', cd2022: 'districts', state_house: 'districts', state_senate: 'districts',
  precincts_2026: 'precincts', precincts_2024: 'precincts', precincts_2022: 'precincts', precincts_2020: 'precincts',
}

export function useGeo<P = Record<string, unknown>>(name: string | null | undefined): Loaded<Geo<P>> {
  const [state, setState] = useState<{ name: string | null | undefined; data: Loaded<Geo> }>({ name, data: undefined })
  useEffect(() => {
    if (!name) return
    let alive = true
    const obj = GEO_OBJECTS[name] ?? name.replace(/_\d{4}$/, '')
    void loadGeo(name, obj).then((d) => alive && setState({ name, data: d }))
    return () => { alive = false }
  }, [name])
  if (!name) return null
  return (state.name === name ? state.data : undefined) as Loaded<Geo<P>>
}

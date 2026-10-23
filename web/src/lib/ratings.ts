import type { Ratings } from '../types/data'
import { ratingIndex } from './colors'

export function consensus(r: Ratings | null | undefined, contestId: string): { label: string; index: number; n: number } | null {
  const row = r?.ratings?.[contestId]
  if (!r || !row) return null
  const idx = Object.values(row).map((l) => ratingIndex(l, r.scale)).filter((i) => i >= 0)
  if (!idx.length) return null
  const mean = idx.reduce((a, b) => a + b, 0) / idx.length
  const index = Math.round(mean)
  return { label: r.scale[index], index, n: idx.length }
}

import { dataBase } from './base'

const cache = new Map<string, Promise<unknown>>()
const LIVE_BUCKET_MS = 30_000

export interface FetchOpts {
  live?: boolean
}

/** Resolves to parsed JSON, or null when the file is missing/invalid. Never throws. */
export function getJson<T>(rel: string, opts: FetchOpts = {}): Promise<T | null> {
  let url = `${dataBase()}/${rel}`
  if (opts.live) url += `?t=${Math.floor(Date.now() / LIVE_BUCKET_MS) * LIVE_BUCKET_MS}`
  const hit = cache.get(url)
  if (hit) return hit as Promise<T | null>
  const p = fetch(url, opts.live ? { cache: 'no-store' } : undefined)
    .then(async (r) => {
      if (!r.ok) return null
      try {
        return (await r.json()) as T
      } catch {
        return null
      }
    })
    .catch(() => null)
  cache.set(url, p)
  // Failures must stay retryable (a file may appear later), so don't keep nulls for live files.
  if (opts.live) void p.then((v) => v === null && cache.delete(url))
  return p
}

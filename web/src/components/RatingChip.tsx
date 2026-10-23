import { RATING_FILL, RATING_TEXT, ratingIndex } from '../lib/colors'

const DEFAULT_SCALE = ['Solid D', 'Likely D', 'Lean D', 'Toss-up', 'Lean R', 'Likely R', 'Solid R']

export function RatingChip({ label, scale = DEFAULT_SCALE, compact = false }: { label: string | undefined | null; scale?: string[]; compact?: boolean }) {
  if (!label) return <span className="rating-chip rating-none">–</span>
  const i = ratingIndex(label, scale)
  const bg = i >= 0 ? RATING_FILL[Math.round((i * 6) / Math.max(1, scale.length - 1))] : '#ddd'
  const fg = i >= 0 ? RATING_TEXT[Math.round((i * 6) / Math.max(1, scale.length - 1))] : '#333'
  const text = scale[i] ?? label
  return (
    <span className={`rating-chip${compact ? ' compact' : ''}`} style={{ background: bg, color: fg }}>
      {text}
    </span>
  )
}

/** Seven-point strip with a marker for each rating source. */
export function RatingStrip({ ratings, scale = DEFAULT_SCALE, sources }: { ratings: Record<string, string>; scale?: string[]; sources: { id: string; name: string }[] }) {
  const marks = sources.map((s) => ({ s, i: ratingIndex(ratings[s.id], scale) })).filter((m) => m.i >= 0)
  return (
    <div className="rating-strip" role="img" aria-label={`Ratings: ${sources.map((s) => `${s.name} ${ratings[s.id] ?? 'none'}`).join(', ')}`}>
      <div className="rating-strip-bar">
        {scale.map((label, i) => (
          <div key={label} className="rating-strip-seg" style={{ background: RATING_FILL[Math.round((i * 6) / Math.max(1, scale.length - 1))] }}>
            <span style={{ color: RATING_TEXT[Math.round((i * 6) / Math.max(1, scale.length - 1))] }}>{label}</span>
            <div className="rating-strip-dots">
              {marks.filter((m) => m.i === i).map((m) => (
                <i key={m.s.id} title={`${m.s.name}: ${ratings[m.s.id]}`} className="dot" />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

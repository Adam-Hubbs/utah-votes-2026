import { RATING_FILL, RATING_TEXT } from '../../lib/colors'
import type { SeatRating } from '../../lib/competitiveness'

const OFFSET = { safe: 3, likely: 2, lean: 1 } as const

function colors(r: SeatRating): { bg: string; fg: string } {
  if (r.tier === 'uncontested') return { bg: 'var(--wash-2)', fg: 'var(--ink-3)' }
  if (r.tier === 'toss-up' || !r.party) return { bg: RATING_FILL[3], fg: RATING_TEXT[3] }
  const i = 3 + (r.party === 'REP' ? 1 : -1) * OFFSET[r.tier]
  return { bg: RATING_FILL[i], fg: RATING_TEXT[i] }
}

export function CompetitivenessChip({ rating }: { rating: SeatRating }) {
  const { bg, fg } = colors(rating)
  return (
    <span className="rating-chip compact" style={{ background: bg, color: fg }} title={`Pre-election rating. ${rating.detail}`}>
      {rating.label}
    </span>
  )
}

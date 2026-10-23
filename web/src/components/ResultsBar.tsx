import { candidateColors } from '../lib/parties'
import { fmtPct } from '../lib/format'

interface Item { candidate_id: string; name: string; party: string | null; pct: number }

/** Single stacked bar. Segments sorted by size; the 50% tick helps read two-way races. */
export function ResultsBar({ items, height = 10, showMid = true, muted = false }: { items: Item[]; height?: number; showMid?: boolean; muted?: boolean }) {
  const colors = candidateColors(items)
  const sorted = [...items].sort((a, b) => b.pct - a.pct)
  const total = sorted.reduce((s, i) => s + i.pct, 0)
  return (
    <div className={`results-bar${muted ? ' muted' : ''}`} style={{ height }} role="img"
      aria-label={sorted.map((i) => `${i.name} ${fmtPct(i.pct)}`).join(', ')}>
      {total === 0 && <div className="results-bar-empty" />}
      {sorted.map((i) => (
        <div key={i.candidate_id} className="results-bar-seg" style={{ width: `${(i.pct / (total || 1)) * 100}%`, background: colors[i.candidate_id] }} />
      ))}
      {showMid && <div className="results-bar-mid" />}
    </div>
  )
}

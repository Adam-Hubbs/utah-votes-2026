import { useRef, useState } from 'react'
import { Tooltip, TooltipHeader, TooltipNote, TooltipRow } from '../components/Tooltip'
import type { SenateRace } from './types'
import { INDEX_LABEL, indexFill, indexText, raceIndex, shortRating } from './lib'

// [row, col] on an 11-column grid; one tile per state so small eastern states stay legible.
const TILES: Record<string, [number, number]> = {
  AK: [0, 0], ME: [0, 10],
  VT: [1, 9], NH: [1, 10],
  WA: [2, 0], ID: [2, 1], MT: [2, 2], ND: [2, 3], MN: [2, 4], IL: [2, 5], WI: [2, 6], MI: [2, 7], NY: [2, 8], RI: [2, 9], MA: [2, 10],
  OR: [3, 0], NV: [3, 1], WY: [3, 2], SD: [3, 3], IA: [3, 4], IN: [3, 5], OH: [3, 6], PA: [3, 7], NJ: [3, 8], CT: [3, 9],
  CA: [4, 0], UT: [4, 1], CO: [4, 2], NE: [4, 3], MO: [4, 4], KY: [4, 5], WV: [4, 6], VA: [4, 7], MD: [4, 8], DE: [4, 9],
  AZ: [5, 1], NM: [5, 2], KS: [5, 3], AR: [5, 4], TN: [5, 5], NC: [5, 6], SC: [5, 7], DC: [5, 8],
  OK: [6, 3], LA: [6, 4], MS: [6, 5], AL: [6, 6], GA: [6, 7],
  HI: [7, 0], TX: [7, 3], FL: [7, 7],
}

interface Props {
  races: SenateRace[]
  selected: string | null
  onSelect: (state: string) => void
}

export function TileMap({ races, selected, onSelect }: Props) {
  const byState = new Map(races.map((r) => [r.state, r]))
  const ref = useRef<HTMLDivElement>(null)
  const [tip, setTip] = useState<{ race: SenateRace; x: number; y: number } | null>(null)
  const show = (race: SenateRace, el: HTMLElement) => {
    const box = ref.current?.getBoundingClientRect()
    const r = el.getBoundingClientRect()
    if (box) setTip({ race, x: r.left - box.left + r.width / 2, y: r.top - box.top + r.height / 2 })
  }
  const bounds = { width: ref.current?.clientWidth ?? 640, height: ref.current?.clientHeight ?? 400 }
  return (
    <div className="tile-map" ref={ref} role="group" aria-label="2026 U.S. Senate races by state" onMouseLeave={() => setTip(null)}>
      {Object.entries(TILES).map(([abbr, [row, col]]) => {
        const race = byState.get(abbr)
        const style = { gridRow: row + 1, gridColumn: col + 1 }
        if (!race) {
          return <div key={abbr} className={`tile tile-none${abbr === 'UT' ? ' tile-utah' : ''}`} style={style} aria-hidden><span className="tile-abbr">{abbr}</span>{abbr === 'UT' && <span className="tile-sub">No race</span>}</div>
        }
        const idx = raceIndex(race)
        const sub = shortRating(race.ratings.cook).replace('Solid ', '').replace('Toss-up', 'Toss')
        return (
          <button key={abbr} type="button" className={`tile${selected === abbr ? ' sel' : ''}`} style={{ ...style, background: indexFill(idx), color: indexText(idx) }}
            onClick={() => onSelect(abbr)} aria-pressed={selected === abbr}
            aria-label={`${race.state_name}${race.special ? ' special election' : ''}: ${INDEX_LABEL[idx]}`}
            onMouseEnter={(e) => show(race, e.currentTarget)} onFocus={(e) => show(race, e.currentTarget)} onBlur={() => setTip(null)}>
            <span className="tile-abbr">{abbr}</span>
            <span className="tile-sub">{sub}</span>
            {race.special && <span className="tile-flag">S</span>}
          </button>
        )
      })}
      {tip && (
        <Tooltip x={tip.x} y={tip.y} bounds={bounds}>
          <TooltipHeader title={tip.race.state_name} subtitle={tip.race.special ? 'Special election' : undefined} />
          <TooltipRow label="Consensus" value={INDEX_LABEL[raceIndex(tip.race)]} />
          {(['cook', 'sabato', 'inside'] as const).map((k) => tip.race.ratings[k] && (
            <TooltipRow key={k} label={{ cook: 'Cook', sabato: 'Sabato', inside: 'Inside Elections' }[k]} value={shortRating(tip.race.ratings[k])} />
          ))}
          <TooltipNote>Click for details</TooltipNote>
        </Tooltip>
      )}
    </div>
  )
}

export function MapLegend() {
  return (
    <div className="legend tile-legend">
      <div className="legend-title">Consensus rating (Cook, Sabato and Inside Elections), not results</div>
      <div className="rating-legend-bar">
        {[0, 1, 2, 3, 4, 5, 6].map((i) => <i key={i} style={{ background: indexFill(i) }} title={INDEX_LABEL[i]} />)}
      </div>
      <div className="legend-ends"><span>Solid D</span><span>Toss-up</span><span>Solid R</span></div>
      <div className="legend-calls"><span><b className="tile-flag-inline">S</b> special election</span><span className="muted">Grey: no Senate race in 2026</span></div>
    </div>
  )
}

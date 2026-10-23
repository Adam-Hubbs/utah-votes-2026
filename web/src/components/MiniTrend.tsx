import { scaleLinear } from 'd3-scale'
import { line } from 'd3-shape'

export function MiniTrend({ values, years, yMin, yMax, color, zero = true, width = 150, height = 64 }: { values: number[]; years: number[]; yMin: number; yMax: number; color: string; zero?: boolean; width?: number; height?: number }) {
  const x = scaleLinear().domain([Math.min(...years), Math.max(...years)]).range([4, width - 4])
  const y = scaleLinear().domain([yMin, yMax]).range([height - 6, 6])
  const d = line<number>().x((_, i) => x(years[i])).y((v) => y(v))(values) ?? ''
  return (
    <svg width="100%" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`Trend ${values.map((v) => v.toFixed(2)).join(', ')}`}>
      {zero && <line x1={0} x2={width} y1={y(0)} y2={y(0)} stroke="#d0d0d0" strokeDasharray="2 2" />}
      <path d={d} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" />
      {values.map((v, i) => <circle key={i} cx={x(years[i])} cy={y(v)} r={i === values.length - 1 ? 3 : 1.8} fill={color} />)}
    </svg>
  )
}

import { useMemo, useState } from 'react'
import type { Feature, Geometry } from 'geojson'
import { useCountyTrends, useDemographics, useGeo } from '../data/hooks'
import { Gate, Section, Segmented, Select } from '../components/Ui'
import { ChoroplethMap } from '../components/ChoroplethMap'
import { ContinuousLegend } from '../components/MapLegend'
import { DemoCompare } from '../components/DemoCompare'
import { Scatter } from '../components/Scatter'
import { SortableTable, type Column } from '../components/SortableTable'
import { DEMO_VARS, demoVar, valueOf } from '../lib/demo'
import { NO_DATA, SEQUENTIAL, sequentialFill } from '../lib/colors'
import { fmtMargin } from '../lib/format'
import { useDocTitle } from '../lib/hooks'
import type { DemographicKey, DemographicUnit } from '../types/data'

type F = Feature<Geometry, Record<string, unknown>>

export function DemographicsPage() {
  useDocTitle('Demographics')
  const counties = useDemographics('counties')
  const districts = useDemographics('cd2026')
  const state = useDemographics('state')
  const countyGeo = useGeo('counties')
  const districtGeo = useGeo('cd2026')
  const trends = useCountyTrends()
  const [geo, setGeo] = useState<'counties' | 'districts'>('counties')
  const [key, setKey] = useState<DemographicKey>('pct_bachelors_plus')
  const [xKey, setXKey] = useState<DemographicKey>('pct_bachelors_plus')
  const [selected, setSelected] = useState<string | null>(null)
  const v = demoVar(key)

  const units = geo === 'counties' ? counties?.units : districts?.units
  const geoData = geo === 'counties' ? countyGeo : districtGeo
  const idKey = geo === 'counties' ? 'fips' : 'district'

  const byId = useMemo(() => new Map((units ?? []).map((u) => [u.id, u])), [units])
  const [lo, hi] = useMemo(() => {
    const vals = (units ?? []).map((u) => valueOf(u, key)).filter((x): x is number => x != null)
    return [Math.min(...vals), Math.max(...vals)]
  }, [units, key])
  const fill = (f: F) => {
    const u = byId.get(String(f.properties?.[idKey]))
    const val = u ? valueOf(u, key) : null
    return val == null ? NO_DATA : sequentialFill((val - lo) / (hi - lo || 1))
  }

  const columns: Column<DemographicUnit>[] = [
    { key: 'name', header: geo === 'counties' ? 'County' : 'District', sort: (u) => u.name, render: (u) => <b>{u.name}</b> },
    ...DEMO_VARS.map((dv): Column<DemographicUnit> => ({
      key: dv.key, header: dv.label, align: 'right', className: dv.key === key ? 'hl' : '', sort: (u) => valueOf(u, dv.key),
      render: (u) => { const x = valueOf(u, dv.key); return <span className="num">{x == null ? '–' : dv.fmt(x)}</span> },
    })),
  ]

  const margin24 = useMemo(() => {
    const m = new Map<string, number>()
    for (const [fips, list] of Object.entries(trends?.counties ?? {})) {
      const e = [...list].filter((x) => x.contest_id === 'president').sort((a, b) => b.year - a.year)[0]
      if (e) m.set(fips, e.margin)
    }
    return m
  }, [trends])

  const xv = demoVar(xKey)
  const points = (counties?.units ?? []).flatMap((u) => {
    const x = valueOf(u, xKey), y = margin24.get(u.id)
    return x != null && y != null ? [{ id: u.id, label: u.name, x, y, r: u.population, color: y > 0 ? '#D6303A' : '#2563B5' }] : []
  })

  return (
    <div className="page">
      <header className="page-head">
        <div className="kicker">Demographics</div>
        <h1 className="headline sm">Who lives where</h1>
        <p className="dek">American Community Survey estimates for Utah’s 29 counties and the four 2026 congressional districts.</p>
      </header>

      <Section title="Map" aside={
        <div className="toolbar-inline">
          <Segmented label="Geography" value={geo} onChange={(g) => { setGeo(g); setSelected(null) }} options={[{ value: 'counties', label: 'Counties' }, { value: 'districts', label: '2026 districts' }]} />
          <Select label="Variable" value={key} onChange={(k) => setKey(k as DemographicKey)}>
            {DEMO_VARS.map((d) => <option key={d.key} value={d.key}>{d.label}</option>)}
          </Select>
        </div>
      }>
        <Gate data={units ? { units } : units === undefined ? undefined : null} what="Demographic data">
          {() => geoData ? (
            <div className="two-col eq">
              <div>
                <ChoroplethMap features={geoData.features as F[]} idOf={(f) => String(f.properties?.[idKey])} fill={fill} selectedId={selected} onSelect={(f) => setSelected(f ? String(f.properties?.[idKey]) : null)}
                  tooltip={(f) => { const u = byId.get(String(f.properties?.[idKey])); const val = u ? valueOf(u, key) : null; return <div><div className="tt-title">{u?.name}</div><div className="tt-row"><span>{v.label}</span><b>{val == null ? '–' : v.fmt(val)}</b></div></div> }}
                  zoomable={geo === 'counties'} aspect={1.1} maxHeight={560} ariaLabel={`Map of ${v.label} by ${geo === 'counties' ? 'county' : '2026 district'}`} />
                <ContinuousLegend title={v.label} colors={SEQUENTIAL} lo={Number.isFinite(lo) ? v.fmt(lo) : ''} hi={Number.isFinite(hi) ? v.fmt(hi) : ''} />
              </div>
              <SortableTable rows={units ?? []} columns={columns} rowKey={(u) => u.id} initialSort={{ key, dir: 'desc' }} activeKey={selected} onRowClick={(u) => setSelected(u.id)} maxHeight={600} caption="Demographics table" />
            </div>
          ) : <div className="map-placeholder">Map geometry not yet available.</div>}
        </Gate>
      </Section>

      <Section title="District profiles" dek="Each 2026 congressional district compared with the state.">
        <Gate data={districts} what="District demographics">
          {(d) => (
            <div className="profile-grid">
              {d.units.map((u) => (
                <article className="profile-card" key={u.id}>
                  <h3>District {u.id}</h3>
                  <div className="profile-pop">{u.population.toLocaleString('en-US')} residents</div>
                  <DemoCompare unit={u} state={state?.units[0]} unitLabel={`D${u.id}`} />
                </article>
              ))}
            </div>
          )}
        </Gate>
      </Section>

      <Section title="Demographics and the vote" dek="Each bubble is a county, sized by population. Vertical axis is the 2024 presidential margin (Republican minus Democratic).">
        <div className="chart-toolbar">
          <Select label="Horizontal axis" value={xKey} onChange={(k) => setXKey(k as DemographicKey)}>
            {DEMO_VARS.filter((d) => d.key !== 'population').map((d) => <option key={d.key} value={d.key}>{d.label}</option>)}
          </Select>
        </div>
        {points.length ? (
          <Scatter points={points} xLabel={xv.label} yLabel="2024 presidential margin" xFormat={xv.fmt} yFormat={(y) => fmtMargin(y, 0)} ariaLabel={`Scatter of ${xv.label} against 2024 presidential margin by county`} />
        ) : <div className="unavailable">Needs county demographics and county trend data.</div>}
      </Section>
    </div>
  )
}

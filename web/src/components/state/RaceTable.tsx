import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { SortableTable, type Column } from '../SortableTable'
import { PartyChip } from '../PartyChip'
import { ReportingMeter } from '../ReportingMeter'
import { Segmented } from '../Ui'
import { useSite } from '../../data/site'
import { fmtMargin, fmtPct } from '../../lib/format'
import { lastName } from '../../lib/results'
import { seatLabel, type SeatState } from '../../lib/legislature'

type Chamber = 'all' | 'house' | 'senate'
type Show = 'all' | 'competitive' | 'open' | 'flips' | 'uncontested'

const COMPETITIVE = 0.1
const PARTY_ORDER: Record<string, number> = { REP: 0, DEM: 1 }

const isOpen = (s: SeatState): boolean => s.seat.vacant || s.seat.incumbent_running === false
const rowKey = (s: SeatState): string => `${s.chamber}-${s.seat.district}`

function candidatesOf(s: SeatState, started: boolean) {
  const list = [...(s.contest?.candidates ?? [])]
  return started ? list.sort((a, b) => b.votes - a.votes) : list.sort((a, b) => (PARTY_ORDER[a.party ?? ''] ?? 2) - (PARTY_ORDER[b.party ?? ''] ?? 2))
}

export function RaceTable({ states, started }: { states: SeatState[]; started: boolean }) {
  const navigate = useNavigate()
  const { currentElection } = useSite()
  const [chamber, setChamber] = useState<Chamber>('all')
  const [show, setShow] = useState<Show>('all')
  const [q, setQ] = useState('')

  const rows = useMemo(() => {
    const needle = q.trim().toLowerCase()
    return states.filter((s) => {
      if (!s.seat.up) return false
      if (chamber !== 'all' && s.chamber !== chamber) return false
      if (show === 'competitive' && !(s.seat.pres24_margin != null && Math.abs(s.seat.pres24_margin) < COMPETITIVE)) return false
      if (show === 'open' && !isOpen(s)) return false
      if (show === 'flips' && !s.flip) return false
      if (show === 'uncontested' && !s.seat.uncontested) return false
      if (!needle) return true
      const hay = [`${s.chamber} ${s.seat.district}`, s.seat.holder ?? '', ...(s.contest?.candidates.map((c) => c.name) ?? [])].join(' ').toLowerCase()
      return hay.includes(needle)
    })
  }, [states, chamber, show, q])

  const columns: Column<SeatState>[] = [
    {
      key: 'seat', header: 'Seat', sort: (s) => (s.chamber === 'house' ? 0 : 1000) + s.seat.district,
      render: (s) => <span className="nowrap"><b>{seatLabel(s.chamber).replace('Utah ', '')} {s.seat.district}</b></span>,
    },
    {
      key: 'holder', header: 'Current holder', sort: (s) => s.seat.holder ?? '~',
      render: (s) => (
        <div>
          {s.seat.vacant ? <span className="muted">Vacant</span> : <><PartyChip party={s.seat.holder_party} /> {s.seat.holder}</>}
          {isOpen(s) && <span className="tag">Open seat</span>}
          {s.seat.running_for && !s.seat.vacant && <div className="sub">Running for {s.seat.running_for.replace('-', ' ')}</div>}
        </div>
      ),
    },
    {
      key: 'cands', header: 'Candidates',
      render: (s) => {
        const cands = candidatesOf(s, started)
        if (!s.contest) return <span className="muted">Not in results feed yet</span>
        if (s.seat.uncontested) return <span><PartyChip party={cands[0]?.party} /> {cands[0]?.name} <span className="tag">Unopposed</span></span>
        return (
          <div className="cand-list">
            {cands.map((c) => (
              <span key={c.candidate_id} className={s.leader?.candidate_id === c.candidate_id ? 'lead' : ''}>
                <PartyChip party={c.party} /> {lastName(c.name)}{started && s.contest!.total_votes > 0 ? ` ${fmtPct(c.pct, 0)}` : ''}
              </span>
            ))}
          </div>
        )
      },
    },
    ...(started
      ? ([
          {
            key: 'leader', header: 'Leader', align: 'left', sort: (s) => (s.leader ? s.margin : null),
            render: (s) => s.leader ? (
              <div>
                <PartyChip party={s.leader.party} /> <b>{lastName(s.leader.name)}</b> <span className="muted">{s.leader.party === 'REP' ? 'R' : s.leader.party === 'DEM' ? 'D' : ''}+{(s.margin * 100).toFixed(1)}</span>
                <div className="sub">{s.called ? 'Called' : 'Leading'}</div>
              </div>
            ) : <span className="muted">–</span>,
          },
          { key: 'counted', header: 'Est. counted', sort: (s) => s.pctCounted, render: (s) => (s.contest ? <ReportingMeter pct={s.pctCounted} size="sm" /> : <span className="muted">–</span>) },
          { key: 'flip', header: 'Flip', align: 'center', sort: (s) => (s.flip ? 1 : 0), render: (s) => (s.flip ? <span className="flip-tag">{s.seat.holder_party?.[0]} → {s.leader?.party?.[0] ?? '?'}</span> : <span className="muted">–</span>) },
        ] satisfies Column<SeatState>[])
      : []),
    {
      key: 'pres', header: '2024 pres.', align: 'right', title: 'Donald Trump minus Kamala Harris margin in the district (2024), from precinct results.',
      sort: (s) => (s.seat.pres24_margin == null ? null : Math.abs(s.seat.pres24_margin)),
      render: (s) => {
        const m = s.seat.pres24_margin
        return (
          <span className={`nowrap ${m != null && m > 0 ? 'rep-text' : 'dem-text'}`}>
            {fmtMargin(m, 0)}{m != null && Math.abs(m) < COMPETITIVE && <span className="tag comp">Competitive</span>}
          </span>
        )
      },
    },
  ]

  return (
    <div>
      <div className="selectors race-filters">
        <Segmented<Chamber> label="Chamber" value={chamber} onChange={setChamber} options={[{ value: 'all', label: 'Both' }, { value: 'house', label: 'House' }, { value: 'senate', label: 'Senate' }]} />
        <Segmented<Show> label="Filter" value={show} onChange={setShow}
          options={[{ value: 'all', label: 'All' }, { value: 'competitive', label: 'Competitive' }, { value: 'open', label: 'Open seats' }, ...(started ? [{ value: 'flips' as const, label: 'Flips' }] : []), { value: 'uncontested', label: 'Unopposed' }]} />
        <input className="search" type="search" placeholder="Search district, name or candidate" aria-label="Search races" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>
      <p className="note small">{rows.length} race{rows.length === 1 ? '' : 's'}. “Competitive” means the 2024 presidential margin in the district was under 10 points.</p>
      <SortableTable<SeatState> rows={rows} columns={columns} rowKey={rowKey} initialSort={{ key: 'seat', dir: 'asc' }} maxHeight={640}
        caption="State legislative races"
        onRowClick={(s) => { if (s.seat.contest_id) navigate(`/results/${currentElection}/${s.seat.contest_id}`) }} empty="No races match." />
    </div>
  )
}

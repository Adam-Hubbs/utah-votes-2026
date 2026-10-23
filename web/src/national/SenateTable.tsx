import { useMemo, useState } from 'react'
import { SortableTable, type Column } from '../components/SortableTable'
import { PartyChip } from '../components/PartyChip'
import { Segmented } from '../components/Ui'
import type { SenateFile, SenateRace } from './types'
import { INDEX_LABEL, SEAT_LETTER, consensusScore, fmtLead, indexFill, indexText, leadClass, raceIndex, shortRating } from './lib'
import { lastName } from '../lib/results'

const SRC = ['cook', 'sabato', 'inside'] as const
const SRC_NAME = { cook: 'Cook', sabato: 'Sabato', inside: 'Inside Elections' }

export function ConsensusChip({ race }: { race: SenateRace }) {
  const i = raceIndex(race)
  return <span className="rating-chip compact" style={{ background: indexFill(i), color: indexText(i) }}>{INDEX_LABEL[i]}</span>
}

export function RatingDots({ race }: { race: SenateRace }) {
  return (
    <span className="rating-dots">
      {SRC.map((s) => {
        const lab = race.ratings[s]
        return <i key={s} title={`${SRC_NAME[s]}: ${shortRating(lab)}`} style={{ background: lab ? indexFill(raceIndexOf(lab)) : '#ddd' }} />
      })}
    </span>
  )
}

function raceIndexOf(label: string): number {
  const fake = { ratings: { cook: label, sabato: null, inside: null } } as SenateRace
  return raceIndex(fake)
}

export function CandidateLine({ race, max = 3 }: { race: SenateRace; max?: number }) {
  const shown = race.candidates.slice(0, max)
  return (
    <span className="cand-line">
      {shown.map((c) => (
        <span key={c.name} className="cand-line-item">{lastName(c.name)} <PartyChip party={c.party === 'IND' ? 'OTH' : c.party} /></span>
      ))}
    </span>
  )
}

export function PollChip({ race }: { race: SenateRace }) {
  const m = race.poll_avg.margin
  if (!m) return <span className="muted">{race.poll_avg.n_polls ? '–' : 'No polls'}</span>
  return (
    <span className="poll-chip">
      <span className={`margin-pill ${leadClass(m.value, m.opponent_party)}`}>{fmtLead(m.value, m.opponent_party, m.opponent)}</span>
      <span className="sub">{race.poll_avg.n_polls} poll{race.poll_avg.n_polls === 1 ? '' : 's'}</span>
    </span>
  )
}

interface Props { senate: SenateFile; selected: string | null; onSelect: (s: string) => void }

export function SenateTable({ senate, selected, onSelect }: Props) {
  const [view, setView] = useState<'close' | 'all'>('close')
  const rows = useMemo(() => {
    const all = senate.races
    return view === 'all' ? all : all.filter((r) => r.call || Math.abs(consensusScore(r) ?? 0) < 2.5)
  }, [senate, view])

  const columns: Column<SenateRace>[] = [
    {
      key: 'state', header: 'State', sort: (r) => r.state_name,
      render: (r) => <div><b>{r.state_name}</b>{r.special && <span className="tag">Special</span>}<div className="sub show-sm">{lastName(r.incumbent)} ({SEAT_LETTER[r.incumbent_party]}){r.open ? ', open' : ''}</div></div>,
    },
    {
      key: 'inc', header: 'Incumbent', sort: (r) => r.incumbent, className: 'hide-sm',
      render: (r) => (
        <div>{r.incumbent} <PartyChip party={r.incumbent_party} />
          <div className="sub">{r.open ? `Open seat${r.status_note ? ` · ${r.status_note}` : ''}` : r.status_note ?? 'Running'}</div>
        </div>
      ),
    },
    { key: 'cands', header: 'Candidates', render: (r) => <CandidateLine race={r} />, className: 'hide-sm' },
    { key: 'poll', header: 'Poll average', align: 'right', sort: (r) => (r.poll_avg.margin ? Math.abs(r.poll_avg.margin.value) : null), render: (r) => <PollChip race={r} /> },
    {
      key: 'rating', header: 'Rating', sort: (r) => Math.abs(consensusScore(r) ?? 9),
      title: 'Consensus of Cook, Sabato and Inside Elections; dots show each source',
      render: (r) => <span className="rating-cell"><ConsensusChip race={r} /><RatingDots race={r} /></span>,
    },
    {
      key: 'call', header: 'Call', sort: (r) => (r.call ? r.call.winner_party : 'zzz'),
      render: (r) => r.call
        ? <span className="call-cell"><span className={`call-pill ${r.call.winner_party.toLowerCase()}`}>{SEAT_LETTER[r.call.winner_party]} win</span><span className="sub">{r.call.winner_name}</span></span>
        : <span className="muted">–</span>,
    },
  ]

  return (
    <div>
      <div className="list-toolbar">
        <Segmented label="Races shown" value={view} onChange={setView} options={[
          { value: 'close', label: 'Competitive and called' }, { value: 'all', label: `All ${senate.races.length} races` },
        ]} />
      </div>
      <SortableTable rows={rows} columns={columns} rowKey={(r) => r.state} initialSort={{ key: 'rating', dir: 'asc' }}
        onRowClick={(r) => onSelect(r.state)} activeKey={selected} caption="2026 U.S. Senate races" />
    </div>
  )
}

export function RaceDetail({ race, senate }: { race: SenateRace; senate: SenateFile }) {
  const pa = race.poll_avg
  return (
    <div className="race-detail">
      <div className="rd-head">
        <h3>{race.state_name}{race.special ? ' (special election)' : ''}</h3>
        <ConsensusChip race={race} />
      </div>
      <p className="rd-line">
        {race.open ? <>Open seat{race.status_note ? ` (${race.status_note.toLowerCase()})` : ''}. Held by {race.incumbent} <PartyChip party={race.incumbent_party} />.</> : <>Incumbent: {race.incumbent} <PartyChip party={race.incumbent_party} />{race.status_note ? `, ${race.status_note.toLowerCase()}` : ''}.</>}
      </p>
      <div className="rd-cands">
        {race.candidates.map((c) => {
          const p = pa.latest.find((l) => l.name === c.name)
          return <div key={c.name} className="rd-cand"><span>{c.name} <PartyChip party={c.party === 'IND' ? 'OTH' : c.party} /></span><b>{p ? `${p.avg.toFixed(1)}%` : '–'}</b></div>
        })}
      </div>
      <div className="rd-ratings">
        {senate.ratings_sources.map((s) => (
          <div key={s.id} className="rating-source"><a href={s.url} target="_blank" rel="noreferrer">{s.name}</a>
            <span className="rating-chip compact" style={{ background: indexFill(raceIndexOf(race.ratings[s.id] ?? '')), color: indexText(raceIndexOf(race.ratings[s.id] ?? '')) }}>{shortRating(race.ratings[s.id])}</span>
          </div>
        ))}
      </div>
      <p className="note small">{pa.n_polls ? `Poll average from ${pa.n_polls} poll${pa.n_polls === 1 ? '' : 's'}, latest ${pa.last_poll_date ?? ''}.` : 'No recent public polls.'}</p>
    </div>
  )
}

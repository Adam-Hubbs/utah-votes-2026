import type { SenateFile } from './types'
import { SEAT_HEX, seatCounts } from './lib'

const tint = (hex: string) => `color-mix(in srgb, ${hex} 38%, #fff)`

interface Seg { key: string; n: number; color: string; label: string; dark?: boolean; hatch?: boolean }

export function BalanceBar({ senate, compact = false }: { senate: SenateFile; compact?: boolean }) {
  const c = seatCounts(senate.composition.not_up, senate.races)
  const segs: Seg[] = [
    { key: 'dHold', n: c.dHold, color: '#163F7F', label: 'Democratic and independent seats not up', dark: true },
    { key: 'calledD', n: c.calledD, color: SEAT_HEX.DEM, label: 'Democratic wins called', dark: true },
    { key: 'calledI', n: c.calledI, color: SEAT_HEX.IND, label: 'Independent wins called' },
    { key: 'ratedD', n: c.ratedD, color: tint(SEAT_HEX.DEM), label: 'Undecided, rated toward Democrats' },
    { key: 'tossup', n: c.tossup, color: '#d9d4e6', label: 'Undecided, toss-up' },
    { key: 'ratedR', n: c.ratedR, color: tint(SEAT_HEX.REP), label: 'Undecided, rated toward Republicans' },
    { key: 'calledR', n: c.calledR, color: SEAT_HEX.REP, label: 'Republican wins called', dark: true },
    { key: 'rHold', n: c.rHold, color: '#9E1B28', label: 'Republican seats not up', dark: true },
  ]
  const total = segs.reduce((a, s) => a + s.n, 0)
  const maj = senate.composition.majority
  const dSecured = c.dHold + c.calledD
  const rSecured = c.rHold + c.calledR
  const election = c.calledD + c.calledR + c.calledI > 0

  return (
    <div className={`balance${compact ? ' compact' : ''}`}>
      {!compact && (
        <div className="balance-heads">
          <div className="bh bh-d"><div className="bh-n">{dSecured}</div><div className="bh-l">Democrats and independents{election ? ' secured' : ' safe'}</div></div>
          <div className="bh bh-mid"><div className="bh-n">{c.ratedD + c.ratedR + c.tossup}</div><div className="bh-l">races undecided</div></div>
          <div className="bh bh-r"><div className="bh-n">{rSecured}</div><div className="bh-l">Republicans{election ? ' secured' : ' safe'}</div></div>
        </div>
      )}
      <div className="balance-bar" role="img"
        aria-label={`Senate seats: Democrats and independents ${dSecured} secured, Republicans ${rSecured} secured, ${c.ratedD + c.ratedR + c.tossup} undecided. ${maj} needed for a majority.`}>
        {segs.filter((s) => s.n > 0).map((s) => (
          <div key={s.key} className="balance-seg" style={{ flex: s.n, background: s.color, color: s.dark ? '#fff' : '#222' }} title={`${s.label}: ${s.n}`}>
            {s.n >= 3 && <span>{s.n}</span>}
          </div>
        ))}
        <div className="balance-line" style={{ left: `${(maj - 0.5) / total * 100}%` }} aria-hidden />
      </div>
      {!compact && (
        <>
          <div className="balance-key">
            <span><i style={{ background: '#163F7F' }} /> D / I not up</span>
            <span><i style={{ background: tint(SEAT_HEX.DEM) }} /> Rated D</span>
            <span><i style={{ background: '#d9d4e6' }} /> Toss-up</span>
            <span><i style={{ background: tint(SEAT_HEX.REP) }} /> Rated R</span>
            <span><i style={{ background: '#9E1B28' }} /> R not up</span>
            {election && <span><i style={{ background: '#777' }} /> Darker = called</span>}
          </div>
          <p className="balance-note">
            The line marks the majority: Democrats need {maj} seats, but {100 - maj + 1} Republicans keep control because the vice president (a Republican) breaks 50–50 ties.
            {' '}If every undecided race went as rated, the Senate would be {c.dHold + c.calledD + c.ratedD + c.calledI}–{c.rHold + c.calledR + c.ratedR} with {c.tossup} toss-up{c.tossup === 1 ? '' : 's'} deciding control.
          </p>
        </>
      )}
    </div>
  )
}

import { partyAbbr, partyGroup, partyLabel } from '../lib/parties'

export function PartyChip({ party, id, long = false }: { party: string | null | undefined; id?: string; long?: boolean }) {
  const g = partyGroup(party, id)
  if (!party) return null
  return (
    <span className={`party-chip party-${g.toLowerCase()}`} title={partyLabel(party)}>
      {long ? partyLabel(party) : partyAbbr(party)}
    </span>
  )
}

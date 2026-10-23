import { useMemo } from 'react'
import type { IndexElection } from '../types/data'
import { OFFICE_LABEL, OFFICE_ORDER } from '../lib/results'
import { Select } from './Ui'

export function ElectionSelect({ elections, value, onChange, label = 'Election' }: { elections: IndexElection[]; value: string; onChange: (id: string) => void; label?: string }) {
  return (
    <Select label={label} value={value} onChange={onChange}>
      {elections.map((e) => <option key={e.election_id} value={e.election_id}>{e.name}</option>)}
    </Select>
  )
}

export function groupContests(election: IndexElection | undefined): { office: string; label: string; contests: IndexElection['contests'] }[] {
  if (!election) return []
  const map = new Map<string, IndexElection['contests']>()
  for (const c of election.contests) map.set(c.office, [...(map.get(c.office) ?? []), c])
  return [...map.entries()]
    .sort((a, b) => (OFFICE_ORDER.indexOf(a[0]) + 1 || 99) - (OFFICE_ORDER.indexOf(b[0]) + 1 || 99))
    .map(([office, contests]) => ({ office, label: OFFICE_LABEL[office] ?? office, contests }))
}

export function ContestSelect({ election, value, onChange }: { election: IndexElection | undefined; value: string; onChange: (id: string) => void }) {
  const groups = useMemo(() => groupContests(election), [election])
  return (
    <Select label="Contest" value={value} onChange={onChange}>
      {groups.map((g) => (
        <optgroup key={g.office} label={g.label}>
          {g.contests.map((c) => <option key={c.contest_id} value={c.contest_id}>{c.name}</option>)}
        </optgroup>
      ))}
    </Select>
  )
}

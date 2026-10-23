import { Link } from 'react-router-dom'
import { Section } from '../components/Ui'
import { BalanceBar } from './BalanceBar'
import { useSenate } from './hooks'
import './national.css'

export function NationalCard() {
  const senate = useSenate()
  if (!senate) return null
  return (
    <Section title="The national picture" dek="Utah is our focus, but control of the Senate and House is also on the ballot." aside={<Link to="/national" className="more">U.S. Senate and House →</Link>}>
      <BalanceBar senate={senate} compact />
      <p className="note">Senate seats: Democrats and independents on the left, Republicans on the right. Lighter blocks are undecided races shaded by expert ratings.</p>
    </Section>
  )
}

import { canAccessSection, type ProtectedSection } from '../lib/auth-route-guard'

type Entry = {
  title: string
  section: ProtectedSection
  detail: string
}

const CATEGORIES: Entry[] = [
  { title: 'Registration & users', section: 'users', detail: 'Inspect user accounts, roles and verification status.' },
  { title: 'Roles & permissions', section: 'access', detail: 'Review the server-managed authorization matrix and access requests.' },
  { title: 'Teacher question review', section: 'moderation', detail: 'Review verified subject teachers, educational content and integrity cases.' },
  { title: 'AI lessons & curriculum', section: 'moderation', detail: 'Open Content Studio for draft courses and reviewed publication workflows.' },
  { title: 'AI workforce', section: 'ai', detail: 'Inspect AI tools and budget-protected operations.' },
  { title: 'Arena integrity', section: 'moderation', detail: 'Review competition integrity incidents and proctored assessments.' },
  { title: 'Opportunity Hub', section: 'opportunities', detail: 'Review employers, verified listings and opportunity moderation.' },
  { title: 'Coins and invitations', section: 'commissions', detail: 'Inspect commission history. Cash settlement remains deferred.' },
  { title: 'Marketplace disputes', section: 'disputes', detail: 'Inspect reports and disputes without releasing escrow.' },
  { title: 'Audit and monitoring', section: 'audit', detail: 'Inspect administrative changes and operational decisions.' },
  { title: 'Payment status (deferred)', section: 'payments', detail: 'Read-only oversight; no financial releases from System Settings.' },
]

export default function AdminSettingsDirectory({
  permissions,
  onOpen,
}: {
  permissions: string[]
  onOpen: (section: ProtectedSection) => void
}) {
  return <section className="panel" aria-label="System settings directory">
    <h2>Settings directory</h2>
    <p>Use these links to existing authorized control panels. Sections not yet configured still require backend work; this directory does not bypass permissions or invent settings.</p>
    <div className="settings-directory">
      {CATEGORIES.map(entry => {
        const available = canAccessSection(permissions, entry.section)
        return <div key={entry.title} className="settings-directory-item">
          <div><h3>{entry.title}</h3><p>{entry.detail}</p></div>
          <button type="button" disabled={!available} onClick={() => onOpen(entry.section)}>
            {available ? 'Open' : 'Restricted'}
          </button>
        </div>
      })}
    </div>
  </section>
}

export type AdminModule = {
  id: string
  label: string
  permission: string
  description: string
  actions: string[]
}

// These permission keys intentionally mirror the authoritative admin.permissions table.
export const operationalModules: AdminModule[] = [
  { id: 'users', label: 'Users', permission: 'users.read', description: 'Search, inspect, verify, suspend and recover accounts.', actions: ['search', 'inspect', 'verify', 'suspend', 'recover'] },
  { id: 'opportunities', label: 'Opportunities', permission: 'employers.manage', description: 'Review employers and approve or reject listings.', actions: ['review', 'approve', 'reject'] },
  { id: 'payments', label: 'Payments', permission: 'finance.manage', description: 'Monitor payments, escrow, coins and payout queues.', actions: ['inspect', 'reconcile', 'review-payout'] },
  { id: 'disputes', label: 'Disputes', permission: 'support.manage', description: 'Handle support tickets, SLA escalation and disputes.', actions: ['assign', 'escalate', 'resolve'] },
  { id: 'moderation', label: 'Moderation', permission: 'moderation.manage', description: 'Review flagged content and integrity events.', actions: ['review', 'warn', 'remove', 'escalate'] },
  { id: 'access', label: 'Authorization', permission: 'authorization.manage', description: 'Manage roles, permissions, access requests and RLS visibility.', actions: ['inspect', 'approve-request', 'revoke'] },
  { id: 'audit', label: 'Audit Log', permission: 'audit.read', description: 'Inspect actor, action, target, before/after and request metadata.', actions: ['filter', 'inspect', 'export'] },
  { id: 'settings', label: 'System', permission: 'system.manage', description: 'Manage feature flags and platform configuration.', actions: ['inspect', 'update'] },
]

export function canUseModule(permissions: string[], permission: string) {
  return permissions.includes('*') || permissions.includes(permission)
}

import type { Session } from '@supabase/supabase-js'
import { canUseModule } from '../modules/operations'

export type ProtectedSection =
  | 'overview'
  | 'users'
  | 'commissions'
  | 'opportunities'
  | 'payments'
  | 'disputes'
  | 'moderation'
  | 'access'
  | 'audit'
  | 'settings'

const SECTION_PERMISSIONS: Record<Exclude<ProtectedSection, 'overview'>, string> = {
  users: 'users.read',
  commissions: 'finance.manage',
  opportunities: 'employers.manage',
  payments: 'finance.manage',
  disputes: 'support.manage',
  moderation: 'moderation.manage',
  access: 'authorization.manage',
  audit: 'audit.read',
  settings: 'system.manage',
}

export type RouteDecision =
  | { allowed: true; section: ProtectedSection }
  | { allowed: false; reason: 'AUTH_REQUIRED' | 'ADMIN_REQUIRED' | 'PERMISSION_DENIED' | 'INVALID_SECTION' }

export function isProtectedSection(value: string): value is ProtectedSection {
  return value === 'overview' || value in SECTION_PERMISSIONS
}

export function sectionPermission(section: ProtectedSection): string | null {
  return section === 'overview' ? null : SECTION_PERMISSIONS[section]
}

export function canAccessSection(permissions: string[], section: ProtectedSection): boolean {
  const permission = sectionPermission(section)
  return permission === null || canUseModule(permissions, permission)
}

/**
 * Central client-side route decision. This is UX protection only; the
 * mela-admin-api Edge Function remains the authoritative authorization layer.
 */
export function authorizeSection(
  session: Session | null,
  adminAllowed: boolean,
  permissions: string[],
  requestedSection: string,
): RouteDecision {
  if (!isProtectedSection(requestedSection)) return { allowed: false, reason: 'INVALID_SECTION' }
  if (!session) return { allowed: false, reason: 'AUTH_REQUIRED' }
  if (!adminAllowed) return { allowed: false, reason: 'ADMIN_REQUIRED' }
  if (!canAccessSection(permissions, requestedSection)) {
    return { allowed: false, reason: 'PERMISSION_DENIED' }
  }
  return { allowed: true, section: requestedSection }
}

export function visibleSections(permissions: string[]): ProtectedSection[] {
  return (Object.keys({ overview: null, ...SECTION_PERMISSIONS }) as ProtectedSection[])
    .filter((section) => canAccessSection(permissions, section))
}

import { describe, expect, it } from 'vitest'
import type { Session } from '@supabase/supabase-js'
import { authorizeSection, isProtectedSection, visibleSections } from '../src/lib/auth-route-guard'

describe('Admin route authorization', () => {
  const session = { user: { id: 'test-admin' } } as Session
  it('rejects inherited object properties as route names', () => {
    for (const route of ['toString', 'constructor', '__proto__', 'hasOwnProperty']) {
      expect(isProtectedSection(route)).toBe(false)
      expect(authorizeSection(session, true, ['*'], route)).toEqual({ allowed: false, reason: 'INVALID_SECTION' })
    }
  })
  it('denies signed-out and non-admin sessions', () => {
    expect(authorizeSection(null, true, ['*'], 'users')).toEqual({ allowed: false, reason: 'AUTH_REQUIRED' })
    expect(authorizeSection(session, false, ['*'], 'users')).toEqual({ allowed: false, reason: 'ADMIN_REQUIRED' })
  })
  it('limits a user reader to its assigned modules', () => {
    expect(visibleSections(['users.read'])).toEqual(['overview', 'users'])
    expect(authorizeSection(session, true, ['users.read'], 'payments')).toEqual({ allowed: false, reason: 'PERMISSION_DENIED' })
    expect(authorizeSection(session, true, ['users.read'], 'users')).toEqual({ allowed: true, section: 'users' })
  })
})

it('protects AI Workforce with system management permission',()=>{
 const session={user:{id:'admin'}} as Session;
 expect(authorizeSection(session,true,['users.read'],'ai')).toEqual({allowed:false,reason:'PERMISSION_DENIED'});
 expect(visibleSections(['system.manage'])).toContain('ai');
});

it('shows Education Review only to administrators with content management permission',()=>{
 const session={user:{id:'reviewer-admin'}} as Session
 expect(visibleSections(['users.read'])).not.toContain('education')
 expect(authorizeSection(session,true,['users.read'],'education')).toEqual({allowed:false,reason:'PERMISSION_DENIED'})
 expect(visibleSections(['content.manage'])).toContain('education')
 expect(authorizeSection(session,true,['content.manage'],'education')).toEqual({allowed:true,section:'education'})
})

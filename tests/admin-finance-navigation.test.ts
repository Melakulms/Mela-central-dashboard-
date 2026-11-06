// @vitest-environment node
import {readFileSync} from 'node:fs'
import {describe,expect,it} from 'vitest'
import {authorizeSection,canAccessSection,visibleSections} from '../src/lib/auth-route-guard'

const main=readFileSync(new URL('../src/main.tsx',import.meta.url),'utf8')
const session={user:{id:'test-verified-admin'}} as Parameters<typeof authorizeSection>[0]

describe('MFA-gated finance menu and routes',()=>{
  it('advertises clear payment readiness and subscription review entries',()=>{
    expect(main).toContain("{id:'subscription_review',label:'Subscription Review'")
    expect(main).toContain("{id:'payment_readiness',label:'Payment Readiness'")
    expect(main).toContain("section==='subscription_review'?<ManualSubscriptionReview client={supabase}/>")
    expect(main).toContain("section==='payment_readiness'?<PaymentReadinessPanel client={supabase}/>")
    expect(main).toContain("Open Subscription Review")
    expect(main).toContain("Open Payment Readiness")
  })
  it('shows both finance screens to authorized finance reviewers',()=>{
    const permissions=['finance.manage']
    expect(canAccessSection(permissions,'subscription_review')).toBe(true)
    expect(canAccessSection(permissions,'payment_readiness')).toBe(true)
    expect(visibleSections(permissions)).toContain('subscription_review')
    expect(visibleSections(permissions)).toContain('payment_readiness')
    expect(authorizeSection(session,true,permissions,'subscription_review')).toEqual({allowed:true,section:'subscription_review'})
    expect(authorizeSection(session,true,permissions,'payment_readiness')).toEqual({allowed:true,section:'payment_readiness'})
  })
  it('keeps financial status and review unavailable to ordinary and signed-out roles',()=>{
    for (const section of ['subscription_review','payment_readiness'] as const){
      expect(canAccessSection(['users.read'],section)).toBe(false)
      expect(canAccessSection([],section)).toBe(false)
      expect(authorizeSection(session,true,['users.read'],section)).toEqual({allowed:false,reason:'PERMISSION_DENIED'})
      expect(authorizeSection(null,true,['finance.manage'],section)).toEqual({allowed:false,reason:'AUTH_REQUIRED'})
      expect(authorizeSection(session,false,['finance.manage'],section)).toEqual({allowed:false,reason:'ADMIN_REQUIRED'})
    }
    expect(canAccessSection(['*'],'payment_readiness')).toBe(true)
  })
  it('does not expose financial tools in overview to unapproved roles',()=>{
    expect(main).toContain("financeAllowed={canAccessSection(permissions,'payments')}")
    expect(main).toContain('{financeAllowed&&<section className="panel" aria-label="Subscription and payment administration">')
  })
})

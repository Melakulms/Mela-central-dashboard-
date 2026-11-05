// @vitest-environment node
import {readFileSync} from 'node:fs'
import {expect,it} from 'vitest'
const sql=readFileSync(
 new URL('../supabase/migrations/20261105220000_payment_admin_financial_release_status.sql',import.meta.url),
 'utf8'
)
it('keeps payment readiness restricted to an MFA-authorized finance reviewer',()=>{
 expect(sql).toContain("auth.jwt()->>'aal') is distinct from 'aal2'")
 expect(sql).toContain('auth.mfa_factors')
 expect(sql).toContain('auth.sessions')
 expect(sql).toContain('admin.admin_users')
 expect(sql).toContain('mela_payments.reviewers')
 expect(sql).toContain("raise exception 'Active administrator with verified MFA")
})
it('returns three evidence statuses without exposing financial evidence or weakening reviews',()=>{
 expect(sql).toContain("'financial_launch_approved'")
 expect(sql).toContain('private.mela_financial_launch_approved()')
 expect(sql).toContain("'financial_release_requirements'")
 expect(sql).toContain("('payments_provider','legal_review','wallet_business_legal')")
 expect(sql).toContain("'evidence_recorded'")
 expect(sql).not.toContain("'evidence_note',r.evidence_note")
 expect(sql).toContain("p_action='verify_account'")
 expect(sql).toContain("p_action not in ('verify_account','deactivate_account')")
 expect(sql).toContain("p_action='status'")
})

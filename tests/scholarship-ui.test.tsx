// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import ScholarshipAccessPanel from '../src/components/ScholarshipAccessPanel'

vi.mock('../src/lib/scholarship-staging', () => ({
  isScholarshipStagingUrl: () => true,
}))

const student = {
  id: '00000000-0000-4000-8000-000000000123',
  full_name: 'Test Scholarship Student',
  email: 'test-student@example.invalid',
  account_status: 'active',
  education_stage_key: 'secondary',
}
const product = {
  product_key: 'practice_plus_30d',
  product_name: 'MELA Practice Plus — 30 days',
  product_type: 'subscription',
  billing_period: 'monthly',
}
let grants: any[] = []
let history: any[] = []
let rpc: ReturnType<typeof vi.fn>
beforeEach(() => {
  grants = []
  history = []
  rpc = vi.fn(async (action: string, payload: any) => {
    if (action === 'admin_learning_grant_query_v1') {
      return { data: {
        students: payload.p_search ? [student] : [],
        products: [product],
        grants,
        audit: history,
      }, error: null }
    }
    if (action === 'admin_learning_access_v1') {
      if (payload.p_action === 'admin_grant') {
        grants = [{
          id: 'grant-id',product_key:product.product_key,status:'active',
          starts_at:'2026-10-21T00:00:00Z',ends_at: null,
          source_reference:'MELA-ADMIN-TEST',created_at:'2026-10-21T00:00:00Z',
        }]
        history = [{id:1,grant_id:'grant-id',actor:'reviewer',action:'granted',product_key:product.product_key,
          reason:payload.p_data.reason,created_at:'2026-10-21T00:00:00Z'}]
        return { data: { status: 'active', existing: false }, error: null }
      }
      if (payload.p_action === 'admin_revoke') {
        grants = [{...grants[0],status:'revoked'}]
        history = [{id:2,grant_id:'grant-id',actor:'reviewer',action:'revoked',product_key:product.product_key,
          reason:payload.p_data.reason,created_at:'2026-10-21T00:00:00Z'},...history]
        return { data: { status: 'revoked' }, error: null }
      }
    }
    throw new Error('Unexpected operation')
  })
})
afterEach(cleanup)

describe('Scholarship Admin phone workflow (mocked UI, not a real MFA test)', () => {
  it('searches for a student, grants access, and requires a reason to revoke', async () => {
    const client = {rpc} as any
    render(<ScholarshipAccessPanel client={client}/>)
    fireEvent.change(screen.getByLabelText('Find a student by name or email'), {target:{value:'Test Scholarship'}})
    fireEvent.click(screen.getByRole('button',{name:'Search students'}))
    fireEvent.click(await screen.findByRole('button',{name:/Test Scholarship Student/}))
    await screen.findByRole('heading',{name:'Test Scholarship Student'})
    fireEvent.change(screen.getByLabelText('Written reason (10–500 characters)'),{target:{value:'Approved hardship scholarship for exam preparation'}})
    fireEvent.click(screen.getByRole('button',{name:'Grant free product access'}))
    await screen.findByText('Student scholarship granted and audited.')
    expect(rpc).toHaveBeenCalledWith('admin_learning_access_v1',expect.objectContaining({
      p_action:'admin_grant',p_data:expect.objectContaining({learner_user_id:student.id,product_key:product.product_key}),
    }))
    fireEvent.click(screen.getByRole('button',{name:'Revoke'}))
    expect((screen.getByRole('button',{name:'Confirm revoke'}) as HTMLButtonElement).disabled).toBe(true)
    fireEvent.change(screen.getByLabelText('Reason (10–500 characters)'),{target:{value:'Scholarship rescinded by reviewer after case review'}})
    fireEvent.click(screen.getByRole('button',{name:'Confirm revoke'}))
    await screen.findByText('Access revoked. The entitlement and permanent audit record were preserved.')
    await waitFor(()=>expect(rpc).toHaveBeenCalledWith('admin_learning_access_v1',expect.objectContaining({
      p_action:'admin_revoke',p_data:expect.objectContaining({learner_user_id:student.id,product_key:product.product_key}),
    })))
  })
})

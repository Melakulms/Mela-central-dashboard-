// @vitest-environment jsdom
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { SupabaseClient } from '@supabase/supabase-js'
import MentorMfaRecoveryPanel from '../src/components/MentorMfaRecoveryPanel'

const request = {
  id: 'abc00000-1111-4111-8111-111111111111',
  mentor_id: 'def00000-1111-4111-8111-111111111111',
  reason: 'lost_device',
  status: 'pending',
  review_count: 1,
  created_at: '2026-10-27T10:00:00Z',
  eligible_after: '2020-01-01T10:00:00Z',
}

const rpc = vi.fn()
const aal = vi.fn()
const invoke = vi.fn()
const client = {
  rpc,
  auth: { mfa: { getAuthenticatorAssuranceLevel: aal }},
  functions: { invoke },
} as unknown as SupabaseClient

beforeEach(() => {
  vi.clearAllMocks()
  rpc.mockImplementation((name: string) => name === 'list_mentor_mfa_recovery_requests'
    ? Promise.resolve({ data: [request], error: null })
    : Promise.resolve({ data: {reviewed:true}, error: null }))
  aal.mockResolvedValue({ data: { currentLevel: 'aal2' }, error: null })
})
afterEach(cleanup)

it('requires out-of-band identity confirmation before allowing approval', async () => {
  render(<MentorMfaRecoveryPanel client={client} />)
  await screen.findByText(/Recovery request abc00000/)
  const approve = screen.getByRole('button', { name: 'Record independent approval' }) as HTMLButtonElement
  expect(approve.disabled).toBe(true)
  const input = screen.getByLabelText('Independent identity-verification case reference')
  fireEvent.focus(input)
  fireEvent.change(input, { target: { value: 'external-case-12345' } })
  expect(approve.disabled).toBe(true)
  fireEvent.click(screen.getByLabelText(/I independently verified identity/))
  expect(approve.disabled).toBe(false)
  fireEvent.click(approve)
  await waitFor(() => expect(rpc).toHaveBeenCalledWith('review_mentor_mfa_recovery', {
    p_request_id: request.id, p_evidence_reference: 'external-case-12345', p_approve: true,
  }))
})

it('rejects sensitive staff actions without AAL2 on recheck', async () => {
  aal.mockResolvedValue({ data: { currentLevel: 'aal1' }, error: null })
  render(<MentorMfaRecoveryPanel client={client} />)
  await screen.findByText(/Recovery request abc00000/)
  fireEvent.focus(screen.getByLabelText('Independent identity-verification case reference'))
  fireEvent.click(screen.getByRole('button', { name: 'Reject' }))
  await screen.findByText(/Staff authenticator verification is required/)
  expect(rpc.mock.calls.some(([name]) => name === 'review_mentor_mfa_recovery')).toBe(false)
})

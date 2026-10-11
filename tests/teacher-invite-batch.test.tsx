// @vitest-environment jsdom
import { beforeEach, afterEach, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { SupabaseClient } from '@supabase/supabase-js'
import BetaInvitesPanel from '../src/components/BetaInvitesPanel'
import { betaAdminApi } from '../src/lib/admin-api'

vi.mock('../src/lib/admin-api', () => ({ betaAdminApi: vi.fn() }))
const api = vi.mocked(betaAdminApi)
let created = 0

beforeEach(() => {
  vi.clearAllMocks()
  created = 0
  api.mockImplementation(async (_client, action) => {
    if (action === 'invite.list') return { data: [] }
    if (action === 'invite.create') return { data: { access_code: `MELA-B-example-${++created}` } }
    throw new Error('Unexpected admin operation')
  })
})
afterEach(cleanup)

it('issues teacher codes only through the MFA-gated admin invite API after an operator click', async () => {
  render(<BetaInvitesPanel client={{} as SupabaseClient}/>)
  await screen.findByText('No beta invites created yet.')
  expect(api.mock.calls.filter(([,action]) => action === 'invite.create')).toHaveLength(0)
  fireEvent.change(screen.getByLabelText('Number of teacher invitation codes'), { target: { value: '5' } })
  fireEvent.click(screen.getByRole('button', { name: 'Generate teacher codes' }))
  await waitFor(() => expect(api.mock.calls.filter(([,action]) => action === 'invite.create')).toHaveLength(5))
  for (const [, action, params] of api.mock.calls.filter(([,a]) => a === 'invite.create')) {
    expect(action).toBe('invite.create')
    expect(params).toMatchObject({role:'teacher', expires_in_days:7})
  }
  const codes = screen.getByLabelText('New teacher invitation codes') as HTMLTextAreaElement
  expect(codes.readOnly).toBe(true)
  expect(codes.value.split('\n')).toHaveLength(5)
  expect(codes.value).toContain('MELA-B-example-5')
})

it('keeps already-created one-time codes visible when a later request fails', async () => {
  api.mockImplementation(async (_client, action) => {
    if (action === 'invite.list') return { data: [] }
    if (action === 'invite.create' && ++created <= 2) return { data: {access_code: `MELA-B-example-${created}`} }
    throw new Error('MFA session expired')
  })
  render(<BetaInvitesPanel client={{} as SupabaseClient}/>)
  await screen.findByText('No beta invites created yet.')
  fireEvent.click(screen.getByRole('button', { name: 'Generate teacher codes' }))
  await screen.findByRole('alert')
  expect(screen.getByRole('alert').textContent).toContain('2 teacher codes were generated')
  expect((screen.getByLabelText('New teacher invitation codes') as HTMLTextAreaElement).value.split('\n')).toHaveLength(2)
})

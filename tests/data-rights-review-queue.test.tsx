// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import DataRightsReviewQueue from '../src/components/DataRightsReviewQueue'

const mocks = vi.hoisted(() => ({
  assurance: vi.fn(),
  from: vi.fn(),
  select: vi.fn(),
  inStatus: vi.fn(),
  order: vi.fn(),
  limit: vi.fn(),
}))
const client = { auth: { mfa: { getAuthenticatorAssuranceLevel: mocks.assurance } },
  from: mocks.from } as any

beforeEach(() => {
  vi.resetAllMocks()
  mocks.assurance.mockResolvedValue({ data: { currentLevel: 'aal2' }, error: null })
  mocks.from.mockReturnValue({ select: mocks.select })
  mocks.select.mockReturnValue({ in: mocks.inStatus })
  mocks.inStatus.mockReturnValue({ order: mocks.order })
  mocks.order.mockReturnValue({ limit: mocks.limit })
  mocks.limit.mockResolvedValue({ data: [], error: null })
})
afterEach(cleanup)

describe('super-admin privacy request review queue', () => {
  it('fails closed before loading private records unless MFA is verified', async () => {
    mocks.assurance.mockResolvedValue({ data: { currentLevel: 'aal1' }, error: null })
    render(<DataRightsReviewQueue client={client} />)
    expect(await screen.findByRole('alert')).toHaveProperty('textContent', expect.stringMatching(/Authenticator verification is required/))
    expect(mocks.from).not.toHaveBeenCalled()
  })

  it('reads a bounded pending and in-review queue without mutating or closing requests', async () => {
    mocks.limit.mockResolvedValue({ data: [{
      id: 'abc12345-0000', user_id: 'private-user-01', request_type: 'erasure',
      status: 'pending', requested_at: '2026-11-02T00:00:00Z', updated_at: '2026-11-02T01:00:00Z',
      details: 'I would like a private deletion review.', response_notes: null,
    }], error: null })
    render(<DataRightsReviewQueue client={client} />)
    expect(await screen.findByText(/1 pending, 0 in review/i)).toBeTruthy()
    expect(mocks.from).toHaveBeenCalledWith('data_subject_requests')
    expect(mocks.inStatus).toHaveBeenCalledWith('status', ['pending', 'in_review'])
    expect(mocks.limit).toHaveBeenCalledWith(100)
    expect(screen.queryByRole('button', {name:/approve|delete|resolve|export/i})).toBeNull()
    fireEvent.click(screen.getByRole('button', {name:'Inspect privacy request abc12345'}))
    expect(screen.getByText('I would like a private deletion review.')).toBeTruthy()
  })

  it('escapes untrusted case notes and does not render executable HTML', async () => {
    const unsafe = '<script>bad()</script>'
    mocks.limit.mockResolvedValue({ data: [{
      id:'request000', user_id:'private000', request_type:'access', status:'in_review',
      requested_at:'2026-11-01T00:00:00Z', updated_at:'2026-11-02T00:00:00Z',
      details:unsafe, response_notes:null,
    }], error:null })
    const view = render(<DataRightsReviewQueue client={client}/>)
    fireEvent.click(await screen.findByRole('button', {name:'Inspect privacy request request0'}))
    expect(screen.getByText(unsafe)).toBeTruthy()
    expect(view.container.querySelector('script')).toBeNull()
  })

  it('reports database failures without falsely displaying an empty queue', async () => {
    mocks.limit.mockResolvedValue({ data:null,error:new Error('Privacy queue unavailable') })
    render(<DataRightsReviewQueue client={client}/>)
    expect(await screen.findByRole('alert')).toHaveProperty('textContent', expect.stringContaining('Privacy queue unavailable'))
    expect(screen.queryByText(/No pending or in-review privacy requests were returned/)).toBeNull()
  })
})

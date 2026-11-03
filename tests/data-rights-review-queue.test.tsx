// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import DataRightsReviewQueue from '../src/components/DataRightsReviewQueue'

const mocks = vi.hoisted(() => ({
  assurance: vi.fn(),
  from: vi.fn(),
  select: vi.fn(),
  inStatus: vi.fn(),
  order: vi.fn(),
  limit: vi.fn(),
  update: vi.fn(),
  updateEq: vi.fn(),
  updateResult: vi.fn(),
}))
const client = { auth: { mfa: { getAuthenticatorAssuranceLevel: mocks.assurance } },
  from: mocks.from } as any

const caseRow = {
  id: 'abc12345-0000', user_id: 'private-user-01', request_type: 'erasure',
  status: 'pending', requested_at: '2026-11-02T00:00:00Z', updated_at: '2026-11-02T01:00:00Z',
  details: 'I would like a private deletion review.', response_notes: null,
}
beforeEach(() => {
  vi.resetAllMocks()
  mocks.assurance.mockResolvedValue({ data: { currentLevel: 'aal2' }, error: null })
  const updateChain = {
    eq(column: string, value: unknown) {
      mocks.updateEq(column, value)
      return updateChain
    },
    select: () => ({ maybeSingle: mocks.updateResult }),
  }
  mocks.from.mockReturnValue({ select: mocks.select, update: mocks.update })
  mocks.select.mockReturnValue({ in: mocks.inStatus })
  mocks.inStatus.mockReturnValue({ order: mocks.order })
  mocks.order.mockReturnValue({ limit: mocks.limit })
  mocks.limit.mockResolvedValue({ data: [], error: null })
  mocks.update.mockReturnValue(updateChain)
  mocks.updateResult.mockResolvedValue({ data: {id: caseRow.id, status: 'in_review'}, error: null })
})
afterEach(cleanup)

describe('super-admin privacy request review queue', () => {
  it('fails closed before loading private records unless MFA is verified', async () => {
    mocks.assurance.mockResolvedValue({ data: { currentLevel: 'aal1' }, error: null })
    render(<DataRightsReviewQueue client={client} />)
    expect(await screen.findByRole('alert')).toHaveProperty('textContent', expect.stringMatching(/Authenticator verification is required/))
    expect(mocks.from).not.toHaveBeenCalled()
  })

  it('reads a bounded queue and does not provide deletion, export or resolution actions', async () => {
    mocks.limit.mockResolvedValue({ data: [caseRow], error: null })
    render(<DataRightsReviewQueue client={client} />)
    expect(await screen.findByText(/1 pending, 0 in review/i)).toBeTruthy()
    expect(mocks.from).toHaveBeenCalledWith('data_subject_requests')
    expect(mocks.inStatus).toHaveBeenCalledWith('status', ['pending', 'in_review'])
    expect(mocks.limit).toHaveBeenCalledWith(100)
    expect(screen.queryByRole('button', {name:/approve|delete|resolve|export/i})).toBeNull()
    fireEvent.click(screen.getByRole('button', {name:'Inspect privacy request abc12345'}))
    expect(screen.getByText('I would like a private deletion review.')).toBeTruthy()
    expect(screen.getByRole('button',{name:'Begin review (audited)'}).hasAttribute('disabled')).toBe(true)
    expect(mocks.update).not.toHaveBeenCalled()
  })

  it('requires confirmation, public note, MFA and stale-row protection to start review', async () => {
    mocks.limit.mockResolvedValue({ data: [caseRow], error: null })
    render(<DataRightsReviewQueue client={client} />)
    fireEvent.click(await screen.findByRole('button', {name:'Inspect privacy request abc12345'}))
    fireEvent.change(screen.getByLabelText(/Message to requester/), {target:{value:'Your request is under review; identity verification is still needed.'}})
    expect(screen.getByRole('button', {name:'Begin review (audited)'}).hasAttribute('disabled')).toBe(true)
    fireEvent.click(screen.getByRole('checkbox', {name:/I am authorized to begin review/}))
    fireEvent.click(screen.getByRole('button', {name:'Begin review (audited)'}))
    await waitFor(() => expect(mocks.update).toHaveBeenCalledWith({
      status:'in_review', response_notes:'Your request is under review; identity verification is still needed.',
    }))
    expect(mocks.updateEq).toHaveBeenCalledWith('id', caseRow.id)
    expect(mocks.updateEq).toHaveBeenCalledWith('status', 'pending')
    expect(mocks.updateEq).toHaveBeenCalledWith('updated_at', caseRow.updated_at)
    expect(await screen.findByText(/Review started and recorded/)).toBeTruthy()
  })

  it('never sends the update when MFA assurance expires', async () => {
    mocks.limit.mockResolvedValue({ data: [caseRow], error: null })
    mocks.assurance.mockResolvedValueOnce({data:{currentLevel:'aal2'},error:null})
      .mockResolvedValueOnce({data:{currentLevel:'aal1'},error:null})
    render(<DataRightsReviewQueue client={client} />)
    fireEvent.click(await screen.findByRole('button', {name:'Inspect privacy request abc12345'}))
    fireEvent.change(screen.getByLabelText(/Message to requester/), {target:{value:'A note to the requesting account for review.'}})
    fireEvent.click(screen.getByRole('checkbox', {name:/I am authorized to begin review/}))
    fireEvent.click(screen.getByRole('button', {name:'Begin review (audited)'}))
    expect(await screen.findByRole('alert')).toHaveProperty('textContent', expect.stringMatching(/Authenticator verification expired/))
    expect(mocks.update).not.toHaveBeenCalled()
  })

  it('does not claim a successful review if the request was modified concurrently', async () => {
    mocks.limit.mockResolvedValue({ data: [caseRow], error: null })
    mocks.updateResult.mockResolvedValue({data:null,error:null})
    render(<DataRightsReviewQueue client={client} />)
    fireEvent.click(await screen.findByRole('button', {name:'Inspect privacy request abc12345'}))
    fireEvent.change(screen.getByLabelText(/Message to requester/), {target:{value:'Your request will be reviewed after a separate identity check.'}})
    fireEvent.click(screen.getByRole('checkbox', {name:/I am authorized to begin review/}))
    fireEvent.click(screen.getByRole('button', {name:'Begin review (audited)'}))
    expect(await screen.findByRole('alert')).toHaveProperty('textContent', expect.stringMatching(/changed or was cancelled/))
    expect(screen.queryByText(/Review started and recorded/)).toBeNull()
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
  it('lets an MFA-verified assigned reviewer send a progress update while keeping the case open', async () => {
    const reviewed = {...caseRow, status:'in_review', response_notes:'Initial review is under way.'}
    mocks.limit.mockResolvedValue({data:[reviewed],error:null})
    render(<DataRightsReviewQueue client={client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Inspect privacy request abc12345'}))
    fireEvent.change(screen.getByLabelText(/Message to requester/), {
      target:{value:'We are still reviewing your request; no action has been taken yet.'},
    })
    fireEvent.click(screen.getByRole('checkbox',{name:/I am the assigned reviewer/}))
    fireEvent.click(screen.getByRole('button',{name:'Send review update (audited)'}))
    await waitFor(() => expect(mocks.update).toHaveBeenCalledWith({
      response_notes:'We are still reviewing your request; no action has been taken yet.',
    }))
    expect(mocks.updateEq).toHaveBeenCalledWith('id',caseRow.id)
    expect(mocks.updateEq).toHaveBeenCalledWith('status','in_review')
    expect(mocks.updateEq).toHaveBeenCalledWith('updated_at',caseRow.updated_at)
    expect(await screen.findByText(/Follow-up message recorded for the requester/)).toBeTruthy()
    expect(screen.queryByRole('button',{name:/complete request|delete personal data|reject request/i})).toBeNull()
  })

  it('rejects unchanged progress notes before any database write', async () => {
    const reviewed = {...caseRow, status:'in_review', response_notes:'Initial review is under way.'}
    mocks.limit.mockResolvedValue({data:[reviewed],error:null})
    render(<DataRightsReviewQueue client={client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Inspect privacy request abc12345'}))
    fireEvent.change(screen.getByLabelText(/Message to requester/), {
      target:{value:'Initial review is under way.'},
    })
    fireEvent.click(screen.getByRole('checkbox',{name:/I am the assigned reviewer/}))
    expect(screen.getByRole('button',{name:'Send review update (audited)'}).hasAttribute('disabled')).toBe(true)
    expect(mocks.update).not.toHaveBeenCalled()
  })

  it('fails closed if reviewer MFA expires before a follow-up message', async () => {
    const reviewed = {...caseRow, status:'in_review', response_notes:'Initial review is under way.'}
    mocks.limit.mockResolvedValue({data:[reviewed],error:null})
    mocks.assurance.mockResolvedValueOnce({data:{currentLevel:'aal2'},error:null})
      .mockResolvedValueOnce({data:{currentLevel:'aal1'},error:null})
    render(<DataRightsReviewQueue client={client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Inspect privacy request abc12345'}))
    fireEvent.change(screen.getByLabelText(/Message to requester/), {
      target:{value:'Please check back after identity verification has been completed.'},
    })
    fireEvent.click(screen.getByRole('checkbox',{name:/I am the assigned reviewer/}))
    fireEvent.click(screen.getByRole('button',{name:'Send review update (audited)'}))
    expect(await screen.findByRole('alert')).toHaveProperty('textContent',expect.stringMatching(/Authenticator verification expired/))
    expect(mocks.update).not.toHaveBeenCalled()
  })

})

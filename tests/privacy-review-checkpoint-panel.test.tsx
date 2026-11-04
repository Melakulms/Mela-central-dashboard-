// @vitest-environment jsdom
import { afterEach,beforeEach,describe,expect,it,vi } from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'

const mocks = vi.hoisted(() => ({
  mfa:vi.fn(),getUser:vi.fn(),from:vi.fn(),
  list:vi.fn(),insert:vi.fn(),insertResult:vi.fn(),
}))
const client = {
  auth: {mfa:{getAuthenticatorAssuranceLevel:mocks.mfa},getUser:mocks.getUser},
  from: (table:string) => {
    mocks.from(table)
    if(table !== 'privacy_review_checkpoints') throw new Error('Unexpected privacy table')
    return {
      select: () => ({
        eq: () => ({order: () => ({limit: () => mocks.list()})}),
      }),
      insert: (payload:unknown) => {
        mocks.insert(payload)
        return {select: () => ({maybeSingle:() => mocks.insertResult()})}
      },
    }
  },
} as any
import PrivacyReviewCheckpointPanel from '../src/components/PrivacyReviewCheckpointPanel'

beforeEach(()=>{
  vi.clearAllMocks()
  mocks.mfa.mockResolvedValue({data:{currentLevel:'aal2'},error:null})
  mocks.getUser.mockResolvedValue({data:{user:{id:'assigned-admin'}},error:null})
  mocks.list.mockResolvedValue({data:[],error:null})
  mocks.insertResult.mockResolvedValue({data:{id:'checkpoint-id'},error:null})
})
afterEach(cleanup)

describe('Restricted privacy-review observations',()=>{
  it('fails closed without MFA before reading restricted evidence',async()=>{
    mocks.mfa.mockResolvedValue({data:{currentLevel:'aal1'},error:null})
    render(<PrivacyReviewCheckpointPanel client={client} requestId="request-id" assignedReviewerId="assigned-admin"/>)
    expect(await screen.findByRole('alert')).toHaveProperty('textContent',expect.stringMatching(/Authenticator verification is required/))
    expect(mocks.from).not.toHaveBeenCalled()
    expect(mocks.insert).not.toHaveBeenCalled()
  })

  it('lets a different super administrator read but not write an assigned case',async()=>{
    mocks.getUser.mockResolvedValue({data:{user:{id:'different-admin'}},error:null})
    render(<PrivacyReviewCheckpointPanel client={client} requestId="request-id" assignedReviewerId="assigned-admin"/>)
    expect(await screen.findByText(/Only the assigned reviewer/)).toBeTruthy()
    expect(screen.queryByRole('button',{name:'Record checkpoint (audited)'})).toBeNull()
    expect(mocks.insert).not.toHaveBeenCalled()
  })

  it('requires explicit attestation and saves only structured observations',async()=>{
    render(<PrivacyReviewCheckpointPanel client={client} requestId="request-id" assignedReviewerId="assigned-admin"/>)
    const btn=await screen.findByRole('button',{name:'Record checkpoint (audited)'})
    expect(btn.hasAttribute('disabled')).toBe(true)
    fireEvent.change(screen.getByLabelText(/Review checkpoint/),{target:{value:'guardian_authority'}})
    fireEvent.change(screen.getByLabelText(/Recorded observation/),{target:{value:'needs_follow_up'}})
    fireEvent.click(screen.getByRole('checkbox',{name:/I personally assessed/}))
    fireEvent.click(btn)
    await waitFor(()=>expect(mocks.insert).toHaveBeenCalledWith({
      request_id:'request-id',reviewer_id:'assigned-admin',
      checkpoint:'guardian_authority',finding:'needs_follow_up',
    }))
    expect(await screen.findByText(/Checkpoint observation recorded/)).toBeTruthy()
    expect(screen.queryByRole('button',{name:/complete|delete|approve/i})).toBeNull()
    expect(screen.queryAllByRole('textbox').every(input => (input as HTMLTextAreaElement).readOnly)).toBe(true)
  })

  it('re-verifies MFA immediately before submission and denies downgraded sessions',async()=>{
    mocks.mfa.mockResolvedValueOnce({data:{currentLevel:'aal2'},error:null})
      .mockResolvedValueOnce({data:{currentLevel:'aal1'},error:null})
    render(<PrivacyReviewCheckpointPanel client={client} requestId="request-id" assignedReviewerId="assigned-admin"/>)
    const btn=await screen.findByRole('button',{name:'Record checkpoint (audited)'})
    fireEvent.click(screen.getByRole('checkbox',{name:/I personally assessed/}))
    fireEvent.click(btn)
    expect(await screen.findByRole('alert')).toHaveProperty('textContent',expect.stringMatching(/Authenticator verification expired/))
    expect(mocks.insert).not.toHaveBeenCalled()
  })

  it('does not claim recording if database returned no inserted checkpoint',async()=>{
    mocks.insertResult.mockResolvedValue({data:null,error:null})
    render(<PrivacyReviewCheckpointPanel client={client} requestId="request-id" assignedReviewerId="assigned-admin"/>)
    const btn=await screen.findByRole('button',{name:'Record checkpoint (audited)'})
    fireEvent.click(screen.getByRole('checkbox',{name:/I personally assessed/}))
    fireEvent.click(btn)
    expect(await screen.findByRole('alert')).toHaveProperty('textContent',expect.stringMatching(/No checkpoint was recorded/))
    expect(screen.queryByText(/Checkpoint observation recorded with an audit entry/)).toBeNull()
  })

  it('shows the latest finding and recorded time, without treating it as legal approval',async()=>{
    mocks.list.mockResolvedValue({data:[{
      id:'entry',checkpoint:'requester_identity',finding:'needs_follow_up',
      recorded_at:'2026-11-03T12:00:00Z',reviewer_id:'assigned-admin',
    }],error:null})
    render(<PrivacyReviewCheckpointPanel client={client} requestId="request-id" assignedReviewerId="assigned-admin"/>)
    expect(await screen.findByText(/1 of 6 categories appear in the latest loaded observations/)).toBeTruthy()
    expect(screen.getByText(/An entry does not mean the related legal requirement is satisfied/)).toBeTruthy()
    expect(screen.getAllByText(/Needs additional verification or action/).length).toBeGreaterThan(0)
  })
  it('offers an explicitly non-certifying, private redacted handoff for counsel',async()=>{
    const writeText=vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText}})
    mocks.list.mockResolvedValue({data:[{
      id:'case-observation-1',checkpoint:'requester_identity',
      finding:'needs_follow_up',recorded_at:'2026-11-03T12:00:00Z',
      reviewer_id:'assigned-admin',response_notes:'NEVER-SHARE-PRIVATE-NOTE',
    }],error:null})
    const view=render(<PrivacyReviewCheckpointPanel
      client={client} requestId="case-reference-1" requestType="access"
      assignedReviewerId="assigned-admin"/>)
    await screen.findByText(/1 of 6 categories appear/)
    fireEvent.click(screen.getByText('Redacted case handoff for authorized legal review'))
    const summary=view.container.querySelector('textarea#privacy-case-handoff-summary') as HTMLTextAreaElement
    expect(summary.value).toContain('Request reference: case-reference-1')
    expect(summary.value).toContain('1 of 6 categories')
    expect(summary.value).toContain('ALWAYS BLOCK FINAL DECISION')
    expect(summary.value).not.toContain('NEVER-SHARE-PRIVATE-NOTE')
    fireEvent.click(screen.getByRole('button',{name:'Copy redacted handoff'}))
    await waitFor(()=>expect(writeText).toHaveBeenCalledWith(summary.value))
    expect(await screen.findByText(/Redacted summary copied/)).toBeTruthy()
    Object.defineProperty(navigator,'clipboard',{configurable:true,value:undefined})
  })

  it('makes read-only data mapping and retention gates accessible without exposing a fulfillment action',async()=>{
    render(<PrivacyReviewCheckpointPanel client={client} requestId="case-1" assignedReviewerId="assigned-admin"/>)
    await screen.findByText(/of 6 categories appear in the latest loaded observations/)
    fireEvent.click(screen.getByText('Data footprint for export/deletion (read-only, not case evidence)'))
    const link=screen.getByRole('link',{name:'View the data map and mandatory fulfillment gates'})
    expect(link.getAttribute('href')).toContain('PRIVACY_DATA_FOOTPRINT_AND_FULFILLMENT_GATES_2026-11-04.md')
    expect(link.getAttribute('rel')).toContain('noopener')
    expect(screen.getByText(/308 application database tables/)).toBeTruthy()
    expect(screen.getByText(/Do not delete a profile to fulfill a privacy request/)).toBeTruthy()
    expect(screen.queryByRole('button',{name:/export personal|erase account|complete request/i})).toBeNull()
    expect(mocks.from).toHaveBeenCalledWith('privacy_review_checkpoints')
    expect(mocks.insert).not.toHaveBeenCalled()
  })

})

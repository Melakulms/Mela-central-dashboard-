import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import PassportVerificationReviewPanel from '../src/components/PassportVerificationReviewPanel'
const rpc=vi.fn()
const client={rpc} as any
const row={id:'review-id',record_kind:'education',record_id:'claim',user_id:'learner',
  record_name:'Local School',record_details:'Math',applicant_note:'Please verify',
  requested_at:'2026-10-26T10:00:00Z'}
beforeEach(()=>{vi.resetAllMocks();rpc.mockResolvedValue({data:[row],error:null})})
afterEach(cleanup)
it('loads the private queue and refuses approval without source and feedback',async()=>{
  render(<PassportVerificationReviewPanel client={client}/>)
  fireEvent.click(await screen.findByText('Review claim'))
  fireEvent.change(screen.getByLabelText('Review decision'),{target:{value:'approved'}})
  expect((screen.getByText('Confirm passport decision') as HTMLButtonElement).disabled).toBe(true)
  fireEvent.change(screen.getByLabelText('Independent verification source'),{target:{value:'School registrar independently confirmed'}})
  fireEvent.change(screen.getByLabelText('Review feedback (10–1500 characters)'),{target:{value:'Independent evidence reviewed by administrator.'}})
  expect((screen.getByText('Confirm passport decision') as HTMLButtonElement).disabled).toBe(false)
})
it('reports saved server decisions and does not claim local approval',async()=>{
  rpc.mockResolvedValueOnce({data:[row],error:null})
    .mockResolvedValueOnce({data:'rejected',error:null})
    .mockResolvedValueOnce({data:[],error:null})
  render(<PassportVerificationReviewPanel client={client}/>)
  fireEvent.click(await screen.findByText('Review claim'))
  fireEvent.change(screen.getByLabelText('Review feedback (10–1500 characters)'),{target:{value:'Need independent institutional evidence.'}})
  fireEvent.click(screen.getByText('Confirm passport decision'))
  await screen.findByText('Verification decision saved with an audit log and learner notification.')
  expect(rpc).toHaveBeenCalledWith('review_passport_verification_request',expect.objectContaining({p_request_id:'review-id',p_decision:'rejected'}))
})
it('fails closed on MFA access errors',async()=>{
  rpc.mockResolvedValueOnce({data:null,error:new Error('MFA required')})
  render(<PassportVerificationReviewPanel client={client}/>)
  await screen.findByText('MFA required')
  expect(screen.queryByText('Review claim')).toBeNull()
})

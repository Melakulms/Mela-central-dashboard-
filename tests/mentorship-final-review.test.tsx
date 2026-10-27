// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { SupabaseClient } from '@supabase/supabase-js'
import MentorshipFinalReviewPanel from '../src/components/MentorshipFinalReviewPanel'

const candidate = {
  id: 'application-1',
  applicant_id: 'applicant-1',
  headline: 'University mathematics instructor',
  expertise: ['Mathematics'],
  background: 'I have independently documented teaching experience.',
  review_notes: 'Eligibility reviewed. Further verification required.',
  reviewed_at: '2026-10-27T00:00:00Z',
}

function clientFixture() {
  const rpc = vi.fn().mockResolvedValue({ data: 'applicant-1', error: null })
  const getUser = vi.fn().mockResolvedValue({ data: {user:{id:'admin-1'}}, error:null })
  const from = vi.fn((name: string) => {
    if (name === 'mentorship_applications') return {
      select: () => ({
        eq: () => ({ order: () => ({
          limit: async () => ({ data:[candidate], error:null }),
        }) }),
      }),
    }
    if (name === 'mentor_profiles') return {
      select: () => ({
        in: () => ({ eq: async () => ({ data:[],error:null }) }),
      }),
    }
    throw new Error('Unexpected table requested: ' + name)
  })
  const client = { auth:{getUser}, from, rpc } as unknown as SupabaseClient
  return { client,rpc,getUser }
}
afterEach(cleanup)

describe('final mentor credential review', () => {
  it('does not submit approval before independent checks and evidence notes', async () => {
    const fixture = clientFixture()
    render(<MentorshipFinalReviewPanel client={fixture.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Verify credentials'}))
    const submit = screen.getByRole('button',{name:'Complete final mentor verification'})
    expect((submit as HTMLButtonElement).disabled).toBe(true)
    fireEvent.click(submit)
    expect(fixture.rpc).not.toHaveBeenCalled()
  })

  it('passes only explicitly reviewed evidence to the guarded server action', async () => {
    const fixture = clientFixture()
    render(<MentorshipFinalReviewPanel client={fixture.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Verify credentials'}))
    fireEvent.click(screen.getByLabelText(/I inspected independently verified professional/))
    fireEvent.click(screen.getByLabelText(/I performed and documented the required safeguarding review/))
    fireEvent.change(screen.getByLabelText(/Evidence reference, verification method/),{
      target:{ value:'Verified the original educator credential with its issuer; safeguarding review was completed by an authorized administrator.' },
    })
    fireEvent.click(screen.getByRole('button',{name:'Complete final mentor verification'}))
    await waitFor(()=>expect(fixture.rpc).toHaveBeenCalledTimes(1))
    expect(fixture.rpc).toHaveBeenCalledWith('finalize_mentorship_verification',{
      p_application_id:'application-1',p_credential_reviewed:true,
      p_safeguarding_reviewed:true,
      p_review_notes:'Verified the original educator credential with its issuer; safeguarding review was completed by an authorized administrator.',
    })
    expect(await screen.findByText(/Independently verified mentor profile activated/)).toBeTruthy()
  })

  it('does not show false success if the database rejects unverified evidence', async () => {
    const fixture=clientFixture()
    fixture.rpc.mockResolvedValueOnce({data:null,error:{message:'an independently verified credential record is required'}})
    render(<MentorshipFinalReviewPanel client={fixture.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Verify credentials'}))
    fireEvent.click(screen.getByLabelText(/I inspected independently verified professional/))
    fireEvent.click(screen.getByLabelText(/I performed and documented the required safeguarding review/))
    fireEvent.change(screen.getByLabelText(/Evidence reference, verification method/),{
      target:{value:'The candidate supplied materials, but database evidence is not yet independently verified.'},
    })
    fireEvent.click(screen.getByRole('button',{name:'Complete final mentor verification'}))
    const message=await screen.findByRole('alert')
    expect(message.textContent).toContain('independently verified credential record')
    expect(screen.queryByText(/Independently verified mentor profile activated/)).toBeNull()
  })
})

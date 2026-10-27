// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { SupabaseClient } from '@supabase/supabase-js'
import MentorshipAdultAgeReviewPanel from '../src/components/MentorshipAdultAgeReviewPanel'

function fixture() {
  const update=vi.fn().mockReturnValue({
    eq:()=>({eq:()=>({select:async()=>({data:[{id:'review-1'}],error:null})})}),
  })
  const from=vi.fn().mockReturnValue({
    select:()=>({eq:()=>({order:()=>({limit:async()=>({data:[{
      id:'review-1',learner_id:'learner-1',claimed_date_of_birth:'1990-01-01',
      status:'pending',created_at:'2026-10-27T00:00:00Z',
    }],error:null})})})}),
    update,
  })
  return {client:{from,auth:{getUser:async()=>({data:{user:{id:'admin-1'}},error:null})}} as unknown as SupabaseClient,update}
}
afterEach(cleanup)

describe('Mentorship administrator adult age review',()=>{
  it('does not approve a claimed age without independent evidence confirmation',async()=>{
    const f=fixture()
    render(<MentorshipAdultAgeReviewPanel client={f.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Review privately'}))
    const approve=screen.getByRole('button',{name:'Approve verified adult'})
    expect((approve as HTMLButtonElement).disabled).toBe(true)
    fireEvent.change(screen.getByLabelText(/Evidence source, verification method/),{
      target:{value:'Only the learner declaration exists; no independent evidence was checked.'},
    })
    expect((approve as HTMLButtonElement).disabled).toBe(true)
    expect(f.update).not.toHaveBeenCalled()
  })
  it('records review only with evidence consent and signed-in administrator',async()=>{
    const f=fixture()
    render(<MentorshipAdultAgeReviewPanel client={f.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Review privately'}))
    fireEvent.click(screen.getByLabelText(/I independently checked the learner's age/))
    fireEvent.change(screen.getByLabelText(/Evidence source, verification method/),{
      target:{value:'Checked a valid approved proof of age with the issuing authority and confirmed the adult age claim.'},
    })
    fireEvent.click(screen.getByRole('button',{name:'Approve verified adult'}))
    await waitFor(()=>expect(f.update).toHaveBeenCalledTimes(1))
    expect(f.update.mock.calls[0][0]).toMatchObject({
      status:'approved',reviewer_id:'admin-1',reviewer_notes:'Checked a valid approved proof of age with the issuing authority and confirmed the adult age claim.',
    })
    expect(await screen.findByText(/Adult mentorship eligibility recorded after review/)).toBeTruthy()
  })
})

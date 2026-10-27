// @vitest-environment jsdom
import {afterEach,describe,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import type {SupabaseClient} from '@supabase/supabase-js'
import MentorshipIndependentOutcomePanel from '../src/components/MentorshipIndependentOutcomePanel'

afterEach(cleanup)
const claims=[{
 id:'claim-1',learner_id:'learner-1',mentor_id:'mentor-1',category:'career',
 outcome_text:'I created a complete CV with professional guidance.',
 review_notes:'I inspected the learner work and it meets learning objectives.',
 status:'mentor_supported',created_at:'2026-10-26T10:00:00Z',
}]
function fixture(denied=false){
 const insert=vi.fn().mockReturnValue({select:async()=>denied
  ? {data:null,error:{message:'MFA independent evidence reviewer required'}}
  : {data:[{claim_id:'claim-1'}],error:null}})
 const from=vi.fn((table:string)=>({
  select:()=>({
   eq:()=>({order:()=>({limit:async()=>({data:claims,error:null})})}),
   order:()=>({limit:async()=>({data:table==='mentorship_outcome_verifications'?[]:claims,error:null})}),
  }),
  insert,
 }))
 return {client:{
  auth:{getUser:async()=>({data:{user:{id:'admin-1'}},error:null})},from,
 } as unknown as SupabaseClient,insert}
}
describe('MFA independent mentorship outcome review',()=>{
 it('requires reviewer evidence and explicit consent',async()=>{
  const f=fixture()
  render(<MentorshipIndependentOutcomePanel client={f.client}/>)
  fireEvent.click(await screen.findByRole('button',{name:'Independently review'}))
  const save=screen.getByRole('button',{name:'Record independent decision'}) as HTMLButtonElement
  expect(save.disabled).toBe(true)
  fireEvent.change(screen.getByLabelText(/Participant-visible independent evidence/),{
   target:{value:'I reviewed the supporting evidence independently, and the outcome is grounded in actual work.'},
  })
  expect(save.disabled).toBe(true)
  expect(f.insert).not.toHaveBeenCalled()
 })
 it('submits an independent narrative decision, not a Career Passport award',async()=>{
  const f=fixture()
  render(<MentorshipIndependentOutcomePanel client={f.client}/>)
  fireEvent.click(await screen.findByRole('button',{name:'Independently review'}))
  fireEvent.change(screen.getByLabelText('Evidence decision'),{target:{value:'evidence_rejected'}})
  fireEvent.change(screen.getByLabelText(/Participant-visible independent evidence/),{
   target:{value:'Evidence reviewed independently did not establish the learning outcome described by the applicant.'},
  })
  fireEvent.click(screen.getByLabelText(/I independently examined appropriate evidence/))
  fireEvent.click(screen.getByRole('button',{name:'Record independent decision'}))
  await waitFor(()=>expect(f.insert).toHaveBeenCalledTimes(1))
  expect(f.insert.mock.calls[0][0]).toMatchObject({
    claim_id:'claim-1',decision:'evidence_rejected',reviewed_by:'admin-1',
  })
  expect(await screen.findByText(/No certificate or Career Passport award was issued/)).toBeTruthy()
 })
 it('reports MFA rejection instead of claiming independent verification',async()=>{
  const f=fixture(true)
  render(<MentorshipIndependentOutcomePanel client={f.client}/>)
  fireEvent.click(await screen.findByRole('button',{name:'Independently review'}))
  fireEvent.change(screen.getByLabelText(/Participant-visible independent evidence/),{
   target:{value:'Independent proof was examined and the program record requires a separate administration decision.'},
  })
  fireEvent.click(screen.getByLabelText(/I independently examined appropriate evidence/))
  fireEvent.click(screen.getByRole('button',{name:'Record independent decision'}))
  expect((await screen.findByRole('alert')).textContent).toContain('MFA independent')
  expect(screen.queryByText(/Independent evidence decision recorded and audited/)).toBeNull()
 })
})

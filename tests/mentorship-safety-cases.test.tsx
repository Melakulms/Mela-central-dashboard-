// @vitest-environment jsdom
import { afterEach,describe,expect,it,vi } from 'vitest'
import { cleanup,fireEvent,render,screen,waitFor } from '@testing-library/react'
import type { SupabaseClient } from '@supabase/supabase-js'
import MentorshipSafetyCasesPanel from '../src/components/MentorshipSafetyCasesPanel'

function fixture(){
 const rpc=vi.fn().mockResolvedValue({data:true,error:null})
 const from=vi.fn().mockReturnValue({
  select:()=>({in:()=>({order:()=>({limit:async()=>({
    data:[{id:'case-1',reporter_id:'learner-1',target_type:'mentorship_request',
      target_id:'request-1',reason:'Harassment or threats',
      details:'An inappropriate request requires investigation.',status:'open',
      created_at:'2026-10-27T10:00:00Z',assigned_to:null,resolution_notes:null}],
    error:null,
  })})})}),
 })
 return {client:{from,rpc} as unknown as SupabaseClient,rpc}
}
afterEach(cleanup)
describe('MFA mentorship case triage',()=>{
 it('requires documented evidence before closing and avoids automatic mentor suspensions',async()=>{
  const f=fixture()
  render(<MentorshipSafetyCasesPanel client={f.client}/>)
  fireEvent.click(await screen.findByRole('button',{name:'Review case'}))
  fireEvent.change(screen.getByLabelText('Decision'),{target:{value:'resolved'}})
  const submit=screen.getByRole('button',{name:'Record reviewed decision'}) as HTMLButtonElement
  expect(submit.disabled).toBe(true)
  expect(f.rpc).not.toHaveBeenCalled()
 })
 it('calls the MFA-protected report review function for an authorized decision',async()=>{
  const f=fixture()
  render(<MentorshipSafetyCasesPanel client={f.client}/>)
  fireEvent.click(await screen.findByRole('button',{name:'Review case'}))
  fireEvent.change(screen.getByLabelText('Decision'),{target:{value:'resolved'}})
  fireEvent.change(screen.getByLabelText(/Case review notes/),{
    target:{value:'Reviewed the incident details with the safeguarding team and documented the resolution.'},
  })
  fireEvent.click(screen.getByRole('button',{name:'Record reviewed decision'}))
  await waitFor(()=>expect(f.rpc).toHaveBeenCalledTimes(1))
  expect(f.rpc).toHaveBeenCalledWith('review_mentorship_concern',{
    p_case_id:'case-1',p_status:'resolved',
    p_resolution_notes:'Reviewed the incident details with the safeguarding team and documented the resolution.',
  })
  expect(await screen.findByText(/Mentorship safety case updated/)).toBeTruthy()
 })
 it('surfaces MFA denial instead of pretending the concern is closed',async()=>{
  const f=fixture()
  f.rpc.mockResolvedValueOnce({data:null,error:{message:'MFA-verified safety administrator required'}})
  render(<MentorshipSafetyCasesPanel client={f.client}/>)
  fireEvent.click(await screen.findByRole('button',{name:'Review case'}))
  fireEvent.change(screen.getByLabelText('Decision'),{target:{value:'resolved'}})
  fireEvent.change(screen.getByLabelText(/Case review notes/),{
    target:{value:'Investigated and retained documentation, but server authorization was not granted.'},
  })
  fireEvent.click(screen.getByRole('button',{name:'Record reviewed decision'}))
  expect((await screen.findByRole('alert')).textContent).toContain('MFA-verified')
  expect(screen.queryByText(/Mentorship safety case updated/)).toBeNull()
 })
})

it('does not attach a delayed history response to another selected case',async()=>{
 let resolveHistory!: (value: unknown)=>void
 const rpc=vi.fn().mockImplementation(()=>new Promise(resolve=>{resolveHistory=resolve}))
 const records=['First concern','Second concern'].map((reason,index)=>({
   id:'case-'+index,reporter_id:'learner-'+index,target_type:'mentorship_request',target_id:'r-'+index,
   reason,details:'Concern details',status:'open',created_at:'2026-10-27T10:00:00Z',
 }))
 const from=vi.fn().mockReturnValue({select:()=>({in:()=>({order:()=>({limit:async()=>({data:records,error:null})})})})})
 render(<MentorshipSafetyCasesPanel client={{from,rpc} as unknown as SupabaseClient}/>)
 const buttons=await screen.findAllByRole('button',{name:'Review case'})
 fireEvent.click(buttons[0])
 fireEvent.click(screen.getByRole('button',{name:'View confidential review history'}))
 fireEvent.click(buttons[1])
 resolveHistory({data:[{decision:'reviewing',notes:'Private first-case evidence',created_at:'2026-10-27'}],error:null})
 await waitFor(()=>expect(screen.getByRole('button',{name:'View confidential review history'})).toBeTruthy())
 expect(screen.queryByText('Private first-case evidence')).toBeNull()
 expect(screen.getByText('Safeguarding review — Second concern')).toBeTruthy()
})

it('clears confidential case views when refresh access is denied',async()=>{
 let denied=false
 const from=vi.fn().mockReturnValue({select:()=>({in:()=>({order:()=>({limit:async()=>denied
   ? {data:null,error:{message:'MFA required'}}
   : {data:[{id:'case',reason:'Private concern',details:'Private learner details',status:'open',created_at:'2026-10-27',target_type:'mentorship_request'}],error:null}
 })})})})
 render(<MentorshipSafetyCasesPanel client={{from,rpc:vi.fn()} as unknown as SupabaseClient}/>)
 fireEvent.click(await screen.findByRole('button',{name:'Review case'}))
 expect(screen.getByText(/Private learner details/)).toBeTruthy()
 denied=true
 fireEvent.click(screen.getByRole('button',{name:'Refresh safety cases'}))
 await screen.findByRole('alert')
 expect(screen.queryByText(/Private learner details/)).toBeNull()
 expect(screen.queryByRole('button',{name:'Review case'})).toBeNull()
 expect(screen.queryByText('No mentorship-specific safety cases have been submitted.')).toBeNull()
})

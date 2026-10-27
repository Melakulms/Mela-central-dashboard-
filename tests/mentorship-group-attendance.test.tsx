// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { SupabaseClient } from '@supabase/supabase-js'
import MentorshipGroupAttendancePanel from '../src/components/MentorshipGroupAttendancePanel'

afterEach(cleanup)

function fixture(denied=false) {
  const groups = [{id:'group-1',title:'Adult career group',starts_at:'2020-01-01T10:00:00Z',status:'published'}]
  const interests = [{id:'interest-1',group_id:'group-1',learner_id:'learner-1',status:'approved'}]
  const insert = vi.fn().mockReturnValue({select:async()=>denied
    ? {data:null,error:{message:'MFA administrator required to record group attendance'}}
    : {data:[{interest_id:'interest-1'}],error:null}})
  const from = vi.fn((table:string)=>({
    select:()=>({
      eq:()=>({order:()=>({limit:async()=>({data:interests,error:null})})}),
      order:()=>({limit:async()=>({data:table==='mentorship_groups'?groups:[],error:null})}),
    }),
    insert,
  }))
  return {client:{
    auth:{getUser:async()=>({data:{user:{id:'admin-1'}},error:null})},from,
  } as unknown as SupabaseClient,insert}
}

describe('Manual group attendance safeguarding',()=>{
  it('does not record without meaningful evidence and explicit confirmation',async()=>{
    const f=fixture()
    render(<MentorshipGroupAttendancePanel client={f.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Review attendance'}))
    const save=screen.getByRole('button',{name:'Save audited attendance report'}) as HTMLButtonElement
    expect(save.disabled).toBe(true)
    fireEvent.change(screen.getByLabelText(/Evidence explanation visible/),{
      target:{value:'Independently checked written attendance record with the facilitator.'},
    })
    expect(save.disabled).toBe(true)
    expect(f.insert).not.toHaveBeenCalled()
  })
  it('records an audited manual report only on explicit review',async()=>{
    const f=fixture()
    render(<MentorshipGroupAttendancePanel client={f.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Review attendance'}))
    fireEvent.change(screen.getByLabelText('Reported outcome'),{target:{value:'reported_absent'}})
    fireEvent.change(screen.getByLabelText(/Evidence explanation visible/),{
      target:{value:'Reviewed the approved group attendance log following the scheduled date.'},
    })
    fireEvent.click(screen.getByLabelText(/I independently reviewed attendance evidence/))
    fireEvent.click(screen.getByRole('button',{name:'Save audited attendance report'}))
    await waitFor(()=>expect(f.insert).toHaveBeenCalledTimes(1))
    expect(f.insert.mock.calls[0][0]).toMatchObject({
      interest_id:'interest-1',status:'reported_absent',recorded_by:'admin-1',
    })
    expect(await screen.findByText(/not an independently verified certificate/)).toBeTruthy()
  })
  it('surfaces server-side MFA denial rather than claiming success',async()=>{
    const f=fixture(true)
    render(<MentorshipGroupAttendancePanel client={f.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Review attendance'}))
    fireEvent.change(screen.getByLabelText(/Evidence explanation visible/),{
      target:{value:'An approved program record was inspected with supporting evidence.'},
    })
    fireEvent.click(screen.getByLabelText(/I independently reviewed attendance evidence/))
    fireEvent.click(screen.getByRole('button',{name:'Save audited attendance report'}))
    expect((await screen.findByRole('alert')).textContent).toContain('MFA administrator required')
    expect(screen.queryByText(/Attendance report recorded and audited/)).toBeNull()
  })
})

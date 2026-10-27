// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { SupabaseClient } from '@supabase/supabase-js'
import MentorshipSafeguardingPanel from '../src/components/MentorshipSafeguardingPanel'

const mentor = {
  user_id:'verified-mentor-1',headline:'Verified teaching mentor',
  organization:'University program',verified:true,active:true,
}
function fixture() {
  const rpc=vi.fn().mockResolvedValue({data:true,error:null})
  const from=vi.fn().mockReturnValue({
    select:()=>({eq:()=>({eq:()=>({order:()=>({
      limit:async()=>({data:[mentor],error:null}),
    })})})}),
  })
  return {client:{from,rpc} as unknown as SupabaseClient,rpc}
}
afterEach(cleanup)

describe('mentor safeguarding suspension review',()=>{
  it('blocks approval without an explicit irreversible-action acknowledgement and case reason',async()=>{
    const f=fixture()
    render(<MentorshipSafeguardingPanel client={f.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Safeguarding suspension'}))
    const confirm=screen.getByRole('button',{name:'Confirm mentor suspension'})
    expect((confirm as HTMLButtonElement).disabled).toBe(true)
    fireEvent.click(confirm)
    expect(f.rpc).not.toHaveBeenCalled()
  })

  it('calls the MFA-restricted backend and only reports completion on success',async()=>{
    const f=fixture()
    render(<MentorshipSafeguardingPanel client={f.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Safeguarding suspension'}))
    fireEvent.change(screen.getByLabelText('Reason and case reference'),{
      target:{value:'Safeguarding case CASE-2026-01: moderator reviewed credible policy concerns.'},
    })
    fireEvent.click(screen.getByLabelText(/I understand that future sessions will be cancelled/))
    fireEvent.click(screen.getByRole('button',{name:'Confirm mentor suspension'}))
    await waitFor(()=>expect(f.rpc).toHaveBeenCalledTimes(1))
    expect(f.rpc).toHaveBeenCalledWith('suspend_mentorship_mentor',{
      p_mentor_id:'verified-mentor-1',
      p_reason:'Safeguarding case CASE-2026-01: moderator reviewed credible policy concerns.',
    })
    expect(await screen.findByText(/Mentor suspended. Future scheduled sessions were cancelled/)).toBeTruthy()
  })

  it('reports server denial rather than claiming suspension',async()=>{
    const f=fixture()
    f.rpc.mockResolvedValueOnce({data:null,error:{message:'MFA administrator required to suspend mentor'}})
    render(<MentorshipSafeguardingPanel client={f.client}/>)
    fireEvent.click(await screen.findByRole('button',{name:'Safeguarding suspension'}))
    fireEvent.change(screen.getByLabelText('Reason and case reference'),{
      target:{value:'Safeguarding case CASE-2026-02: urgent reviewed concern for this mentor.'},
    })
    fireEvent.click(screen.getByLabelText(/I understand that future sessions will be cancelled/))
    fireEvent.click(screen.getByRole('button',{name:'Confirm mentor suspension'}))
    expect((await screen.findByRole('alert')).textContent).toContain('MFA administrator required')
    expect(screen.queryByText(/Mentor suspended. Future scheduled sessions were cancelled/)).toBeNull()
  })
})

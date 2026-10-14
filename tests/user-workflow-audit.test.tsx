// @vitest-environment jsdom
import React from 'react'
import {afterEach,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import UserWorkflowAudit from '../src/components/UserWorkflowAudit'
afterEach(cleanup)
it('shows additional historical workflow audit entries separately from admin privileged audit',async()=>{
 const rows=[{id:'audit-1',actor_id:'user-a',action:'complete_profile_v37',entity_id:null,entity_type:'profile',created_at:'2026-10-13T12:00:00Z',details:{stage:'Grade 7'}}]
 const range=vi.fn().mockResolvedValue({data:rows,error:null,count:70})
 const client={from:vi.fn(()=>({select:()=>({order:()=>({range})})}))} as any
 render(<UserWorkflowAudit client={client}/>)
 expect(await screen.findByText('70 workflow audit entries')).toBeTruthy()
 expect(screen.getByText('complete_profile_v37')).toBeTruthy()
 fireEvent.click(screen.getByRole('button',{name:'Inspect workflow audit-1'}))
 expect(screen.getByText('Actor: user-a')).toBeTruthy()
 fireEvent.click(screen.getByRole('button',{name:'Next workflow records'}))
 await waitFor(()=>expect(range).toHaveBeenCalledWith(25,49))
})
it('shows a visible permission or networking error and does not suggest all records were empty',async()=>{
 const client={from:()=>({select:()=>({order:()=>({range:async()=>({data:null,error:new Error('Access denied'),count:null})})})})} as any
 render(<UserWorkflowAudit client={client}/>)
 expect(await screen.findByRole('alert')).toHaveProperty('textContent','Access denied')
 expect(screen.queryByText('No workflow entries.')).toBeNull()
})

// @vitest-environment jsdom
import {afterEach,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import type {SupabaseClient} from '@supabase/supabase-js'
import AICourseAssignments from '../src/components/AICourseAssignments'
afterEach(cleanup)
it('assigns one selected course to the selected verified teacher',async()=>{
 const rpc=vi.fn(async(name:string)=>({data:name==='get_ai_course_assignments_admin_v1'?[{course_id:'c1',title:'AI Fundamentals',active:false}]:null,error:null}))
 render(<AICourseAssignments client={{rpc} as unknown as SupabaseClient} userId="teacher-1"/>)
 fireEvent.click(await screen.findByRole('button',{name:'Assign course'}))
 await waitFor(()=>expect(rpc).toHaveBeenCalledWith('assign_ai_course_reviewer_v1',{p_course_id:'c1',p_user_id:'teacher-1',p_active:true}))
})
it('does not claim success when the server denies assignment access',async()=>{
 const rpc=vi.fn(async()=>({data:null,error:{message:'MFA-protected administrator access required'}}))
 render(<AICourseAssignments client={{rpc} as unknown as SupabaseClient} userId="teacher-1"/>)
 expect(await screen.findByRole('alert')).toBeTruthy()
 expect(screen.queryByRole('button',{name:'Assign course'})).toBeNull()
})

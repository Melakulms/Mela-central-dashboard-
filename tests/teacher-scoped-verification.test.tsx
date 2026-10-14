// @vitest-environment jsdom
import React from 'react'
import {afterEach,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import TeacherVerificationPanel from '../src/components/TeacherVerificationPanel'
vi.mock('../src/components/TeacherDocumentReview',()=>({default:()=> <div>Qualification documents UI</div>}))
vi.mock('../src/components/AICourseAssignments',()=>({default:()=> <div>Course assignment UI</div>}))
afterEach(cleanup)
const record={user_id:'22222222-2222-4222-8222-222222222222',full_name:'Educator Example',
 qualification:'BSc Mathematics',institution:'Verified School',subjects_taught:['Mathematics','Biology'],
 grade_levels:['7','8'],verification_status:'pending'}
it('requires administrators to select credential-backed teaching subjects before approval',async()=>{
 const rpc=vi.fn().mockImplementation(async (name:string)=>name==='get_teacher_verification_queue'?
  {data:[record],error:null}:{data:{},error:null})
 const client={rpc} as any
 render(<TeacherVerificationPanel client={client}/>)
 fireEvent.click(await screen.findByRole('button',{name:'Review'}))
 fireEvent.change(screen.getByLabelText('Decision'),{target:{value:'approved'}})
 fireEvent.change(screen.getByLabelText('Verification note'),{target:{value:'Verified Mathematics degree by independent issuing institution.'}})
 expect((screen.getByRole('button',{name:'Save audited decision'}) as HTMLButtonElement).disabled).toBe(true)
 fireEvent.click(screen.getByLabelText(/Mathematics/))
 expect((screen.getByLabelText(/Biology/) as HTMLInputElement).checked).toBe(false)
 fireEvent.click(screen.getByRole('button',{name:'Save audited decision'}))
 await waitFor(()=>expect(rpc).toHaveBeenCalledWith('review_teacher_profile_scoped',{
  p_user_id:record.user_id,p_decision:'approved',p_note:'Verified Mathematics degree by independent issuing institution.',p_subjects:['Mathematics'],
 }))
 expect(rpc).not.toHaveBeenCalledWith('review_teacher_profile',expect.objectContaining({p_decision:'approved'}))
})

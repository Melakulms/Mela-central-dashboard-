// @vitest-environment jsdom
import {afterEach,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import TeacherDocumentReview from '../src/components/TeacherDocumentReview'

afterEach(cleanup)

const credential={id:'33333333-3333-4333-8333-333333333333',
 teacher_id:'11111111-1111-4111-8111-111111111111',document_kind:'degree',
 original_name:'teaching-degree.pdf',storage_path:'11111111-1111-4111-8111-111111111111/33333333-3333-4333-8333-333333333333.pdf',
 review_status:'pending',review_note:null,uploaded_at:'2026-10-14T01:00:00Z',reviewed_at:null}

it('offers expiring certificate access and saves an audited admin decision',async()=>{
 const rpc=vi.fn().mockResolvedValue({data:{status:'approved'},error:null})
 const createSignedUrl=vi.fn().mockResolvedValue({data:{signedUrl:'https://private.example.invalid/signed'},error:null})
 const download={location:{replace:vi.fn()},close:vi.fn(),opener:null}
 const opener=vi.spyOn(window,'open').mockReturnValue(download as unknown as Window)
 const client={
   from:()=>({select:()=>({eq:()=>({order:async()=>({data:[credential],error:null})})})}),
   storage:{from:()=>({createSignedUrl})},rpc,
 } as any
 render(<TeacherDocumentReview client={client} teacherId={credential.teacher_id}/>)
 expect(await screen.findByText('1 uploaded · 0 approved')).toBeTruthy()
 fireEvent.click(screen.getByRole('button',{name:/View private document/}))
 await waitFor(()=>expect(createSignedUrl).toHaveBeenCalledWith(credential.storage_path,60))
 await waitFor(()=>expect(download.location.replace).toHaveBeenCalledWith('https://private.example.invalid/signed'))
 fireEvent.click(screen.getByRole('button',{name:'Review evidence'}))
 fireEvent.change(screen.getByLabelText('Verification evidence and reason'),{target:{value:'Certificate serial checked directly with school records.'}})
 fireEvent.click(screen.getByRole('button',{name:'Save audited document decision'}))
 await waitFor(()=>expect(rpc).toHaveBeenCalledWith('review_teacher_credential_document',{
  p_document_id:credential.id,p_decision:'approved',p_note:'Certificate serial checked directly with school records.',
 }))
 expect(await screen.findByText(/Credential evidence approved and audited/)).toBeTruthy()
 opener.mockRestore()
})

it('does not display documents when the server returns an empty queue',async()=>{
 const client={from:()=>({select:()=>({eq:()=>({order:async()=>({data:[],error:null})})})})} as any
 render(<TeacherDocumentReview client={client} teacherId={credential.teacher_id}/>)
 expect(await screen.findByText(/No documents submitted yet/)).toBeTruthy()
 expect(screen.queryByRole('button',{name:'Review evidence'})).toBeNull()
})

// @vitest-environment jsdom
import React from 'react'
import {afterEach,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import MfaBackupSetup from '../src/components/MfaBackupSetup'
afterEach(cleanup)
it('does not offer backup enrollment without an AAL2 session',async()=>{
 const mfa={
  getAuthenticatorAssuranceLevel:vi.fn().mockResolvedValue({data:{currentLevel:'aal1'},error:null}),
  listFactors:vi.fn().mockResolvedValue({data:{all:[]},error:null}),
  enroll:vi.fn(),
 }
 const client={auth:{mfa}} as any
 render(<MfaBackupSetup client={client}/>)
 expect(await screen.findByRole('alert')).toHaveProperty('textContent','Complete administrator MFA before managing backup authenticators.')
 expect(mfa.enroll).not.toHaveBeenCalled()
})
it('enrolls a separate backup factor only after an AAL2 session, confirms a second code',async()=>{
 let all:any[]=[{id:'primary',factor_type:'totp',status:'verified',friendly_name:'Primary'}]
 const mfa={
  getAuthenticatorAssuranceLevel:vi.fn().mockResolvedValue({data:{currentLevel:'aal2'},error:null}),
  listFactors:vi.fn().mockImplementation(async()=>({data:{all},error:null})),
  enroll:vi.fn().mockResolvedValue({data:{id:'backup',totp:{qr_code:'data:image/svg+xml;base64,PHN2Zy8+',secret:'BACKUPTESTSECRET'}},error:null}),
  challengeAndVerify:vi.fn().mockImplementation(async()=>{all=[...all,{id:'backup',factor_type:'totp',status:'verified',friendly_name:'MELA Admin backup'}];return {data:{},error:null}}),
 }
 const client={auth:{mfa,refreshSession:vi.fn()}} as any
 render(<MfaBackupSetup client={client}/>)
 fireEvent.click(await screen.findByRole('button',{name:'Add backup authenticator'}))
 expect(await screen.findByText('BACKUPTESTSECRET')).toBeTruthy()
 fireEvent.change(screen.getByLabelText('Backup authenticator code'),{target:{value:'123456'}})
 fireEvent.click(screen.getByRole('button',{name:'Verify backup code'}))
 await waitFor(()=>expect(mfa.challengeAndVerify).toHaveBeenCalledWith({factorId:'backup',code:'123456'}))
 expect(await screen.findByText(/Backup authenticator verified/)).toBeTruthy()
 expect(screen.queryByText('BACKUPTESTSECRET')).toBeNull()
 expect(screen.getByText(/2 verified authenticators/)).toBeTruthy()
})

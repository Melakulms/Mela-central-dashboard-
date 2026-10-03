import {beforeEach,expect,it,vi} from 'vitest'
import {resolveAdminAccess} from '../src/lib/admin-access'
const mock=vi.hoisted(()=>({getAdminMe:vi.fn()}))
vi.mock('../src/lib/admin-api',()=>({getAdminMe:mock.getAdminMe}))
const assurance=vi.fn(),factors=vi.fn()
const client={auth:{mfa:{getAuthenticatorAssuranceLevel:assurance,listFactors:factors}}} as any
beforeEach(()=>{vi.resetAllMocks();assurance.mockResolvedValue({data:{currentLevel:'aal1'},error:null});factors.mockResolvedValue({data:{totp:[]},error:null})})
it('does not start MFA enrollment after an assurance network failure',async()=>{
 assurance.mockResolvedValue({data:null,error:new Error('Network unavailable')})
 await expect(resolveAdminAccess(client)).rejects.toThrow('Network unavailable');expect(factors).not.toHaveBeenCalled();expect(mock.getAdminMe).not.toHaveBeenCalled()
})
it('does not treat failed factor retrieval as a missing authenticator',async()=>{
 factors.mockResolvedValue({data:null,error:new Error('Try again')})
 await expect(resolveAdminAccess(client)).rejects.toThrow('Try again')
})
it('uses a verified authenticator and ignores unfinished enrollment',async()=>{
 factors.mockResolvedValue({data:{totp:[{id:'pending',status:'unverified'},{id:'verified',status:'verified'}]},error:null})
 await expect(resolveAdminAccess(client)).resolves.toEqual({kind:'challenge',factorId:'verified'})
 expect(mock.getAdminMe).not.toHaveBeenCalled()
})
it('offers enrollment only after a successful check finds no verified factor',async()=>{
 await expect(resolveAdminAccess(client)).resolves.toEqual({kind:'enroll'})
})
it('requires the backend to confirm MFA before granting access',async()=>{
 assurance.mockResolvedValue({data:{currentLevel:'aal2'},error:null});mock.getAdminMe.mockResolvedValue({mfa:{currentLevel:'aal1'}})
 await expect(resolveAdminAccess(client)).rejects.toThrow('MFA verification is required')
 mock.getAdminMe.mockResolvedValue({role:{key:'support'},permissions:['support.read'],mfa:{currentLevel:'aal2'}})
 await expect(resolveAdminAccess(client)).resolves.toMatchObject({kind:'ready',admin:{permissions:['support.read']}})
})

import { beforeEach, expect, it, vi } from 'vitest'
import { verifyEnrollment } from '../src/lib/verify-enrollment'
const challenge=vi.fn(), verify=vi.fn(), refreshSession=vi.fn(), assurance=vi.fn()
const client={auth:{mfa:{challenge,verify,getAuthenticatorAssuranceLevel:assurance},refreshSession}} as any
beforeEach(()=>{
 vi.resetAllMocks()
 challenge.mockResolvedValue({data:{id:'challenge'},error:null})
 verify.mockResolvedValue({error:null})
 refreshSession.mockResolvedValue({data:{session:{access_token:'test-fixture'}},error:null})
 assurance.mockResolvedValue({data:{currentLevel:'aal2',nextLevel:'aal2'},error:null})
})
it('rejects invalid input before creating a challenge',async()=>{
 await expect(verifyEnrollment(client,'factor','123')).rejects.toThrow('six-digit')
 expect(challenge).not.toHaveBeenCalled()
})
it('does not verify if challenge retrieval fails',async()=>{
 challenge.mockResolvedValue({data:null,error:new Error('Offline')})
 await expect(verifyEnrollment(client,'factor','123456')).rejects.toThrow('Offline')
 expect(verify).not.toHaveBeenCalled()
})
it('rejects incomplete challenge responses',async()=>{
 challenge.mockResolvedValue({data:null,error:null})
 await expect(verifyEnrollment(client,'factor','123456')).rejects.toThrow('Could not start')
 expect(verify).not.toHaveBeenCalled()
})
it('does not refresh after an invalid code',async()=>{
 verify.mockResolvedValue({error:new Error('Invalid code')})
 await expect(verifyEnrollment(client,'factor','123456')).rejects.toThrow('Invalid code')
 expect(refreshSession).not.toHaveBeenCalled()
})
it('does not accept old assurance after refresh failure',async()=>{
 refreshSession.mockResolvedValue({data:null,error:new Error('Refresh unavailable')})
 await expect(verifyEnrollment(client,'factor','123456')).rejects.toThrow('Refresh unavailable')
 expect(assurance).not.toHaveBeenCalled()
})
it('rejects a refresh that has no session',async()=>{
 refreshSession.mockResolvedValue({data:{session:null},error:null})
 await expect(verifyEnrollment(client,'factor','123456')).rejects.toThrow('session expired')
})
it('requires confirmed AAL2 after a successful refresh',async()=>{
 assurance.mockResolvedValue({data:{currentLevel:'aal1',nextLevel:'aal2'},error:null})
 await expect(verifyEnrollment(client,'factor','123456')).rejects.toThrow('assurance')
})
it('completes after all verification gates pass',async()=>{
 await expect(verifyEnrollment(client,'factor','123456')).resolves.toBeUndefined()
 expect(verify).toHaveBeenCalledWith({factorId:'factor',challengeId:'challenge',code:'123456'})
})

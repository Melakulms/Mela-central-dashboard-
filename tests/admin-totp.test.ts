import {beforeEach,expect,it,vi} from 'vitest'
import {safeTotpError,verifyAdminTotp} from '../src/lib/admin-totp'
const check=vi.fn(),assurance=vi.fn(),refresh=vi.fn()
const client={auth:{
 mfa:{challengeAndVerify:check,getAuthenticatorAssuranceLevel:assurance},
 refreshSession:refresh,
}} as any
beforeEach(()=>{
 vi.resetAllMocks()
 check.mockResolvedValue({data:{},error:null})
 assurance.mockResolvedValue({data:{currentLevel:'aal2',nextLevel:'aal2'},error:null})
 refresh.mockResolvedValue({data:{session:{access_token:'fixture'}},error:null})
})
it('verifies a six-digit Google Authenticator code against the actual MFA provider and confirms AAL2',async()=>{
 await verifyAdminTotp(client,'verified-factor','123 456')
 expect(check).toHaveBeenCalledWith({factorId:'verified-factor',code:'123456'})
 expect(assurance).toHaveBeenCalled()
})
it('does not report MFA success when a provider code is rejected',async()=>{
 check.mockResolvedValue({data:null,error:{code:'mfa_verification_failed',message:'invalid OTP'}})
 await expect(verifyAdminTotp(client,'factor','123456')).rejects.toMatchObject({code:'mfa_verification_failed'})
 expect(assurance).not.toHaveBeenCalled()
})
it('rechecks the assurance level after refreshing session when needed',async()=>{
 assurance.mockResolvedValueOnce({data:{currentLevel:'aal1'},error:null}).mockResolvedValueOnce({data:{currentLevel:'aal2'},error:null})
 await verifyAdminTotp(client,'factor','123456')
 expect(refresh).toHaveBeenCalledOnce()
})
it('fails closed if the provider cannot confirm AAL2 after refreshing',async()=>{
 assurance.mockResolvedValue({data:{currentLevel:'aal1'},error:null})
 await expect(verifyAdminTotp(client,'factor','123456')).rejects.toThrow('MFA could not be confirmed')
})
it('does not accept malformed OTPs or share secrets in error feedback',async()=>{
 await expect(verifyAdminTotp(client,'factor','abc123')).rejects.toThrow('six-digit')
 expect(check).not.toHaveBeenCalled()
 expect(safeTotpError({code:'mfa_verification_failed',message:'invalid OTP'})).toMatch(/selected authenticator/)
})

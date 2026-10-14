import type { SupabaseClient } from '@supabase/supabase-js'

/** Verify the actual Google Authenticator code with Supabase.
 * No browser-only "success": AAL2 must be confirmed server-side before
 * the administrator may request access through mela-admin-api.
 */
export async function verifyAdminTotp(client:SupabaseClient,factorId:string,rawCode:string){
 const code=rawCode.replace(/\s+/g,'')
 if(!factorId||!/^\d{6}$/.test(code))throw new Error('Enter the current six-digit code.')
 const {error}=await client.auth.mfa.challengeAndVerify({factorId,code})
 if(error)throw error
 // challengeAndVerify renews the Auth session; confirm AAL2 before proceeding.
 const {data:level,error:levelError}=await client.auth.mfa.getAuthenticatorAssuranceLevel()
 if(levelError)throw levelError
 if(level?.currentLevel!=='aal2'){
   const {error:refreshError}=await client.auth.refreshSession()
   if(refreshError)throw refreshError
   const next=await client.auth.mfa.getAuthenticatorAssuranceLevel()
   if(next.error)throw next.error
   if(next.data?.currentLevel!=='aal2')throw new Error('MFA could not be confirmed. Sign in again and retry.')
 }
}

/** Only actionable non-secret feedback. Avoid exposing internal auth codes. */
export function safeTotpError(cause:unknown){
 const code=String((cause as {code?:string})?.code??'')
 const msg=cause instanceof Error?cause.message:''
 if(code==='mfa_verification_failed'||/invalid.*(code|totp)|verification.failed|incorrect.*code/i.test(msg)){
   return 'This code did not match the selected authenticator. Choose the correct MELA Admin entry (or a backup authenticator), use the newest code before it changes, and ensure your phone time is automatic. If the setup key was lost, use the recovery instructions below.'
 }
 if(/rate limit|too many/i.test(msg))return 'Too many verification attempts. Do not repeatedly guess codes; retry after the authentication limit clears.'
 if(/network|fetch|timeout/i.test(msg))return 'Unable to contact authentication. Check connectivity and retry. No permissions were granted.'
 return msg||'Unable to verify your authenticator. No administrative access was granted.'
}

import type { SupabaseClient } from '@supabase/supabase-js'
import { adminApi } from './admin-api'

export type InvitationCommissionStatus='pending'|'paid'|'cancelled'
export type InvitationCommission={
  id:string
  inviter_user_id:string
  registered_user_id:string
  invitation_code:string|null
  amount:number
  currency:string
  status:InvitationCommissionStatus
  transaction_reference:string
  eligibility_reason?:string|null
  created_at:string
  paid_at?:string|null
  cancelled_at?:string|null
  cancellation_reason?:string|null
}

export async function listInvitationCommissions(client:SupabaseClient,filters:{status?:InvitationCommissionStatus;search?:string;limit?:number}={}){
  return adminApi(client,'commission.list',{...filters,commission_type:'invitation_registration'})
}

export async function cancelInvitationCommission(client:SupabaseClient,commissionId:string,reason:string){
  const clean=reason.trim()
  if(!commissionId)throw new Error('Commission ID is required')
  if(!clean)throw new Error('A cancellation reason is required')
  if(clean.length>500)throw new Error('Cancellation reason must be 500 characters or fewer')
  return adminApi(client,'commission.cancel',{commission_id:commissionId,reason:clean,commission_type:'invitation_registration'})
}

export async function getInvitationCommission(client:SupabaseClient,commissionId:string){
  return adminApi(client,'commission.inspect',{commission_id:commissionId,commission_type:'invitation_registration'})
}

/** Trusted registration backend contract. Never calculate money in the browser. */
export interface RegistrationCommissionEvent{
  registered_user_id:string
  invitation_code:string
  registration_id:string
}

/** The registration backend must atomically validate the invitation and create at most one commission. */
export const INVITATION_COMMISSION_RULE='registration_invitation'

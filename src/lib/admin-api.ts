import { createClient, type SupabaseClient } from '@supabase/supabase-js'

export type AdminMe={user:{id:string;email?:string};role:{key:string;name:string};permissions:string[];mfa:{currentLevel?:string;nextLevel?:string}}
export function createAdminClient(){const url=import.meta.env.VITE_SUPABASE_URL as string;const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string;if(!url||!key)throw new Error('Missing Supabase public configuration');return createClient(url,key)}
export async function adminApi(client:SupabaseClient,action:string,body:Record<string,unknown>={}){const{data:{session}}=await client.auth.getSession();if(!session)throw new Error('Authentication required');const{data,error}=await client.functions.invoke('mela-admin-api',{body:{action,...body},headers:{'x-request-id':crypto.randomUUID()}});if(error)throw error;if(data?.error)throw Object.assign(new Error(data.error),{code:data.code});return data}
export async function getAdminMe(client:SupabaseClient):Promise<AdminMe>{return adminApi(client,'me')}

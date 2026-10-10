import { useEffect,useRef,useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { adminApi } from '../lib/admin-api'
type UserRecord={id:string;full_name?:string;email?:string;phone_number?:string;role?:string;account_status?:string;profile_completion?:number;updated_at?:string;created_at?:string;region?:string;city?:string;email_verified?:boolean;phone_verified?:boolean}
type Detail={profile:UserRecord|null;auth:{id:string;email?:string;phone?:string;email_confirmed_at?:string;phone_confirmed_at?:string;last_sign_in_at?:string;banned_until?:string}|null}
const statuses=['active','pending_verification','suspended','banned','deleted']
export default function UsersPanel({client,permissions}:{client:SupabaseClient;permissions:string[]}) {
 const [rows,setRows]=useState<UserRecord[]>([]),[total,setTotal]=useState(0),[page,setPage]=useState(0),[search,setSearch]=useState(''),[role,setRole]=useState(''),[status,setStatus]=useState(''),[filters,setFilters]=useState({search:'',role:'',status:''})
 const [loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[success,setSuccess]=useState(''),[revision,setRevision]=useState(0)
 const [detail,setDetail]=useState<Detail|null>(null),[nextStatus,setNextStatus]=useState(''),[reason,setReason]=useState('')
 const command=useRef(false),generation=useRef(0)
 const canManage=permissions.includes('*')||permissions.includes('users.manage')
 useEffect(()=>{
  const request=++generation.current;setLoading(true);setError('');setDetail(null)
  adminApi(client,'users.list',{...filters,limit:25,offset:page*25}).then(result=>{if(request===generation.current){setRows(result.data??[]);setTotal(result.total??0)}}).catch(cause=>{if(request===generation.current)setError(cause instanceof Error?cause.message:'Unable to load users.')}).finally(()=>{if(request===generation.current)setLoading(false)})
  return ()=>{generation.current++}
 },[client,filters,page,revision])
 const inspect=async(id:string)=>{
  if(command.current)return;command.current=true;setBusy(true);setError('');setSuccess('');const request=generation.current
  try {const result=await adminApi(client,'user.inspect',{user_id:id});if(request!==generation.current)return;setDetail(result.data);setNextStatus(result.data?.profile?.account_status??'');setReason('')}
  catch(cause){if(request===generation.current)setError(cause instanceof Error?cause.message:'Unable to inspect user.')}
  finally{command.current=false;setBusy(false)}
 }
 const save=async(e:React.FormEvent)=>{
  e.preventDefault();const profile=detail?.profile;if(!profile||command.current||!canManage||nextStatus===profile.account_status||reason.trim().length<5)return
  command.current=true;setBusy(true);setError('');setSuccess('')
  try {const result=await adminApi(client,'user.update',{user_id:profile.id,account_status:nextStatus,reason:reason.trim(),expected_updated_at:profile.updated_at});setDetail(current=>current?{...current,profile:{...profile,...result.data}}:null);setRows(current=>current.map(row=>row.id===profile.id?{...row,...result.data}:row));setReason('');setSuccess('Account status saved and audited.')}
  catch(cause){setError(cause instanceof Error?cause.message:'Status was not saved. Refresh the record before retrying.')}
  finally{command.current=false;setBusy(false)}
 }
 return <section className="panel"><div className="module-head"><div><h2>Users</h2><p>Search, inspect and manage accounts through the protected admin API.</p></div><strong>{total} total</strong></div>
  <form className="toolbar" onSubmit={e=>{e.preventDefault();setPage(0);setFilters({search,role,status});setSuccess('')}}><label>Search users<input value={search} onChange={e=>setSearch(e.target.value)} maxLength={200} disabled={busy}/></label><label>User role<select value={role} disabled={busy} onChange={e=>setRole(e.target.value)}><option value="">All roles</option>{['student','parent','teacher','employer','mentor','company','partner','admin'].map(v=><option key={v}>{v}</option>)}</select></label><label>Account status<select value={status} disabled={busy} onChange={e=>setStatus(e.target.value)}><option value="">All statuses</option>{statuses.map(v=><option key={v}>{v}</option>)}</select></label><button disabled={busy}>Apply user filters</button></form>
  {loading&&<p role="status">Loading users…</p>}{error&&<div className="error" role="alert">{error}<button disabled={busy||loading} onClick={()=>setRevision(v=>v+1)}>Retry users</button></div>}{success&&<p role="status">{success}</p>}
  {detail?<section className="detail-card"><button disabled={busy} onClick={()=>{setDetail(null);setSuccess('');setError('')}}>Back to users</button><h3>{detail.profile?.full_name??detail.auth?.email??'User account'}</h3><dl>{[['User ID',detail.profile?.id??detail.auth?.id],['Email',detail.profile?.email??detail.auth?.email],['Phone',detail.profile?.phone_number??detail.auth?.phone],['Role',detail.profile?.role],['Status',detail.profile?.account_status],['Region',detail.profile?.region],['City',detail.profile?.city],['Email confirmed',detail.auth?.email_confirmed_at],['Phone confirmed',detail.auth?.phone_confirmed_at],['Last sign in',detail.auth?.last_sign_in_at],['Auth ban until',detail.auth?.banned_until]].map(([label,value])=><div key={label}><dt>{label}</dt><dd>{value??'—'}</dd></div>)}</dl>
   {detail.profile&&<button disabled={busy} onClick={()=>void inspect(detail.profile!.id)}>Refresh user details</button>}
   {canManage&&detail.profile?<form onSubmit={save}><h3>Account status change</h3><label>New account status<select value={nextStatus} disabled={busy} onChange={e=>setNextStatus(e.target.value)}>{statuses.map(v=><option key={v}>{v}</option>)}</select></label><label>Status change reason<textarea value={reason} maxLength={1000} disabled={busy} onChange={e=>setReason(e.target.value)} required/></label><p>Change {detail.profile.account_status} → {nextStatus}. This changes platform access; it does not delete account data or change authentication-provider confirmation.</p><button disabled={busy||nextStatus===detail.profile.account_status||reason.trim().length<5}>{busy?'Saving status…':'Confirm account status change'}</button></form>:<p>This role can inspect accounts. Account changes require users.manage permission.</p>}
  </section>:<><div className="table-wrap"><table><thead><tr><th>User</th><th>Role</th><th>Status</th><th>Profile</th><th>Details</th></tr></thead><tbody>{!loading&&!error&&rows.map(row=><tr key={row.id}><td>{row.full_name??'Unnamed user'}<small>{row.email??row.phone_number??row.id}</small></td><td>{row.role}</td><td>{row.account_status}</td><td>{row.profile_completion??0}%</td><td><button disabled={busy} onClick={()=>void inspect(row.id)}>Inspect {row.full_name??row.id}</button></td></tr>)}</tbody></table></div>{!loading&&!error&&!rows.length&&<p>No users match these filters.</p>}<div className="toolbar"><button disabled={busy||loading||page===0} onClick={()=>setPage(v=>v-1)}>Previous users</button><span>Page {page+1} · {total} accounts</span><button disabled={busy||loading||(page+1)*25>=total} onClick={()=>setPage(v=>v+1)}>Next users</button></div></>}
 </section>
}

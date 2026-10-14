import {useEffect,useState} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'

type AuditEvent={id:string;action:string;actor_id:string|null;entity_type:string|null;entity_id:string|null;details:unknown;created_at:string}

/** Public legacy action audit is separate from the central admin audit_log.
 * It is still RLS-admin-only. Never treat either table as the other.
 */
export default function UserWorkflowAudit({client}:{client:SupabaseClient}){
 const [events,setEvents]=useState<AuditEvent[]>([])
 const [total,setTotal]=useState<number|null>(null)
 const [page,setPage]=useState(0)
 const [revision,setRevision]=useState(0)
 const [loading,setLoading]=useState(true)
 const [error,setError]=useState('')
 const [selected,setSelected]=useState<AuditEvent|null>(null)
 useEffect(()=>{
  let live=true
  setLoading(true);setError('');setSelected(null)
  void(async()=>{
   try{
    const {data,error,count}=await client.from('admin_audit_logs')
      .select('id,action,actor_id,entity_type,entity_id,details,created_at',{count:'exact'})
      .order('created_at',{ascending:false}).range(page*25,page*25+24)
    if(error)throw error
    if(live){setEvents((data??[]) as AuditEvent[]);setTotal(count??0)}
   }catch(cause){
    if(live)setError(cause instanceof Error?cause.message:'Could not load the legacy workflow audit.')
   }finally{if(live)setLoading(false)}
  })()
  return()=>{live=false}
 },[client,page,revision])
 return <section className="panel" aria-label="User workflow audit trail">
  <div className="module-head"><div><h2>User workflow audit (legacy records)</h2>
   <p>This is separate from the protected Central Admin audit log above. It includes historical account-type, education-stage and professional verification actions; it does not imply these entries were all performed by administrators.</p></div>
   <button type="button" disabled={loading} onClick={()=>setRevision(x=>x+1)}>Refresh workflow audit</button>
  </div>
  <p role="status">{total===null?'Count unavailable':`${total} workflow audit entries`}</p>
  {loading&&<p>Loading workflow audit…</p>}
  {error&&<div className="error" role="alert">{error}</div>}
  {!loading&&!error&&<div className="table-wrap"><table><thead><tr><th>Time</th><th>Action</th><th>Entity</th><th>Details</th></tr></thead>
   <tbody>{events.map(event=><tr key={event.id}>
    <td>{new Date(event.created_at).toLocaleString()}</td><td>{event.action}</td><td>{event.entity_type??'—'}</td>
    <td><button type="button" onClick={()=>setSelected(event)}>Inspect workflow {event.id}</button></td>
   </tr>)}
   {!events.length&&<tr><td colSpan={4}>No workflow entries.</td></tr>}</tbody></table></div>}
  {selected&&<section className="detail-card"><h3>{selected.action}</h3><p>Actor: {selected.actor_id??'—'}</p>
   <p>Entity: {selected.entity_type??'—'} / {selected.entity_id??'—'}</p>
   <pre style={{whiteSpace:'pre-wrap',overflowWrap:'anywhere'}}>{JSON.stringify(selected.details,null,2)}</pre>
   <button type="button" onClick={()=>setSelected(null)}>Close workflow details</button>
  </section>}
  <div className="toolbar"><button disabled={loading||page===0} onClick={()=>setPage(x=>x-1)}>Previous workflow records</button>
   <span>Page {page+1} / {total??'?'}</span><button disabled={loading||total===null||(page+1)*25>=total}
    onClick={()=>setPage(x=>x+1)}>Next workflow records</button></div>
 </section>
}

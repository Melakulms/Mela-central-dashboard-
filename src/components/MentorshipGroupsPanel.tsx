import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Mentor = { user_id: string; headline: string | null }
type Program = {
  id:string; title:string; description:string; category:string;mentor_id:string;
  starts_at:string | null; capacity:number; status:string
}
type Interest = {id:string;group_id:string;learner_id:string;status:string;created_at:string}
export default function MentorshipGroupsPanel({client}:{client:SupabaseClient}) {
  const [groups,setGroups] = useState<Program[]>([])
  const [mentors,setMentors] = useState<Mentor[]>([])
  const [interests,setInterests] = useState<Interest[]>([])
  const [error,setError] = useState('')
  const [notice,setNotice] = useState('')
  const [loading,setLoading] = useState(true)
  const [busy,setBusy] = useState(false)
  const [revision,setRevision] = useState(0)
  const [selectedMentor,setSelectedMentor] = useState('')
  const [title,setTitle] = useState('')
  const [description,setDescription] = useState('')
  const [category,setCategory] = useState('career')
  const [starts,setStarts] = useState('')
  const [capacity,setCapacity] = useState(20)
  const lock=useRef(false)

  useEffect(()=>{
    let active=true
    setLoading(true);setError('')
    setGroups([]);setMentors([]);setInterests([]);setSelectedMentor('')
    void (async()=>{
      try{
        const [m,g,i] = await Promise.all([
          client.from('mentor_profiles').select('user_id,headline').eq('verified',true).eq('active',true).order('user_id').limit(250),
          client.from('mentorship_groups').select('id,title,description,category,mentor_id,starts_at,capacity,status').order('created_at',{ascending:false}).limit(100),
          client.from('mentorship_group_interests').select('id,group_id,learner_id,status,created_at')
            .order('created_at',{ascending:false}).limit(100),
        ])
        if(m.error)throw m.error
        if(g.error)throw g.error
        if(i.error)throw i.error
        if(active){setMentors((m.data??[]) as Mentor[]);setGroups((g.data??[]) as Program[]);setInterests((i.data??[]) as Interest[])}
      }catch(cause){if(active)setError(cause instanceof Error?cause.message:'Could not load mentorship group administration.')}
      finally{if(active)setLoading(false)}
    })()
    return ()=>{active=false}
  },[client,revision])

  const write=async(fn:()=>Promise<void>,message:string)=>{
    if(lock.current)return
    lock.current=true;setBusy(true);setError('');setNotice('')
    try{await fn();setNotice(message);setRevision(v=>v+1)}
    catch(cause){setError(cause instanceof Error?cause.message:'Could not save group program.')}
    finally{lock.current=false;setBusy(false)}
  }
  const createProgram=(event:React.FormEvent)=>{
    event.preventDefault()
    void write(async()=>{
      if(!mentors.some(m=>m.user_id===selectedMentor))throw new Error('Choose a real verified mentor.')
      if(!starts || !Number.isFinite(new Date(starts).getTime()) || Date.parse(starts)<=Date.now())throw new Error('Select a future program start date.')
      if(title.trim().length<3||title.trim().length>160||!Number.isInteger(capacity)||capacity<2||capacity>200)throw new Error('Provide a valid title and capacity.')
      const {error:insertError}=await client.from('mentorship_groups').insert({
        title:title.trim(),description:description.trim().slice(0,2000),category,
        mentor_id:selectedMentor,starts_at:new Date(starts).toISOString(),capacity,status:'draft'
      })
      if(insertError)throw new Error(insertError.message)
      setTitle('');setDescription('');setStarts('')
    },'Program saved as draft. It is not visible to learners until you publish it.')
  }
  const publish=(program:Program)=>{
    void write(async()=>{
      if(program.status!=='draft')throw new Error('Only draft programs can be published.')
      const {data,error:editError}=await client.from('mentorship_groups')
        .update({status:'published'}).eq('id',program.id).eq('status','draft').select('id')
      if(editError)throw new Error(editError.message)
      if(!data?.length)throw new Error('Program was already changed or reviewer lacks MFA access.')
    },'Published group program is now visible to eligible learners. No live call or enrollment is automatically created.')
  }
  const review=(record:Interest, decision:'approved'|'declined')=>{
    void write(async()=>{
      const {data:auth,error:authError}=await client.auth.getUser()
      if(authError)throw authError
      if(!auth.user)throw new Error('MFA administrator sign-in is required.')
      const {data,error:editError}=await client.from('mentorship_group_interests')
        .update({status:decision,reviewed_by:auth.user.id,reviewed_at:new Date().toISOString()})
        .eq('id',record.id).eq('status','pending').select('id')
      if(editError)throw new Error(editError.message)
      if(!data?.length)throw new Error('Already reviewed or administrator permission denied.')
    },decision==='approved'?'Interest approved within capacity. No private call has been activated.':'Interest declined and decision audited.')
  }
  const counts=new Map<string,number>()
  for(const interest of interests)if(interest.status==='approved')counts.set(interest.group_id,(counts.get(interest.group_id)??0)+1)

  return <section className="panel" aria-label="Supervised group mentoring administration">
    <h2>Supervised group programs</h2>
    <p>Only MFA-verified administrators may create, publish or review group programs. Facilitators must already be verified and active. This is not a live call or payment system.</p>
    {error&&<div className="error" role="alert">{error}</div>}
    {notice&&<p role="status">{notice}</p>}
    <button type="button" disabled={loading||busy} onClick={()=>setRevision(v=>v+1)}>Refresh programs</button>
    {loading?<p role="status">Loading verified mentors and group programs…</p>:<>
      <h3>New group program</h3>
      {mentors.length===0?<p>No verified mentors are available. Publishing a real group program is blocked until mentor verification is completed.</p>
        :<form onSubmit={createProgram}>
          <label>Verified mentor<select required disabled={busy} value={selectedMentor} onChange={e=>setSelectedMentor(e.target.value)}>
            <option value="">Select approved facilitator</option>
            {mentors.map(m=><option key={m.user_id} value={m.user_id}>{m.headline||'Mentor'} · {m.user_id.slice(0,8)}</option>)}
          </select></label>
          <label>Program title<input required minLength={3} maxLength={160} disabled={busy} value={title} onChange={e=>setTitle(e.target.value)}/></label>
          <label>Description<textarea maxLength={2000} disabled={busy} value={description} onChange={e=>setDescription(e.target.value)}/></label>
          <label>Category<select disabled={busy} value={category} onChange={e=>setCategory(e.target.value)}>
            <option value="career">Career</option><option value="academic">Academic</option>
            <option value="scholarships">University & scholarships</option><option value="technology">Technology & AI</option>
            <option value="business">Business & entrepreneurship</option><option value="research">Research</option>
          </select></label>
          <label>Start time<input type="datetime-local" required disabled={busy} value={starts} onChange={e=>setStarts(e.target.value)}/></label>
          <label>Capacity<input type="number" min={2} max={200} required disabled={busy} value={capacity} onChange={e=>setCapacity(Number(e.target.value))}/></label>
          <button disabled={busy||!selectedMentor}>Save draft</button>
        </form>}
      <h3>Group program directory</h3>
      {!groups.length?<p>No real group programs have been created yet.</p>:<div className="table-wrap"><table>
        <thead><tr><th>Program</th><th>Status</th><th>Seats</th><th>Action</th></tr></thead>
        <tbody>{groups.map(g=><tr key={g.id}><td>{g.title}<small>{g.starts_at?new Date(g.starts_at).toLocaleString():'Unscheduled'}</small></td>
          <td>{g.status}</td><td>{counts.get(g.id)??0} approved (at most {g.capacity})</td>
          <td>{g.status==='draft'?<button disabled={busy} onClick={()=>publish(g)}>Publish verified program</button>:'—'}</td></tr>)}</tbody>
      </table></div>}
      <h3>Adult group interest reviews</h3>
      {!interests.length?<p>No adult group interest requests yet.</p>:<div className="table-wrap"><table>
        <thead><tr><th>Program</th><th>Application</th><th>Status</th><th>Decision</th></tr></thead>
        <tbody>{interests.map(r=><tr key={r.id}>
          <td>{groups.find(g=>g.id===r.group_id)?.title||r.group_id.slice(0,8)}</td>
          <td>{r.id.slice(0,8)} · {new Date(r.created_at).toLocaleDateString()}</td>
          <td>{r.status}</td>
          <td>{r.status==='pending'?<><button disabled={busy} onClick={()=>review(r,'approved')}>Approve</button>{' '}
            <button disabled={busy} onClick={()=>review(r,'declined')}>Decline</button></>:'Reviewed'}</td>
        </tr>)}</tbody>
      </table></div>}
      <p className="muted">This queue is limited to 100 recent applications; capacity is strictly checked by the server under a group row lock. The seat summary may be partial if there are more than 100 applications.</p>
    </>}
  </section>
}

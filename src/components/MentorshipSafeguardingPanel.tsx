import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type VerifiedMentor = {
  user_id: string
  headline: string | null
  organization: string | null
  verified: boolean
  active: boolean
}

export default function MentorshipSafeguardingPanel({client}:{client:SupabaseClient}) {
  const [mentors,setMentors]=useState<VerifiedMentor[]>([])
  const [selected,setSelected]=useState<VerifiedMentor|null>(null)
  const [reason,setReason]=useState('')
  const [confirmed,setConfirmed]=useState(false)
  const [loading,setLoading]=useState(true)
  const [busy,setBusy]=useState(false)
  const [revision,setRevision]=useState(0)
  const [error,setError]=useState('')
  const [notice,setNotice]=useState('')
  const lock=useRef(false)
  useEffect(()=>{
    let active=true
    setLoading(true);setError('')
    void client.from('mentor_profiles')
      .select('user_id,headline,organization,verified,active')
      .eq('verified',true).eq('active',true).order('updated_at',{ascending:false}).limit(100)
      .then(({data,error:readError})=>{
        if(readError)throw new Error(readError.message)
        if(active)setMentors((data??[]) as VerifiedMentor[])
      }).catch((cause)=>{
        if(active)setError(cause instanceof Error?cause.message:'Could not fetch active mentors.')
      }).finally(()=>{if(active)setLoading(false)})
    return()=>{active=false}
  },[client,revision])

  const suspend=async(event:React.FormEvent)=>{
    event.preventDefault()
    if(!selected||!confirmed||reason.trim().length<20||lock.current)return
    lock.current=true;setBusy(true);setError('');setNotice('')
    try {
      const { data, error:rpcError }=await client.rpc('suspend_mentorship_mentor',{
        p_mentor_id:selected.user_id,p_reason:reason.trim(),
      })
      if(rpcError)throw new Error(rpcError.message)
      if(data!==true)throw new Error('The database did not confirm suspension.')
      setSelected(null);setConfirmed(false);setReason('')
      setNotice('Mentor suspended. Future scheduled sessions were cancelled, pending requests declined and published groups closed. The database recorded the administrator and reason.')
      setRevision(n=>n+1)
    }catch(cause){
      setError(cause instanceof Error?cause.message:'Could not safely suspend mentor.')
    }finally{lock.current=false;setBusy(false)}
  }
  return <section className="panel" aria-label="Mentor safeguarding and suspension">
    <h2>Mentor safeguarding controls</h2>
    <p>Authorized MFA administrators can suspend an active verified mentor for safeguarding concerns. This immediately stops new mentor requests, cancels future sessions and closes published group programs. Suspension is audited and has no automatic reversal.</p>
    <button type="button" disabled={loading||busy} onClick={()=>setRevision(n=>n+1)}>Refresh active mentors</button>
    {notice&&<p role="status">{notice}</p>}
    {error&&<div role="alert" className="error">{error}</div>}
    {loading?<p role="status">Loading currently active verified mentors…</p>:
      mentors.length===0?<p>No verified active mentors available for suspension.</p>:
        <div className="table-wrap"><table>
          <thead><tr><th>Verified mentor</th><th>Action</th></tr></thead>
          <tbody>{mentors.map(mentor=><tr key={mentor.user_id}>
            <td><strong>{mentor.headline??'Verified mentor'}</strong><small>{mentor.organization??'No organization supplied'} · {mentor.user_id.slice(0,8)}</small></td>
            <td><button type="button" disabled={busy} onClick={()=>{
              setSelected(mentor);setReason('');setConfirmed(false);setError('')
            }}>Safeguarding suspension</button></td>
          </tr>)}</tbody>
        </table></div>}
    {selected&&<form onSubmit={suspend} className="panel">
      <h3>Suspend: {selected.headline??'Verified mentor'}</h3>
      <p>Record an actual safeguarding case reference and reason. Do not paste student contact details, secret credentials or private evidence into this form. The action cancels future sessions and closes programs; it cannot be undone here.</p>
      <label>Reason and case reference
        <textarea required rows={4} minLength={20} maxLength={2000}
          value={reason} disabled={busy} onChange={e=>setReason(e.target.value)} />
      </label>
      <label><input type="checkbox" checked={confirmed} disabled={busy}
        onChange={e=>setConfirmed(e.target.checked)}/>
        I understand that future sessions will be cancelled and new requests stopped.</label>
      <button disabled={busy||!confirmed||reason.trim().length<20}>
        {busy?'Suspending…':'Confirm mentor suspension'}
      </button>{' '}
      <button type="button" disabled={busy} onClick={()=>setSelected(null)}>Cancel</button>
    </form>}
  </section>
}

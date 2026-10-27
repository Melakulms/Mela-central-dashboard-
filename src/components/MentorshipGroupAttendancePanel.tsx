import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Program = { id:string; title:string; starts_at:string|null; status:string }
type Interest = { id:string; group_id:string; learner_id:string; status:string }
type Attendance = { interest_id:string; status:'reported_present'|'reported_absent'; recorded_at:string }
type Choice = 'reported_present'|'reported_absent'

/** Manual attendance register; NOT meeting telemetry, a certificate or a career credential. */
export default function MentorshipGroupAttendancePanel({client}:{client:SupabaseClient}) {
  const [programs,setPrograms] = useState<Program[]>([])
  const [interests,setInterests] = useState<Interest[]>([])
  const [attendance,setAttendance] = useState<Attendance[]>([])
  const [selected,setSelected] = useState<string|null>(null)
  const [choice,setChoice] = useState<Choice>('reported_present')
  const [explanation,setExplanation] = useState('')
  const [confirmed,setConfirmed] = useState(false)
  const [error,setError] = useState('')
  const [notice,setNotice] = useState('')
  const [loading,setLoading] = useState(true)
  const [busy,setBusy] = useState(false)
  const [revision,setRevision] = useState(0)
  const lock = useRef(false)
  useEffect(()=>{
    let active=true
    setLoading(true);setError('');setPrograms([]);setInterests([]);setAttendance([])
    setSelected(null);setConfirmed(false);setExplanation('')
    void (async()=>{
      try {
        const [g,i,a] = await Promise.all([
          client.from('mentorship_groups').select('id,title,starts_at,status')
            .order('starts_at',{ascending:false}).limit(150),
          client.from('mentorship_group_interests').select('id,group_id,learner_id,status')
            .eq('status','approved').order('created_at',{ascending:false}).limit(200),
          client.from('mentorship_group_attendance').select('interest_id,status,recorded_at')
            .order('recorded_at',{ascending:false}).limit(200),
        ])
        if(g.error)throw g.error
        if(i.error)throw i.error
        if(a.error)throw a.error
        if(active){setPrograms((g.data??[]) as Program[]);setInterests((i.data??[]) as Interest[]);setAttendance((a.data??[]) as Attendance[])}
      }catch(cause){if(active)setError(cause instanceof Error?cause.message:'Attendance records could not be loaded.')}
      finally{if(active)setLoading(false)}
    })()
    return ()=>{active=false}
  },[client,revision])

  const eligible = interests.filter(i=>{
    const g=programs.find(p=>p.id===i.group_id)
    return g && ['published','closed'].includes(g.status) && !!g.starts_at
      && Date.parse(g.starts_at) <= Date.now()-60*60*1000
  })
  const recorded = new Map(attendance.map(a=>[a.interest_id,a]))
  const submit = async()=>{
    if(lock.current||!selected||!confirmed||explanation.trim().length<20||explanation.trim().length>1000)return
    if(!eligible.some(i=>i.id===selected)||recorded.has(selected)){setError('Choose a currently eligible, unrecorded participant.');return}
    lock.current=true;setBusy(true);setError('');setNotice('')
    try {
      const {data:auth,error:authError}=await client.auth.getUser()
      if(authError)throw authError
      if(!auth.user)throw new Error('Sign in with an MFA-verified administrator account.')
      const {data,error:insertError}=await client.from('mentorship_group_attendance')
        .insert({interest_id:selected,status:choice,explanation:explanation.trim(),recorded_by:auth.user.id})
        .select('interest_id')
      if(insertError)throw new Error(insertError.message)
      if(!data?.length)throw new Error('The attendance record was not saved. Check MFA and participant status.')
      setNotice('Attendance report recorded and audited. It is not an independently verified certificate.')
      setRevision(n=>n+1)
    }catch(cause){setError(cause instanceof Error?cause.message:'Could not record group attendance.')}
    finally{lock.current=false;setBusy(false)}
  }

  return <section aria-label="Group attendance reporting">
    <h3>Group attendance reports</h3>
    <p>Only an MFA administrator may report a participant's attendance after a program start. This is a manual report, not proof of a monitored call, learning achievement, certificate or Career Passport award. Do not enter ID numbers, private case details or sensitive personal information.</p>
    {error&&<div className="error" role="alert">{error}</div>}
    {notice&&<p role="status">{notice}</p>}
    <button type="button" disabled={loading||busy} onClick={()=>setRevision(n=>n+1)}>Refresh attendance</button>
    {loading?<p role="status">Loading attendance records…</p>:<>
      {!eligible.length?<p>No approved participants in started programs to review.</p>:<div className="table-wrap"><table>
        <thead><tr><th>Group</th><th>Approved interest</th><th>Reported status</th><th>Action</th></tr></thead>
        <tbody>{eligible.map(i=>{
          const record=recorded.get(i.id)
          return <tr key={i.id}>
            <td>{programs.find(p=>p.id===i.group_id)?.title??'Program'}</td>
            <td>{i.id.slice(0,8)}</td>
            <td>{record?record.status==='reported_present'?'Reported present':'Reported absent':'Not yet reported'}</td>
            <td>{!record?<button type="button" disabled={busy} onClick={()=>{
              setSelected(i.id);setChoice('reported_present');setExplanation('');setConfirmed(false);setError('');setNotice('')
            }}>Review attendance</button>:'Recorded'}</td>
          </tr>
        })}</tbody>
      </table></div>}
      {selected&&!recorded.has(selected)&&eligible.some(i=>i.id===selected)&&<div>
        <h4>Record manual attendance</h4>
        <p>Selected application: {selected.slice(0,8)}. Once recorded, it cannot be changed from this screen. Confirm your evidence before saving.</p>
        <label>Reported outcome<select value={choice} disabled={busy} onChange={e=>setChoice(e.target.value as Choice)}>
          <option value="reported_present">Reported present</option>
          <option value="reported_absent">Reported absent</option>
        </select></label>
        <label>Evidence explanation visible to the participant
          <textarea value={explanation} disabled={busy} maxLength={1000} onChange={e=>setExplanation(e.target.value)}
            placeholder="State how attendance was checked (20–1000 characters). No confidential data."/>
        </label>
        <label><input type="checkbox" checked={confirmed} disabled={busy}
          onChange={e=>setConfirmed(e.target.checked)}/> I independently reviewed attendance evidence and understand this is not a credential.</label>
        <button type="button" disabled={busy||!confirmed||explanation.trim().length<20||explanation.trim().length>1000}
          onClick={()=>void submit()}>Save audited attendance report</button>
        <button type="button" disabled={busy} onClick={()=>setSelected(null)}>Cancel</button>
      </div>}
      <p className="muted">Only the most recent 200 approved interests and 200 reports are shown; older records require separate audit review. No attendance is fabricated.</p>
    </>}
  </section>
}

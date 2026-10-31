import React,{useEffect,useState} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'
import {ShieldCheck,RefreshCw,AlertTriangle} from 'lucide-react'

type Account = {
 id:string;method_code:string;institution_name:string;account_name:string;
 masked_number:string;suffix:string;active:boolean;created_at:string;
}
type ReceiverResponse = {collection_enabled:boolean;accounts:Account[]}

/** Owner-only secure staging workflow: registering a receiver never opens checkout. */
export default function ReceivingAccountsPanel({client}:{client:SupabaseClient}){
 const [records,setRecords]=useState<Account[]>([])
 const [collectionOpen,setCollectionOpen]=useState(false)
 const [method,setMethod]=useState('dashen_bank')
 const [accountName,setAccountName]=useState('')
 const [accountNumber,setAccountNumber]=useState('')
 const [acknowledged,setAcknowledged]=useState(false)
 const [selected,setSelected]=useState<Account|null>(null)
 const [suffix,setSuffix]=useState('')
 const [note,setNote]=useState('')
 const [providerConfirmed,setProviderConfirmed]=useState(false)
 const [holderConfirmed,setHolderConfirmed]=useState(false)
 const [busy,setBusy]=useState(false)
 const [error,setError]=useState('')
 const [notice,setNotice]=useState('')

 const load=async()=>{
  setBusy(true);setError('')
  try {
   const {data,error:problem}=await client.rpc('mela_billing_receiving_admin_v1',{p_action:'list',p_data:{}})
   if(problem)throw problem
   const response=data as ReceiverResponse|null
   setRecords(Array.isArray(response?.accounts)?response.accounts:[])
   setCollectionOpen(response?.collection_enabled===true)
  } catch(e){setError(e instanceof Error?e.message:'Unable to read receiving accounts')}
  finally{setBusy(false)}
 }
 useEffect(()=>{void load()},[])
 const register=async()=>{
  setBusy(true);setError('');setNotice('')
  try{
   const {error:problem}=await client.rpc('mela_billing_receiving_admin_v1',{
    p_action:'register',p_data:{
      method_code:method,account_name:accountName.trim(),
      account_number:accountNumber.trim(),owner_acknowledgment:acknowledged
    }
   })
   if(problem)throw problem
   setNotice('Receiving account saved as INACTIVE. Check its ownership in your official bank or telebirr app before activating.')
   setAccountNumber('');setAccountName('');setAcknowledged(false)
   await load()
  }catch(e){setError(e instanceof Error?e.message:'Account registration failed')}
  finally{setBusy(false)}
 }
 const choose=(a:Account)=>{
  setSelected(a);setSuffix('');setNote('');setProviderConfirmed(false);
  setHolderConfirmed(false);setError('');setNotice('')
 }
 const changeStatus=async()=>{
  if(!selected)return
  const activating=!selected.active
  setBusy(true);setError('');setNotice('')
  try{
   const {error:problem}=await client.rpc('mela_billing_receiving_admin_v1',{
    p_action:activating?'activate':'deactivate',
    p_data:{account_id:selected.id,evidence_note:note.trim(),
     confirmed_suffix:suffix.trim(),provider_verified:providerConfirmed,holder_verified:holderConfirmed}
   })
   if(problem)throw problem
   setNotice(activating
     ?'Receiving account marked active. Payment collection remains OFF and must be reviewed separately.'
     :'Receiving account disabled. New orders cannot use this destination.')
   setSelected(null);setNote('');setSuffix('');await load()
  }catch(e){setError(e instanceof Error?e.message:'Account status could not be updated')}
  finally{setBusy(false)}
 }

 return <section className="panel" aria-label="MELA payment receiving account setup">
   <div className="module-head"><div>
    <h2>Payment receiving accounts</h2>
    <p>Secure Super Admin setup for Dashen Bank and telebirr. Enter details here on your own phone, not in chat. No transfers are requested by this setup.</p>
   </div><button className="refresh" onClick={()=>void load()} disabled={busy}>
     <RefreshCw size={16}/>{busy?'Loading':'Refresh'}
   </button></div>
   <p role="status"><strong>Payment collection: {collectionOpen?'ENABLED':'OFF'}</strong>. Receiver activation does not enable payment collection.</p>
   {error&&<p className="error" role="alert"><AlertTriangle size={16}/>{error}</p>}
   {notice&&<p role="status">{notice}</p>}
   <h3>Existing receiving accounts</h3>
   <div className="table-wrap"><table><thead><tr><th>Provider</th><th>Holder</th><th>Account</th><th>Status</th><th>Action</th></tr></thead>
    <tbody>{records.map(a=><tr key={a.id}>
      <td>{a.institution_name}</td><td>{a.account_name}</td><td>{a.masked_number}</td>
      <td>{a.active?'Active':'Inactive'}</td>
      <td><button type="button" disabled={busy} onClick={()=>choose(a)}>{a.active?'Disable':'Verify / Activate'}</button></td>
    </tr>)}
    {!records.length&&<tr><td colSpan={5}>No receiving accounts registered.</td></tr>}
    </tbody></table></div>
   {selected&&<div className="detail-card">
     <h3>{selected.active?'Disable':'Verify and activate'} {selected.institution_name}</h3>
     <p>{selected.account_name} — {selected.masked_number}</p>
     {!selected.active&&<>
       <p className="muted">Before activating, independently inspect the official provider account and match the holder name and final four digits. This is an owner attestation, not automated bank confirmation.</p>
       <label>Last 4 digits of verified receiving account
         <input inputMode="numeric" maxLength={4} value={suffix}
            onChange={e=>setSuffix(e.target.value.replace(/\D/g,''))}/>
       </label>
       <label><input type="checkbox" checked={providerConfirmed} onChange={e=>setProviderConfirmed(e.target.checked)}/>
         I personally checked the receiving number in the official banking or telebirr app.
       </label>
       <label><input type="checkbox" checked={holderConfirmed} onChange={e=>setHolderConfirmed(e.target.checked)}/>
         I personally confirmed the receiving account holder is authorized for MELA.
       </label>
     </>}
     <label>Detailed verification evidence or deactivation reason (30–500 characters)
      <textarea value={note} onChange={e=>setNote(e.target.value)} minLength={30} maxLength={500}/>
     </label>
     <div className="toolbar">
      <button type="button" className="secondary" disabled={busy} onClick={()=>setSelected(null)}>Cancel</button>
      <button type="button" disabled={busy||note.trim().length<30||(!selected.active&&(!providerConfirmed||!holderConfirmed||suffix!==selected.suffix))}
       onClick={()=>void changeStatus()}><ShieldCheck size={15}/>{selected.active?'Confirm disable':'Confirm verified destination'}</button>
     </div>
   </div>}
   <h3>Add receiving account (initially inactive)</h3>
   <p className="muted">Use an account that you own or are authorized to use for MELA. Verify its actual holder with the provider before activation.</p>
   <label>Receiving provider
    <select value={method} onChange={e=>{setMethod(e.target.value);setAccountNumber('')}}>
     <option value="dashen_bank">Dashen Bank</option>
     <option value="telebirr">telebirr</option>
    </select>
   </label>
   <label>Account holder's exact name
    <input value={accountName} autoComplete="off" maxLength={100}
     onChange={e=>setAccountName(e.target.value)} placeholder="Name registered at the provider"/>
   </label>
   <label>{method==='telebirr'?'Receiving telebirr mobile number':'Dashen Bank receiving account number'}
    <input value={accountNumber} autoComplete="off" inputMode="numeric" maxLength={20}
     onChange={e=>setAccountNumber(e.target.value.replace(/\D/g,''))}
     placeholder={method==='telebirr'?'09XXXXXXXX':'Bank account number'}/>
   </label>
   <label><input type="checkbox" checked={acknowledged} onChange={e=>setAcknowledged(e.target.checked)}/>
     I own or am authorized to use this receiving account for MELA.
   </label>
   <button type="button" disabled={busy||!acknowledged||accountName.trim().length<4||
    (method==='telebirr'?!/^0[0-9]{9}$/.test(accountNumber):!/^[0-9]{8,20}$/.test(accountNumber))}
    onClick={()=>void register()}>Save inactive receiving account</button>
 </section>
}

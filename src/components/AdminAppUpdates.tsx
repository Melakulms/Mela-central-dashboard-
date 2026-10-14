import {useEffect,useState} from 'react'

/** PWA is intentionally network-only for administrative data. The user must
 * opt in to restarting: admin tokens are memory-only and a reload signs out.
 */
export default function AdminAppUpdates(){
 const [installed,setInstalled]=useState(false)
 const [serviceWorker,setServiceWorker]=useState(false)
 const [checking,setChecking]=useState(false)
 const [message,setMessage]=useState('')
 useEffect(()=>{
   setInstalled(Boolean(window.matchMedia?.('(display-mode: standalone)').matches))
   setServiceWorker('serviceWorker' in navigator)
 },[])
 const check=async()=>{
   if(checking)return
   setChecking(true);setMessage('')
   try{
     if(!('serviceWorker' in navigator))throw new Error('This browser cannot check app updates. Open the installed admin app in Chrome.')
     const registration=await navigator.serviceWorker.getRegistration(import.meta.env.BASE_URL)
     if(!registration)throw new Error('Admin service worker is not registered. Open MELA Admin in Chrome and reload once while online.')
     await registration.update()
     setMessage('Update check completed. Close and reopen MELA Admin to load the latest files. Administrative sessions are not saved on the device; sign in and verify MFA again.')
   }catch(cause){
     setMessage(cause instanceof Error?cause.message:'Unable to check for app updates. Check your connection and try again.')
   }finally{setChecking(false)}
 }
 return <section className="panel" aria-label="Mobile admin app installation and updates">
  <h2>Mobile Admin app · installation & updates</h2>
  <p role="status">Current display: <strong>{installed?'Standalone app':'Browser tab'}</strong>. Service worker: {serviceWorker?'Supported':'Not supported'}.</p>
  <p>The standalone Admin app has its own name, icon, start URL and scope, separate from the MELA Users app. In Chrome on Android, open this admin URL and choose <strong>Install app</strong>. A shortcut is not a confirmed standalone installation.</p>
  <button type="button" disabled={checking} onClick={()=>void check()}>{checking?'Checking update…':'Check admin app update'}</button>
  {message&&<p role="status">{message}</p>}
  <p>Updates require internet. The admin app never stores private account data for offline viewing. Reopening or refreshing may require signing in and entering your authenticator code again.</p>
 </section>
}

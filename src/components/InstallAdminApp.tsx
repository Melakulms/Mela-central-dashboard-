import { useEffect, useState } from 'react'

type InstallPrompt = Event & {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

export default function InstallAdminApp() {
  const [prompt, setPrompt] = useState<InstallPrompt | null>(null)
  const [installed, setInstalled] = useState(() => window.matchMedia?.('(display-mode: standalone)').matches ?? false)
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    const ready = (event: Event) => { event.preventDefault(); setPrompt(event as InstallPrompt) }
    const done = () => { setInstalled(true); setPrompt(null) }
    window.addEventListener('beforeinstallprompt', ready)
    window.addEventListener('appinstalled', done)
    return () => {
      window.removeEventListener('beforeinstallprompt', ready)
      window.removeEventListener('appinstalled', done)
    }
  }, [])
  if (installed) return null
  const install = async () => {
    if (!prompt) {
      setMessage('Open this page in Chrome, then choose Install app from the browser menu. If it only offers a shortcut, reload this page and try again when installation is available.')
      return
    }
    setBusy(true)
    try {
      await prompt.prompt()
      const choice = await prompt.userChoice
      setMessage(choice.outcome === 'accepted' ? 'Installation requested. Look for MELA Admin in your apps.' : 'Installation cancelled. You can install from the Chrome menu later.')
    } catch { setMessage('Installation could not start. Try Install app in the Chrome menu.') }
    finally { setPrompt(null); setBusy(false) }
  }
  return <aside className="admin-install" aria-label="Install MELA Admin">
    <div><strong>MELA Admin app</strong><p>Install separately from the MELA student app.</p></div>
    <button type="button" onClick={() => void install()} disabled={busy}>{busy ? 'Opening installer…' : 'Install MELA Admin'}</button>
    {message && <p role="status">{message}</p>}
  </aside>
}

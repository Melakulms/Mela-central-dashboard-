import type { AuthChangeEvent, Session, SupabaseClient } from '@supabase/supabase-js'

/** A newer auth event always wins over the initial asynchronous snapshot. */
export function observeSession(
  auth: Pick<SupabaseClient['auth'], 'getSession' | 'onAuthStateChange'>,
  onSession: (session: Session | null, event: AuthChangeEvent) => void,
  onError: (error: unknown) => void,
): () => void {
  let active = true
  let receivedEvent = false
  let lastSession: Session | null = null
  const { data } = auth.onAuthStateChange((event, session) => {
    if (!active) return
    receivedEvent = true
    if (event === 'SIGNED_IN' && session?.access_token && session.access_token === lastSession?.access_token && session.user.id === lastSession.user.id) return
    lastSession = session
    onSession(session, event)
  })
  void auth.getSession().then(({ data, error }) => {
    if (!active || receivedEvent) return
    if (error) onError(error)
    else { lastSession = data.session; onSession(data.session, 'INITIAL_SESSION') }
  }).catch((error: unknown) => {
    if (active && !receivedEvent) onError(error)
  })
  return () => {
    active = false
    data.subscription.unsubscribe()
  }
}

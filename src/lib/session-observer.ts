import type { AuthChangeEvent, Session, SupabaseClient } from '@supabase/supabase-js'

/** A newer auth event always wins over the initial asynchronous snapshot. */
export function observeSession(
  auth: Pick<SupabaseClient['auth'], 'getSession' | 'onAuthStateChange'>,
  onSession: (session: Session | null, event: AuthChangeEvent) => void,
  onError: (error: unknown) => void,
): () => void {
  let active = true
  let receivedEvent = false
  const { data } = auth.onAuthStateChange((event, session) => {
    if (!active) return
    receivedEvent = true
    onSession(session, event)
  })
  void auth.getSession().then(({ data, error }) => {
    if (!active || receivedEvent) return
    if (error) onError(error)
    else onSession(data.session, 'INITIAL_SESSION')
  }).catch((error: unknown) => {
    if (active && !receivedEvent) onError(error)
  })
  return () => {
    active = false
    data.subscription.unsubscribe()
  }
}

import { describe, expect, it, vi } from 'vitest'
import type { AuthChangeEvent, Session } from '@supabase/supabase-js'
import { observeSession } from '../src/lib/session-observer'

const oldSession = { user: { id: 'old-account' } } as Session
const newSession = { user: { id: 'new-account' } } as Session
function setup() {
  let resolve!: (value: { data: { session: Session | null }; error: Error | null }) => void
  let reject!: (error: Error) => void
  let emit!: (event: AuthChangeEvent, session: Session | null) => void
  const pending = new Promise<{ data: { session: Session | null }; error: Error | null }>((yes, no) => { resolve = yes; reject = no })
  const unsubscribe = vi.fn()
  const auth = {
    getSession: vi.fn(() => pending),
    onAuthStateChange: vi.fn((callback) => { emit = callback; return { data: { subscription: { unsubscribe } } } }),
  }
  const receive = vi.fn(), fail = vi.fn()
  const stop = observeSession(auth as unknown as Parameters<typeof observeSession>[0], receive, fail)
  return { resolve, reject, emit, receive, fail, stop, unsubscribe }
}
const flush = async () => { await Promise.resolve(); await Promise.resolve() }

describe('session restoration ordering', () => {
  it('restores an initial session when no event has arrived', async () => {
    const s = setup(); s.resolve({ data: { session: oldSession }, error: null }); await flush()
    expect(s.receive).toHaveBeenCalledWith(oldSession, 'INITIAL_SESSION')
  })
  it('does not resurrect an old session after sign-out', async () => {
    const s = setup(); s.emit('SIGNED_OUT', null)
    s.resolve({ data: { session: oldSession }, error: null }); await flush()
    expect(s.receive.mock.calls).toEqual([[null, 'SIGNED_OUT']])
  })
  it('does not discard a newer sign-in or password recovery', async () => {
    for (const event of ['SIGNED_IN', 'PASSWORD_RECOVERY'] as const) {
      const s = setup(); s.emit(event, newSession)
      s.resolve({ data: { session: null }, error: null }); await flush()
      expect(s.receive.mock.calls).toEqual([[newSession, event]])
    }
  })
  it('ignores restoration failures after a newer event', async () => {
    const s = setup(); s.emit('SIGNED_IN', newSession); s.reject(new Error('offline')); await flush()
    expect(s.fail).not.toHaveBeenCalled()
  })
  it('surfaces initial restoration errors', async () => {
    const s = setup(); const error = new Error('restore failed')
    s.resolve({ data: { session: null }, error }); await flush()
    expect(s.fail).toHaveBeenCalledWith(error)
    expect(s.receive).not.toHaveBeenCalled()
  })
  it('surfaces rejected initial restoration', async () => {
    const s = setup(); const error = new Error('offline'); s.reject(error); await flush()
    expect(s.fail).toHaveBeenCalledWith(error)
  })
  it('ignores snapshots and events after unmount', async () => {
    const s = setup(); s.stop(); s.emit('SIGNED_IN', newSession)
    s.resolve({ data: { session: oldSession }, error: null }); await flush()
    expect(s.receive).not.toHaveBeenCalled(); expect(s.fail).not.toHaveBeenCalled()
    expect(s.unsubscribe).toHaveBeenCalledOnce()
  })
  it('continues to receive token refreshes after the initial snapshot', async () => {
    const s = setup(); s.resolve({ data: { session: oldSession }, error: null }); await flush()
    s.emit('TOKEN_REFRESHED', newSession)
    expect(s.receive).toHaveBeenLastCalledWith(newSession, 'TOKEN_REFRESHED')
  })
})

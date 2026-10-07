import { describe, expect, it, vi } from 'vitest'
import { prepareEnrollment } from '../src/lib/prepare-enrollment'
const name = 'MELA Central Admin - admin@example.invalid'
function setup(all: object[] = []) {
  const mfa = { listFactors: vi.fn().mockResolvedValue({ data: { all, totp: [] }, error: null }),
    unenroll: vi.fn().mockResolvedValue({ error: null }),
    enroll: vi.fn().mockResolvedValue({ data: { id: 'new', totp: { qr_code: 'test-qr', secret: 'test-secret' } }, error: null }) }
  return { mfa, client: { auth: { mfa } } as any }
}
describe('MFA enrollment recovery', () => {
  it('removes an abandoned matching TOTP from all even when totp is empty', async () => {
    const { client, mfa } = setup([{ id: 'old', friendly_name: name, factor_type: 'totp', status: 'unverified' }])
    expect(await prepareEnrollment(client, 'admin@example.invalid')).toEqual({ kind: 'enroll', id: 'new', qr: 'test-qr', secret: 'test-secret' })
    expect(mfa.unenroll).toHaveBeenCalledWith({ factorId: 'old' })
    expect(mfa.enroll).toHaveBeenCalledOnce()
    expect(mfa.unenroll.mock.invocationCallOrder[0]).toBeLessThan(mfa.enroll.mock.invocationCallOrder[0])
  })
  it('preserves verified factors and returns to the challenge flow', async () => {
    const { client, mfa } = setup([{ id: 'verified', factor_type: 'totp', status: 'verified' }])
    expect(await prepareEnrollment(client)).toEqual({ kind: 'verified' })
    expect(mfa.unenroll).not.toHaveBeenCalled(); expect(mfa.enroll).not.toHaveBeenCalled()
  })
  it('preserves unrelated unfinished factors', async () => {
    const { client, mfa } = setup([{ id: 'other', friendly_name: 'Other app', factor_type: 'totp', status: 'unverified' }])
    await prepareEnrollment(client); expect(mfa.unenroll).not.toHaveBeenCalled()
  })
  it('shares concurrent preparation calls rather than enrolling twice', async () => {
    const { client, mfa } = setup()
    await Promise.all([prepareEnrollment(client), prepareEnrollment(client)])
    expect(mfa.enroll).toHaveBeenCalledOnce()
  })
  it('stops if listing or removing old factors fails', async () => {
    const { client, mfa } = setup([{ id: 'old', friendly_name: name, factor_type: 'totp', status: 'unverified' }])
    mfa.unenroll.mockResolvedValue({ error: new Error('offline') })
    await expect(prepareEnrollment(client, 'admin@example.invalid')).rejects.toThrow('offline')
    expect(mfa.enroll).not.toHaveBeenCalled()
  })
  it('allows retry after a rejected setup', async () => {
    const { client, mfa } = setup()
    mfa.listFactors.mockRejectedValueOnce(new Error('offline'))
    await expect(prepareEnrollment(client)).rejects.toThrow('offline')
    await expect(prepareEnrollment(client)).resolves.toMatchObject({ kind: 'enroll' })
  })
})

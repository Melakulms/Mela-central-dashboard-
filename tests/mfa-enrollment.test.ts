import { beforeEach, expect, it, vi } from 'vitest'
import { prepareTotpEnrollment } from '../src/lib/mfa-enrollment'

const listFactors = vi.fn()
const unenroll = vi.fn()
const enroll = vi.fn()

const client = {
  auth: {
    mfa: { listFactors, unenroll, enroll },
  },
} as any

beforeEach(() => {
  vi.resetAllMocks()
  listFactors.mockResolvedValue({ data: { totp: [], phone: [] }, error: null })
  unenroll.mockResolvedValue({ data: {}, error: null })
  enroll.mockResolvedValue({
    data: { id: 'fresh-factor', totp: { qr_code: 'data:image/svg+xml;base64,qr', secret: 'SECRET' } },
    error: null,
  })
})

it('reuses a verified TOTP factor without creating or deleting factors', async () => {
  listFactors.mockResolvedValue({
    data: { totp: [{ id: 'verified-factor', status: 'verified', friendly_name: 'MELA Central Admin' }], phone: [] },
    error: null,
  })

  await expect(prepareTotpEnrollment(client)).resolves.toEqual({
    kind: 'verified',
    factorId: 'verified-factor',
  })
  expect(unenroll).not.toHaveBeenCalled()
  expect(enroll).not.toHaveBeenCalled()
})

it('removes abandoned TOTP factors and enrolls without a collision-prone friendly name', async () => {
  listFactors.mockResolvedValue({
    data: {
      totp: [
        { id: 'stale-one', status: 'unverified', friendly_name: 'MELA Central Admin - admin@example.com' },
        { id: 'stale-two', status: 'unverified', friendly_name: 'MELA Central Admin' },
      ],
      phone: [],
    },
    error: null,
  })

  await expect(prepareTotpEnrollment(client)).resolves.toEqual({
    kind: 'new',
    factorId: 'fresh-factor',
    qrCode: 'data:image/svg+xml;base64,qr',
    secret: 'SECRET',
  })

  expect(unenroll).toHaveBeenNthCalledWith(1, { factorId: 'stale-one' })
  expect(unenroll).toHaveBeenNthCalledWith(2, { factorId: 'stale-two' })
  expect(enroll).toHaveBeenCalledWith({ factorType: 'totp' })
  expect(enroll.mock.calls[0]?.[0]).not.toHaveProperty('friendlyName')
})

it('fails closed when factors cannot be listed', async () => {
  listFactors.mockResolvedValue({ data: null, error: new Error('Network unavailable') })
  await expect(prepareTotpEnrollment(client)).rejects.toThrow('Network unavailable')
  expect(unenroll).not.toHaveBeenCalled()
  expect(enroll).not.toHaveBeenCalled()
})

// @vitest-environment jsdom
import React from 'react'
import { afterEach, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { MfaEnrollment } from '../src/components/MfaEnrollment'
afterEach(cleanup)
it('verifies the existing setup after a page remount without deleting or replacing it', async () => {
  const mfa = {
    listFactors: vi.fn().mockResolvedValue({ data: { all: [{id: 'pending-factor', friendly_name: 'MELA Central Admin - test@example.invalid', factor_type: 'totp', status: 'unverified'}] }, error: null }),
    enroll: vi.fn(), unenroll: vi.fn(),
    challenge: vi.fn().mockResolvedValue({ data: {id: 'challenge'}, error: null }),
    verify: vi.fn().mockResolvedValue({error: null}),
    getAuthenticatorAssuranceLevel: vi.fn().mockResolvedValue({data: {currentLevel:'aal2', nextLevel:'aal2'}, error:null}),
  }
  const client = {auth: {mfa, refreshSession: vi.fn().mockResolvedValue({data: {session: {access_token:'test'}}, error:null})}} as any
  const onEnrolled = vi.fn()
  const props = {client, email:'test@example.invalid', onEnrolled, onCancel:vi.fn()}
  const first = render(<MfaEnrollment {...props} />)
  await screen.findByText('Continue your unfinished setup')
  first.unmount()
  render(<MfaEnrollment {...props} />)
  await screen.findByText('Continue your unfinished setup')
  fireEvent.change(screen.getByLabelText('Authenticator code'), {target:{value:'123456'}})
  fireEvent.click(screen.getByRole('button', {name:'Enable MFA and continue'}))
  await vi.waitFor(() => expect(onEnrolled).toHaveBeenCalledOnce())
  expect(mfa.verify).toHaveBeenCalledWith({factorId:'pending-factor', challengeId:'challenge', code:'123456'})
  expect(mfa.enroll).not.toHaveBeenCalled()
  expect(mfa.unenroll).not.toHaveBeenCalled()
})

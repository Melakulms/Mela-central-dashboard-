// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen, waitFor } from '@testing-library/react'
import StagingScholarshipApp from '../src/components/StagingScholarshipApp'

vi.mock('../src/lib/scholarship-staging', () => ({
  isScholarshipStagingUrl: () => true,
}))
vi.mock('../src/components/MfaEnrollment', () => ({
  MfaEnrollment: () => <div data-testid="mfa-enrollment">MFA setup</div>,
}))
vi.mock('../src/components/ScholarshipAccessPanel', () => ({
  default: () => <div data-testid="scholarship-form">Scholarship form</div>,
}))

afterEach(cleanup)

describe('Staging reviewer authorization before MFA', () => {
  it('rejects non-reviewer users without starting an MFA challenge', async () => {
    const getAuthenticatorAssuranceLevel = vi.fn()
    const client = {
      auth: {
        getSession: vi.fn().mockResolvedValue({ data: {session: {user: {id: 'test-id',email: 'qa@sample.test'}}}, error: null}),
        getUser: vi.fn().mockResolvedValue({data: {user: {id: 'test-id'}}, error: null}),
        mfa: {getAuthenticatorAssuranceLevel},
      },
      rpc: vi.fn().mockResolvedValue({data: false, error: null}),
    } as any
    render(<StagingScholarshipApp client={client}/>)
    expect(await screen.findByRole('heading', {name:'Scholarship access blocked'})).toBeTruthy()
    expect(screen.getByText('This account has no active staging scholarship reviewer assignment.')).toBeTruthy()
    expect(client.rpc).toHaveBeenCalledWith('staging_scholarship_reviewer_status_v1')
    expect(getAuthenticatorAssuranceLevel).not.toHaveBeenCalled()
    expect(screen.queryByTestId('mfa-enrollment')).toBeNull()
    expect(screen.queryByTestId('scholarship-form')).toBeNull()
  })
  it('allows an assigned reviewer to reach MFA setup, not scholarship access, at aal1', async () => {
    const mfa = {
      getAuthenticatorAssuranceLevel: vi.fn().mockResolvedValue({data:{currentLevel:'aal1',nextLevel:'aal2'},error:null}),
      listFactors: vi.fn().mockResolvedValue({data:{totp:[],all:[]},error:null}),
    }
    const client = {
      auth: {
        getSession: vi.fn().mockResolvedValue({data:{session:{user:{id:'test-id',email:'qa@sample.test'}}},error:null}),
        getUser: vi.fn().mockResolvedValue({data:{user:{id:'test-id'}},error:null}),
        mfa,
      },
      rpc: vi.fn().mockResolvedValue({data:true,error:null}),
    } as any
    render(<StagingScholarshipApp client={client}/>)
    expect(await screen.findByTestId('mfa-enrollment')).toBeTruthy()
    expect(screen.queryByTestId('scholarship-form')).toBeNull()
    await waitFor(() => expect(mfa.getAuthenticatorAssuranceLevel).toHaveBeenCalled())
  })
})

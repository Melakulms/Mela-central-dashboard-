// @vitest-environment jsdom
import { afterEach, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import InstallAdminApp from '../src/components/InstallAdminApp'

afterEach(cleanup)
it('opens the native install prompt from the install button', async () => {
  render(<InstallAdminApp />)
  const prompt = vi.fn().mockResolvedValue(undefined)
  const event = Object.assign(new Event('beforeinstallprompt', { cancelable: true }), { prompt, userChoice: Promise.resolve({ outcome: 'accepted' }) })
  fireEvent(window, event)
  expect(event.defaultPrevented).toBe(true)
  fireEvent.click(screen.getByRole('button', { name: 'Install MELA Admin' }))
  await waitFor(() => expect(prompt).toHaveBeenCalledOnce())
  expect(await screen.findByRole('status')).toBeTruthy()
  fireEvent(window, new Event('appinstalled'))
  expect(screen.queryByRole('button')).toBeNull()
})
it('provides instructions when the browser has not offered installation', () => {
  render(<InstallAdminApp />)
  fireEvent.click(screen.getByRole('button', { name: 'Install MELA Admin' }))
  expect(screen.getByRole('status').textContent).toContain('Install app')
})

import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const config = JSON.parse(readFileSync(new URL('../vercel.json', import.meta.url), 'utf8'))
const manifest = JSON.parse(readFileSync(new URL('../public/manifest.webmanifest', import.meta.url), 'utf8'))

describe('isolated Central Admin hosting', () => {
  it('routes root traffic to the scoped Admin application on Vercel', () => {
    expect(config.redirects).toContainEqual({source: '/', destination: '/Mela-central-dashboard-/', permanent: false})
    expect(config.rewrites).toContainEqual({source: '/Mela-central-dashboard-/', destination: '/index.html'})
    expect(config.rewrites).toContainEqual({source: '/Mela-central-dashboard-/:path*', destination: '/:path*'})
    expect(manifest.start_url).toBe('/Mela-central-dashboard-/')
    expect(manifest.scope).toBe('/Mela-central-dashboard-/')
  })

  it('enforces server-delivered anti-framing and script protections', () => {
    const policy = config.headers.find((entry: {source: string}) => entry.source === '/(.*)').headers
    const header = (key: string) => policy.find((entry: {key: string}) => entry.key === key)?.value ?? ''
    expect(header('Content-Security-Policy')).toContain("frame-ancestors 'none'")
    expect(header('Content-Security-Policy')).toContain("script-src 'self'")
    expect(header('X-Frame-Options')).toBe('DENY')
    expect(header('X-Content-Type-Options')).toBe('nosniff')
    expect(header('Referrer-Policy')).toBe('no-referrer')
  })
})

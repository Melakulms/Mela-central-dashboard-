import {readFileSync} from 'node:fs'
import {expect,it} from 'vitest'
const manifest=JSON.parse(readFileSync(new URL('../public/manifest.webmanifest',import.meta.url),'utf8'))
const sw=readFileSync(new URL('../public/sw.js',import.meta.url),'utf8')
it('has a standalone Android PWA identity scoped only to MELA Central Admin',()=>{
 expect(manifest.id).toBe('/Mela-central-dashboard-/')
 expect(manifest.display).toBe('standalone')
 expect(manifest.scope).toBe('/Mela-central-dashboard-/')
 expect(manifest.start_url).toBe('/Mela-central-dashboard-/')
 expect(manifest.icons).toEqual(expect.arrayContaining([expect.objectContaining({sizes:'192x192'}),expect.objectContaining({sizes:'512x512'})]))
})
it('never caches private admin API or authenticated dashboard data for offline access',()=>{
 expect(sw).toMatch(/event.request.mode !== 'navigate'/)
 expect(sw).toContain("status: 503")
 expect(sw).toContain("'Cache-Control': 'no-store'")
 expect(sw).not.toMatch(/cache\.put\(|caches\.open\(|respondWith\(caches/)
})

it('redirects legacy same-origin admin entry to the isolated administration origin before app startup', () => {
 const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8')
 const script = readFileSync(new URL('../public/admin-origin-redirect.js', import.meta.url), 'utf8')
 expect(html.indexOf('./admin-origin-redirect.js')).toBeGreaterThan(0)
 expect(html.indexOf('./admin-origin-redirect.js')).toBeLessThan(html.indexOf('/src/main.tsx'))
 expect(script).toContain("window.location.origin === 'https://melakulms.github.io'")
 expect(script).toContain("window.location.replace('https://central-dashboard-gamma.vercel.app/Mela-central-dashboard-/')")
 expect(script).not.toContain('window.location.search')
 expect(script).not.toContain('window.location.hash')
})

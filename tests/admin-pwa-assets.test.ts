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

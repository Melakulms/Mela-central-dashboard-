// @vitest-environment jsdom
import React from "react"
import { act, fireEvent, screen, waitFor, cleanup } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
const m=vi.hoisted(()=>({receive:null as any,signOut:vi.fn()}))
vi.mock('../src/lib/admin-api',()=>({createAdminClient:()=>({auth:{}}),signOutAdmin:m.signOut,adminApi:vi.fn(async()=>({}))}))
vi.mock('../src/lib/session-observer',()=>({observeSession:(_auth:any,receive:any)=>{m.receive=receive;return ()=>{}}}))
vi.mock('../src/lib/admin-access',()=>({resolveAdminAccess:vi.fn(async()=>({kind:'allowed',admin:{role:{key:'super_admin',name:'Administrator'},permissions:['*']}}))}))
vi.mock('../src/components/InstallAdminApp',()=>({default:()=>null}))
vi.mock('../src/components/UsersPanel',()=>({default:()=> <p>Private users panel</p>}))
afterEach(cleanup)
it('returns the same administrator to Overview after logout and clears identity inputs',async()=>{
 document.body.innerHTML='<div id="root"></div>'
 await import('../src/main')
 await waitFor(()=>expect(m.receive).toBeTypeOf('function'))
 const session={user:{id:'admin-one',email:'private@example.test'}}
 await act(async()=>m.receive(session,'SIGNED_IN'))
 await screen.findByRole('heading',{name:'Overview',exact:true})
 fireEvent.click(screen.getByRole('button',{name:'Users',exact:true}))
 await screen.findByText('Private users panel')
 m.signOut.mockImplementation(async()=>m.receive(null,'SIGNED_OUT'))
 fireEvent.click(screen.getByRole('button',{name:'Sign out'}))
 await screen.findByRole('heading',{name:'Administrator sign in'})
 expect((screen.getByLabelText('Email') as HTMLInputElement).value).toBe('')
 expect(screen.queryByText('Private users panel')).toBeNull()
 await act(async()=>m.receive(session,'SIGNED_IN'))
 await screen.findByRole('heading',{name:'Overview',exact:true})
 expect(screen.queryByText('Private users panel')).toBeNull()
})

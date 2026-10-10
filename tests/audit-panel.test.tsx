// @vitest-environment jsdom
import { afterEach,beforeEach,it,expect,vi } from 'vitest'
import { cleanup,render,screen,fireEvent,waitFor } from '@testing-library/react'
import AuditPanel from '../src/components/AuditPanel'
const mock=vi.hoisted(()=>({api:vi.fn()}))
vi.mock('../src/lib/admin-api',()=>({adminApi:mock.api}))
const client:any={};const row={id:'audit-a',action:'user.update',created_at:'2026-10-10T03:00:00Z',before_data:{account_status:'active'},after_data:{account_status:'suspended'},metadata:{reason:'Reviewed <script>unsafe()</script>'}}
beforeEach(()=>{vi.resetAllMocks();mock.api.mockResolvedValue({data:[row],total:501})})
afterEach(cleanup)
it('browses older audit records and resets page on a new action filter',async()=>{
 render(<AuditPanel client={client}/>);await screen.findByText('user.update');fireEvent.click(screen.getByRole('button',{name:'Next audit records'}));await waitFor(()=>expect(mock.api).toHaveBeenLastCalledWith(client,'audit.list',{offset:25,limit:25,search:''}));await screen.findByText('user.update');fireEvent.change(screen.getByLabelText('Audit action search'),{target:{value:'user.update'}});fireEvent.click(screen.getByRole('button',{name:'Apply audit filter'}));await waitFor(()=>expect(mock.api).toHaveBeenLastCalledWith(client,'audit.list',{offset:0,limit:25,search:'user.update'}))
})
it('shows before/after and reasons as escaped text',async()=>{
 const view=render(<AuditPanel client={client}/>);fireEvent.click(await screen.findByRole('button',{name:'Inspect audit audit-a'}));expect(screen.getByText(/Reviewed <script>/)).toBeTruthy();expect(view.container.querySelector('script')).toBeNull();expect(screen.getByRole('heading',{name:'Before'})).toBeTruthy();expect(screen.getByRole('heading',{name:'After'})).toBeTruthy()
})
it('recovers from load failure without showing a false empty state',async()=>{
 mock.api.mockRejectedValueOnce(new Error('Network unavailable'));render(<AuditPanel client={client}/>);await screen.findByRole('alert');expect(screen.queryByText('No audit records match this filter.')).toBeNull();fireEvent.click(screen.getByRole('button',{name:'Retry audit log'}));await screen.findByText('user.update')
})

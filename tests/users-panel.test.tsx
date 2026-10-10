// @vitest-environment jsdom
import { afterEach,beforeEach,it,expect,vi } from 'vitest'
import { cleanup,render,screen,fireEvent,waitFor } from '@testing-library/react'
import UsersPanel from '../src/components/UsersPanel'
const mock=vi.hoisted(()=>({api:vi.fn()}))
vi.mock('../src/lib/admin-api',()=>({adminApi:mock.api}))
const client:any={};const profile={id:'user-a',full_name:'Learner One',email:'learner@example.invalid',role:'student',account_status:'active',updated_at:'2026-10-10T03:00:00Z'}
beforeEach(()=>{vi.resetAllMocks();mock.api.mockImplementation(async(_client,action)=>action==='users.list'?{data:[profile],total:70}:action==='user.inspect'?{data:{profile,auth:{id:'user-a',email:profile.email,email_confirmed_at:'2026-10-09T01:00:00Z'}}}:{data:{...profile,account_status:'suspended'}})})
afterEach(cleanup)
it('browses every account page and resets pagination when filters change',async()=>{
 render(<UsersPanel client={client} permissions={['users.read']}/>);await screen.findByText('Learner One');fireEvent.click(screen.getByRole('button',{name:'Next users'}));await waitFor(()=>expect(mock.api).toHaveBeenLastCalledWith(client,'users.list',expect.objectContaining({offset:25,limit:25})));
 await screen.findByText('Learner One');fireEvent.change(screen.getByLabelText('Search users'),{target:{value:'Learner'}});fireEvent.click(screen.getByRole('button',{name:'Apply user filters'}));await waitFor(()=>expect(mock.api).toHaveBeenLastCalledWith(client,'users.list',expect.objectContaining({offset:0,search:'Learner'})))
})
it('renders the actual profile/auth envelope and keeps readers read-only',async()=>{
 render(<UsersPanel client={client} permissions={['users.read']}/>);fireEvent.click(await screen.findByRole('button',{name:'Inspect Learner One'}));await screen.findByRole('heading',{name:'Learner One'});expect(screen.getByText('2026-10-09T01:00:00Z')).toBeTruthy();expect(screen.queryByLabelText('New account status')).toBeNull()
})
it('preserves failed status decisions and submits a guarded, audited change once',async()=>{
 let writes=0;mock.api.mockImplementation(async(_client,action)=>{if(action==='users.list')return {data:[profile],total:1};if(action==='user.inspect')return {data:{profile,auth:null}};if(++writes===1)throw new Error('Record changed; refresh before retrying');return {data:{...profile,account_status:'suspended'}}});
 render(<UsersPanel client={client} permissions={['users.read','users.manage']}/>);fireEvent.click(await screen.findByRole('button',{name:'Inspect Learner One'}));await screen.findByLabelText('New account status');fireEvent.change(screen.getByLabelText('New account status'),{target:{value:'suspended'}});fireEvent.change(screen.getByLabelText('Status change reason'),{target:{value:'Confirmed moderation decision'}});
 fireEvent.click(screen.getByRole('button',{name:'Confirm account status change'}));await screen.findByRole('alert');expect((screen.getByLabelText('Status change reason') as HTMLTextAreaElement).value).toBe('Confirmed moderation decision');
 const retry=screen.getByRole('button',{name:'Confirm account status change'});fireEvent.click(retry);fireEvent.click(retry);await screen.findByText('Account status saved and audited.');expect(writes).toBe(2);expect(mock.api).toHaveBeenLastCalledWith(client,'user.update',{user_id:'user-a',account_status:'suspended',reason:'Confirmed moderation decision',expected_updated_at:profile.updated_at});expect((screen.getByRole('button',{name:'Confirm account status change'}) as HTMLButtonElement).disabled).toBe(true)
})
it('shows a retryable load error rather than an empty account list',async()=>{
 mock.api.mockRejectedValueOnce(new Error('Network unavailable'));render(<UsersPanel client={client} permissions={['users.read']}/>);await screen.findByRole('alert');expect(screen.queryByText('No users match these filters.')).toBeNull();fireEvent.click(screen.getByRole('button',{name:'Retry users'}));await screen.findByText('Learner One')
})

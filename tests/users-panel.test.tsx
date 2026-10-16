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

it('distinguishes a confirmed teacher email from a submitted professional profile',async()=>{
 const teacher={...profile,id:'teacher-a',role:'teacher',full_name:'Verified Teacher',profile_completion:0}
 mock.api.mockImplementation(async(_client,action)=>action==='users.list'?{data:[teacher],total:1}:action==='user.inspect'?{data:{profile:teacher,auth:{id:'teacher-a',email_confirmed_at:'2026-10-13T20:02:31Z'}}}:{})
 render(<UsersPanel client={client} permissions={['users.read']}/>)
 fireEvent.click(await screen.findByRole('button',{name:'Inspect Verified Teacher'}))
 expect(await screen.findByText(/teacher has not completed the required qualifications/)).toBeTruthy()
 expect(screen.getByText(/Email confirmation and teacher registration are separate/)).toBeTruthy()
 expect(screen.queryByLabelText('New account status')).toBeNull()
})

it.each(['student','parent','teacher','employer','company','mentor','partner'])('prepares approval for a pending %s without submitting until confirmed',async(role)=>{
 const pending={...profile,role,account_status:'pending_verification'}
 mock.api.mockImplementation(async(_client,action)=>action==='users.list'?{data:[pending],total:1}:action==='user.inspect'?{data:{profile:pending,auth:null}}:{data:{...pending,account_status:'active'}})
 render(<UsersPanel client={client} permissions={['users.read','users.manage']}/>)
 fireEvent.click(await screen.findByRole('button',{name:'Inspect Learner One'}))
 fireEvent.click(await screen.findByRole('button',{name:'Approve app access'}))
 expect(mock.api.mock.calls.filter(call=>call[1]==='user.update')).toHaveLength(0)
 fireEvent.click(screen.getByRole('button',{name:'Confirm account status change'}))
 await screen.findByText('App access is already active. No additional account approval is needed.')
 expect(mock.api).toHaveBeenLastCalledWith(client,'user.update',{user_id:profile.id,account_status:'active',reason:'Reviewed account and approved app access.',expected_updated_at:profile.updated_at})
})

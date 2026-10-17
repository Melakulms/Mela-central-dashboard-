// @vitest-environment jsdom
import { afterEach,beforeEach,it,expect,vi } from 'vitest'
import { cleanup,render,screen,fireEvent,waitFor } from '@testing-library/react'
import AIWorkforcePanel from '../src/modules/AIWorkforcePanel'
const mocks=vi.hoisted(()=>({agents:vi.fn(),approvals:vi.fn(),runs:vi.fn(),health:vi.fn(),consult:vi.fn(),review:vi.fn(),toggle:vi.fn()}))
vi.mock('../src/modules/aiWorkforce',()=>({getAIAgents:mocks.agents,getAIApprovals:mocks.approvals,getAIRuns:mocks.runs,getAIHealth:mocks.health,consultAIWorker:mocks.consult,reviewAIApproval:mocks.review,setAgentEnabled:mocks.toggle}))
const agent={id:'agent-a',name:'Student tutor',description:'Educational support',domain:'education',enabled:true,autonomy_level:1,max_steps:2,timeout_seconds:30}
const approval={id:'approval-a',task_id:'task-a',requested_by:'requester-a',level:2,action_type:'content.draft',action_payload:{request:'Prepare a mathematics lesson'},status:'pending',created_at:'2026-10-10T03:00:00Z'}
const client:any={functions:{invoke:vi.fn()}}
beforeEach(()=>{vi.resetAllMocks();mocks.agents.mockResolvedValue([agent]);mocks.approvals.mockResolvedValue({data:[approval],total:51});mocks.runs.mockResolvedValue({data:[],total:60});mocks.consult.mockResolvedValue({ok:true,response:'Review the curriculum mapping first.',agent:{name:'Student tutor'},advisory_only:true});mocks.health.mockResolvedValue({provider_configured:true,enabled_agents:26,tool_assignments:97,run_count:0,task_count:0,configuration_ready:true,execution_verified:false,note:'Requires live check'});mocks.review.mockResolvedValue({});mocks.toggle.mockResolvedValue({})})
afterEach(cleanup)
it('passes the verified client and browses beyond the first run page',async()=>{
 render(<AIWorkforcePanel client={client}/>);await screen.findByText('Student tutor');
 expect(mocks.agents).toHaveBeenCalledWith(client);fireEvent.click(screen.getByRole('button',{name:'Next runs'}));
 await waitFor(()=>expect(mocks.runs).toHaveBeenLastCalledWith(client,25,''));await screen.findByLabelText('Run status');
 fireEvent.change(screen.getByLabelText('Run status'),{target:{value:'failed'}});await waitFor(()=>expect(mocks.runs).toHaveBeenLastCalledWith(client,0,'failed'));
})
it('retries initial loading failures without claiming there are no pending approvals',async()=>{
 mocks.approvals.mockRejectedValueOnce(new Error('Network unavailable'));render(<AIWorkforcePanel client={client}/>);
 await screen.findByRole('alert');expect(screen.queryByText('No pending approvals.')).toBeNull();fireEvent.click(screen.getByRole('button',{name:'Retry AI workforce'}));await screen.findByText('Student tutor');expect(screen.queryByRole('alert')).toBeNull()
})
it('shows approval payload, preserves a failed review and serializes retry',async()=>{
 mocks.review.mockRejectedValueOnce(new Error('Please retry'));render(<AIWorkforcePanel client={client}/>);await screen.findByText('Student tutor');
 fireEvent.click(screen.getByRole('button',{name:'Inspect approval approval-a'}));expect(screen.getByText(/Prepare a mathematics lesson/)).toBeTruthy();
 const button=screen.getByRole('button',{name:'Approve request'}) as HTMLButtonElement;expect(button.disabled).toBe(true);
 fireEvent.change(screen.getByLabelText('Review reason'),{target:{value:'Reviewed the draft request.'}});fireEvent.click(button);await screen.findByRole('alert');
 expect((screen.getByLabelText('Review reason') as HTMLTextAreaElement).value).toBe('Reviewed the draft request.');fireEvent.click(button);fireEvent.click(button);
 await waitFor(()=>expect(mocks.review).toHaveBeenCalledTimes(2));expect(mocks.review).toHaveBeenLastCalledWith(client,'approval-a','approved','Reviewed the draft request.');await screen.findByText(/The requester must resume the task/)
})
it('inspects previously reviewed approvals with read-only details',async()=>{
 mocks.approvals.mockResolvedValue({data:[{...approval,status:'approved',review_note:'Reviewed'}],total:1});render(<AIWorkforcePanel client={client}/>);await screen.findByText('Student tutor');
 fireEvent.change(screen.getByLabelText('Approval status'),{target:{value:'approved'}});await waitFor(()=>expect(mocks.approvals).toHaveBeenLastCalledWith(client,0,'approved'));await screen.findByText('Student tutor');
 fireEvent.click(screen.getByRole('button',{name:'Inspect approval approval-a'}));expect(screen.queryByRole('button',{name:'Approve request'})).toBeNull();expect(screen.getByText('Review note: Reviewed')).toBeTruthy()
})
it('does not clear a failed AI task and does not execute twice',async()=>{
 client.functions.invoke.mockResolvedValueOnce({data:{error:'Provider unavailable'},error:null}).mockResolvedValueOnce({data:{ok:true,response:'Start with algebra.'},error:null});
 render(<AIWorkforcePanel client={client}/>);await screen.findByText('Student tutor');fireEvent.change(screen.getByLabelText('AI task'),{target:{value:'Explain algebra'}});fireEvent.click(screen.getByRole('button',{name:'Run AI'}));await screen.findByRole('alert');expect((screen.getByLabelText('AI task') as HTMLTextAreaElement).value).toBe('Explain algebra');
 const retry=screen.getByRole('button',{name:'Run AI'});fireEvent.click(retry);fireEvent.click(retry);await screen.findByText('Start with algebra.');expect(client.functions.invoke).toHaveBeenCalledTimes(2)
})

it('does not confuse configured agents with successfully executed runs',async()=>{
 render(<AIWorkforcePanel client={client}/>)
 await screen.findByText('Student tutor')
 expect(screen.getByText(/Configuration present; a successful real AI response is still required/)).toBeTruthy()
 expect(screen.getByText(/Choose an enabled worker for advice/)).toBeTruthy()
})
it('warns the administrator if the AI provider secret is not configured',async()=>{
 mocks.health.mockResolvedValueOnce({provider_configured:false,enabled_agents:26,tool_assignments:97,run_count:0,task_count:0,configuration_ready:false,execution_verified:false,note:'Missing secret'})
 render(<AIWorkforcePanel client={client}/>)
 await screen.findByText(/add GROQ_API_KEY/)
 expect(screen.getByText(/AI service is not ready/)).toBeTruthy()
})

it('routes a selected AI worker task only through the admin-authorized endpoint',async()=>{
 render(<AIWorkforcePanel client={client}/>)
 await screen.findByText('Student tutor')
 fireEvent.change(screen.getByLabelText('AI worker'),{target:{value:'agent-a'}})
 fireEvent.change(screen.getByLabelText('AI task'),{target:{value:'Review the question bank process'}})
 fireEvent.click(screen.getByRole('button',{name:'Run AI'}))
 await screen.findByText('Review the curriculum mapping first.')
 expect(mocks.consult).toHaveBeenCalledWith(client,'agent-a','Review the question bank process')
 expect(client.functions.invoke).not.toHaveBeenCalled()
 expect(screen.getByText(/No administrative action was executed/)).toBeTruthy()
})

it('shows Groq free-tier provider selection without claiming completed AI responses',async()=>{
 mocks.health.mockResolvedValueOnce({provider_configured:true,provider:'groq',enabled_agents:26,tool_assignments:97,run_count:0,task_count:0,configuration_ready:true,execution_verified:false,note:'Not verified'})
 render(<AIWorkforcePanel client={client}/>)
 await screen.findByText(/Configured \\(Groq free API\\)/)
 expect(screen.getByText(/successful real AI response is still required/)).toBeTruthy()
})

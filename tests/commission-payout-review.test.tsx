// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import CommissionPayoutReview from '../src/components/CommissionPayoutReview'
import {adminApi} from '../src/lib/admin-api'

vi.mock('../src/lib/admin-api',()=>({adminApi:vi.fn()}))
const api=vi.mocked(adminApi)
const rpc=vi.fn()
const client={rpc} as any
const row={id:'commission-1',inviter_user_id:'11111111-aaaa-bbbb-cccc-dddddddddddd',
  registered_user_id:'22222222-aaaa-bbbb-cccc-dddddddddddd',
  amount:20,currency:'ETB',source_order_id:'33333333-aaaa-bbbb-cccc-dddddddddddd',
  status:'pending',invitation_code:'REF-123'}

beforeEach(()=>{
 vi.resetAllMocks()
 api.mockImplementation(async (_client,action)=>{
   if(action==='commission.list')return {data:[row]}
   if(action==='commission.inspect')return {data:{status:'paid'}}
   throw new Error('Unexpected action: '+action)
 })
})
afterEach(cleanup)

it('fails closed when live commission payout flag is disabled',async()=>{
 rpc.mockResolvedValue({data:{payouts_enabled:false},error:null})
 render(<CommissionPayoutReview client={client}/>)
 await screen.findByText(/Commission disbursements are disabled/)
 expect((screen.getByText('Review outgoing evidence') as HTMLButtonElement).disabled).toBe(true)
 expect(rpc).not.toHaveBeenCalledWith('mela_record_referral_payout_v1',expect.anything())
})

it('requires independent proof and server-side confirmation before recording a paid commission',async()=>{
 rpc.mockImplementation(async (name:string)=>{
   if(name==='mela_payment_readiness_v1')return {data:{payouts_enabled:true},error:null}
   if(name==='mela_record_referral_payout_v1')return {data:{status:'paid',commission_id:row.id},error:null}
   throw new Error('Unknown RPC')
 })
 render(<CommissionPayoutReview client={client}/>)
 fireEvent.click(await screen.findByText('Review outgoing evidence'))
 const record=screen.getByText('Record verified outgoing payout') as HTMLButtonElement
 expect(record.disabled).toBe(true)
 fireEvent.change(screen.getByLabelText('Outgoing method'),{target:{value:'telebirr'}})
 fireEvent.change(screen.getByLabelText('Actual outgoing transfer reference'),{target:{value:'TRANSFER12345'}})
 fireEvent.change(screen.getByLabelText('Private independent evidence (20–500 characters)'),{
   target:{value:'Actual outgoing provider account statement independently reviewed.'}
 })
 expect(record.disabled).toBe(true)
 const checks=screen.getAllByRole('checkbox') as HTMLInputElement[]
 expect(checks.length).toBe(3)
 checks.forEach(check=>fireEvent.click(check))
 expect(record.disabled).toBe(false)
 fireEvent.click(record)
 await waitFor(()=>expect(rpc).toHaveBeenCalledWith('mela_record_referral_payout_v1',{
   p_commission_id:row.id,p_provider:'telebirr',p_reference:'TRANSFER12345',
   p_evidence_note:'Actual outgoing provider account statement independently reviewed.'
 }))
 await waitFor(()=>expect(api).toHaveBeenCalledWith(client,'commission.inspect',{commission_id:row.id}))
})

it('does not render payout actions on a failed authorization or readiness check',async()=>{
 api.mockRejectedValueOnce(new Error('MFA authorization required'))
 rpc.mockResolvedValue({data:{payouts_enabled:true},error:null})
 render(<CommissionPayoutReview client={client}/>)
 await screen.findByText('MFA authorization required')
 expect(screen.queryByText('Review outgoing evidence')).toBeNull()
})

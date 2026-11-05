// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import PaymentReadinessPanel from '../src/components/PaymentReadinessPanel'

const rpc=vi.fn()
const client={rpc} as any
const ready={
 checkout_enabled:true,platform_payments_enabled:true,payouts_enabled:false,active_reviewers:1,
 financial_launch_approved:false,
 financial_release_requirements:[
  {requirement_key:'payments_provider',status:'pending',required:true,evidence_recorded:false},
  {requirement_key:'legal_review',status:'pending',required:true,evidence_recorded:false},
  {requirement_key:'wallet_business_legal',status:'pending',required:true,evidence_recorded:false},
 ],
 paid_products:[{product_key:'mela_pro_monthly',title:'MELA Pro',amount_minor:5000,active:true}],
 accounts:[{id:'receiver-1',provider:'telebirr',recipient:'masked-for-test',label:'Verified receiver',active:true,verified:true}],
}
beforeEach(()=>{vi.resetAllMocks();rpc.mockResolvedValue({data:ready,error:null})})
afterEach(cleanup)

it('warns when checkout is enabled without assuming provider authorization',async()=>{
 render(<PaymentReadinessPanel client={client}/>)
 expect(await screen.findByText(/Enabled in database — NOT proof of launch approval/)).toBeTruthy()
 const alert=screen.getByRole('alert')
 expect(alert.textContent).toContain('Account verification is not the same')
 expect(alert.textContent).toContain('server-side gating')
 expect(screen.getByText('Commission payouts:').parentElement?.textContent).toContain('Disabled')
 expect(screen.queryByText(/Payment collection and payouts remain separately disabled/)).toBeNull()
})

it('does not falsely describe a receiving-account verification as enabling or disabling checkout',async()=>{
 rpc.mockImplementation(async (_name:string,params:{p_action:string})=>{
   if(params.p_action==='verify_account')return {data:{status:'verified'},error:null}
   return {data:ready,error:null}
 })
 render(<PaymentReadinessPanel client={client}/>)
 fireEvent.click(await screen.findByText('Review / deactivate'))
 const checkboxes=screen.getAllByRole('checkbox')
 checkboxes.forEach(el=>fireEvent.click(el))
 fireEvent.change(screen.getByPlaceholderText(/Describe the bank statement/),{target:{value:'Reviewed current signed account statement and verified owner of receiving account.'}})
 fireEvent.click(screen.getByText('Record MFA-verified ownership'))
 await waitFor(()=>expect(rpc).toHaveBeenCalledWith('mela_payment_readiness_v1',expect.objectContaining({p_action:'verify_account'})))
 expect(await screen.findByText(/This does NOT establish payment-provider authorization/)).toBeTruthy()
})

it('fails closed when administrator readiness status cannot be read',async()=>{
 rpc.mockRejectedValueOnce(new Error('MFA required'))
 render(<PaymentReadinessPanel client={client}/>)
 expect((await screen.findByRole('alert')).textContent).toContain('MFA required')
 expect(screen.queryByText(/Enabled in database/)).toBeNull()
})

it('does not show collection enabled if the checkout setting is disabled',async()=>{
 rpc.mockResolvedValue({data:{...ready,checkout_enabled:false,platform_payments_enabled:false},error:null})
 render(<PaymentReadinessPanel client={client}/>)
 expect(await screen.findByText(/Disabled — no subscription transfers should be requested/)).toBeTruthy()
 expect(screen.queryByText(/Account verification is not the same/)).toBeNull()
})

it('shows independent payment-provider, legal and business launch blockers even when payment settings are enabled',async()=>{
 render(<PaymentReadinessPanel client={client}/>)
 expect(await screen.findByText(/New subscription orders and Telegram payment linking are blocked/)).toBeTruthy()
 for(const phrase of ['Licensed payment-provider agreement','Qualified Ethiopian legal review','Business and financial operating authorization']){
  expect(screen.getByText(new RegExp(phrase))).toBeTruthy()
 }
 expect(screen.getAllByText('pending — blocked').length).toBe(3)
})

it('does not mistake three recorded approvals for actual financial or legal certification',async()=>{
 rpc.mockResolvedValue({data:{
  ...ready,
  financial_launch_approved:true,
  financial_release_requirements:ready.financial_release_requirements.map(g=>({...g,status:'complete',evidence_recorded:true})),
 },error:null})
 render(<PaymentReadinessPanel client={client}/>)
 expect(await screen.findByText(/Three approval evidence records are marked complete/)).toBeTruthy()
 expect(screen.getAllByText(/Evidence recorded — independent review still required/).length).toBe(3)
 expect(screen.getByText(/this screen does not certify legal authorization/)).toBeTruthy()
})

it('fails closed when an older status RPC omits provider and legal checks',async()=>{
 rpc.mockResolvedValue({data:{...ready,financial_launch_approved:undefined,financial_release_requirements:undefined},error:null})
 render(<PaymentReadinessPanel client={client}/>)
 expect(await screen.findByText(/Release-gate details could not be verified/)).toBeTruthy()
})

// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest'
import {cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import PaymentReadinessPanel from '../src/components/PaymentReadinessPanel'

const rpc=vi.fn()
const client={rpc} as any
const ready={
 checkout_enabled:true,platform_payments_enabled:true,payouts_enabled:false,active_reviewers:1,
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

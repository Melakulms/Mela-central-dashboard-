import {describe,it,expect} from 'vitest'
import {decisionFor} from '../src/lib/operational-decisions'
describe('Operational review controls',()=>{
 it('only shows decisions to the matching manager',()=>{
  expect(decisionFor('Employer registrations',{status:'pending'},['dashboard.read'])).toBeNull()
  expect(decisionFor('Flagged opportunities',{moderation_status:'flagged'},['moderation.manage'])).toBeNull()
  expect(decisionFor('Reports',{status:'open'},['moderation.manage'])?.action).toBe('report.resolve')
 })
 it('offers explicit company verification without repeating the current decision',()=>{
  expect(decisionFor('Employer accounts',{verification_status:'pending'},['*'])?.action).toBe('employer.verify')
  expect(decisionFor('Employer accounts',{verification_status:'verified'},['employers.manage'])?.choices).not.toContain('verified')
 })
 it('keeps finalized registrations and reports closed',()=>{
  expect(decisionFor('Employer registrations',{status:'approved'},['*'])).toBeNull()
  expect(decisionFor('Reports',{status:'resolved'},['*'])).toBeNull()
 })
 it('offers only permitted moderation transitions',()=>{
  expect(decisionFor('Opportunities',{moderation_status:'rejected'},['employers.manage'])?.choices).toEqual(['pending_review'])
  expect(decisionFor('Opportunities',{moderation_status:'approved'},['*'])?.choices).toEqual(['flagged'])
 })
})

it('does not offer generic closure for contract disputes',()=>{
 expect(decisionFor('Reports',{status:'open',target_type:'freelance_contract'},['*'])).toBeNull()
 expect(decisionFor('Reports',{status:'open',reason:'contract_dispute'},['moderation.manage'])).toBeNull()
})

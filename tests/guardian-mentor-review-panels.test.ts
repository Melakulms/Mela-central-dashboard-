// @vitest-environment node
import {readFileSync} from 'node:fs'
import {expect,it} from 'vitest'
const guardian=readFileSync(new URL('../src/components/GuardianConsentReviewPanel.tsx',import.meta.url),'utf8')
const mentor=readFileSync(new URL('../src/components/MentorApplicationReviewPanel.tsx',import.meta.url),'utf8')
const operations=readFileSync(new URL('../src/components/OperationalModule.tsx',import.meta.url),'utf8')
it('admin guardian decisions require evidence and use the safeguarded RPC',()=>{
  expect(guardian).toContain("client.rpc('review_guardian_consent'")
  expect(guardian).toContain('checked')
  expect(guardian).toContain('guardian_user_id')
  expect(guardian).toContain('independent')
  expect(guardian).not.toContain(".from('guardian_relationships').update(")
})
it('mentor eligibility review cannot grant mentor permissions or promote roles',()=>{
  expect(mentor).toContain("client.from('mentorship_applications')")
  expect(mentor).toContain("'reviewed_eligible'")
  expect(mentor).toContain("review_notes:notes.trim()")
  expect(mentor).not.toContain('mentor_profiles')
  expect(mentor).not.toContain('review_mentor_profile')
  expect(operations).toContain("<GuardianConsentReviewPanel client={client}/>")
  expect(operations).toContain("<MentorApplicationReviewPanel client={client}/>")
})

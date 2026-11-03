import { describe, expect, it } from 'vitest'
import { privacyReviewHandoff } from '../src/lib/privacy-case-handoff'

describe('redacted privacy case handoff', () => {
  it('is unconditionally not a legal resolution, even with six staff observations', () => {
    const entries = [
      'requester_identity', 'guardian_authority', 'scope_and_third_parties',
      'retention_and_legal_basis', 'safeguarding_review', 'fulfillment_plan',
    ].map(checkpoint=>({
      checkpoint, finding:'reviewed_no_issue_identified', recorded_at:'2026-11-03T12:00:00Z',
    }))
    const text = privacyReviewHandoff({requestId:'request-001',requestType:'erasure',entries})
    expect(text).toContain('6 of 6 categories')
    expect(text).toContain('UNVERIFIED REQUIREMENTS — ALWAYS BLOCK FINAL DECISION HERE')
    expect(text).toContain('No personal information was exported, erased or delivered')
    expect(text).toContain('request-001')
    expect(text).not.toContain('Case approved')
  })

  it('flags unresolved categories without copying any free-text messages or user IDs', () => {
    const entries = [{
      checkpoint:'safeguarding_review',finding:'needs_follow_up',
      recorded_at:'2026-11-03T12:00:00Z',
      response_notes:'PRIVATE-MESSAGE-DO-NOT-COPY',
      user_id:'PRIVATE-USER-ID-DO-NOT-COPY',
    }]
    const text = privacyReviewHandoff({requestId:'request-002',requestType:'export',entries})
    expect(text).toContain('1 of 6 categories')
    expect(text).toContain('FOLLOW-UP REQUIRED')
    expect(text).toContain('NO RECORDED OBSERVATION')
    expect(text).not.toContain('PRIVATE-MESSAGE-DO-NOT-COPY')
    expect(text).not.toContain('PRIVATE-USER-ID-DO-NOT-COPY')
  })

  it('does not include unexpected or untrusted request category text', () => {
    const text = privacyReviewHandoff({
      requestId:'request-003',requestType:'<script>bad()</script>',entries:[],
    })
    expect(text).toContain('Request category: other')
    expect(text).not.toContain('<script>')
  })
})

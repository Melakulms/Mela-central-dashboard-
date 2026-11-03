/**
 * Redacted, human-readable privacy review handoff. It is not evidence of
 * fulfillment, legal approval, identity verification or data delivery.
 * Never pass account IDs, user names, case notes, documents or free text here.
 */
export type ReviewObservation = {
  checkpoint: string
  finding: string
  recorded_at: string
}
export const PRIVACY_CHECKPOINTS = [
  ['requester_identity','Requester identity'],
  ['guardian_authority','Guardian authority when applicable'],
  ['scope_and_third_parties','Scope and third-party privacy'],
  ['retention_and_legal_basis','Legal basis and retention'],
  ['safeguarding_review','Child safeguarding and preserved evidence'],
  ['fulfillment_plan','Secure fulfillment planning'],
] as const
const permittedFindings = new Set(['needs_follow_up','reviewed_no_issue_identified'])

export function privacyReviewHandoff({
  requestId, requestType, entries,
}: {
  requestId: string
  requestType: string
  entries: ReviewObservation[]
}): string {
  const observations = PRIVACY_CHECKPOINTS.map(([key,label])=>{
    const entry = entries.find(item=>item.checkpoint===key)
    const finding = entry && permittedFindings.has(entry.finding)
      ? entry.finding === 'needs_follow_up' ? 'FOLLOW-UP REQUIRED' : 'Staff noted no issue (unverified)'
      : 'NO RECORDED OBSERVATION'
    return {key,label,hasEntry:!!entry,finding}
  })
  const observedCount = observations.filter(row=>row.hasEntry).length
  const unresolved = observations.filter(row=>row.finding!=='Staff noted no issue (unverified)').length
  const safeCategory = ['access','export','rectification','erasure','objection','restriction'].includes(requestType)
    ? requestType : 'other'
  return [
    'MELA PRIVACY REQUEST — REDACTED CASE HANDOFF',
    'DRAFT OPERATIONAL SUMMARY — NOT FULFILLMENT OR LEGAL APPROVAL',
    `Request reference: ${requestId}`,
    `Request category: ${safeCategory}`,
    'Status: in review (open)',
    `Visible staff observations: ${observedCount} of 6 categories (last 60 records only)`,
    `Categories lacking a clear staff observation: ${unresolved}`,
    '',
    ...observations.map(row=>`- ${row.label}: ${row.finding}`),
    '',
    'UNVERIFIED REQUIREMENTS — ALWAYS BLOCK FINAL DECISION HERE:',
    '- Independent requester identity and guardian authorization where applicable',
    '- Safeguarding, legal basis, retention and Ethiopia data-hosting approval',
    '- Authorized actual fulfillment, redaction and secure delivery evidence',
    '- Independent legal/operational review of fulfillment outcome and appeals',
    '',
    'No personal information was exported, erased or delivered by this summary.',
    'It excludes names, user IDs, messages, attachments and documents.',
    'A staff observation is not independent verification; checklist coverage is not readiness.',
    'Share the request reference only through an approved private case-management channel.',
  ].join('\n')
}

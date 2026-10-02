export type Decision = { action: string; idField: string; statusField: string; notesField: string; choices: string[] }
export function decisionFor(group: string, row: Record<string, unknown>, permissions: string[]): Decision | null {
  const can = (permission: string) => permissions.includes('*') || permissions.includes(permission)
  if (group === 'Employer accounts' && can('employers.manage')) return {action:'employer.verify',idField:'employer_id',statusField:'verification_status',notesField:'verification_notes',choices:['under_review','verified','rejected','suspended'].filter(status=>status!==row.verification_status)}
  if (group === 'Employer registrations' && can('employers.manage') && ['pending','under_review'].includes(String(row.status))) {
    return { action:'employer.review',idField:'request_id',statusField:'status',notesField:'review_notes',choices:['under_review','approved','rejected'] }
  }
  if (['Opportunities','Flagged opportunities'].includes(group) && can('employers.manage')) {
    const transitions: Record<string,string[]> = {pending_review:['approved','rejected','flagged'],flagged:['pending_review','approved','rejected'],rejected:['pending_review'],approved:['flagged']}
    const choices = transitions[String(row.moderation_status)]
    if (choices) return {action:'opportunity.review',idField:'opportunity_id',statusField:'moderation_status',notesField:'moderation_notes',choices}
  }
  if (group === 'Proctor reviews' && can('moderation.manage') && String(row.status) === 'review_required') {
    return {action:'review_proctored_attempt',idField:'attempt_id',statusField:'decision',notesField:'notes',choices:['clear','void']}
  }
  if (row.target_type === 'freelance_contract' || row.reason === 'contract_dispute') return null
  if (group === 'Reports' && can('moderation.manage') && ['open','reviewing'].includes(String(row.status))) {
    return {action:'report.resolve',idField:'report_id',statusField:'status',notesField:'resolution_notes',choices:['reviewing','resolved','dismissed']}
  }
  return null
}

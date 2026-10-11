import { afterEach, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { SupabaseClient } from '@supabase/supabase-js'
import ProfessionalQuestionReviewPanel from '../src/components/ProfessionalQuestionReviewPanel'

afterEach(cleanup)

it('loads real teacher-only progress on demand and filters grade/subject rows', async () => {
  const rpc=vi.fn().mockResolvedValue({error:null,data:{
    active_questions:140000,teacher_approved:9,teacher_changes_required:1,
    pending_or_unverified:139990,review_slices:1400,assigned_slices:5,qualified_teacher_reviewers:2,
    generated_at:'2026-10-11T10:00:00Z',
    programs:[{program_key:'g4_math',grade_level:4,subject_title:'Mathematics',total:100,teacher_approved:9,needs_changes:1,remaining:90},
      {program_key:'g6_science',grade_level:6,subject_title:'Science',total:120,teacher_approved:0,needs_changes:0,remaining:120}],
  }})
  const client={rpc} as unknown as SupabaseClient
  render(<ProfessionalQuestionReviewPanel client={client}/>)
  expect(rpc).not.toHaveBeenCalled()
  fireEvent.click(screen.getByRole('button',{name:'Load teacher review counts'}))
  await screen.findByText('140,000')
  expect(rpc).toHaveBeenCalledWith('get_admin_question_review_progress_v39')
  expect(screen.getByText('139,990')).toBeTruthy()
  fireEvent.change(screen.getByLabelText('Filter question review subjects'),{target:{value:'Math'}})
  expect(screen.getByText('Mathematics')).toBeTruthy()
  expect(screen.queryByText('Science')).toBeNull()
})

it('reports inaccessible database rather than treating unavailable review stats as zero', async () => {
  const rpc=vi.fn().mockResolvedValue({data:null,error:new Error('Access denied')})
  render(<ProfessionalQuestionReviewPanel client={{rpc} as unknown as SupabaseClient}/>)
  fireEvent.click(screen.getByRole('button',{name:'Load teacher review counts'}))
  expect((await screen.findByRole('alert')).textContent).toContain('Access denied')
  expect(screen.queryByText('0')).toBeNull()
})

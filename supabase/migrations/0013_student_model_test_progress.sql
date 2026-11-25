-- ============================================================================
-- 0013 Student model-test progress + class positions
-- Apply with:  supabase db push (or paste into the Supabase SQL editor)
--
-- Computes progress and ranks from submitted official attempts only
-- ('submitted' / 'auto_submitted'). Local practice never writes attempts.
-- The SECURITY DEFINER function reads the tenant/session itself and returns
-- aggregate ranks only — never another student's answers or private details.
-- ============================================================================

create index if not exists idx_model_test_attempts_progress_scope
  on public.model_test_attempts (academy_id, status, class_name, student_id);

create or replace function public.student_model_test_progress(
  p_academy_id text,
  p_class_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sid text := public.current_actor_id();
  v_academy text := public.current_academy_id();
  v_student_class text;
  v_class text;
  v_result jsonb;
begin
  if coalesce(public.current_user_role(), '') <> 'student' then
    raise exception 'Only students can view progress';
  end if;

  if p_academy_id is null or btrim(p_academy_id) = ''
     or btrim(p_academy_id) <> coalesce(v_academy, '') then
    raise exception 'প্রতিষ্ঠানের তথ্য মেলেনি।';
  end if;

  -- Prefer the signed-in student's own stored class; p_class_name is only a
  -- fallback for older sessions. A forged class name cannot widen the scope.
  select r."class"::text into v_student_class
    from public.students r
   where r.id::text = v_sid
     and r.academy_id::text = v_academy
   limit 1;
  v_class := coalesce(nullif(btrim(v_student_class), ''), btrim(coalesce(p_class_name, '')));

  if coalesce(v_class, '') = '' then
    return jsonb_build_object(
      'student_id', v_sid,
      'class_name', '',
      'overall', '{}'::jsonb,
      'subjects', '[]'::jsonb,
      'history', '[]'::jsonb
    );
  end if;

  with submitted as (
    select
      a.student_id,
      a.test_id,
      coalesce(nullif(btrim(e.subject_name), ''), 'অনির্দিষ্ট') as subject_name,
      coalesce(nullif(btrim(e.exam_title), ''), 'পরীক্ষা') as exam_title,
      a.score,
      a.total_marks,
      a.percentage,
      a.correct_count,
      a.wrong_count,
      a.unanswered_count,
      a.passed,
      a.submitted_at,
      a.id
    from public.model_test_attempts a
    left join public.exam_schedules e
      on e.id::text = a.test_id
     and e.academy_id::text = a.academy_id
    where a.academy_id = v_academy
      and a.status in ('submitted', 'auto_submitted')
      and lower(coalesce(nullif(btrim(a.class_name), ''), nullif(btrim(e.class_name), ''), '')) = lower(v_class)
      and (e.class_name is null or btrim(e.class_name) = '' or lower(btrim(e.class_name)) = lower(v_class))
  ),
  ranked_scores as (
    select
      s.*,
      row_number() over (
        partition by s.student_id, s.subject_name
        order by s.percentage desc, s.submitted_at desc nulls last, s.id
      ) as best_rn,
      row_number() over (
        partition by s.student_id, s.subject_name
        order by s.submitted_at desc nulls last, s.id
      ) as latest_rn
    from submitted s
  ),
  student_totals as (
    select
      student_id,
      count(*) as tests_taken,
      sum(score) as total_score,
      sum(total_marks) as max_score,
      round(avg(score), 2) as average_score,
      round(avg(percentage), 2) as average_percentage,
      round(count(*) filter (where passed) * 100.0 / count(*), 2) as pass_rate,
      sum(correct_count) as correct,
      sum(wrong_count) as wrong,
      sum(unanswered_count) as unanswered
    from submitted
    group by student_id
  ),
  ranked_overall as (
    select
      st.*,
      rank() over (
        order by st.total_score desc, st.average_percentage desc, st.tests_taken desc
      ) as rank,
      count(*) over () as total_students
    from student_totals st
  ),
  subject_totals as (
    select
      subject_name,
      student_id,
      count(*) as tests_taken,
      sum(score) as total_score,
      sum(total_marks) as max_score,
      round(avg(score), 2) as average_score,
      round(avg(percentage), 2) as average_percentage,
      round(count(*) filter (where passed) * 100.0 / count(*), 2) as pass_rate,
      sum(correct_count) as correct,
      sum(wrong_count) as wrong,
      sum(unanswered_count) as unanswered
    from submitted
    group by subject_name, student_id
  ),
  ranked_subjects as (
    select
      st.*,
      rank() over (
        partition by st.subject_name
        order by st.total_score desc, st.average_percentage desc, st.tests_taken desc
      ) as rank,
      count(*) over (partition by st.subject_name) as total_students
    from subject_totals st
  )
  select jsonb_build_object(
    'student_id', v_sid,
    'class_name', v_class,
    'overall', coalesce((
      select jsonb_build_object(
        'rank', ro.rank,
        'total_students', ro.total_students,
        'tests_taken', ro.tests_taken,
        'total_score', ro.total_score,
        'max_score', ro.max_score,
        'average_score', ro.average_score,
        'average_percentage', ro.average_percentage,
        'pass_rate', ro.pass_rate,
        'correct', ro.correct,
        'wrong', ro.wrong,
        'unanswered', ro.unanswered
      )
      from ranked_overall ro
      where ro.student_id = v_sid
    ), '{}'::jsonb),
    'subjects', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'subject_name', rs.subject_name,
          'rank', rs.rank,
          'total_students', rs.total_students,
          'tests_taken', rs.tests_taken,
          'total_score', rs.total_score,
          'max_score', rs.max_score,
          'average_score', rs.average_score,
          'average_percentage', rs.average_percentage,
          'pass_rate', rs.pass_rate,
          'correct', rs.correct,
          'wrong', rs.wrong,
          'unanswered', rs.unanswered,
          'best_score', best.score,
          'best_total', best.total_marks,
          'best_percentage', best.percentage,
          'latest_score', latest.score,
          'latest_total', latest.total_marks,
          'latest_percentage', latest.percentage
        )
        order by rs.subject_name
      )
      from ranked_subjects rs
      left join lateral (
        select r.score, r.total_marks, r.percentage
          from ranked_scores r
         where r.student_id = rs.student_id
           and r.subject_name = rs.subject_name
           and r.best_rn = 1
         limit 1
      ) best on true
      left join lateral (
        select r.score, r.total_marks, r.percentage
          from ranked_scores r
         where r.student_id = rs.student_id
           and r.subject_name = rs.subject_name
           and r.latest_rn = 1
         limit 1
      ) latest on true
      where rs.student_id = v_sid
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'test_id', h.test_id,
          'title', h.exam_title,
          'subject_name', h.subject_name,
          'submitted_at', h.submitted_at,
          'score', h.score,
          'total_marks', h.total_marks,
          'percentage', h.percentage,
          'passed', h.passed
        )
        order by h.submitted_at desc nulls last
      )
      from (
        select s.*
          from submitted s
         where s.student_id = v_sid
         order by s.submitted_at desc nulls last
         limit 10
      ) h
    ), '[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;

comment on function public.student_model_test_progress(text, text) is
  'Aggregate-only progress and class/subject ranks for the signed-in student; submitted official attempts only.';

revoke all on function public.student_model_test_progress(text, text) from public;
grant execute on function public.student_model_test_progress(text, text) to authenticated;

notify pgrst, 'reload schema';

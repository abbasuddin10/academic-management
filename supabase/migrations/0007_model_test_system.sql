-- ============================================================================
-- 0007 Complete Model Test system
-- Apply with:  supabase db push   (or paste into the Supabase SQL editor)
--
-- Depends on 0001 (app_sessions / RLS helpers), 0002 (reader key),
--            0003/0006 (student notification pipeline).
--
-- WHAT THIS ADDS
--   1. Explicit model-test configuration + lifecycle on `exam_schedules`:
--      duration_minutes, marks_per_question, total_marks, negative_marks,
--      pass_percent, status (draft|published|cancelled|expired), snapshot.
--      `is_active` is kept ONLY as a compatibility mirror of published status.
--   2. Immutable question snapshot per test + accurate question_hash trigger.
--   3. `model_test_attempts` / `model_test_answers` with ownership, status and
--      duplicate-submit protection (one live attempt per test+student).
--   4. Role-aware RLS: staff manage, students take; no direct score writes.
--   5. SECURITY DEFINER RPCs so scoring/deadlines are enforced server-side.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 0. Small role helpers (reuse the functions created in 0001/0002).
-- ---------------------------------------------------------------------------
create or replace function public.current_actor_id()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select case
    when strpos(coalesce(public.current_reader_key(), ''), ':') > 0
      then split_part(public.current_reader_key(), ':', 2)
    else coalesce(auth.uid()::text, '')
  end;
$$;

create or replace function public.is_academy_staff()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(public.current_user_role(), '') in
    ('teacher', 'staff', 'super_admin', 'admin');
$$;

create or replace function public.is_academy_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(public.current_user_role(), '') in ('super_admin', 'admin');
$$;

create or replace function public.can_manage_model_test(p_creator_id text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select public.is_academy_staff()
    and (
      public.is_academy_admin()
      or p_creator_id is null
      or btrim(p_creator_id) = ''
      or p_creator_id = public.current_actor_id()
    );
$$;

revoke all on function public.current_actor_id() from public;
revoke all on function public.is_academy_staff() from public;
revoke all on function public.is_academy_admin() from public;
revoke all on function public.can_manage_model_test(text) from public;
grant execute on function public.current_actor_id() to authenticated;
grant execute on function public.is_academy_staff() to authenticated;
grant execute on function public.is_academy_admin() to authenticated;
grant execute on function public.can_manage_model_test(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. exam_schedules configuration + lifecycle columns.
-- ---------------------------------------------------------------------------
alter table public.exam_schedules
  -- Core columns (older installs may be missing some of these).
  add column if not exists academy_id            text,
  add column if not exists class_name            text,
  add column if not exists subject_name          text,
  add column if not exists exam_title            text,
  add column if not exists chapter_name          text,
  add column if not exists start_time            timestamptz,
  add column if not exists end_time              timestamptz,
  add column if not exists created_at            timestamptz not null default now(),
  -- Compatibility columns.
  add column if not exists is_active             boolean not null default true,
  add column if not exists question_count        integer not null default 0,
  add column if not exists selected_question_ids text,
  add column if not exists question_creator_id   text,
  add column if not exists question_creator_name text,
  -- Model-test configuration + lifecycle.
  add column if not exists duration_minutes   integer,
  add column if not exists marks_per_question numeric not null default 1,
  add column if not exists total_marks        numeric not null default 0,
  add column if not exists negative_marks     numeric not null default 0,
  add column if not exists pass_percent       numeric not null default 33,
  add column if not exists status             text not null default 'published',
  add column if not exists questions_snapshot jsonb not null default '[]'::jsonb,
  add column if not exists published_at       timestamptz,
  add column if not exists cancelled_at       timestamptz,
  add column if not exists updated_at         timestamptz not null default now();

-- One-time backfill: legacy is_active=false rows were either cancelled by a
-- teacher or simply expired. Distinguish them so the two are never conflated.
update public.exam_schedules
   set status = case
     when coalesce(is_active, false) then 'published'
     when (end_time::timestamptz) < now() then 'expired'
     else 'cancelled'
   end
 where status = 'published'
   and (coalesce(is_active, true) = false or (end_time::timestamptz) < now());

alter table public.exam_schedules
  drop constraint if exists exam_schedules_status_check;
alter table public.exam_schedules
  add constraint exam_schedules_status_check
  check (status in ('draft', 'published', 'cancelled', 'expired'));

create index if not exists idx_exam_schedules_status
  on public.exam_schedules (academy_id, status, start_time);

-- Keep legacy `is_active` in sync, accept old clients that "cancel" by writing
-- is_active = false, and stamp lifecycle timestamps.
create or replace function public.sync_model_test_state()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    if NEW.status is null or btrim(NEW.status) = '' then
      NEW.status := 'published';
    end if;
  elsif TG_OP = 'UPDATE' and (
          NEW.status is null or NEW.status is distinct from OLD.status
        ) then
    NEW.status := coalesce(NEW.status, OLD.status);
  elsif TG_OP = 'UPDATE'
        and OLD.status = 'published'
        and coalesce(NEW.is_active, true) = false
        and coalesce(OLD.is_active, true) = true then
    -- Legacy client cancelled a published test via is_active only.
    NEW.status := 'cancelled';
  end if;

  if TG_OP = 'UPDATE' then
    if NEW.status = 'published' and OLD.status is distinct from 'published' then
      NEW.published_at := now();
      NEW.cancelled_at := null;
    elsif NEW.status = 'cancelled' and OLD.status is distinct from 'cancelled' then
      NEW.cancelled_at := now();
    end if;
  elsif NEW.status = 'published' then
    NEW.published_at := now();
  end if;

  NEW.is_active := (NEW.status = 'published');
  NEW.updated_at := now();
  return NEW;
end;
$$;

drop trigger if exists trg_model_test_state on public.exam_schedules;
create trigger trg_model_test_state
  before insert or update on public.exam_schedules
  for each row execute function public.sync_model_test_state();

-- ---------------------------------------------------------------------------
-- 2. Immutable question snapshot. Rebuilt only while no student has started.
-- ---------------------------------------------------------------------------
create or replace function public.build_model_test_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids      text[];
  v_snap     jsonb;
  v_ids_json jsonb := '[]'::jsonb;
  v_ids_text text;
begin
  if TG_OP = 'UPDATE'
     and (to_jsonb(NEW) ->> 'selected_question_ids') is distinct from
         (to_jsonb(OLD) ->> 'selected_question_ids')
     and exists (select 1 from public.model_test_attempts a
                  where a.test_id = NEW.id::text)
  then
    raise exception 'Question set cannot change after students have started this test';
  end if;

  if TG_OP = 'INSERT'
     or (TG_OP = 'UPDATE' and (
          (to_jsonb(NEW) ->> 'selected_question_ids') is distinct from
          (to_jsonb(OLD) ->> 'selected_question_ids')
          or coalesce(NEW.questions_snapshot, '[]'::jsonb) = '[]'::jsonb
        ))
  then
    -- Migration 0007 originally did a raw `... ::jsonb` cast here. A legacy
    -- placeholder such as "—" raised 22P02 (Token "—" is invalid) on every
    -- model-test save. Parse defensively and always fall back to an array.
    v_ids_text := btrim(coalesce(to_jsonb(NEW) ->> 'selected_question_ids', ''));
    if left(v_ids_text, 1) = '[' then
      begin
        v_ids_json := v_ids_text::jsonb;
      exception when others then
        v_ids_json := '[]'::jsonb;
      end;
    else
      v_ids_json := '[]'::jsonb;
    end if;
    if jsonb_typeof(v_ids_json) <> 'array' then
      v_ids_json := '[]'::jsonb;
    end if;

    select coalesce(array_agg(elem #>> '{}'), '{}'::text[])
      into v_ids
      from jsonb_array_elements(v_ids_json) as elem;

    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'id',            q.id::text,
                 'question',      coalesce(to_jsonb(q) ->> 'question_text',
                                           to_jsonb(q) ->> 'question', ''),
                 'option_a',      coalesce(to_jsonb(q) ->> 'option_a', ''),
                 'option_b',      coalesce(to_jsonb(q) ->> 'option_b', ''),
                 'option_c',      coalesce(to_jsonb(q) ->> 'option_c', ''),
                 'option_d',      coalesce(to_jsonb(q) ->> 'option_d', ''),
                 'correct_option',coalesce(upper(btrim(coalesce(to_jsonb(q) ->> 'correct_option', ''))), ''),
                 'explanation',   coalesce(to_jsonb(q) ->> 'explanation', ''),
                 'chapter_name',  coalesce(to_jsonb(q) ->> 'chapter_name', '')
               ) order by x.ord
             ), '[]'::jsonb)
      into v_snap
      from unnest(v_ids) with ordinality as x(qid, ord)
      join public.academy_questions q
        on q.id::text = x.qid
       and q.academy_id::text = NEW.academy_id::text;

    NEW.questions_snapshot := v_snap;
    NEW.question_count := jsonb_array_length(v_snap);
    if coalesce(NEW.total_marks, 0) <= 0 then
      NEW.total_marks := jsonb_array_length(v_snap) * coalesce(NEW.marks_per_question, 1);
    end if;
    if NEW.duration_minutes is null or NEW.duration_minutes <= 0 then
      NEW.duration_minutes := greatest(
        1,
        ceil(extract(epoch from ((to_jsonb(NEW) ->> 'end_time')::timestamptz
                               - (to_jsonb(NEW) ->> 'start_time')::timestamptz)) / 60)::integer
      );
    end if;
  end if;

  NEW.negative_marks := greatest(0, coalesce(NEW.negative_marks, 0));
  NEW.marks_per_question := greatest(0, coalesce(NEW.marks_per_question, 1));
  return NEW;
end;
$$;

drop trigger if exists trg_model_test_snapshot on public.exam_schedules;
create trigger trg_model_test_snapshot
  before insert or update on public.exam_schedules
  for each row execute function public.build_model_test_snapshot();

-- Keep question_hash truthful even when a question is edited outside the app.
create or replace function public.sync_question_hash()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  j     jsonb := to_jsonb(NEW);
  v_txt text := coalesce(j ->> 'question_text', j ->> 'question', '');
begin
  NEW.question_hash := encode(
    digest(lower(btrim(v_txt)), 'sha256'), 'hex'
  );
  return NEW;
end;
$$;

drop trigger if exists trg_question_hash on public.academy_questions;
create trigger trg_question_hash
  before insert or update on public.academy_questions
  for each row execute function public.sync_question_hash();

-- Backfill legacy rows whose hash was never stored.
update public.academy_questions
   set question_hash = encode(
         digest(lower(btrim(coalesce(to_jsonb(academy_questions) ->> 'question_text',
                                     to_jsonb(academy_questions) ->> 'question', ''))), 'sha256'),
         'hex')
 where question_hash is null or btrim(question_hash) = '';

-- ---------------------------------------------------------------------------
-- 3. Attempt & answer tables.
-- ---------------------------------------------------------------------------
create table if not exists public.model_test_attempts (
  id                uuid primary key default gen_random_uuid(),
  academy_id        text not null,
  test_id           text not null,
  student_id        text not null,
  student_roll      text,
  class_name        text,
  status            text not null default 'in_progress'
                    check (status in ('in_progress', 'submitted', 'auto_submitted')),
  started_at        timestamptz not null default now(),
  deadline_at       timestamptz not null,
  submitted_at      timestamptz,
  score             numeric not null default 0,
  total_marks       numeric not null default 0,
  correct_count     integer not null default 0,
  wrong_count       integer not null default 0,
  unanswered_count  integer not null default 0,
  percentage        numeric not null default 0,
  passed            boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists idx_model_test_attempts_test
  on public.model_test_attempts (test_id, status);
create index if not exists idx_model_test_attempts_student
  on public.model_test_attempts (academy_id, student_id, started_at desc);

-- A student may retake a test, but never two simultaneous attempts.
drop index if exists idx_model_test_attempts_one_live;
create unique index idx_model_test_attempts_one_live
  on public.model_test_attempts (test_id, student_id)
  where status = 'in_progress';

create table if not exists public.model_test_answers (
  id             uuid primary key default gen_random_uuid(),
  academy_id     text not null,
  attempt_id     uuid not null
                 references public.model_test_attempts(id) on delete cascade,
  question_id    text not null,
  selected_option text,
  is_correct     boolean not null default false,
  marks_awarded  numeric not null default 0,
  answered_at    timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (attempt_id, question_id)
);

create index if not exists idx_model_test_answers_attempt
  on public.model_test_answers (attempt_id);

create or replace function public.cleanup_model_test_attempts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.model_test_attempts where test_id = OLD.id::text;
  return OLD;
end; $$;

drop trigger if exists trg_cleanup_model_test_attempts on public.exam_schedules;
create trigger trg_cleanup_model_test_attempts
  after delete on public.exam_schedules
  for each row execute function public.cleanup_model_test_attempts();

-- ---------------------------------------------------------------------------
-- 4. Role-aware RLS. Replace the generic tenant-only policies on the two
--    tables this migration governs; all other tables keep migration 0001.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['exam_schedules', 'academy_questions'] loop
    execute format('drop policy if exists tenant_select on public.%I', t);
    execute format('drop policy if exists tenant_insert on public.%I', t);
    execute format('drop policy if exists tenant_update on public.%I', t);
    execute format('drop policy if exists tenant_delete on public.%I', t);
  end loop;
end $$;

-- exam_schedules -----------------------------------------------------------
drop policy if exists model_test_select on public.exam_schedules;
create policy model_test_select on public.exam_schedules
  for select to authenticated
  using (
    academy_id::text = public.current_academy_id()
    and (public.is_academy_staff() or status <> 'draft')
  );

drop policy if exists model_test_insert on public.exam_schedules;
create policy model_test_insert on public.exam_schedules
  for insert to authenticated
  with check (
    academy_id::text = public.current_academy_id()
    and public.is_academy_staff()
    and status in ('draft', 'published')
  );

drop policy if exists model_test_update on public.exam_schedules;
create policy model_test_update on public.exam_schedules
  for update to authenticated
  using (
    academy_id::text = public.current_academy_id()
    and public.can_manage_model_test(question_creator_id::text)
  )
  with check (
    academy_id::text = public.current_academy_id()
    and public.can_manage_model_test(question_creator_id::text)
  );

drop policy if exists model_test_delete on public.exam_schedules;
create policy model_test_delete on public.exam_schedules
  for delete to authenticated
  using (
    academy_id::text = public.current_academy_id()
    and public.can_manage_model_test(question_creator_id::text)
  );

-- academy_questions --------------------------------------------------------
drop policy if exists question_bank_select on public.academy_questions;
create policy question_bank_select on public.academy_questions
  for select to authenticated
  using (academy_id::text = public.current_academy_id());

drop policy if exists question_bank_insert on public.academy_questions;
create policy question_bank_insert on public.academy_questions
  for insert to authenticated
  with check (academy_id::text = public.current_academy_id()
              and public.is_academy_staff());

drop policy if exists question_bank_update on public.academy_questions;
create policy question_bank_update on public.academy_questions
  for update to authenticated
  using (academy_id::text = public.current_academy_id()
          and public.is_academy_staff())
  with check (academy_id::text = public.current_academy_id()
              and public.is_academy_staff());

drop policy if exists question_bank_delete on public.academy_questions;
create policy question_bank_delete on public.academy_questions
  for delete to authenticated
  using (academy_id::text = public.current_academy_id()
          and public.is_academy_staff());

-- attempts / answers: reads only; all writes go through the RPCs below. -----
alter table public.model_test_attempts enable row level security;
alter table public.model_test_answers  enable row level security;

revoke all on public.model_test_attempts from anon, authenticated;
revoke all on public.model_test_answers  from anon, authenticated;
grant select on public.model_test_attempts to authenticated;
grant select on public.model_test_answers  to authenticated;

drop policy if exists attempt_select on public.model_test_attempts;
create policy attempt_select on public.model_test_attempts
  for select to authenticated
  using (
    academy_id = public.current_academy_id()
    and (
      public.is_academy_staff()
      or student_id = public.current_actor_id()
    )
  );

drop policy if exists answer_select on public.model_test_answers;
create policy answer_select on public.model_test_answers
  for select to authenticated
  using (
    academy_id = public.current_academy_id()
    and (
      public.is_academy_staff()
      or exists (
        select 1 from public.model_test_attempts a
         where a.id = attempt_id
           and a.student_id = public.current_actor_id()
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 5. Server-side attempt lifecycle + scoring.
-- ---------------------------------------------------------------------------
create or replace function public.finalize_model_test_attempt(
  p_attempt_id uuid,
  p_auto       boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attempt model_test_attempts%rowtype;
  v_test    exam_schedules%rowtype;
  v_q       jsonb;
  v_ans     model_test_answers%rowtype;
  v_correct integer := 0;
  v_wrong   integer := 0;
  v_blank   integer := 0;
  v_score   numeric := 0;
  v_total   numeric;
  v_perq    numeric;
  v_neg     numeric;
  v_pct     numeric;
begin
  select * into v_attempt
    from public.model_test_attempts where id = p_attempt_id for update;
  if not found then
    raise exception 'Attempt not found';
  end if;

  -- Idempotent duplicate-submit guard: return the persisted result as-is.
  if v_attempt.status <> 'in_progress' then
    return jsonb_build_object(
      'attempt_id', v_attempt.id::text,
      'status', v_attempt.status,
      'score', v_attempt.score,
      'total_marks', v_attempt.total_marks,
      'percentage', v_attempt.percentage,
      'correct_count', v_attempt.correct_count,
      'wrong_count', v_attempt.wrong_count,
      'unanswered_count', v_attempt.unanswered_count,
      'passed', v_attempt.passed,
      'already_submitted', true
    );
  end if;

  select * into v_test
    from public.exam_schedules where id::text = v_attempt.test_id;
  if not found then
    raise exception 'Test no longer exists';
  end if;

  v_total := coalesce(v_test.total_marks, 0);
  v_perq  := greatest(0, coalesce(v_test.marks_per_question, 1));
  v_neg   := greatest(0, coalesce(v_test.negative_marks, 0));

  for v_q in
    select value from jsonb_array_elements(coalesce(v_test.questions_snapshot, '[]'::jsonb))
  loop
    select * into v_ans
      from public.model_test_answers
     where attempt_id = v_attempt.id
       and question_id = coalesce(v_q ->> 'id', '');

    if not found then
      insert into public.model_test_answers
        (academy_id, attempt_id, question_id, selected_option, is_correct, marks_awarded)
      values
        (v_attempt.academy_id, v_attempt.id, coalesce(v_q ->> 'id', ''),
         null, false, 0);
      v_blank := v_blank + 1;
    elsif v_ans.selected_option is null
          or btrim(v_ans.selected_option) = '' then
      v_blank := v_blank + 1;
    elsif upper(btrim(v_ans.selected_option)) =
          upper(btrim(coalesce(v_q ->> 'correct_option', ''))) then
      v_correct := v_correct + 1;
      update public.model_test_answers
         set is_correct = true, marks_awarded = v_perq, updated_at = now()
       where id = v_ans.id;
    else
      v_wrong := v_wrong + 1;
      update public.model_test_answers
         set is_correct = false, marks_awarded = -v_neg, updated_at = now()
       where id = v_ans.id;
    end if;
  end loop;

  v_score := greatest(0, v_correct::numeric * v_perq - v_wrong::numeric * v_neg);
  if v_total <= 0 then
    v_total := (v_correct + v_wrong + v_blank)::numeric * v_perq;
  end if;
  v_pct := case when v_total > 0
                then round(v_score / v_total * 100, 2) else 0 end;

  update public.model_test_attempts
     set status = case when coalesce(p_auto, false)
                       then 'auto_submitted' else 'submitted' end,
         submitted_at = now(),
         score = v_score,
         total_marks = v_total,
         correct_count = v_correct,
         wrong_count = v_wrong,
         unanswered_count = v_blank,
         percentage = v_pct,
         passed = v_pct >= coalesce(v_test.pass_percent, 33),
         updated_at = now()
   where id = v_attempt.id
  returning * into v_attempt;

  return jsonb_build_object(
    'attempt_id', v_attempt.id::text,
    'status', v_attempt.status,
    'score', v_attempt.score,
    'total_marks', v_attempt.total_marks,
    'percentage', v_attempt.percentage,
    'correct_count', v_attempt.correct_count,
    'wrong_count', v_attempt.wrong_count,
    'unanswered_count', v_attempt.unanswered_count,
    'passed', v_attempt.passed,
    'already_submitted', false
  );
end;
$$;

create or replace function public.start_model_test_attempt(p_test_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_test      exam_schedules%rowtype;
  v_attempt   model_test_attempts%rowtype;
  v_sid       text := public.current_actor_id();
  v_start     timestamptz;
  v_end       timestamptz;
  v_deadline  timestamptz;
  v_now       timestamptz := now();
  v_roll      text;
  v_class     text;
begin
  if coalesce(public.current_user_role(), '') <> 'student' then
    raise exception 'Only students can take model tests';
  end if;

  select * into v_test
    from public.exam_schedules
   where id::text = p_test_id
     and academy_id::text = public.current_academy_id();
  if not found then
    raise exception 'পরীক্ষাটি পাওয়া যায়নি।';
  end if;
  if v_test.status <> 'published' then
    raise exception 'এই পরীক্ষাটি এখন উপলব্ধ নয়।';
  end if;

  v_start := (to_jsonb(v_test) ->> 'start_time')::timestamptz;
  v_end   := (to_jsonb(v_test) ->> 'end_time')::timestamptz;
  if v_now < v_start then
    raise exception 'পরীক্ষা এখনো শুরু হয়নি।';
  end if;
  if v_now > v_end then
    raise exception 'পরীক্ষার নির্ধারিত সময় শেষ হয়ে গেছে।';
  end if;

  -- Re-entry: reuse the still-live attempt instead of creating a duplicate.
  select * into v_attempt
    from public.model_test_attempts
   where test_id = p_test_id
     and student_id = v_sid
     and status = 'in_progress'
   order by started_at desc
   limit 1;

  if found then
    if v_now >= v_attempt.deadline_at then
      -- Auto-submit the old attempt and NEVER hand out a fresh timer for the
      -- same test: that would let a student restart an expired attempt.
      perform public.finalize_model_test_attempt(v_attempt.id, true);
      raise exception 'পরীক্ষার সময় শেষ হয়ে গেছে।';
    else
      return jsonb_build_object(
        'attempt', to_jsonb(v_attempt),
        'questions', v_test.questions_snapshot,
        'total_marks', v_test.total_marks,
        'marks_per_question', v_test.marks_per_question,
        'negative_marks', v_test.negative_marks,
        'answers', coalesce((
          select jsonb_object_agg(a.question_id, a.selected_option)
            from public.model_test_answers a
           where a.attempt_id = v_attempt.id
        ), '{}'::jsonb),
        'server_now', v_now,
        'resumed', true
      );
    end if;
  end if;

  v_deadline := least(
    v_now + make_interval(mins => greatest(coalesce(v_test.duration_minutes, 30), 1)),
    v_end
  );

  select r.roll::text, r."class"::text
    into v_roll, v_class
    from public.students r
   where r.id::text = v_sid
     and r.academy_id::text = public.current_academy_id()
   limit 1;

  insert into public.model_test_attempts
    (academy_id, test_id, student_id, student_roll, class_name,
     status, started_at, deadline_at, total_marks)
  values
    (v_test.academy_id::text, p_test_id, v_sid, v_roll, v_class,
     'in_progress', v_now, v_deadline, coalesce(v_test.total_marks, 0))
  returning * into v_attempt;

  return jsonb_build_object(
    'attempt', to_jsonb(v_attempt),
    'questions', v_test.questions_snapshot,
    'total_marks', v_test.total_marks,
    'marks_per_question', v_test.marks_per_question,
    'negative_marks', v_test.negative_marks,
    'answers', '{}'::jsonb,
    'server_now', v_now,
    'resumed', false
  );
end;
$$;

create or replace function public.save_model_test_answer(
  p_attempt_id     uuid,
  p_question_id    text,
  p_selected_option text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attempt model_test_attempts%rowtype;
  v_status  text;
begin
  select * into v_attempt
    from public.model_test_attempts where id = p_attempt_id;
  if not found or v_attempt.student_id <> public.current_actor_id() then
    raise exception 'Attempt not found';
  end if;
  if v_attempt.status <> 'in_progress' then
    raise exception 'এই পরীক্ষার উত্তর আর পরিবর্তন করা যাবে না।';
  end if;
  if now() >= v_attempt.deadline_at then
    raise exception 'পরীক্ষার সময় শেষ হয়ে গেছে।';
  end if;

  select status into v_status
    from public.exam_schedules where id::text = v_attempt.test_id;
  if coalesce(v_status, '') <> 'published' then
    raise exception 'পরীক্ষাটি বাতিল বা শেষ হয়ে গেছে।';
  end if;

  if p_selected_option is not null
     and upper(btrim(p_selected_option)) not in ('A', 'B', 'C', 'D', '') then
    raise exception 'Invalid option';
  end if;

  insert into public.model_test_answers
    (academy_id, attempt_id, question_id, selected_option, answered_at, updated_at)
  values
    (v_attempt.academy_id, p_attempt_id, p_question_id,
     nullif(upper(btrim(coalesce(p_selected_option, ''))), ''), now(), now())
  on conflict (attempt_id, question_id)
  do update set selected_option = excluded.selected_option,
                answered_at = now(),
                updated_at = now();
end;
$$;

create or replace function public.submit_model_test_attempt(
  p_attempt_id uuid,
  p_auto       boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner text;
begin
  select student_id into v_owner
    from public.model_test_attempts where id = p_attempt_id;
  if v_owner is null or v_owner <> public.current_actor_id() then
    raise exception 'Attempt not found';
  end if;
  return public.finalize_model_test_attempt(p_attempt_id, coalesce(p_auto, false));
end;
$$;

create or replace function public.expire_model_tests()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count   integer;
  v_attempt record;
begin
  update public.exam_schedules
     set status = 'expired'
   where academy_id::text = public.current_academy_id()
     and status = 'published'
     and (end_time::timestamptz) < now();
  get diagnostics v_count = row_count;

  -- Auto-submit attempts whose personal deadline passed (the app may have been
  -- closed when it expired). Scoring is computed by the same finalizer used by
  -- the in-app timer, so results stay identical.
  for v_attempt in
    select a.id
      from public.model_test_attempts a
     where a.academy_id = public.current_academy_id()
       and a.status = 'in_progress'
       and a.deadline_at < now()
  loop
    perform public.finalize_model_test_attempt(v_attempt.id, true);
  end loop;

  return v_count;
end;
$$;

revoke all on function public.finalize_model_test_attempt(uuid, boolean) from public;
revoke all on function public.start_model_test_attempt(text) from public;
revoke all on function public.save_model_test_answer(uuid, text, text) from public;
revoke all on function public.submit_model_test_attempt(uuid, boolean) from public;
revoke all on function public.expire_model_tests() from public;
grant execute on function public.start_model_test_attempt(text) to authenticated;
grant execute on function public.save_model_test_answer(uuid, text, text) to authenticated;
grant execute on function public.submit_model_test_attempt(uuid, boolean) to authenticated;
grant execute on function public.expire_model_tests() to authenticated;

-- Re-expose the composite snapshot through a convenient view-free select for
-- the apps' result screens (answers + snapshot are read directly via RLS).
-- No grant changes needed: `authenticated` already has SELECT on both tables.

-- Keep notification fan-out working: trg_model_test_push (0006) ignores
-- is_active=false updates. Status-driven expiry/cancellation now follows the
-- same rule because sync_model_test_state also flips is_active to false.

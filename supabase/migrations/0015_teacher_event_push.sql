-- ============================================================================
-- 0015 Teacher push + inbox fan-out (notice / exam routine / result)
-- Apply with:  supabase db push   (or paste into Supabase SQL editor)
--
-- WHY THIS MIGRATION
-- -----------------
-- 0005/0006 fan out notices and academic events to `student:<id>` only.
-- 0014 is the sole teacher-facing push source (salary payment). This migration
-- adds teacher/staff recipients for the three missing admin events WITHOUT
-- touching the existing student triggers, the dedupe helper contract, the
-- dispatch trigger, or the `send-push` Edge Function.
--
-- Pipeline (unchanged):
--   source INSERT/UPDATE
--     -> NEW independent teacher trigger
--     -> public.queue_student_notification_once()  (dedupe, 15 min window)
--     -> public.app_notifications (reader_key = 'teacher:<id>')
--     -> trg_dispatch_student_push (0003/0004/0006)
--     -> pg_net -> send-push -> users.fcm_token
--
-- Why separate triggers instead of editing 0006/full setup:
--   * `model_test_full_setup.sql` re-creates `trg_notice_push`,
--     `trg_model_test_push`, and the shared queue functions. These new triggers
--     have different names and live on tables that script does not clean up,
--     so re-running it cannot drop or duplicate teacher fan-out.
--   * Student rows are still produced by the original triggers; nothing here
--     changes their dedupe keys or reader keys.
-- ============================================================================

create extension if not exists pgcrypto;

-- Dedupe column/index are normally added by 0006/0014/full setup. Re-assert so
-- this migration is safe on a database where only 0001-0004 were applied.
alter table public.app_notifications
  add column if not exists dedupe_key text;

create index if not exists idx_app_notifications_dedupe
  on public.app_notifications (reader_key, type, dedupe_key, created_at desc);

-- ---------------------------------------------------------------------------
-- 0. Shared queue helper (same signature/semantics as 0006 + full setup).
--    Re-asserted defensively; an invalid academy id is ignored, never thrown.
-- ---------------------------------------------------------------------------
create or replace function public.queue_student_notification_once(
  p_academy_id     text,
  p_reader_key     text,
  p_type           text,
  p_title          text,
  p_body           text,
  p_route          text,
  p_target_id      text,
  p_dedupe_key     text,
  p_dedupe_minutes integer default 15
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_academy uuid;
begin
  if coalesce(btrim(p_academy_id), '') = ''
     or coalesce(btrim(p_reader_key), '') = '' then
    return;
  end if;

  begin
    v_academy := btrim(p_academy_id)::uuid;
  exception when others then
    return;
  end;

  if exists (
    select 1
      from public.app_notifications
     where reader_key = p_reader_key
       and type = p_type
       and coalesce(dedupe_key, '') = coalesce(p_dedupe_key, '')
       and created_at > now() - make_interval(mins => coalesce(p_dedupe_minutes, 15))
  ) then
    return; -- already queued for this exact logical event
  end if;

  insert into public.app_notifications
    (academy_id, reader_key, type, title, body, route, target_id, dedupe_key)
  values
    (v_academy, p_reader_key, p_type, p_title, p_body,
     p_route, p_target_id, p_dedupe_key);
exception when others then
  -- A notification problem must never roll back the admin's source write.
  null;
end;
$$;

revoke all on function public.queue_student_notification_once(
  text, text, text, text, text, text, text, text, integer
) from public;

-- ---------------------------------------------------------------------------
-- 1. Teacher/staff fan-out helper.
--    Mirrors SessionService.readerKeyFor(): teacher/staff use `teacher:<id>`,
--    exactly like 0014. Admin is deliberately not a fan-out target here (the
--    admin is the publisher). `send-push` already resolves this reader key to
--    `users.fcm_token`, so no Edge Function change is required.
-- ---------------------------------------------------------------------------
create or replace function public.fanout_teacher_notification(
  p_academy_id    text,
  p_type          text,
  p_title         text,
  p_body          text,
  p_route         text,
  p_target_id     text,
  p_dedupe_prefix text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r       record;
  v_academy text := coalesce(btrim(p_academy_id), '');
begin
  if v_academy = '' then
    return;
  end if;

  for r in
    select u.id::text as uid
      from public.users u
     where u.academy_id::text = v_academy
       and lower(btrim(coalesce(u.role, ''))) in ('teacher', 'staff')
  loop
    perform public.queue_student_notification_once(
      v_academy,
      'teacher:' || r.uid,
      p_type,
      p_title,
      p_body,
      p_route,
      p_target_id,
      coalesce(btrim(p_dedupe_prefix), p_type) || ':' || r.uid
    );
  end loop;
exception when others then
  -- Fan-out is best effort; never fail the source write.
  null;
end;
$$;

revoke all on function public.fanout_teacher_notification(
  text, text, text, text, text, text, text
) from public;

-- ===========================================================================
-- 2a. Notices -> teacher/staff inbox + FCM push
--     Teacher audiences: 'teachers' (and harmless aliases), academy-wide
--     'everyone'/'all'/empty. 'all_students' and 'class' remain student-only,
--     matching the admin UI labels and NoticeRepository.isTargeted().
-- ===========================================================================
create or replace function public.trg_teacher_notice_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target text := lower(btrim(coalesce(new.target_type, '')));
begin
  if v_target not in ('', 'teachers', 'teacher', 'all_teachers', 'everyone', 'all') then
    return null;
  end if;

  perform public.fanout_teacher_notification(
    new.academy_id::text,
    'notice',
    coalesce(new.title, 'নতুন নোটিশ'),
    coalesce(left(new.description, 200), ''),
    'notice',
    new.id::text,
    'teacher_notice:' || new.id::text
  );

  return null;
end;
$$;

drop trigger if exists trg_teacher_notice_push on public.notices;
create trigger trg_teacher_notice_push
  after insert on public.notices
  for each row execute function public.trg_teacher_notice_push();

revoke all on function public.trg_teacher_notice_push() from public;

-- ===========================================================================
-- 2b. Exam routine -> teacher/staff inbox + FCM push
--     One notification per teacher per exam/academy, even when the admin save
--     deletes and bulk-inserts many routine rows for different classes.
--     The original trg_exam_routine_push (0006) keeps handling students.
-- ===========================================================================
create or replace function public.trg_teacher_exam_routine_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  j       jsonb := to_jsonb(new);
  v_exam  text := coalesce(
             nullif(btrim(coalesce(j->>'exam_id', '')), ''),
             nullif(btrim(coalesce(j->>'id', '')), ''),
             ''
           );
  v_body  text;
begin
  if tg_op = 'UPDATE' and to_jsonb(new) = to_jsonb(old) then
    return null;
  end if;

  v_body := concat_ws(
    ' ',
    coalesce(nullif(btrim(coalesce(j->>'exam_title', '')), ''), 'পরীক্ষার রুটিন'),
    nullif(btrim(coalesce(j->>'exam_date', '')), ''),
    nullif(btrim(coalesce(j->>'subject_name', '')), ''),
    nullif(btrim(coalesce(j->>'class_name', '')), '')
  );

  perform public.fanout_teacher_notification(
    j->>'academy_id',
    'exam_routine',
    'পরীক্ষার রুটিন আপডেট',
    v_body,
    'exam_routine',
    v_exam,
    'teacher_exam_routine:' || coalesce(j->>'academy_id', '') || ':' || v_exam
  );

  return null;
end;
$$;

drop trigger if exists trg_teacher_exam_routine_push on public.exam_routines;
create trigger trg_teacher_exam_routine_push
  after insert or update on public.exam_routines
  for each row execute function public.trg_teacher_exam_routine_push();

revoke all on function public.trg_teacher_exam_routine_push() from public;

-- ===========================================================================
-- 2c. Exam result -> teacher/staff inbox + FCM push
--     Bulk upload upserts one row per student. Dedupe by exam + class (not by
--     roll) so a whole-class publish produces ONE teacher push, not dozens.
--     The original trg_result_push (0006) keeps handling students.
-- ===========================================================================
create or replace function public.trg_teacher_result_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  j        jsonb := to_jsonb(new);
  v_exam   text := coalesce(nullif(btrim(coalesce(j->>'exam_title', '')), ''), 'পরীক্ষা');
  v_class  text := lower(btrim(coalesce(j->>'class_name', '')));
  v_body   text;
begin
  if tg_op = 'UPDATE' and to_jsonb(new) = to_jsonb(old) then
    return null;
  end if;

  v_body := concat_ws(
    ' ',
    v_exam,
    nullif(v_class, ''),
    nullif(btrim(coalesce(j->>'roll', '')), '')
  );

  perform public.fanout_teacher_notification(
    j->>'academy_id',
    'result',
    'পরীক্ষার ফলাফল প্রকাশিত',
    v_body,
    'result',
    coalesce(nullif(btrim(coalesce(j->>'id', '')), ''), v_exam),
    'teacher_result:' || coalesce(j->>'academy_id', '') || ':'
      || lower(v_exam) || ':' || v_class
  );

  return null;
end;
$$;

drop trigger if exists trg_teacher_result_push on public.exam_results;
create trigger trg_teacher_result_push
  after insert or update on public.exam_results
  for each row execute function public.trg_teacher_result_push();

revoke all on function public.trg_teacher_result_push() from public;

-- ---------------------------------------------------------------------------
-- 3. Verification (run manually after applying)
-- ---------------------------------------------------------------------------
-- select tgname, tgenabled from pg_trigger
--  where tgname in ('trg_teacher_notice_push',
--                   'trg_teacher_exam_routine_push',
--                   'trg_teacher_result_push',
--                   'trg_teacher_salary_push',
--                   'trg_dispatch_student_push')
--  order by tgname;
--
-- select reader_key, type, title, body, route, dedupe_key, created_at
--   from public.app_notifications
--  where reader_key like 'teacher:%'
--  order by created_at desc limit 20;
--
-- select created, status_code, content from net._http_response
--  order by created desc limit 10;   -- 200 = dispatched; inspect content for "sent"

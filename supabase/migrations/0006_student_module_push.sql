-- ============================================================================
-- 0006 Student-module push fan-out (fees / attendance / model test /
--      class routine / result / exam routine)
-- Apply with:  supabase db push   (or paste into Supabase SQL Editor)
--
-- WHY THIS MIGRATION
-- -----------------
-- Notices already deliver real pushes: create_notice_view inserts into
-- `notices` -> trg_notice_push (0005) -> queue_student_notification ->
-- `app_notifications` -> trg_dispatch_student_push -> pg_net -> `send-push`
-- Edge Function -> FCM. The Flutter side (inbox, badge, router, token sync) is
-- already wired for ALL seven categories.
--
-- The six academic tables were covered by migration 0003, but that pipeline is
-- either not applied on some projects or has defects that silently drop or
-- flood notifications:
--   * `class_name` was compared with exact string equality against
--     `students."class"` (case / whitespace differences => zero recipients).
--   * bulk upserts (attendance, class routine, exam routine) fire one trigger
--     per row -> dozens of duplicate pushes per student per save.
--   * re-saving unchanged data re-notified.
--   * model test notified for drafts/cancellations (is_active = false).
--
-- This migration is IDEMPOTENT and self-contained. It reuses the SAME
-- `app_notifications` -> `trg_dispatch_student_push` -> `send-push` path as
-- notices. It does NOT modify the notice trigger, the dispatch trigger, or the
-- Edge Function, so existing notice behaviour is preserved exactly.
-- ============================================================================

create extension if not exists pgcrypto;

-- pg_net is required for the DB -> Edge Function hop. Supabase SQL Editor runs
-- as postgres, so this is allowed. If your project blocks it, enable the
-- extension once from Dashboard -> Database -> Extensions instead.
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- 0. Re-assert the locked-down config table + dispatcher (idempotent, no-op
--    when 0003/0004 were applied). Configuration itself is set by push_setup.sql.
-- ---------------------------------------------------------------------------
create table if not exists public.notification_config (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now()
);
alter table public.notification_config enable row level security;
revoke all on public.notification_config from public, anon, authenticated;

-- Dedupe bookkeeping column on the shared inbox. NULL for notice rows, so the
-- notice pipeline is completely unaffected.
alter table public.app_notifications add column if not exists dedupe_key text;
create index if not exists idx_app_notifications_dedupe
  on public.app_notifications (reader_key, type, dedupe_key, created_at desc);

-- Ensure the dispatch trigger exists (uses the function from 0003/0004).
do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'dispatch_student_push'
  ) then
    drop trigger if exists trg_dispatch_student_push on public.app_notifications;
    create trigger trg_dispatch_student_push
      after insert on public.app_notifications
      for each row execute function public.dispatch_student_push();
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Dedupe-aware queue helper.
--    Keeps the original 7-argument queue_student_notification() (used by the
--    notice trigger) untouched. New academic triggers use this variant, which
--    suppresses repeat notifications for the same logical event within a
--    short window. That is what stops bulk routine/attendance saves from
--    flooding a student's phone.
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
begin
  if p_academy_id is null or coalesce(p_reader_key, '') = '' then
    return;
  end if;

  if exists (
    select 1
      from public.app_notifications
     where reader_key = p_reader_key
       and type = p_type
       and coalesce(dedupe_key, '') = coalesce(p_dedupe_key, '')
       and created_at > now() - make_interval(mins => coalesce(p_dedupe_minutes, 15))
  ) then
    return; -- already notified about this exact event recently
  end if;

  insert into public.app_notifications
    (academy_id, reader_key, type, title, body, route, target_id, dedupe_key)
  values
    (p_academy_id::uuid, p_reader_key, p_type, p_title, p_body,
     p_route, p_target_id, p_dedupe_key);
end;
$$;

revoke all on function public.queue_student_notification_once(
  text, text, text, text, text, text, text, text, integer
) from public;

-- ---------------------------------------------------------------------------
-- 2. Class-wide fan-out with the SAME audience rule the app uses:
--    empty class => whole academy, otherwise case/whitespace-insensitive match
--    against students."class" (mirrors NoticeRepository.isTargeted + 0005).
-- ---------------------------------------------------------------------------
create or replace function public.fanout_class_notification(
  p_academy_id    text,
  p_class_name    text,
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
  r        record;
  v_class  text := lower(btrim(coalesce(p_class_name, '')));
begin
  if coalesce(p_academy_id, '') = '' then
    return;
  end if;

  for r in
    select 'student:' || s.id::text as rk, s.id::text as sid
      from public.students s
     where s.academy_id::text = p_academy_id
       and (v_class = '' or lower(btrim(s."class"::text)) = v_class)
  loop
    perform public.queue_student_notification_once(
      p_academy_id,
      r.rk,
      p_type,
      p_title,
      p_body,
      p_route,
      p_target_id,
      coalesce(p_dedupe_prefix, p_type) || ':' || r.sid
    );
  end loop;
end;
$$;

revoke all on function public.fanout_class_notification(
  text, text, text, text, text, text, text, text
) from public;

-- ---------------------------------------------------------------------------
-- 2b. Notices: replace 0005's non-deduped trigger so a single notice cannot
--     create two inbox rows / pushes for the same student.
-- ---------------------------------------------------------------------------
create or replace function public.trg_notice_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_target text := lower(btrim(coalesce(new.target_type, '')));
  v_class  text := lower(btrim(coalesce(new.target_class, '')));
  r record;
begin
  if v_target not in ('', 'everyone', 'all', 'all_students', 'class') then
    return null;
  end if;

  for r in
    select 'student:' || s.id::text as rk
      from public.students s
     where s.academy_id::text = new.academy_id::text
       and (v_target <> 'class' or lower(btrim(s."class"::text)) = v_class)
  loop
    perform public.queue_student_notification_once(
      new.academy_id::text,
      r.rk,
      'notice',
      coalesce(new.title, 'নতুন নোটিশ'),
      coalesce(left(new.description, 200), ''),
      'notice',
      new.id::text,
      'notice:' || new.id::text
    );
  end loop;
  return null;
end; $$;

drop trigger if exists trg_notice_push on public.notices;
create trigger trg_notice_push
  after insert on public.notices
  for each row execute function public.trg_notice_push();

revoke all on function public.trg_notice_push() from public;

-- ---------------------------------------------------------------------------
-- 3. Drop the OLD 0003 triggers/functions so a DB that applied 0003 does not
--    dispatch twice. The notice trigger is recreated above with dedupe.
-- ---------------------------------------------------------------------------
drop trigger if exists trg_fee_notification on public.student_fee_history;
drop trigger if exists trg_attendance_notification on public.student_attendance;
drop trigger if exists trg_exam_routine_notification on public.exam_routines;
drop trigger if exists trg_model_test_notification on public.exam_schedules;
drop trigger if exists trg_result_notification on public.exam_results;
drop trigger if exists trg_class_routine_notification on public.class_routines;

drop function if exists public.trg_fee_notification();
drop function if exists public.trg_attendance_notification();
drop function if exists public.trg_exam_routine_notification();
drop function if exists public.trg_model_test_notification();
drop function if exists public.trg_result_notification();
drop function if exists public.trg_class_routine_notification();

-- ===========================================================================
-- 4a. বেতন / Fees  ->  student_fee_history (insert + update)
-- ===========================================================================
create or replace function public.trg_fee_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  j      jsonb := to_jsonb(new);
  v_month text := nullif(btrim(coalesce(j->>'month', '')), '');
  v_amt   text := nullif(btrim(coalesce(j->>'amount', '')), '');
begin
  if tg_op = 'UPDATE' and to_jsonb(new) = to_jsonb(old) then
    return null; -- no-op update
  end if;

  perform public.queue_student_notification_once(
    j->>'academy_id',
    'student:' || coalesce(j->>'student_id', ''),
    'fee',
    'বেতন / ফি আপডেট',
    concat_ws(' ', coalesce(v_month, 'ফি'), coalesce(v_amt, '0') || ' ৳'),
    'fee',
    j->>'id',
    'fee:' || coalesce(j->>'student_id', '') || ':' || coalesce(j->>'id', '')
  );
  return null;
end;
$$;

drop trigger if exists trg_fee_push on public.student_fee_history;
create trigger trg_fee_push
  after insert or update on public.student_fee_history
  for each row execute function public.trg_fee_push();

revoke all on function public.trg_fee_push() from public;

-- 4a-2. বার্ষিক বকেয়া (yearly due saved on academic-year promotion).
create or replace function public.trg_yearly_due_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new);
begin
  perform public.queue_student_notification_once(
    j->>'academy_id',
    'student:' || coalesce(j->>'student_id', ''),
    'fee',
    'বার্ষিক বকেয়া আপডেট',
    coalesce(j->>'year', '') || ' সাল ৳ ' || coalesce(j->>'due_amount', '0'),
    'fee',
    j->>'id',
    'fee:due:' || coalesce(j->>'student_id', '') || ':' || coalesce(j->>'year', '')
  );
  return null;
end;
$$;

drop trigger if exists trg_yearly_due_push on public.yearly_due_history;
create trigger trg_yearly_due_push
  after insert on public.yearly_due_history
  for each row execute function public.trg_yearly_due_push();

revoke all on function public.trg_yearly_due_push() from public;

-- ===========================================================================
-- 4b. উপস্থিতি / Attendance  ->  student_attendance (insert + update)
--     One row per student -> one notification per student. Repeat saves of the
--     same date+status are deduped; a corrected status notifies once.
-- ===========================================================================
create or replace function public.trg_attendance_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  j        jsonb := to_jsonb(new);
  v_status text;
  v_sid    text := coalesce(j->>'student_id', '');
  v_date   text := coalesce(j->>'date', '');
begin
  if tg_op = 'UPDATE' and to_jsonb(new) = to_jsonb(old) then
    return null;
  end if;

  v_status := case lower(coalesce(j->>'status', ''))
    when 'present' then 'উপস্থিত'
    when 'absent'  then 'অনুপস্থিত'
    else coalesce(j->>'status', '')
  end;

  perform public.queue_student_notification_once(
    j->>'academy_id',
    'student:' || v_sid,
    'attendance',
    'উপস্থিতি আপডেট',
    concat_ws(' ', nullif(v_date, ''), nullif(v_status, '')),
    'attendance',
    v_sid,
    'attendance:' || v_sid || ':' || v_date || ':' || coalesce(j->>'status', '')
  );
  return null;
end;
$$;

drop trigger if exists trg_attendance_push on public.student_attendance;
create trigger trg_attendance_push
  after insert or update on public.student_attendance
  for each row execute function public.trg_attendance_push();

revoke all on function public.trg_attendance_push() from public;

-- ===========================================================================
-- 4c. মডেল টেস্ট / Model Test  ->  exam_schedules (publish + meaningful update)
--     Draft (is_active = false) and cancel/expire updates are ignored.
-- ===========================================================================
create or replace function public.trg_model_test_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  j         jsonb := to_jsonb(new);
  o         jsonb;
  v_active  boolean := coalesce((j->>'is_active')::boolean, false);
  v_was     boolean;
  v_title   text := coalesce(nullif(btrim(coalesce(j->>'exam_title', '')), ''), 'নতুন মডেল টেস্ট');
  v_body    text;
begin
  if tg_op = 'INSERT' then
    if not v_active then
      return null; -- not published yet
    end if;
  else
    o := to_jsonb(old);
    v_was := coalesce((o->>'is_active')::boolean, false);
    if not v_active then
      return null; -- cancelled / expired => no 'new test' push
    end if;
    if v_was
       and (j->>'exam_title') = (o->>'exam_title')
       and (j->>'start_time') is not distinct from (o->>'start_time')
       and (j->>'class_name') is not distinct from (o->>'class_name') then
      return null; -- irrelevant field changed
    end if;
  end if;

  v_body := v_title
    || case when coalesce(j->>'class_name', '') <> ''
            then ' ' || j->>'class_name' else '' end
    || case when coalesce(j->>'start_time', '') <> ''
            then ' ' || left(j->>'start_time', 16) else '' end;

  perform public.fanout_class_notification(
    j->>'academy_id', j->>'class_name',
    'model_test', 'নতুন মডেল টেস্ট', v_body,
    'model_test', j->>'id',
    'model_test:' || coalesce(j->>'id', '')
  );
  return null;
end;
$$;

drop trigger if exists trg_model_test_push on public.exam_schedules;
create trigger trg_model_test_push
  after insert or update on public.exam_schedules
  for each row execute function public.trg_model_test_push();

revoke all on function public.trg_model_test_push() from public;

-- ===========================================================================
-- 4d. ক্লাস রুটিন / Class Routine  ->  class_routines (insert + update)
--     A full timetable save upserts many rows. All rows of one class share a
--     dedupe key, so each student receives exactly ONE notification per save.
-- ===========================================================================
create or replace function public.trg_class_routine_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  j        jsonb := to_jsonb(new);
  v_day    text := coalesce(nullif(btrim(coalesce(j->>'day', '')), ''), 'নতুন রুটিন');
  v_period text := nullif(btrim(coalesce(j->>'period_name', '')), '');
  v_body   text;
begin
  if tg_op = 'UPDATE' and to_jsonb(new) = to_jsonb(old) then
    return null;
  end if;

  v_body := v_day || case when v_period is not null then ' ' || v_period else '' end;

  perform public.fanout_class_notification(
    j->>'academy_id', j->>'class_name',
    'class_routine', 'ক্লাস রুটিন আপডেট', v_body,
    'class_routine', j->>'id',
    'class_routine:' || coalesce(j->>'academy_id', '') || ':'
      || lower(btrim(coalesce(j->>'class_name', '')))
  );
  return null;
end;
$$;

drop trigger if exists trg_class_routine_push on public.class_routines;
create trigger trg_class_routine_push
  after insert or update on public.class_routines
  for each row execute function public.trg_class_routine_push();

revoke all on function public.trg_class_routine_push() from public;

-- ===========================================================================
-- 4e. রেজাল্ট / Result  ->  exam_results (insert + update)
--     Targeted by roll + class (mirrors the app's result lookup).
-- ===========================================================================
create or replace function public.trg_result_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  j       jsonb := to_jsonb(new);
  r       record;
  v_class text := nullif(btrim(coalesce(j->>'class_name', '')), '');
  v_title text := coalesce(nullif(btrim(coalesce(j->>'exam_title', '')), ''), 'পরীক্ষা');
  v_body  text;
begin
  if tg_op = 'UPDATE' and to_jsonb(new) = to_jsonb(old) then
    return null;
  end if;

  v_body := v_title || case when v_class is not null then ' ' || v_class else '' end;

  for r in
    select 'student:' || s.id::text as rk, s.id::text as sid
      from public.students s
     where s.academy_id::text = j->>'academy_id'
       and s.roll::text = j->>'roll'
       and (v_class is null or lower(btrim(s."class"::text)) = lower(v_class))
  loop
    perform public.queue_student_notification_once(
      j->>'academy_id', r.rk,
      'result', 'পরীক্ষার ফলাফল প্রকাশিত', v_body,
      'result', j->>'id',
      'result:' || coalesce(j->>'id', '') || ':' || r.sid
    );
  end loop;
  return null;
end;
$$;

drop trigger if exists trg_result_push on public.exam_results;
create trigger trg_result_push
  after insert or update on public.exam_results
  for each row execute function public.trg_result_push();

revoke all on function public.trg_result_push() from public;

-- ===========================================================================
-- 4f. পরীক্ষার রুটিন / Exam Routine  ->  exam_routines (insert + update)
--     Delete-then-bulk-insert and title edits are collapsed to one push per
--     exam + class via the shared dedupe key.
-- ===========================================================================
create or replace function public.trg_exam_routine_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  j        jsonb := to_jsonb(new);
  v_title  text := coalesce(nullif(btrim(coalesce(j->>'exam_title', '')), ''), 'পরীক্ষার রুটিন');
  v_body   text;
  v_exam   text := coalesce(j->>'exam_id', j->>'id');
begin
  if tg_op = 'UPDATE' and to_jsonb(new) = to_jsonb(old) then
    return null;
  end if;

  v_body := v_title
    || case when coalesce(j->>'exam_date', '') <> ''
            then ' ' || j->>'exam_date' else '' end
    || case when coalesce(j->>'subject_name', '') <> ''
            then ' ' || j->>'subject_name' else '' end;

  perform public.fanout_class_notification(
    j->>'academy_id', j->>'class_name',
    'exam_routine', 'পরীক্ষার রুটিন আপডেট', v_body,
    'exam_routine', coalesce(v_exam, j->>'id'),
    'exam_routine:' || coalesce(j->>'academy_id', '') || ':'
      || coalesce(v_exam, '') || ':'
      || lower(btrim(coalesce(j->>'class_name', '')))
  );
  return null;
end;
$$;

drop trigger if exists trg_exam_routine_push on public.exam_routines;
create trigger trg_exam_routine_push
  after insert or update on public.exam_routines
  for each row execute function public.trg_exam_routine_push();

revoke all on function public.trg_exam_routine_push() from public;

-- ---------------------------------------------------------------------------
-- 5. Realtime: ensure the unified inbox is published so the AppBar badge keeps
--    updating live (already done in 0003; idempotent guard for safety).
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'app_notifications'
     )
  then
    alter publication supabase_realtime add table public.app_notifications;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Verification (run manually)
-- ---------------------------------------------------------------------------
-- select tgname, tgenabled from pg_trigger
--  where tgname in ('trg_notice_push','trg_dispatch_student_push',
--    'trg_fee_push','trg_attendance_push','trg_model_test_push',
--    'trg_class_routine_push','trg_result_push','trg_exam_routine_push')
--  order by tgname;
--
-- select key, left(value, 45) as preview from public.notification_config;
-- select type, count(*) from public.app_notifications group by type order by type;
-- select reader_key, type, title, body, created_at
--   from public.app_notifications order by created_at desc limit 20;
-- select created, status_code, content from net._http_response
--  order by created desc limit 10;   -- 200 = dispatched, 401 = key mismatch

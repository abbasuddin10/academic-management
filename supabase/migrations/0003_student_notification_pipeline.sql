-- ============================================================================
-- 0003 Student notification pipeline (fee / attendance / exam / routine events)
-- Apply with:  supabase db push   (or paste into Supabase SQL editor)
--
-- Depends on 0001 + 0002:
--   * public.academies, public.students, public.app_sessions
--   * public.current_reader_key(), public.academy_is_current()
--
-- WHAT THIS ADDS
--   1. public.student_devices  - FCM token registry (one row per device/token).
--   2. public.app_notifications- per-recipient inbox for ALL event categories.
--   3. Triggers on the six source tables that create inbox rows for the
--      targeted students (student-specific or class/academy-wide).
--   4. Best-effort pg_net dispatch to the `send-push` Edge Function so the
--      message is delivered while the app is backgrounded or terminated.
--
-- SETUP REQUIRED IN THE SUPABASE DASHBOARD (one time)
--   a) Enable the `pg_net` extension:  create extension if not exists pg_net;
--      (Supabase hosts usually have it available in Extensions.)
--   b) Deploy the Edge Function `send-push` (see supabase/functions/send-push/index.ts)
--      and set its secrets:
--         supabase secrets set FCM_SERVER_KEY="<firebase-server-key>"
--      (or FIREBASE_SERVICE_ACCOUNT_JSON="<service account json>" for OAuth2).
--   c) Store the dispatch settings in the locked-down `notification_config`
--      table below (SQL Editor / service role only — NEVER expose to clients):
--         insert into public.notification_config (key, value) values
--           ('push_function_url', 'https://<REF>.supabase.co/functions/v1/send-push'),
--           ('push_service_role_key', '<service_role_jwt>')
--         on conflict (key) do update set value = excluded.value,
--           updated_at = now();
--      The trigger reads these through a SECURITY DEFINER function. When they
--      are absent the inbox row is still created and the badge still updates;
--      only the outbound push is skipped. No source-table write can fail.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. FCM device tokens
-- ---------------------------------------------------------------------------
create table if not exists public.student_devices (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references public.academies(id) on delete cascade,
  student_id  text,
  fcm_token   text not null,
  platform    text not null default 'android',
  updated_at  timestamptz not null default now(),
  constraint student_devices_token_unique unique (fcm_token)
);

create index if not exists idx_student_devices_student
  on public.student_devices (academy_id, student_id);
create index if not exists idx_student_devices_updated
  on public.student_devices (updated_at desc);

alter table public.student_devices enable row level security;

drop policy if exists student_devices_select_own on public.student_devices;
create policy student_devices_select_own on public.student_devices
  for select to authenticated
  using (
    public.academy_is_current(academy_id::text)
    and (
      student_id::text = split_part(public.current_reader_key(), ':', 2)
      or public.current_reader_key() = (select auth.uid()::text)
    )
  );

drop policy if exists student_devices_insert_own on public.student_devices;
create policy student_devices_insert_own on public.student_devices
  for insert to authenticated
  with check (
    public.academy_is_current(academy_id::text)
    and student_id::text = split_part(public.current_reader_key(), ':', 2)
  );

drop policy if exists student_devices_update_own on public.student_devices;
create policy student_devices_update_own on public.student_devices
  for update to authenticated
  using (
    public.academy_is_current(academy_id::text)
    and student_id::text = split_part(public.current_reader_key(), ':', 2)
  )
  with check (
    public.academy_is_current(academy_id::text)
    and student_id::text = split_part(public.current_reader_key(), ':', 2)
  );

revoke all on public.student_devices from anon;
grant select, insert, update on public.student_devices to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Unified notification inbox (notices + academic events)
-- ---------------------------------------------------------------------------
create table if not exists public.app_notifications (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references public.academies(id) on delete cascade,
  reader_key  text not null,                  -- 'student:<id>'
  type        text not null default 'notice',
  title       text not null,
  body        text not null default '',
  target_id   text,
  route       text,                           -- fee|attendance|exam_routine|result|class_routine|model_test|notice
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);

create index if not exists idx_app_notifications_inbox
  on public.app_notifications (academy_id, reader_key, created_at desc);
create index if not exists idx_app_notifications_unread
  on public.app_notifications (reader_key, read_at);

alter table public.app_notifications enable row level security;

drop policy if exists app_notifications_select_own on public.app_notifications;
create policy app_notifications_select_own on public.app_notifications
  for select to authenticated
  using (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key()
  );

drop policy if exists app_notifications_update_own on public.app_notifications;
create policy app_notifications_update_own on public.app_notifications
  for update to authenticated
  using (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key()
  )
  with check (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key()
  );

drop policy if exists app_notifications_delete_own on public.app_notifications;
create policy app_notifications_delete_own on public.app_notifications
  for delete to authenticated
  using (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key()
  );

revoke all on public.app_notifications from anon;
grant select, update, delete on public.app_notifications to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Locked-down push configuration.
--    RLS is enabled with NO policies for anon/authenticated and all privileges
--    revoked from those roles. Only the SECURITY DEFINER trigger function (and
--    the service role / SQL Editor, which bypass RLS) can read these values.
-- ---------------------------------------------------------------------------
create table if not exists public.notification_config (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now()
);

alter table public.notification_config enable row level security;
revoke all on public.notification_config from public, anon, authenticated;
-- Intentionally NO policies: no client role can select/insert/update/delete.
-- (service_role bypasses RLS; the SECURITY DEFINER function below also reads it.)

-- ---------------------------------------------------------------------------
-- 4. Best-effort push dispatch via pg_net -> Edge Function
-- ---------------------------------------------------------------------------
create or replace function public.dispatch_student_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url  text;
  v_key  text;
begin
  -- Read through SECURITY DEFINER: clients cannot see this table (no policies).
  v_url := nullif(
    (select value from public.notification_config where key = 'push_function_url'),
    ''
  );
  v_key := nullif(
    (select value from public.notification_config where key = 'push_service_role_key'),
    ''
  );

  if v_url is null then
    return null; -- inbox-only mode until the function URL is configured
  end if;

  begin
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || coalesce(v_key, '')
      ),
      body := jsonb_build_object(
        'reader_key', new.reader_key,
        'type', new.type,
        'title', new.title,
        'body', new.body,
        'route', new.route,
        'target_id', new.target_id,
        'academy_id', new.academy_id::text,
        'notification_id', new.id::text
      )
    );
  exception when others then
    -- Push must never break a fee/attendance/result write.
    null;
  end;

  return null;
exception when others then
  -- Missing config table / pg_net hiccup must never break a source-table write.
  return null;
end;
$$;

drop trigger if exists trg_dispatch_student_push on public.app_notifications;
create trigger trg_dispatch_student_push
  after insert on public.app_notifications
  for each row execute function public.dispatch_student_push();

revoke all on function public.dispatch_student_push() from public;

-- ---------------------------------------------------------------------------
-- 4. Helper: insert one inbox row for a single reader (used by the triggers)
-- ---------------------------------------------------------------------------
create or replace function public.queue_student_notification(
  p_academy_id text,
  p_reader_key text,
  p_type text,
  p_title text,
  p_body text,
  p_route text,
  p_target_id text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_academy_id is null or p_reader_key is null then
    return;
  end if;

  insert into public.app_notifications
    (academy_id, reader_key, type, title, body, route, target_id)
  values
    (p_academy_id::uuid, p_reader_key, p_type, p_title, p_body, p_route, p_target_id);
end;
$$;

revoke all on function public.queue_student_notification(text, text, text, text, text, text, text) from public;

-- ---------------------------------------------------------------------------
-- 5. Source-table triggers. jsonb extraction keeps them tolerant of columns
--    that may be absent in older schemas (missing key => NULL, never an error).
-- ---------------------------------------------------------------------------

-- 5a. Fee / payment (student-specific)
create or replace function public.trg_fee_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new);
begin
  perform public.queue_student_notification(
    j->>'academy_id', 'student:' || coalesce(j->>'student_id',''),
    'fee', 'বেতন / ফি আপডেট',
    coalesce(j->>'month','ফি') || ' ৳ ' || coalesce(j->>'amount','0'),
    'fee', j->>'id');
  return null;
end; $$;

drop trigger if exists trg_fee_notification on public.student_fee_history;
create trigger trg_fee_notification after insert or update on public.student_fee_history
  for each row execute function public.trg_fee_notification();

-- 5b. Attendance (student-specific)
create or replace function public.trg_attendance_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new);
begin
  perform public.queue_student_notification(
    j->>'academy_id', 'student:' || coalesce(j->>'student_id',''),
    'attendance', 'উপস্থিতি আপডেট',
    coalesce(j->>'date','') || ' ' || coalesce(j->>'status',''),
    'attendance', j->>'student_id');
  return null;
end; $$;

drop trigger if exists trg_attendance_notification on public.student_attendance;
create trigger trg_attendance_notification after insert or update on public.student_attendance
  for each row execute function public.trg_attendance_notification();

-- 5c. Exam routine (class / academy wide)
create or replace function public.trg_exam_routine_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new); r record;
begin
  for r in
    select 'student:' || s.id::text as rk
      from public.students s
     where s.academy_id::text = j->>'academy_id'
       and (j->>'class_name' is null or s."class"::text = j->>'class_name')
  loop
    perform public.queue_student_notification(
      j->>'academy_id', r.rk, 'exam_routine', 'পরীক্ষার রুটিন আপডেট',
      coalesce(j->>'exam_title','নতুন রুটিন'), 'exam_routine', j->>'id');
  end loop;
  return null;
end; $$;

drop trigger if exists trg_exam_routine_notification on public.exam_routines;
create trigger trg_exam_routine_notification after insert or update on public.exam_routines
  for each row execute function public.trg_exam_routine_notification();

-- 5d. Model test (exam_schedules, class / academy wide)
create or replace function public.trg_model_test_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new); r record;
begin
  for r in
    select 'student:' || s.id::text as rk
      from public.students s
     where s.academy_id::text = j->>'academy_id'
       and (j->>'class_name' is null or s."class"::text = j->>'class_name')
  loop
    perform public.queue_student_notification(
      j->>'academy_id', r.rk, 'model_test', 'নতুন মডেল টেস্ট',
      coalesce(j->>'exam_title','মডেল টেস্ট প্রকাশিত'), 'model_test', j->>'id');
  end loop;
  return null;
end; $$;

drop trigger if exists trg_model_test_notification on public.exam_schedules;
create trigger trg_model_test_notification after insert or update on public.exam_schedules
  for each row execute function public.trg_model_test_notification();

-- 5e. Result (student-specific via roll + class)
create or replace function public.trg_result_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new); r record;
begin
  for r in
    select 'student:' || s.id::text as rk
      from public.students s
     where s.academy_id::text = j->>'academy_id'
       and s.roll::text = j->>'roll'
       and (j->>'class_name' is null or s."class"::text = j->>'class_name')
  loop
    perform public.queue_student_notification(
      j->>'academy_id', r.rk, 'result', 'পরীক্ষার ফলাফল প্রকাশিত',
      coalesce(j->>'exam_title','ফলাফল') || ' '
        || coalesce(j->>'class_name',''), 'result', j->>'id');
  end loop;
  return null;
end; $$;

drop trigger if exists trg_result_notification on public.exam_results;
create trigger trg_result_notification after insert or update on public.exam_results
  for each row execute function public.trg_result_notification();

-- 5f. Class routine (class / academy wide)
create or replace function public.trg_class_routine_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new); r record;
begin
  for r in
    select 'student:' || s.id::text as rk
      from public.students s
     where s.academy_id::text = j->>'academy_id'
       and (j->>'class_name' is null or s."class"::text = j->>'class_name')
  loop
    perform public.queue_student_notification(
      j->>'academy_id', r.rk, 'class_routine', 'ক্লাস রুটিন আপডেট',
      coalesce(j->>'day','') || ' ' || coalesce(j->>'period_name','নতুন রুটিন'),
      'class_routine', j->>'id');
  end loop;
  return null;
end; $$;

drop trigger if exists trg_class_routine_notification on public.class_routines;
create trigger trg_class_routine_notification after insert or update on public.class_routines
  for each row execute function public.trg_class_routine_notification();

-- ---------------------------------------------------------------------------
-- 6. Realtime for the inbox + devices
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'app_notifications'
    ) then
      alter publication supabase_realtime add table public.app_notifications;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'student_devices'
    ) then
      alter publication supabase_realtime add table public.student_devices;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Verification
-- ---------------------------------------------------------------------------
-- select type, count(*) from public.app_notifications group by type;
-- select fcm_token, platform, updated_at from public.student_devices limit 5;
-- select key, left(value, 40) from public.notification_config; -- service role only

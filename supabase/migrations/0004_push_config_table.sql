-- ============================================================================
-- 0004 Push configuration table (replaces current_setting() GUC usage)
-- Apply with:  supabase db push   (or paste into Supabase SQL editor)
--
-- WHY: `ALTER DATABASE postgres SET app.settings.push_function_url ...` is
-- rejected in the Supabase SQL Editor with 42501 (permission denied). This
-- migration stores the two dispatch settings in a locked-down table instead.
--
-- Fresh installs get the same table from 0003; this migration is idempotent and
-- is the one to apply to databases where 0003 was already run.
-- ============================================================================

create table if not exists public.notification_config (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now()
);

alter table public.notification_config enable row level security;

-- No policies on purpose: anon/authenticated cannot see a single row.
-- Reads happen inside the SECURITY DEFINER function below; the service role
-- (and SQL Editor, running as postgres) bypass RLS to configure the values.
revoke all on public.notification_config from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Replace the dispatcher: config now comes from the table, not GUC settings.
-- Behaviour is unchanged — inbox-only when unconfigured, never fails a write.
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
  v_url := nullif(
    (select value from public.notification_config where key = 'push_function_url'),
    ''
  );
  v_key := nullif(
    (select value from public.notification_config where key = 'push_service_role_key'),
    ''
  );

  if v_url is null then
    return null; -- inbox-only mode until push_function_url is configured
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
    -- A push failure must never roll back a fee/attendance/result write.
    null;
  end;

  return null;
exception when others then
  -- Missing config row / pg_net hiccup: still never break the source write.
  return null;
end;
$$;

revoke all on function public.dispatch_student_push() from public;

-- Ensure the trigger is attached (idempotent).
drop trigger if exists trg_dispatch_student_push on public.app_notifications;
create trigger trg_dispatch_student_push
  after insert on public.app_notifications
  for each row execute function public.dispatch_student_push();

-- ---------------------------------------------------------------------------
-- SETUP (run in SQL Editor; runs as postgres / service role, bypasses RLS)
-- ---------------------------------------------------------------------------
-- insert into public.notification_config (key, value) values
--   ('push_function_url', 'https://<PROJECT_REF>.supabase.co/functions/v1/send-push'),
--   ('push_service_role_key', '<service_role_jwt>')
-- on conflict (key) do update set value = excluded.value, updated_at = now();
--
-- select key, left(value, 40) from public.notification_config;

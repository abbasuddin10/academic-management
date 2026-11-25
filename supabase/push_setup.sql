-- One-time push setup. Run in the Supabase SQL Editor (runs as postgres /
-- service role, so it bypasses the notification_config RLS lock).
-- Replace <PROJECT_REF> and <SERVICE_ROLE_KEY> before running.
--
-- IMPORTANT: <SERVICE_ROLE_KEY> must be the EXACT value the `send-push` Edge
-- Function sees in its SUPABASE_SERVICE_ROLE_KEY secret. A mismatch -> 401.

create extension if not exists pg_net;

insert into public.notification_config (key, value) values
  ('push_function_url',
   'https://<PROJECT_REF>.supabase.co/functions/v1/send-push'),
  ('push_service_role_key', '<SERVICE_ROLE_KEY>')
on conflict (key) do update set value = excluded.value, updated_at = now();

-- ---- Verification queries -------------------------------------------------
-- select key, left(value, 50) as preview from public.notification_config;
-- select extname from pg_extension where extname = 'pg_net';
-- select tgname, tgenabled from pg_trigger
--  where tgname in ('trg_dispatch_student_push', 'trg_notice_push');
-- select created, status_code, content from net._http_response
--  order by created desc limit 10;

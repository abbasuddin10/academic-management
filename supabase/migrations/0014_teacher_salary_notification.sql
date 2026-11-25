-- 0014 Teacher salary payment notifications
--
-- Reuses the existing pipeline:
--   teacher_salary_history INSERT
--     -> trg_teacher_salary_push
--     -> queue_student_notification_once() (one deduped inbox row)
--     -> app_notifications
--     -> trg_dispatch_student_push
--     -> send-push Edge Function
--     -> users.fcm_token for this exact teacher/staff recipient
--
-- The repository has no earlier trigger on teacher_salary_history, so this is
-- the only salary notification source. The dedupe key makes a repeated save of
-- the same payment event safe (no second inbox row and no second FCM push).

alter table public.app_notifications
  add column if not exists dedupe_key text;

create index if not exists idx_app_notifications_dedupe
  on public.app_notifications (reader_key, type, dedupe_key, created_at desc);

create or replace function public.trg_teacher_salary_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     text;
  v_role        text;
  v_reader_key  text;
  v_amount      text;
  v_month       text;
  v_body        text;
  v_dedupe_key  text;
begin
  select u.id::text, u.role
    into v_user_id, v_role
    from public.users u
   where u.id::text = new.teacher_id::text
     and (u.academy_id is null or u.academy_id::text = new.academy_id::text);

  if v_user_id is null then
    return null; -- payment for a deleted/unknown user: never notify anybody
  end if;

  -- Mirrors SessionService.readerKeyFor(): teacher/staff use `teacher:<id>`,
  -- while an admin recipient is keyed by their auth uid directly.
  if v_role in ('teacher', 'staff') then
    v_reader_key := 'teacher:' || v_user_id;
  else
    v_reader_key := v_user_id;
  end if;

  v_amount := coalesce(nullif(btrim(new.amount::text), ''), '0');
  v_month := coalesce(nullif(btrim(new.month::text), ''), 'চলতি');
  v_body := v_month || ' মাসের বেতন ' || v_amount || ' টাকা প্রদান করা হয়েছে।';

  v_dedupe_key := 'teacher_salary:'
    || coalesce(new.teacher_id::text, '')
    || ':' || coalesce(new.academy_id::text, '')
    || ':' || coalesce(new.month::text, '')
    || ':' || coalesce(new.payment_date::text, '')
    || ':' || coalesce(new.amount::text, '')
    || ':' || coalesce(new.created_at::text, '');

  -- type 'fee' keeps the existing Bengali "বেতন" category/icon; route tells the
  -- recipient's notification center to open their salary page.
  perform public.queue_student_notification_once(
    new.academy_id::text,
    v_reader_key,
    'fee',
    'বেতন প্রদান',
    v_body,
    'teacher_salary',
    new.teacher_id::text,
    v_dedupe_key,
    15
  );

  return null;
exception when others then
  -- A notification problem must never roll back a successful salary payment.
  return null;
end;
$$;

drop trigger if exists trg_teacher_salary_push on public.teacher_salary_history;
create trigger trg_teacher_salary_push
  after insert on public.teacher_salary_history
  for each row execute function public.trg_teacher_salary_notification();

revoke all on function public.trg_teacher_salary_notification() from public;

-- Verification:
--   select tgname, tgenabled from pg_trigger
--    where tgrelid = 'public.teacher_salary_history'::regclass;
--   select reader_key, title, body, route, created_at
--     from public.app_notifications
--    where type = 'fee' and route = 'teacher_salary'
--    order by created_at desc limit 10;

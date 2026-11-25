-- ============================================================================
-- 0005 Notice push fan-out
-- Apply with:  supabase db push   (or paste into Supabase SQL editor)
--
-- Notices are the one notification type that previously never reached the
-- push pipeline: `create_notice_view.dart` inserts straight into `notices`
-- and the in-app badge is driven by realtime on that table. This migration
-- mirrors the app's own audience rules (NoticeRepository.isTargeted) into an
-- AFTER INSERT trigger that queues one `app_notifications` row per targeted
-- student. The existing trg_dispatch_student_push trigger then sends the FCM
-- push, so no Edge Function changes are required.
-- ============================================================================

create or replace function public.trg_notice_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target text := lower(btrim(coalesce(new.target_type, '')));
  v_class  text := lower(btrim(coalesce(new.target_class, '')));
  r record;
begin
  -- Audiences understood by the app: everyone / class. Unknown audiences are
  -- intentionally ignored (the app would not show those notices to students).
  if v_target not in ('', 'everyone', 'all', 'all_students', 'class') then
    return null;
  end if;

  for r in
    select 'student:' || s.id::text as rk
      from public.students s
     where s.academy_id::text = new.academy_id::text
       and (
         v_target <> 'class'
         or lower(btrim(s."class"::text)) = v_class
       )
  loop
    perform public.queue_student_notification(
      new.academy_id::text,
      r.rk,
      'notice',
      coalesce(new.title, 'নতুন নোটিশ'),
      coalesce(left(new.description, 200), ''),
      'notice',
      new.id::text
    );
  end loop;

  return null;
end;
$$;

drop trigger if exists trg_notice_push on public.notices;
create trigger trg_notice_push
  after insert on public.notices
  for each row execute function public.trg_notice_push();

revoke all on function public.trg_notice_push() from public;

-- Verify:
-- select tgname, tgenabled from pg_trigger where tgname = 'trg_notice_push';
-- select reader_key, title, created_at from public.app_notifications
--  where type = 'notice' order by created_at desc limit 10;

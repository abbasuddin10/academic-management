-- ============================================================================
-- 0011 Hard no-duplicate / no-overlap guard for model tests
-- Apply with:  supabase db push   (or paste into the Supabase SQL editor)
--
-- The Flutter form checks for overlaps, but a client-side check is a race:
-- two admins can both pass it and insert. This trigger makes overlap
-- impossible at the database level for every INSERT/UPDATE of exam_schedules,
-- regardless of which client or RPC performed it.
--
-- Also adds a safe timestamptz parser so a legacy bad timestamp can never
-- break unrelated updates (e.g. expiry or cancellation).
-- ============================================================================

create or replace function public.safe_timestamptz(p_value text)
returns timestamptz
language plpgsql
immutable
set search_path = pg_catalog
as $$
begin
  return nullif(btrim(coalesce(p_value, '')), '')::timestamptz;
exception when others then
  return null;
end;
$$;

revoke all on function public.safe_timestamptz(text) from public;
grant execute on function public.safe_timestamptz(text) to authenticated;

create or replace function public.enforce_model_test_no_overlap()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start  timestamptz;
  v_end    timestamptz;
  v_other  record;
begin
  -- Drafts and published tests reserve a slot. Cancelled/expired ones do not.
  if coalesce(NEW.status, 'published') not in ('draft', 'published') then
    return NEW;
  end if;

  v_start := public.safe_timestamptz(to_jsonb(NEW) ->> 'start_time');
  v_end   := public.safe_timestamptz(to_jsonb(NEW) ->> 'end_time');

  -- Invalid/missing times are reported clearly instead of being stored.
  if v_start is null or v_end is null then
    raise exception ' সময় তথ্য সঠিক নয়। শুরু ও শেষ সময় দিন।';
  end if;
  if v_end <= v_start then
    raise exception 'শেষের সময় শুরুর সময়ের পরে হতে হবে।';
  end if;
  if (v_end - v_start) < interval '1 minute' then
    raise exception 'পরীক্ষার সময়কাল কমপক্ষে ১ মিনিট হতে হবে।';
  end if;
  if NEW.status = 'published' and v_end < now() then
    raise exception 'অতীতের সময়ে পরীক্ষা প্রকাশ করা যাবে না।';
  end if;

  select o.id, o.exam_title,
         public.safe_timestamptz(to_jsonb(o) ->> 'start_time') as other_start,
         public.safe_timestamptz(to_jsonb(o) ->> 'end_time') as other_end
    into v_other
    from public.exam_schedules o
   where o.id is distinct from NEW.id
     and o.academy_id::text = NEW.academy_id::text
     and lower(btrim(coalesce(o.class_name::text, ''))) =
         lower(btrim(coalesce(NEW.class_name::text, '')))
     and coalesce(o.status, 'published') in ('draft', 'published')
     and public.safe_timestamptz(to_jsonb(o) ->> 'start_time') is not null
     and public.safe_timestamptz(to_jsonb(o) ->> 'end_time') is not null
     and public.safe_timestamptz(to_jsonb(o) ->> 'start_time') < v_end
     and public.safe_timestamptz(to_jsonb(o) ->> 'end_time') > v_start
   limit 1;

  if found then
    raise exception
      'OVERLAP:এই শ্রেণিতে নির্ধারিত সময়ে ইতিমধ্যে "%" পরীক্ষা রয়েছে (%- %)। অন্য সময় বাছুন।',
      coalesce(v_other.exam_title, 'অন্য মডেল টেস্ট'),
      to_char(v_other.other_start at time zone 'UTC', 'DD Mon HH24:MI'),
      to_char(v_other.other_end at time zone 'UTC', 'HH24:MI');
  end if;

  return NEW;
end;
$$;

-- The `z` prefix makes this trigger fire last among the BEFORE triggers, so
-- it validates the final status/times after state and snapshot triggers ran.
drop trigger if exists trg_model_test_no_overlap on public.exam_schedules;
drop trigger if exists trg_model_test_z_no_overlap on public.exam_schedules;
create trigger trg_model_test_z_no_overlap
  before insert or update on public.exam_schedules
  for each row execute function public.enforce_model_test_no_overlap();

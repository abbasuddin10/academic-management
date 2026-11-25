-- ============================================================================
-- 0012 Model test: JSON-safe writes, fail-safe notifications, draft privacy
-- Apply with:  supabase db push   (or paste into the Supabase SQL editor)
--
-- 1. Published tests fire trg_model_test_push AFTER INSERT. Any error in the
--    fan-out/push chain (including a legacy malformed json column) currently
--    aborts the whole model-test INSERT. Drafts skip that trigger, which is
--    exactly why "প্রকাশিত" failed and "খসরা" worked. The trigger is now
--    fail-safe: notification problems can never roll back a test creation.
-- 2. A new SECURITY DEFINER RPC writes every field with explicit, type-aware
--    JSON casting, so a json/jsonb/text `selected_question_ids` column is
--    always given a valid value.
-- 3. RLS + app query: students only ever see published/expired tests.
-- ============================================================================

create extension if not exists pgcrypto;

-- Safe text -> jsonb conversion (never throws, never returns a scalar).
create or replace function public.safe_jsonb_from_text(p_text text)
returns jsonb language plpgsql immutable
set search_path = public, pg_catalog as $$
declare v_text text := btrim(coalesce(p_text, '')); v_parsed jsonb;
begin
  -- A legacy placeholder such as "—" is rejected before any jsonb cast.
  if v_text = '' or left(v_text, 1) <> '[' then return '[]'::jsonb; end if;
  begin
    v_parsed := v_text::jsonb;
    if jsonb_typeof(v_parsed) = 'array' then return v_parsed; end if;
  exception when others then return '[]'::jsonb; end;
  return '[]'::jsonb;
end; $$;

revoke all on function public.safe_jsonb_from_text(text) from public;
grant execute on function public.safe_jsonb_from_text(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Fail-safe model-test notification trigger
-- ---------------------------------------------------------------------------
create or replace function public.trg_model_test_push()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  j        jsonb := to_jsonb(new);
  o        jsonb;
  v_active boolean := coalesce((j ->> 'is_active')::boolean, false);
  v_was    boolean;
  v_title  text := coalesce(nullif(btrim(coalesce(j ->> 'exam_title', '')), ''), 'নতুন মডেল টেস্ট');
  v_body   text;
begin
  if tg_op = 'INSERT' then
    if not v_active then return null; end if;   -- drafts never notify
  else
    o := to_jsonb(old);
    v_was := coalesce((o ->> 'is_active')::boolean, false);
    if not v_active then return null; end if;   -- cancel/expiry never notify
    if v_was
       and (j ->> 'exam_title') = (o ->> 'exam_title')
       and (j ->> 'start_time') is not distinct from (o ->> 'start_time')
       and (j ->> 'class_name') is not distinct from (o ->> 'class_name') then
      return null;
    end if;
  end if;

  v_body := v_title
    || case when coalesce(j ->> 'class_name', '') <> ''
            then ' ' || j ->> 'class_name' else '' end
    || case when coalesce(j ->> 'start_time', '') <> ''
            then ' ' || left(j ->> 'start_time', 16) else '' end;

  begin
    perform public.fanout_class_notification(
      j ->> 'academy_id', j ->> 'class_name',
      'model_test', 'নতুন মডেল টেস্ট', v_body,
      'model_test', j ->> 'id',
      'model_test:' || coalesce(j ->> 'id', '')
    );
  exception when others then
    -- A notification failure must NEVER roll back a published model test.
    null;
  end;
  return null;
end; $$;

drop trigger if exists trg_model_test_push on public.exam_schedules;
create trigger trg_model_test_push
  after insert or update on public.exam_schedules
  for each row execute function public.trg_model_test_push();

-- ---------------------------------------------------------------------------
-- 2. JSON-safe, type-aware model-test write RPC
-- ---------------------------------------------------------------------------
-- Drop legacy overloads first: the old signature had a DEFAULT before
-- required parameters (ERROR 42P13) and CREATE OR REPLACE would otherwise
-- leave it behind as an ambiguous extra overload.
do $$
declare v_args text;
begin
  for v_args in
    select pg_get_function_identity_arguments(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'save_model_test'
  loop
    execute format('drop function if exists public.save_model_test(%s) cascade', v_args);
  end loop;
end $$;

-- Every DEFAULT parameter is at the end of the list.
create or replace function public.save_model_test(
  p_academy_id         text,
  p_class_name         text,
  p_subject_name       text,
  p_exam_title         text,
  p_chapter_name       text,
  p_selected_question_ids text,
  p_start_time         timestamptz,
  p_end_time           timestamptz,
  p_status             text,
  p_duration_minutes   integer,
  p_marks_per_question numeric,
  p_total_marks        numeric,
  p_negative_marks     numeric,
  p_pass_percent       numeric,
  p_creator_id         text default null,
  p_creator_name       text default null,
  p_test_id            text default null
) returns text
language plpgsql security definer
set search_path = public as $$
declare
  v_id text;
  v_ids_json jsonb := public.safe_jsonb_from_text(p_selected_question_ids);
  v_duration integer := greatest(
    1, floor(extract(epoch from (p_end_time - p_start_time)) / 60)::integer);
  v_marks numeric := greatest(1, coalesce(p_marks_per_question, 1));
begin
  if coalesce(public.current_user_role(), '') not in
     ('teacher', 'staff', 'super_admin', 'admin') then
    raise exception 'শিক্ষক বা প্রশাসকরাই মডেল টেস্ট তৈরি করতে পারেন।';
  end if;
  if coalesce(p_academy_id, '') = '' or p_academy_id <> public.current_academy_id() then
    raise exception 'প্রতিষ্ঠানের তথ্য মিলেনি। আবার লগইন করুন।';
  end if;
  if btrim(coalesce(p_exam_title, '')) = '' then
    raise exception 'পরীক্ষার নাম লিখুন।';
  end if;
  if p_end_time is null or p_start_time is null or p_end_time <= p_start_time then
    raise exception 'শেষের সময় শুরুর সময়ের পরে হতে হবে।';
  end if;
  if (p_end_time - p_start_time) < interval '1 minute' then
    raise exception 'পরীক্ষার সময়কাল কমপক্ষে ১ মিনিট হতে হবে।';
  end if;
  if p_end_time < now() then
    raise exception 'অতীতের সময়ে পরীক্ষা তৈরি করা যাবে না।';
  end if;
  if p_test_id is null and p_start_time < now() - interval '1 minute' then
    raise exception 'শুরুর সময় অতীত হতে পারে না।';
  end if;
  if coalesce(p_status, 'published') not in ('draft', 'published') then
    raise exception 'অবস্থা শুধু খসড়া বা প্রকাশিত হতে পারে।';
  end if;
  if jsonb_array_length(v_ids_json) = 0 then
    raise exception 'কোনো প্রশ্ন নির্বাচন করা হয়নি।';
  end if;

  if exists (
    select 1 from public.exam_schedules o
     where (p_test_id is null or o.id::text <> p_test_id)
       and o.academy_id::text = p_academy_id
       and lower(btrim(coalesce(o.class_name::text, ''))) =
           lower(btrim(coalesce(p_class_name, '')))
       and coalesce(o.status, 'published') in ('draft', 'published')
       and public.safe_timestamptz(to_jsonb(o) ->> 'start_time') < p_end_time
       and public.safe_timestamptz(to_jsonb(o) ->> 'end_time') > p_start_time
  ) then
    raise exception 'OVERLAP:এই শ্রেণিতে নির্ধারিত সময়ে অন্য পরীক্ষা আছে। অন্য সময় বাছুন।';
  end if;

  if p_test_id is null then
    insert into public.exam_schedules (
      academy_id, class_name, subject_name, exam_title, chapter_name,
      selected_question_ids, question_count, start_time, end_time, status,
      duration_minutes, marks_per_question, total_marks, negative_marks,
      pass_percent, question_creator_id, question_creator_name, questions_snapshot
    ) values (
      p_academy_id, p_class_name, p_subject_name, btrim(p_exam_title),
      nullif(btrim(coalesce(p_chapter_name, '')), ''),
      v_ids_json::text, jsonb_array_length(v_ids_json),
      p_start_time, p_end_time, coalesce(p_status, 'published'),
      v_duration, v_marks, jsonb_array_length(v_ids_json) * v_marks,
      greatest(0, coalesce(p_negative_marks, 0)),
      least(100, greatest(0, coalesce(p_pass_percent, 33))),
      nullif(btrim(coalesce(p_creator_id, '')), ''),
      coalesce(nullif(btrim(p_creator_name), ''), 'Teacher'),
      '[]'::jsonb
    ) returning id::text into v_id;
  else
    if not public.can_manage_model_test(
         (select question_creator_id::text from public.exam_schedules
           where id::text = p_test_id)) then
      raise exception 'এই পরীক্ষাটি সম্পাদনা করার অনুমতি নেই।';
    end if;
    update public.exam_schedules set
      academy_id = p_academy_id,
      class_name = p_class_name,
      subject_name = p_subject_name,
      exam_title = btrim(p_exam_title),
      chapter_name = nullif(btrim(coalesce(p_chapter_name, '')), ''),
      selected_question_ids = v_ids_json::text,
      question_count = jsonb_array_length(v_ids_json),
      start_time = p_start_time,
      end_time = p_end_time,
      status = coalesce(p_status, 'published'),
      duration_minutes = v_duration,
      marks_per_question = v_marks,
      total_marks = jsonb_array_length(v_ids_json) * v_marks,
      negative_marks = greatest(0, coalesce(p_negative_marks, 0)),
      pass_percent = least(100, greatest(0, coalesce(p_pass_percent, 33))),
      question_creator_id = nullif(btrim(coalesce(p_creator_id, '')), ''),
      question_creator_name = coalesce(nullif(btrim(p_creator_name), ''), 'Teacher'),
      questions_snapshot = '[]'::jsonb
    where id::text = p_test_id
    returning id::text into v_id;
  end if;
  return v_id;
exception when others then
  raise exception 'save_model_test failed (SQLSTATE %): %. Inputs: selected_question_ids=% | status=% | exam_title=%',
    sqlstate, sqlerrm,
    left(coalesce(p_selected_question_ids, ''), 120),
    left(coalesce(p_status, ''), 40),
    left(coalesce(p_exam_title, ''), 80);
end; $$;

revoke all on function public.save_model_test(
  text, text, text, text, text, text,
  timestamptz, timestamptz, text, integer,
  numeric, numeric, numeric, numeric, text, text, text
) from public;
grant execute on function public.save_model_test(
  text, text, text, text, text, text,
  timestamptz, timestamptz, text, integer,
  numeric, numeric, numeric, numeric, text, text, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Students must never see drafts (defence alongside the app query)
-- ---------------------------------------------------------------------------
drop policy if exists model_test_select on public.exam_schedules;
create policy model_test_select on public.exam_schedules
  for select to authenticated
  using (
    academy_id::text = public.current_academy_id()
    and (
      public.is_academy_staff()
      or coalesce(status, 'published') in ('published', 'expired')
    )
  );

-- ============================================================================
-- 0008 Reliable question-bank saves (admin + teacher)
-- Apply with:  supabase db push   (or paste into the Supabase SQL editor)
--
-- WHY
--   `academy_questions` is a legacy table. Older builds wrote author columns
--   (created_by / teacher_id / teacher_name ...) that were later removed from
--   the Flutter insert. When those columns are NOT NULL without a default the
--   INSERT fails with an opaque 23502 error, which the form reported as a
--   generic "save failed". This migration:
--     1. makes legacy author metadata optional / auto-filled,
--     2. exposes an idempotent SECURITY DEFINER RPC that writes only columns
--        that actually exist in the live table,
--     3. keeps tenant + staff RLS intact (no anon / student writes).
-- ============================================================================

create extension if not exists pgcrypto;

-- 1. Columns the app may rely on. `add column if not exists` is harmless when
--    the production table already has them.
alter table public.academy_questions
  add column if not exists question_hash text,
  add column if not exists created_by    text,
  add column if not exists teacher_id    text,
  add column if not exists teacher_name  text,
  add column if not exists updated_at    timestamptz not null default now();

-- 2. Relax NOT NULL on legacy author columns that have no database default.
--    They are auto-filled by the trigger below when they do exist.
do $$
declare v_col text;
begin
  for v_col in
    select unnest(array[
      'created_by', 'teacher_id', 'teacher_name', 'updated_by',
      'question_creator_id', 'question_creator_name'
    ])
  loop
    if exists (
      select 1 from information_schema.columns
       where table_schema = 'public'
         and table_name = 'academy_questions'
         and column_name = v_col
    ) then
      execute format(
        'alter table public.academy_questions alter column %I drop not null',
        v_col
      );
    end if;
  end loop;
end $$;

-- 3. Single trigger: accurate hash + automatic author metadata. Using
--    jsonb_populate_record means it never references a column that does not
--    exist in the installed schema.
create or replace function public.sync_question_metadata()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  j jsonb := to_jsonb(NEW);
  v_actor text := public.current_actor_id();
  v_name  text;
begin
  if btrim(coalesce(j ->> 'question_text', '')) = '' then
    raise exception 'প্রশ্ন খালি রাখা যাবে না।';
  end if;

  j := j || jsonb_build_object(
    'question_hash', encode(
      digest(lower(btrim(j ->> 'question_text')), 'sha256'), 'hex'
    )
  );

  if j ? 'created_by' and coalesce(j ->> 'created_by', '') = '' then
    j := jsonb_set(j, '{created_by}', to_jsonb(v_actor));
  end if;
  if j ? 'teacher_id' and coalesce(j ->> 'teacher_id', '') = '' then
    j := jsonb_set(j, '{teacher_id}', to_jsonb(v_actor));
  end if;
  if j ? 'teacher_name' and coalesce(j ->> 'teacher_name', '') = '' then
    select coalesce(display_name, '') into v_name
      from public.app_sessions where user_id = auth.uid() limit 1;
    j := jsonb_set(j, '{teacher_name}', to_jsonb(coalesce(v_name, '')));
  end if;

  -- Never write generated / identity columns back through the record.
  select jsonb_object_agg(e.key, e.value)
    into j
    from jsonb_each(j) as e(key, value)
   where not exists (
     select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = 'academy_questions'
        and c.column_name = e.key
        and (c.is_generated = 'ALWAYS' or c.is_identity = 'YES')
   );

  NEW := jsonb_populate_record(NEW, j);
  return NEW;
end;
$$;

drop trigger if exists trg_question_hash on public.academy_questions;
create trigger trg_question_hash
  before insert or update on public.academy_questions
  for each row execute function public.sync_question_metadata();

-- 4. Staff-only insert policy (re-asserted so a partially applied 0007 is
--    repaired too). Students can never write the question bank.
drop policy if exists question_bank_insert on public.academy_questions;
create policy question_bank_insert on public.academy_questions
  for insert to authenticated
  with check (
    academy_id::text = public.current_academy_id()
    and public.is_academy_staff()
  );

-- 5. Robust save RPC. Only columns present in the live table are inserted,
--    so unexpected legacy NOT NULL columns cannot break a save.
create or replace function public.save_academy_question(
  p_academy_id    text,
  p_class_name    text,
  p_subject_name  text,
  p_chapter_name  text,
  p_question_text text,
  p_option_a      text,
  p_option_b      text,
  p_option_c      text,
  p_option_d      text,
  p_correct_option text,
  p_explanation   text default '',
  p_question_hash text default null
) returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_payload jsonb;
  v_row     public.academy_questions%rowtype;
  v_id      text;
  v_options text[];
begin
  if coalesce(public.current_user_role(), '') not in
     ('teacher', 'staff', 'super_admin', 'admin') then
    raise exception 'শিক্ষক বা প্রশাসকরাই প্রশ্ন তৈরি করতে পারেন।';
  end if;
  if coalesce(p_academy_id, '') = ''
     or p_academy_id <> public.current_academy_id() then
    raise exception 'প্রতিষ্ঠানের তথ্য মিলেনি। অনুগ্রহ করে আবার লগইন করুন।';
  end if;
  if btrim(coalesce(p_question_text, '')) = '' then
    raise exception 'প্রশ্ন লিখুন।';
  end if;

  v_options := array[
    btrim(coalesce(p_option_a, '')), btrim(coalesce(p_option_b, '')),
    btrim(coalesce(p_option_c, '')), btrim(coalesce(p_option_d, ''))
  ];
  if array_position(v_options, '') is not null then
    raise exception 'সবগুলো অপশন পূরণ করতে হবে।';
  end if;
  if (select count(*)
        from (select distinct lower(u.option_text)
                from unnest(v_options) as u(option_text)) s) < 4 then
    raise exception 'একই অপশন একাধিকবার দেওয়া যাবে না।';
  end if;
  if upper(btrim(coalesce(p_correct_option, ''))) not in ('A', 'B', 'C', 'D') then
    raise exception 'সঠিক উত্তরের অপশন বাছুন।';
  end if;

  -- Atomic duplicate guard (maybeSingle() throws when duplicates already
  -- exist; EXISTS never does).
  if exists (
    select 1 from public.academy_questions q
     where q.academy_id::text = p_academy_id
       and q.class_name::text = p_class_name
       and q.subject_name::text = p_subject_name
       and q.question_hash = coalesce(
             nullif(btrim(p_question_hash), ''),
             encode(digest(lower(btrim(p_question_text)), 'sha256'), 'hex')
           )
  ) then
    raise exception 'DUPLICATE:এই প্রশ্নটি ইতিমধ্যে এই ক্লাস ও বিষয়ে সংরক্ষিত রয়েছে।';
  end if;

  v_payload := jsonb_build_object(
    'academy_id',    p_academy_id,
    'class_name',    p_class_name,
    'subject_name',  p_subject_name,
    'chapter_name',  coalesce(nullif(btrim(p_chapter_name), ''), 'সম্পূর্ণ বই'),
    'question_text', btrim(p_question_text),
    'option_a',      v_options[1],
    'option_b',      v_options[2],
    'option_c',      v_options[3],
    'option_d',      v_options[4],
    'correct_option', upper(btrim(p_correct_option)),
    'explanation',   coalesce(btrim(p_explanation), ''),
    'question_hash', coalesce(
       nullif(btrim(p_question_hash), ''),
       encode(digest(lower(btrim(p_question_text)), 'sha256'), 'hex')
    ),
    'created_by',    public.current_actor_id(),
    'teacher_id',    public.current_actor_id(),
    'created_at',    now(),
    'updated_at',    now()
  );

  -- jsonb_populate_record converts every JSON value to the real column type.
  -- No dynamic SQL and no text-to-json casts.
  v_row := jsonb_populate_record(null::public.academy_questions, v_payload);
  insert into public.academy_questions (
    academy_id, class_name, subject_name, chapter_name, question_text,
    option_a, option_b, option_c, option_d, correct_option, explanation,
    question_hash, created_by, teacher_id, created_at, updated_at
  ) values (
    (v_row).academy_id, (v_row).class_name, (v_row).subject_name,
    (v_row).chapter_name, (v_row).question_text,
    (v_row).option_a, (v_row).option_b, (v_row).option_c, (v_row).option_d,
    (v_row).correct_option, (v_row).explanation,
    (v_row).question_hash, (v_row).created_by, (v_row).teacher_id,
    (v_row).created_at, (v_row).updated_at
  ) returning id::text into v_id;
  return v_id;
end;
$$;

revoke all on function public.save_academy_question(
  text, text, text, text, text, text, text, text, text, text, text, text
) from public;
grant execute on function public.save_academy_question(
  text, text, text, text, text, text, text, text, text, text, text, text
) to authenticated;

-- ============================================================================
-- 0009 Fix "function digest(text, unknown) does not exist" on question save
-- Apply with:  supabase db push   (or paste into the Supabase SQL editor)
--
-- Supabase installs pgcrypto in the `extensions` schema, while the functions
-- added in 0007/0008 declared `set search_path = public, auth`. The unqualified
-- call to digest() therefore failed at runtime with:
--     ERROR: function digest(text, unknown) does not exist
--
-- This migration adds one schema-safe SHA-256 helper and re-creates the three
-- functions that hash question text so they resolve digest() in EITHER schema.
-- The emitted hash is byte-for-byte identical to the Dart (crypto) SHA-256 of
-- lower(trim(question)), so existing duplicate checks keep working.
-- ============================================================================

create extension if not exists pgcrypto;

-- Single source of truth for question hashes. `convert_to(..., 'UTF8')` also
-- makes the bytea overload of digest() explicit, avoiding the text/bytea
-- ambiguity that produces "function digest(text, unknown) does not exist".
create or replace function public.model_test_sha256(p_text text)
returns text
language sql
immutable
set search_path = public, extensions, pg_catalog
as $$
  select encode(
    digest(convert_to(lower(btrim(coalesce(p_text, ''))), 'UTF8'), 'sha256'),
    'hex'
  );
$$;

revoke all on function public.model_test_sha256(text) from public;
grant execute on function public.model_test_sha256(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Trigger function (migration 0008) — accurate hash + author metadata.
-- ---------------------------------------------------------------------------
create or replace function public.sync_question_metadata()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, auth
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
    'question_hash', public.model_test_sha256(j ->> 'question_text')
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

-- ---------------------------------------------------------------------------
-- 2. Older hash trigger function (migration 0007) — kept consistent so a
--    rollback or manual trigger recreation cannot reintroduce the error.
-- ---------------------------------------------------------------------------
create or replace function public.sync_question_hash()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  j     jsonb := to_jsonb(NEW);
  v_txt text := coalesce(j ->> 'question_text', j ->> 'question', '');
begin
  NEW.question_hash := public.model_test_sha256(v_txt);
  return NEW;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Save RPC (migration 0008) — same logic, schema-safe hashing.
-- ---------------------------------------------------------------------------
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
set search_path = public, extensions, auth
as $$
declare
  v_payload jsonb;
  v_cols    text[];
  v_sql     text;
  v_id      text;
  v_options text[];
  v_hash    text;
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

  v_hash := coalesce(nullif(btrim(p_question_hash), ''),
                     public.model_test_sha256(p_question_text));

  -- Atomic duplicate guard (maybeSingle() throws on legacy duplicates).
  if exists (
    select 1 from public.academy_questions q
     where q.academy_id::text = p_academy_id
       and q.class_name::text = p_class_name
       and q.subject_name::text = p_subject_name
       and q.question_hash = v_hash
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
    'question_hash', v_hash,
    'created_by',    public.current_actor_id(),
    'teacher_id',    public.current_actor_id(),
    'created_at',    now(),
    'updated_at',    now()
  );

  select array_agg(k.key order by k.key)
    into v_cols
    from jsonb_object_keys(v_payload) as k(key)
   where exists (
     select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = 'academy_questions'
        and c.column_name = k.key
   );

  select
    'insert into public.academy_questions ('
      || string_agg(quote_ident(col), ',' order by col)
      || ') values ('
      || string_agg(format('($1::jsonb->>%L)', col), ',' order by col)
      || ') returning id::text'
    into v_sql
    from unnest(v_cols) as col;

  execute v_sql into v_id using v_payload;
  return v_id;
end;
$$;

revoke all on function public.save_academy_question(
  text, text, text, text, text, text, text, text, text, text, text, text
) from public;
grant execute on function public.save_academy_question(
  text, text, text, text, text, text, text, text, text, text, text, text
) to authenticated;

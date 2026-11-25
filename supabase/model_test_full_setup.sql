-- ============================================================================
-- MODEL TEST — FULL SETUP (single, idempotent script)
-- Paste once into the Supabase SQL Editor.
-- Equivalent to migrations 0007 + 0008 + 0009 + 0010 + 0011 + 0012 in final form.
-- Requires only 0001/0002 (app_sessions, current_academy_id,
-- current_user_role, current_reader_key). The notification pipeline is
-- recreated here, so stale 0003/0006 function bodies cannot affect saves.
-- ============================================================================

create extension if not exists pgcrypto;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- 0a. NUCLEAR CLEANUP OF STALE TRIGGERS
-- PostgreSQL stores a compiled function body. CREATE OR REPLACE cannot repair
-- an old trigger function that still contains a raw text::json/jsonb cast, and
-- PostgREST will happily keep calling whichever overload/trigger survived.
-- Drop EVERY non-internal trigger on the two tables this script owns, then
-- drop its function unless this script recreates it below. This is the only
-- reliable way to guarantee a stale invalid-token body cannot fire.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  v_keep text[] := array[
    'sync_model_test_state', 'build_model_test_snapshot',
    'enforce_model_test_no_overlap', 'trg_model_test_push',
    'cleanup_model_test_attempts', 'sync_question_metadata'
  ];
begin
  for r in
    select distinct p.proname, pg_get_function_identity_arguments(p.oid) as args
      from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid in ('public.exam_schedules'::regclass,
                         'public.academy_questions'::regclass)
       and not t.tgisinternal
  loop
    if not (r.proname = any (v_keep)) then
      execute format('drop function if exists public.%I(%s) cascade', r.proname, r.args);
    end if;
  end loop;

  for r in
    select t.tgname, t.tgrelid::regclass::text as tbl
      from pg_trigger t
     where t.tgrelid in ('public.exam_schedules'::regclass,
                         'public.academy_questions'::regclass)
       and not t.tgisinternal
  loop
    execute format('drop trigger if exists %I on %s', r.tgname, r.tbl);
  end loop;
end $$;

-- Legacy 0003 trigger/function (not recreated: 0006/full setup replaces it).
drop trigger if exists trg_model_test_notification on public.exam_schedules;
drop function if exists public.trg_model_test_notification();

-- ---------------------------------------------------------------------------
-- 0. Role/tenant helpers
-- ---------------------------------------------------------------------------
create or replace function public.current_actor_id()
returns text language sql stable security definer
set search_path = public, auth as $$
  select case
    when strpos(coalesce(public.current_reader_key(), ''), ':') > 0
      then split_part(public.current_reader_key(), ':', 2)
    else coalesce(auth.uid()::text, '')
  end;
$$;

create or replace function public.is_academy_staff()
returns boolean language sql stable security definer
set search_path = public, auth as $$
  select coalesce(public.current_user_role(), '') in
    ('teacher', 'staff', 'super_admin', 'admin');
$$;

create or replace function public.is_academy_admin()
returns boolean language sql stable security definer
set search_path = public, auth as $$
  select coalesce(public.current_user_role(), '') in ('super_admin', 'admin');
$$;

create or replace function public.can_manage_model_test(p_creator_id text)
returns boolean language sql stable security definer
set search_path = public, auth as $$
  select public.is_academy_staff() and (
    public.is_academy_admin() or p_creator_id is null
    or btrim(p_creator_id) = '' or p_creator_id = public.current_actor_id()
  );
$$;

-- Safe parsers: malformed legacy values never abort a write.
create or replace function public.safe_timestamptz(p_value text)
returns timestamptz language plpgsql immutable
set search_path = pg_catalog as $$
begin
  return nullif(btrim(coalesce(p_value, '')), '')::timestamptz;
exception when others then return null;
end;
$$;

create or replace function public.safe_jsonb_array(p_value jsonb)
returns jsonb language plpgsql immutable
set search_path = public, pg_catalog as $$
declare v_text text; v_parsed jsonb;
begin
  if p_value is null or p_value = 'null'::jsonb then return '[]'::jsonb; end if;
  if jsonb_typeof(p_value) = 'array' then return p_value; end if;
  if jsonb_typeof(p_value) = 'string' then
    v_text := btrim(coalesce(p_value #>> '{}', ''));
    -- Never hand a non-array token (for example a dash or pipe placeholder)
    -- to a jsonb cast. This guard stops the 22P02 invalid-token JSON error
    -- before it can be raised.
    if v_text = '' or left(v_text, 1) <> '[' then return '[]'::jsonb; end if;
    begin
      v_parsed := v_text::jsonb;
      if jsonb_typeof(v_parsed) = 'array' then return v_parsed; end if;
    exception when others then return '[]'::jsonb; end;
  end if;
  return '[]'::jsonb;
end;
$$;

-- Safe text -> jsonb conversion (never throws, never returns a scalar).
create or replace function public.safe_jsonb_from_text(p_text text)
returns jsonb language plpgsql immutable
set search_path = public, pg_catalog as $$
declare v_text text := btrim(coalesce(p_text, '')); v_parsed jsonb;
begin
  if v_text = '' or left(v_text, 1) <> '[' then return '[]'::jsonb; end if;
  begin
    v_parsed := v_text::jsonb;
    if jsonb_typeof(v_parsed) = 'array' then return v_parsed; end if;
  exception when others then return '[]'::jsonb; end;
  return '[]'::jsonb;
end; $$;

-- SHA-256 helper: works whether pgcrypto lives in public or extensions.
create or replace function public.model_test_sha256(p_text text)
returns text language sql immutable
set search_path = public, extensions, pg_catalog as $$
  select encode(
    digest(convert_to(lower(btrim(coalesce(p_text, ''))), 'UTF8'), 'sha256'),
    'hex'
  );
$$;

revoke all on function public.current_actor_id() from public;
revoke all on function public.is_academy_staff() from public;
revoke all on function public.is_academy_admin() from public;
revoke all on function public.can_manage_model_test(text) from public;
revoke all on function public.safe_timestamptz(text) from public;
revoke all on function public.safe_jsonb_array(jsonb) from public;
revoke all on function public.safe_jsonb_from_text(text) from public;
revoke all on function public.model_test_sha256(text) from public;
grant execute on function public.current_actor_id() to authenticated;
grant execute on function public.is_academy_staff() to authenticated;
grant execute on function public.is_academy_admin() to authenticated;
grant execute on function public.can_manage_model_test(text) to authenticated;
grant execute on function public.safe_timestamptz(text) to authenticated;
grant execute on function public.safe_jsonb_array(jsonb) to authenticated;
grant execute on function public.safe_jsonb_from_text(text) to authenticated;
grant execute on function public.model_test_sha256(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Model-test configuration + lifecycle
-- ---------------------------------------------------------------------------
alter table public.exam_schedules
  -- Core columns (older installs may be missing some of these).
  add column if not exists academy_id            text,
  add column if not exists class_name            text,
  add column if not exists subject_name          text,
  add column if not exists exam_title            text,
  add column if not exists chapter_name          text,
  add column if not exists start_time            timestamptz,
  add column if not exists end_time              timestamptz,
  add column if not exists created_at            timestamptz not null default now(),
  -- Compatibility columns.
  add column if not exists is_active             boolean not null default true,
  add column if not exists question_count        integer not null default 0,
  add column if not exists selected_question_ids text,
  add column if not exists question_creator_id   text,
  add column if not exists question_creator_name text,
  -- Model-test configuration + lifecycle.
  add column if not exists duration_minutes   integer,
  add column if not exists marks_per_question numeric not null default 1,
  add column if not exists total_marks        numeric not null default 0,
  add column if not exists negative_marks     numeric not null default 0,
  add column if not exists pass_percent       numeric not null default 33,
  add column if not exists status             text not null default 'published',
  add column if not exists questions_snapshot jsonb not null default '[]'::jsonb,
  add column if not exists published_at       timestamptz,
  add column if not exists cancelled_at       timestamptz,
  add column if not exists updated_at         timestamptz not null default now();

update public.exam_schedules
   set status = case
     when coalesce(is_active, false) then 'published'
     when public.safe_timestamptz(end_time::text) < now() then 'expired'
     else 'cancelled' end
 where status = 'published'
   and (coalesce(is_active, true) = false
        or public.safe_timestamptz(end_time::text) < now());

alter table public.exam_schedules
  drop constraint if exists exam_schedules_status_check;
alter table public.exam_schedules
  add constraint exam_schedules_status_check
  check (status in ('draft', 'published', 'cancelled', 'expired'));

create index if not exists idx_exam_schedules_status
  on public.exam_schedules (academy_id, status, start_time);

-- Keep legacy is_active in sync; distinguish cancel vs expire.
create or replace function public.sync_model_test_state()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    if NEW.status is null or btrim(NEW.status) = '' then NEW.status := 'published'; end if;
  elsif TG_OP = 'UPDATE' and (
          NEW.status is null or NEW.status is distinct from OLD.status) then
    NEW.status := coalesce(NEW.status, OLD.status);
  elsif TG_OP = 'UPDATE' and OLD.status = 'published'
        and coalesce(NEW.is_active, true) = false
        and coalesce(OLD.is_active, true) = true then
    NEW.status := 'cancelled';
  end if;

  if TG_OP = 'UPDATE' then
    if NEW.status = 'published' and OLD.status is distinct from 'published' then
      NEW.published_at := now(); NEW.cancelled_at := null;
    elsif NEW.status = 'cancelled' and OLD.status is distinct from 'cancelled' then
      NEW.cancelled_at := now();
    end if;
  elsif NEW.status = 'published' then
    NEW.published_at := now();
  end if;
  NEW.is_active := (NEW.status = 'published');
  NEW.updated_at := now();
  return NEW;
end;
$$;

-- Immutable snapshot built from the selected question IDs. Safe JSON parsing.
-- Drop first so no stale body (migration 0007's raw ::jsonb cast) can survive.
drop function if exists public.build_model_test_snapshot() cascade;
create or replace function public.build_model_test_snapshot()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  v_ids text[];
  v_snap jsonb := '[]'::jsonb;
  v_ids_json jsonb := '[]'::jsonb;
begin
  if TG_OP = 'UPDATE'
     and (to_jsonb(NEW) ->> 'selected_question_ids') is distinct from
         (to_jsonb(OLD) ->> 'selected_question_ids')
     and exists (select 1 from public.model_test_attempts a
                  where a.test_id = NEW.id::text) then
    raise exception 'Question set cannot change after students have started this test';
  end if;

  -- Snapshot building is best-effort. A legacy/corrupt value can never abort
  -- the save: any internal error falls back to a valid empty jsonb array.
  begin
  if TG_OP = 'INSERT' or (TG_OP = 'UPDATE' and (
       (to_jsonb(NEW) ->> 'selected_question_ids') is distinct from
       (to_jsonb(OLD) ->> 'selected_question_ids')
       or coalesce(NEW.questions_snapshot, '[]'::jsonb) = '[]'::jsonb)) then
    -- Reset first: even an unexpected downstream failure can never leave a
    -- scalar or stale value in questions_snapshot.
    NEW.questions_snapshot := '[]'::jsonb;
    v_ids_json := public.safe_jsonb_array(to_jsonb(NEW) -> 'selected_question_ids');
    if jsonb_typeof(v_ids_json) <> 'array' then
      v_ids_json := '[]'::jsonb;
    end if;
    select coalesce(array_agg(elem #>> '{}'), '{}'::text[])
      into v_ids from jsonb_array_elements(v_ids_json) as elem;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', q.id::text,
      'question', coalesce(to_jsonb(q) ->> 'question_text',
                           to_jsonb(q) ->> 'question', ''),
      'option_a', coalesce(to_jsonb(q) ->> 'option_a', ''),
      'option_b', coalesce(to_jsonb(q) ->> 'option_b', ''),
      'option_c', coalesce(to_jsonb(q) ->> 'option_c', ''),
      'option_d', coalesce(to_jsonb(q) ->> 'option_d', ''),
      'correct_option', coalesce(upper(btrim(coalesce(to_jsonb(q) ->> 'correct_option', ''))), ''),
      'explanation', coalesce(to_jsonb(q) ->> 'explanation', ''),
      'chapter_name', coalesce(to_jsonb(q) ->> 'chapter_name', '')
    ) order by x.ord), '[]'::jsonb)
      into v_snap
      from unnest(v_ids) with ordinality as x(qid, ord)
      join public.academy_questions q
        on q.id::text = x.qid
       and q.academy_id::text = NEW.academy_id::text;

    -- v_snap is always a jsonb ARRAY of OBJECTS; never a raw text token.
    NEW.questions_snapshot := coalesce(v_snap, '[]'::jsonb);
    if jsonb_typeof(NEW.questions_snapshot) <> 'array' then
      NEW.questions_snapshot := '[]'::jsonb;
    end if;
    NEW.question_count := jsonb_array_length(NEW.questions_snapshot);
    if coalesce(NEW.total_marks, 0) <= 0 then
      NEW.total_marks := jsonb_array_length(NEW.questions_snapshot) * coalesce(NEW.marks_per_question, 1);
    end if;
    if NEW.duration_minutes is null or NEW.duration_minutes <= 0 then
      NEW.duration_minutes := greatest(1, ceil(extract(epoch from (
        public.safe_timestamptz(to_jsonb(NEW) ->> 'end_time')
        - public.safe_timestamptz(to_jsonb(NEW) ->> 'start_time'))) / 60)::integer);
    end if;
  end if;

  exception when others then
    -- No snapshot error (including a stale 22P02 JSON cast) may fail the save.
    NEW.questions_snapshot := '[]'::jsonb;
    NEW.question_count := 0;
  end;

  NEW.negative_marks := greatest(0, coalesce(NEW.negative_marks, 0));
  NEW.marks_per_question := greatest(0, coalesce(NEW.marks_per_question, 1));
  return NEW;
end;
$$;

-- Hard no-duplicate / no-overlap rule (fires last among BEFORE triggers).
create or replace function public.enforce_model_test_no_overlap()
returns trigger language plpgsql security definer
set search_path = public as $$
declare v_start timestamptz; v_end timestamptz; v_other record;
begin
  if coalesce(NEW.status, 'published') not in ('draft', 'published') then
    return NEW;
  end if;
  v_start := public.safe_timestamptz(to_jsonb(NEW) ->> 'start_time');
  v_end   := public.safe_timestamptz(to_jsonb(NEW) ->> 'end_time');
  if v_start is null or v_end is null then
    raise exception 'সময় তথ্য সঠিক নয়। শুরু ও শেষ সময় দিন।';
  end if;
  if v_end <= v_start or (v_end - v_start) < interval '1 minute' then
    raise exception 'শেষের সময় শুরুর পরে হতে হবে এবং কমপক্ষে ১ মিনিট হতে হবে।';
  end if;
  -- Never publish (or directly insert) a test whose window has already ended.
  -- expire_model_tests updates status to 'expired', so it is unaffected.
  if NEW.status = 'published' and v_end < now() then
    raise exception 'অতীতের সময়ে পরীক্ষা প্রকাশ করা যাবে না।';
  end if;

  select o.id, o.exam_title,
         public.safe_timestamptz(to_jsonb(o) ->> 'start_time') as os,
         public.safe_timestamptz(to_jsonb(o) ->> 'end_time') as oe
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
    raise exception 'OVERLAP:এই শ্রেণিতে ওই সময়ে "%" পরীক্ষা আছে। অন্য সময় বাছুন।',
      coalesce(v_other.exam_title, 'অন্য মডেল টেস্ট');
  end if;
  return NEW;
end;
$$;

-- Remove ANY legacy trigger/function on exam_schedules that still contains
-- the unsafe raw `selected_question_ids ... ::jsonb` cast from migration 0007.
-- This is name-independent: a manually renamed old trigger cannot survive and
-- reintroduce a 22P02 invalid-token JSON error on the next model-test save.
do $$
declare r record;
begin
  for r in
    select t.tgname
      from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'public.exam_schedules'::regclass
       and not t.tgisinternal
       and p.prosrc like '%selected_question_ids%'
       and (p.prosrc like '%::jsonb%' or p.prosrc like '%::json%')
  loop
    execute format('drop trigger if exists %I on public.exam_schedules', r.tgname);
  end loop;

  for r in
    select p.proname, pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname not in ('build_model_test_snapshot')
       and p.prosrc like '%selected_question_ids%'
       and (p.prosrc like '%to_jsonb(NEW)%' or p.prosrc like '%to_jsonb(new)%')
  loop
    execute format('drop function if exists public.%I(%s) cascade', r.proname, r.args);
  end loop;
end $$;

drop trigger if exists trg_model_test_notification on public.exam_schedules;
drop trigger if exists trg_model_test_state on public.exam_schedules;
drop trigger if exists trg_model_test_snapshot on public.exam_schedules;
drop trigger if exists trg_model_test_no_overlap on public.exam_schedules;
drop trigger if exists trg_model_test_z_no_overlap on public.exam_schedules;
create trigger trg_model_test_state
  before insert or update on public.exam_schedules
  for each row execute function public.sync_model_test_state();
create trigger trg_model_test_snapshot
  before insert or update on public.exam_schedules
  for each row execute function public.build_model_test_snapshot();
create trigger trg_model_test_z_no_overlap
  before insert or update on public.exam_schedules
  for each row execute function public.enforce_model_test_no_overlap();

-- ---------------------------------------------------------------------------
-- 2. Question bank: metadata trigger + role-aware RLS
-- ---------------------------------------------------------------------------
alter table public.academy_questions
  add column if not exists question_hash text,
  add column if not exists created_by    text,
  add column if not exists teacher_id    text,
  add column if not exists teacher_name  text,
  add column if not exists updated_at    timestamptz not null default now();

do $$ declare v_col text;
begin
  foreach v_col in array array[
    'created_by','teacher_id','teacher_name','updated_by',
    'question_creator_id','question_creator_name'] loop
    if exists (select 1 from information_schema.columns
                where table_schema='public' and table_name='academy_questions'
                  and column_name=v_col) then
      execute format('alter table public.academy_questions alter column %I drop not null', v_col);
    end if;
  end loop;
end $$;

create or replace function public.sync_question_metadata()
returns trigger language plpgsql security definer
set search_path = public, extensions, auth as $$
declare j jsonb := to_jsonb(NEW); v_actor text := public.current_actor_id(); v_name text;
begin
  if btrim(coalesce(j ->> 'question_text', '')) = '' then
    raise exception 'প্রশ্ন খালি রাখা যাবে না।';
  end if;
  j := j || jsonb_build_object('question_hash', public.model_test_sha256(j ->> 'question_text'));
  if j ? 'created_by' and coalesce(j ->> 'created_by', '') = '' then
    j := jsonb_set(j, '{created_by}', to_jsonb(v_actor)); end if;
  if j ? 'teacher_id' and coalesce(j ->> 'teacher_id', '') = '' then
    j := jsonb_set(j, '{teacher_id}', to_jsonb(v_actor)); end if;
  if j ? 'teacher_name' and coalesce(j ->> 'teacher_name', '') = '' then
    select coalesce(display_name, '') into v_name
      from public.app_sessions where user_id = auth.uid() limit 1;
    j := jsonb_set(j, '{teacher_name}', to_jsonb(coalesce(v_name, ''))); end if;
  select jsonb_object_agg(e.key, e.value) into j
    from jsonb_each(j) as e(key, value)
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema='public' and c.table_name='academy_questions'
                        and c.column_name=e.key
                        and (c.is_generated='ALWAYS' or c.is_identity='YES'));
  NEW := jsonb_populate_record(NEW, j);
  return NEW;
end;
$$;

drop trigger if exists trg_question_hash on public.academy_questions;
create trigger trg_question_hash
  before insert or update on public.academy_questions
  for each row execute function public.sync_question_metadata();

do $$ declare t text;
begin
  foreach t in array array['exam_schedules','academy_questions'] loop
    execute format('drop policy if exists tenant_select on public.%I', t);
    execute format('drop policy if exists tenant_insert on public.%I', t);
    execute format('drop policy if exists tenant_update on public.%I', t);
    execute format('drop policy if exists tenant_delete on public.%I', t);
  end loop;
end $$;

drop policy if exists model_test_select on public.exam_schedules;
create policy model_test_select on public.exam_schedules for select to authenticated
  using (academy_id::text = public.current_academy_id()
         and (public.is_academy_staff()
              or coalesce(status, 'published') in ('published', 'expired')));
drop policy if exists model_test_insert on public.exam_schedules;
create policy model_test_insert on public.exam_schedules for insert to authenticated
  with check (academy_id::text = public.current_academy_id()
              and public.is_academy_staff() and status in ('draft','published'));
drop policy if exists model_test_update on public.exam_schedules;
create policy model_test_update on public.exam_schedules for update to authenticated
  using (academy_id::text = public.current_academy_id()
         and public.can_manage_model_test(question_creator_id::text))
  with check (academy_id::text = public.current_academy_id()
              and public.can_manage_model_test(question_creator_id::text));
drop policy if exists model_test_delete on public.exam_schedules;
create policy model_test_delete on public.exam_schedules for delete to authenticated
  using (academy_id::text = public.current_academy_id()
         and public.can_manage_model_test(question_creator_id::text));

drop policy if exists question_bank_select on public.academy_questions;
create policy question_bank_select on public.academy_questions for select to authenticated
  using (academy_id::text = public.current_academy_id());
drop policy if exists question_bank_insert on public.academy_questions;
create policy question_bank_insert on public.academy_questions for insert to authenticated
  with check (academy_id::text = public.current_academy_id() and public.is_academy_staff());
drop policy if exists question_bank_update on public.academy_questions;
create policy question_bank_update on public.academy_questions for update to authenticated
  using (academy_id::text = public.current_academy_id() and public.is_academy_staff())
  with check (academy_id::text = public.current_academy_id() and public.is_academy_staff());
drop policy if exists question_bank_delete on public.academy_questions;
create policy question_bank_delete on public.academy_questions for delete to authenticated
  using (academy_id::text = public.current_academy_id() and public.is_academy_staff());

-- ---------------------------------------------------------------------------
-- 3. Attempts & answers
-- ---------------------------------------------------------------------------
create table if not exists public.model_test_attempts (
  id uuid primary key default gen_random_uuid(),
  academy_id text not null, test_id text not null, student_id text not null,
  student_roll text, class_name text,
  status text not null default 'in_progress'
    check (status in ('in_progress','submitted','auto_submitted')),
  started_at timestamptz not null default now(), deadline_at timestamptz not null,
  submitted_at timestamptz, score numeric not null default 0,
  total_marks numeric not null default 0,
  correct_count integer not null default 0, wrong_count integer not null default 0,
  unanswered_count integer not null default 0, percentage numeric not null default 0,
  passed boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists idx_model_test_attempts_test
  on public.model_test_attempts (test_id, status);
create index if not exists idx_model_test_attempts_student
  on public.model_test_attempts (academy_id, student_id, started_at desc);
create index if not exists idx_model_test_attempts_progress_scope
  on public.model_test_attempts (academy_id, status, class_name, student_id);
drop index if exists idx_model_test_attempts_one_live;
create unique index idx_model_test_attempts_one_live
  on public.model_test_attempts (test_id, student_id) where status = 'in_progress';

create table if not exists public.model_test_answers (
  id uuid primary key default gen_random_uuid(),
  academy_id text not null,
  attempt_id uuid not null references public.model_test_attempts(id) on delete cascade,
  question_id text not null, selected_option text,
  is_correct boolean not null default false, marks_awarded numeric not null default 0,
  answered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (attempt_id, question_id)
);
create index if not exists idx_model_test_answers_attempt
  on public.model_test_answers (attempt_id);

create or replace function public.cleanup_model_test_attempts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.model_test_attempts where test_id = OLD.id::text;
  return OLD;
end; $$;
drop trigger if exists trg_cleanup_model_test_attempts on public.exam_schedules;
create trigger trg_cleanup_model_test_attempts
  after delete on public.exam_schedules
  for each row execute function public.cleanup_model_test_attempts();

alter table public.model_test_attempts enable row level security;
alter table public.model_test_answers  enable row level security;
revoke all on public.model_test_attempts from anon, authenticated;
revoke all on public.model_test_answers  from anon, authenticated;
grant select on public.model_test_attempts to authenticated;
grant select on public.model_test_answers  to authenticated;

drop policy if exists attempt_select on public.model_test_attempts;
create policy attempt_select on public.model_test_attempts for select to authenticated
  using (academy_id = public.current_academy_id()
         and (public.is_academy_staff() or student_id = public.current_actor_id()));
drop policy if exists answer_select on public.model_test_answers;
create policy answer_select on public.model_test_answers for select to authenticated
  using (academy_id = public.current_academy_id() and (
    public.is_academy_staff() or exists (
      select 1 from public.model_test_attempts a
       where a.id = attempt_id and a.student_id = public.current_actor_id())));

-- ---------------------------------------------------------------------------
-- 4. Server-side scoring / attempt lifecycle
-- ---------------------------------------------------------------------------
create or replace function public.finalize_model_test_attempt(
  p_attempt_id uuid, p_auto boolean default false)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare v_attempt model_test_attempts%rowtype; v_test exam_schedules%rowtype;
  v_q jsonb; v_ans model_test_answers%rowtype;
  v_correct int:=0; v_wrong int:=0; v_blank int:=0;
  v_score numeric:=0; v_total numeric; v_perq numeric; v_neg numeric; v_pct numeric;
begin
  select * into v_attempt from public.model_test_attempts
   where id=p_attempt_id for update;
  if not found then raise exception 'Attempt not found'; end if;
  if v_attempt.status <> 'in_progress' then
    return jsonb_build_object(
      'attempt_id', v_attempt.id::text, 'status', v_attempt.status,
      'score', v_attempt.score, 'total_marks', v_attempt.total_marks,
      'percentage', v_attempt.percentage, 'correct_count', v_attempt.correct_count,
      'wrong_count', v_attempt.wrong_count,
      'unanswered_count', v_attempt.unanswered_count,
      'passed', v_attempt.passed, 'already_submitted', true);
  end if;
  select * into v_test from public.exam_schedules where id::text=v_attempt.test_id;
  if not found then raise exception 'Test no longer exists'; end if;
  v_total := coalesce(v_test.total_marks, 0);
  v_perq := greatest(0, coalesce(v_test.marks_per_question, 1));
  v_neg := greatest(0, coalesce(v_test.negative_marks, 0));

  for v_q in select value from jsonb_array_elements(
      coalesce(v_test.questions_snapshot, '[]'::jsonb)) loop
    select * into v_ans from public.model_test_answers
     where attempt_id=v_attempt.id and question_id=coalesce(v_q->>'id','');
    if not found then
      insert into public.model_test_answers
        (academy_id, attempt_id, question_id, selected_option, is_correct, marks_awarded)
      values (v_attempt.academy_id, v_attempt.id, coalesce(v_q->>'id',''), null, false, 0);
      v_blank := v_blank + 1;
    elsif v_ans.selected_option is null or btrim(v_ans.selected_option)='' then
      v_blank := v_blank + 1;
    elsif upper(btrim(v_ans.selected_option)) = upper(btrim(coalesce(v_q->>'correct_option',''))) then
      v_correct := v_correct + 1;
      update public.model_test_answers
         set is_correct=true, marks_awarded=v_perq, updated_at=now() where id=v_ans.id;
    else
      v_wrong := v_wrong + 1;
      update public.model_test_answers
         set is_correct=false, marks_awarded=-v_neg, updated_at=now() where id=v_ans.id;
    end if;
  end loop;

  v_score := greatest(0, v_correct::numeric*v_perq - v_wrong::numeric*v_neg);
  if v_total <= 0 then v_total := (v_correct+v_wrong+v_blank)::numeric*v_perq; end if;
  v_pct := case when v_total>0 then round(v_score/v_total*100,2) else 0 end;

  update public.model_test_attempts set
    status=case when coalesce(p_auto,false) then 'auto_submitted' else 'submitted' end,
    submitted_at=now(), score=v_score, total_marks=v_total,
    correct_count=v_correct, wrong_count=v_wrong, unanswered_count=v_blank,
    percentage=v_pct, passed=v_pct>=coalesce(v_test.pass_percent,33), updated_at=now()
   where id=v_attempt.id returning * into v_attempt;

  return jsonb_build_object(
    'attempt_id', v_attempt.id::text, 'status', v_attempt.status,
    'score', v_attempt.score, 'total_marks', v_attempt.total_marks,
    'percentage', v_attempt.percentage, 'correct_count', v_attempt.correct_count,
    'wrong_count', v_attempt.wrong_count, 'unanswered_count', v_attempt.unanswered_count,
    'passed', v_attempt.passed, 'already_submitted', false);
end; $$;

create or replace function public.start_model_test_attempt(p_test_id text)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare v_test exam_schedules%rowtype; v_attempt model_test_attempts%rowtype;
  v_sid text:=public.current_actor_id(); v_start timestamptz; v_end timestamptz;
  v_deadline timestamptz; v_now timestamptz:=now(); v_roll text; v_class text;
begin
  if coalesce(public.current_user_role(),'') <> 'student' then
    raise exception 'Only students can take model tests'; end if;
  select * into v_test from public.exam_schedules
   where id::text=p_test_id and academy_id::text=public.current_academy_id();
  if not found then raise exception 'পরীক্ষাটি পাওয়া যায়নি।'; end if;
  if v_test.status <> 'published' then raise exception 'এই পরীক্ষাটি এখন উপলব্ধ নয়।'; end if;
  v_start := public.safe_timestamptz(to_jsonb(v_test)->>'start_time');
  v_end := public.safe_timestamptz(to_jsonb(v_test)->>'end_time');
  if v_now < v_start then raise exception 'পরীক্ষা এখনো শুরু হয়নি।'; end if;
  if v_now > v_end then raise exception 'পরীক্ষার নির্ধারিত সময় শেষ হয়ে গেছে।'; end if;

  select * into v_attempt from public.model_test_attempts
   where test_id=p_test_id and student_id=v_sid and status='in_progress'
   order by started_at desc limit 1;
  if found then
    if v_now >= v_attempt.deadline_at then
      perform public.finalize_model_test_attempt(v_attempt.id, true);
      raise exception 'পরীক্ষার সময় শেষ হয়ে গেছে।';
    end if;
    return jsonb_build_object(
      'attempt', to_jsonb(v_attempt), 'questions', v_test.questions_snapshot,
      'total_marks', v_test.total_marks,
      'marks_per_question', v_test.marks_per_question,
      'negative_marks', v_test.negative_marks,
      'answers', coalesce((select jsonb_object_agg(a.question_id,a.selected_option)
                            from public.model_test_answers a
                           where a.attempt_id=v_attempt.id), '{}'::jsonb),
      'server_now', v_now, 'resumed', true);
  end if;

  v_deadline := least(v_now + make_interval(
      mins => greatest(coalesce(v_test.duration_minutes,30),1)), v_end);
  select r.roll::text, r."class"::text into v_roll, v_class
    from public.students r
   where r.id::text=v_sid and r.academy_id::text=public.current_academy_id() limit 1;

  insert into public.model_test_attempts
    (academy_id, test_id, student_id, student_roll, class_name,
     status, started_at, deadline_at, total_marks)
  values (v_test.academy_id::text, p_test_id, v_sid, v_roll, v_class,
          'in_progress', v_now, v_deadline, coalesce(v_test.total_marks,0))
  returning * into v_attempt;

  return jsonb_build_object(
    'attempt', to_jsonb(v_attempt), 'questions', v_test.questions_snapshot,
    'total_marks', v_test.total_marks,
    'marks_per_question', v_test.marks_per_question,
    'negative_marks', v_test.negative_marks,
    'answers', '{}'::jsonb, 'server_now', v_now, 'resumed', false);
end; $$;

create or replace function public.save_model_test_answer(
  p_attempt_id uuid, p_question_id text, p_selected_option text)
returns void language plpgsql security definer
set search_path = public as $$
declare v_attempt model_test_attempts%rowtype; v_status text;
begin
  select * into v_attempt from public.model_test_attempts where id=p_attempt_id;
  if not found or v_attempt.student_id <> public.current_actor_id() then
    raise exception 'Attempt not found'; end if;
  if v_attempt.status <> 'in_progress' then
    raise exception 'এই পরীক্ষার উত্তর আর পরিবর্তন করা যাবে না।'; end if;
  if now() >= v_attempt.deadline_at then
    raise exception 'পরীক্ষার সময় শেষ হয়ে গেছে।'; end if;
  select status into v_status from public.exam_schedules where id::text=v_attempt.test_id;
  if coalesce(v_status,'') <> 'published' then
    raise exception 'পরীক্ষাটি বাতিল বা শেষ হয়ে গেছে।'; end if;
  if p_selected_option is not null
     and upper(btrim(p_selected_option)) not in ('A','B','C','D','') then
    raise exception 'Invalid option'; end if;
  insert into public.model_test_answers
    (academy_id, attempt_id, question_id, selected_option, answered_at, updated_at)
  values (v_attempt.academy_id, p_attempt_id, p_question_id,
          nullif(upper(btrim(coalesce(p_selected_option,''))),''), now(), now())
  on conflict (attempt_id, question_id)
  do update set selected_option=excluded.selected_option,
                answered_at=now(), updated_at=now();
end; $$;

create or replace function public.submit_model_test_attempt(
  p_attempt_id uuid, p_auto boolean default false)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare v_owner text;
begin
  select student_id into v_owner from public.model_test_attempts where id=p_attempt_id;
  if v_owner is null or v_owner <> public.current_actor_id() then
    raise exception 'Attempt not found'; end if;
  return public.finalize_model_test_attempt(p_attempt_id, coalesce(p_auto,false));
end; $$;

create or replace function public.expire_model_tests()
returns integer language plpgsql security definer
set search_path = public as $$
declare v_count integer; v_attempt record;
begin
  update public.exam_schedules set status='expired'
   where academy_id::text=public.current_academy_id()
     and status='published'
     and public.safe_timestamptz(end_time::text) < now();
  get diagnostics v_count = row_count;
  for v_attempt in
    select a.id from public.model_test_attempts a
     where a.academy_id=public.current_academy_id()
       and a.status='in_progress' and a.deadline_at < now()
  loop
    perform public.finalize_model_test_attempt(v_attempt.id, true);
  end loop;
  return v_count;
end; $$;

-- ---------------------------------------------------------------------------
-- 5. Robust question-save RPC (safe hashing, dynamic column filtering)
-- ---------------------------------------------------------------------------
-- Remove every legacy overload first. CREATE OR REPLACE only replaces a
-- function with the exact same argument-type signature; otherwise it silently
-- adds a new overload, which makes the named-argument RPC ambiguous.
do $$
declare v_args text;
begin
  for v_args in
    select pg_get_function_identity_arguments(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'save_academy_question'
  loop
    execute format('drop function if exists public.save_academy_question(%s) cascade', v_args);
  end loop;
end $$;

create or replace function public.save_academy_question(
  p_academy_id text, p_class_name text, p_subject_name text,
  p_chapter_name text, p_question_text text,
  p_option_a text, p_option_b text, p_option_c text, p_option_d text,
  p_correct_option text, p_explanation text default '',
  p_question_hash text default null)
returns text language plpgsql security definer
set search_path = public, extensions, auth as $$
declare v_payload jsonb; v_row public.academy_questions%rowtype; v_id text;
  v_options text[]; v_hash text;
begin
  if coalesce(public.current_user_role(),'') not in
     ('teacher','staff','super_admin','admin') then
    raise exception 'শিক্ষক বা প্রশাসকরাই প্রশ্ন তৈরি করতে পারেন।'; end if;
  if coalesce(p_academy_id,'')='' or p_academy_id <> public.current_academy_id() then
    raise exception 'প্রতিষ্ঠানের তথ্য মিলেনি। আবার লগইন করুন।'; end if;
  if btrim(coalesce(p_question_text,''))='' then raise exception 'প্রশ্ন লিখুন।'; end if;
  v_options := array[btrim(coalesce(p_option_a,'')), btrim(coalesce(p_option_b,'')),
                     btrim(coalesce(p_option_c,'')), btrim(coalesce(p_option_d,''))];
  if array_position(v_options,'') is not null then
    raise exception 'সবগুলো অপশন পূরণ করতে হবে।'; end if;
  if (select count(*) from (select distinct lower(u.option_text)
        from unnest(v_options) as u(option_text)) s) < 4 then
    raise exception 'একই অপশন একাধিকবার দেওয়া যাবে না।'; end if;
  if upper(btrim(coalesce(p_correct_option,''))) not in ('A','B','C','D') then
    raise exception 'সঠিক উত্তরের অপশন বাছুন।'; end if;

  v_hash := coalesce(nullif(btrim(p_question_hash),''),
                     public.model_test_sha256(p_question_text));
  if exists (select 1 from public.academy_questions q
              where q.academy_id::text=p_academy_id
                and q.class_name::text=p_class_name
                and q.subject_name::text=p_subject_name
                and q.question_hash=v_hash) then
    raise exception 'DUPLICATE:এই প্রশ্নটি ইতিমধ্যে সংরক্ষিত রয়েছে।';
  end if;

  v_payload := jsonb_build_object(
    'academy_id',p_academy_id, 'class_name',p_class_name,
    'subject_name',p_subject_name,
    'chapter_name',coalesce(nullif(btrim(p_chapter_name),''),'সম্পূর্ণ বই'),
    'question_text',btrim(p_question_text),
    'option_a',v_options[1], 'option_b',v_options[2],
    'option_c',v_options[3], 'option_d',v_options[4],
    'correct_option',upper(btrim(p_correct_option)),
    'explanation',coalesce(btrim(p_explanation),''),
    'question_hash',v_hash,
    'created_by',public.current_actor_id(), 'teacher_id',public.current_actor_id(),
    'created_at',now(), 'updated_at',now());

  -- jsonb_populate_record converts every field to the REAL column type.
  -- No dynamic SQL and no text::json/jsonb casts anywhere in this RPC.
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
end; $$;

-- ---------------------------------------------------------------------------
-- 6. Fail-safe publish notifications + JSON-safe model-test write RPC
-- ---------------------------------------------------------------------------
-- 6a. Self-contained notification pipeline. This script no longer depends on
-- the exact body text of 0003/0006 being present in the live database. Every
-- value below is text or jsonb built by jsonb_build_object; no text value is
-- ever cast to json/jsonb, so a separator or placeholder cannot cause 22P02.
create table if not exists public.app_notifications (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references public.academies(id) on delete cascade,
  reader_key  text not null,
  type        text not null default 'notice',
  title       text not null,
  body        text not null default '',
  target_id   text,
  route       text,
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
alter table public.app_notifications add column if not exists dedupe_key text;
create index if not exists idx_app_notifications_inbox
  on public.app_notifications (academy_id, reader_key, created_at desc);
create index if not exists idx_app_notifications_unread
  on public.app_notifications (reader_key, read_at);
create index if not exists idx_app_notifications_dedupe
  on public.app_notifications (reader_key, type, dedupe_key, created_at desc);
alter table public.app_notifications enable row level security;
drop policy if exists app_notifications_select_own on public.app_notifications;
create policy app_notifications_select_own on public.app_notifications for select
  to authenticated using (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key());
drop policy if exists app_notifications_update_own on public.app_notifications;
create policy app_notifications_update_own on public.app_notifications for update
  to authenticated using (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key())
  with check (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key());
drop policy if exists app_notifications_delete_own on public.app_notifications;
create policy app_notifications_delete_own on public.app_notifications for delete
  to authenticated using (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key());
revoke all on public.app_notifications from anon;
grant select, update, delete on public.app_notifications to authenticated;

create table if not exists public.notification_config (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now()
);
alter table public.notification_config enable row level security;
revoke all on public.notification_config from public, anon, authenticated;

create or replace function public.queue_student_notification(
  p_academy_id text, p_reader_key text, p_type text,
  p_title text, p_body text, p_route text, p_target_id text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare v_academy uuid;
begin
  if coalesce(p_academy_id,'')='' or coalesce(p_reader_key,'')='' then return; end if;
  begin
    v_academy := nullif(btrim(p_academy_id),'')::uuid;
  exception when others then
    return;
  end;
  insert into public.app_notifications
    (academy_id, reader_key, type, title, body, route, target_id)
  values (v_academy, p_reader_key, p_type, p_title, p_body, p_route, p_target_id);
exception when others then
  null; -- notification must never break the source-table write
end; $$;

create or replace function public.queue_student_notification_once(
  p_academy_id text, p_reader_key text, p_type text,
  p_title text, p_body text, p_route text, p_target_id text,
  p_dedupe_key text, p_dedupe_minutes integer default 15
) returns void
language plpgsql security definer set search_path = public as $$
declare v_academy uuid;
begin
  if coalesce(p_academy_id,'')='' or coalesce(p_reader_key,'')='' then return; end if;
  begin
    v_academy := nullif(btrim(p_academy_id),'')::uuid;
  exception when others then
    return;
  end;
  if exists (
    select 1 from public.app_notifications
     where reader_key=p_reader_key and type=p_type
       and coalesce(dedupe_key,'')=coalesce(p_dedupe_key,'')
       and created_at > now() - make_interval(mins => coalesce(p_dedupe_minutes,15))
  ) then return; end if;
  insert into public.app_notifications
    (academy_id, reader_key, type, title, body, route, target_id, dedupe_key)
  values (v_academy, p_reader_key, p_type, p_title, p_body,
          p_route, p_target_id, p_dedupe_key);
exception when others then
  null;
end; $$;

create or replace function public.fanout_class_notification(
  p_academy_id text, p_class_name text, p_type text,
  p_title text, p_body text, p_route text,
  p_target_id text, p_dedupe_prefix text
) returns void
language plpgsql security definer set search_path = public as $$
declare r record; v_class text := lower(btrim(coalesce(p_class_name,'')));
begin
  if coalesce(p_academy_id,'')='' then return; end if;
  for r in
    select 'student:' || s.id::text as rk, s.id::text as sid
      from public.students s
     where s.academy_id::text=p_academy_id
       and (v_class='' or lower(btrim(s."class"::text))=v_class)
  loop
    perform public.queue_student_notification_once(
      p_academy_id, r.rk, p_type, p_title, p_body, p_route, p_target_id,
      coalesce(p_dedupe_prefix,p_type) || ':' || r.sid);
  end loop;
exception when others then
  null;
end; $$;

create or replace function public.dispatch_student_push()
returns trigger language plpgsql security definer
set search_path = public, extensions as $$
declare v_url text; v_key text;
begin
  v_url := nullif((select value from public.notification_config
                    where key='push_function_url'), '');
  v_key := nullif((select value from public.notification_config
                    where key='push_service_role_key'), '');
  if v_url is null then return null; end if;
  begin
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer ' || coalesce(v_key,'')),
      body := jsonb_build_object(
        'reader_key', new.reader_key, 'type', new.type,
        'title', new.title, 'body', new.body, 'route', new.route,
        'target_id', new.target_id, 'academy_id', new.academy_id::text,
        'notification_id', new.id::text));
  exception when others then
    null;
  end;
  return null;
exception when others then
  return null;
end; $$;

drop trigger if exists trg_dispatch_student_push on public.app_notifications;
create trigger trg_dispatch_student_push
  after insert on public.app_notifications
  for each row execute function public.dispatch_student_push();

-- 6a-2. Notices: one inbox row (and therefore one push) per notice/student.
-- Older databases kept 0005's non-deduped notice trigger, which can insert two
-- app_notifications rows for the same notice and makes the inbox show it twice.
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

revoke all on function public.queue_student_notification(text,text,text,text,text,text,text) from public;
revoke all on function public.queue_student_notification_once(text,text,text,text,text,text,text,text,integer) from public;
revoke all on function public.fanout_class_notification(text,text,text,text,text,text,text,text) from public;
revoke all on function public.dispatch_student_push() from public;

-- 6b. Publish notification: body is plain text and is NEVER parsed as JSON.
create or replace function public.trg_model_test_push()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  j jsonb := to_jsonb(new); o jsonb;
  v_active boolean := coalesce((j ->> 'is_active')::boolean, false);
  v_was boolean;
  v_title text := coalesce(nullif(btrim(coalesce(j ->> 'exam_title', '')), ''), 'নতুন মডেল টেস্ট');
  v_body text;
begin
  if tg_op = 'INSERT' then
    if not v_active then return null; end if;
  else
    o := to_jsonb(old);
    v_was := coalesce((o ->> 'is_active')::boolean, false);
    if not v_active then return null; end if;
    if v_was
       and (j ->> 'exam_title') = (o ->> 'exam_title')
       and (j ->> 'start_time') is not distinct from (o ->> 'start_time')
       and (j ->> 'class_name') is not distinct from (o ->> 'class_name') then
      return null;
    end if;
  end if;

  -- Plain text only. concat_ws never produces a JSON token and body is stored
  -- in a text column; the dispatch function wraps it with jsonb_build_object.
  v_body := concat_ws(' ', v_title,
    nullif(j ->> 'class_name', ''),
    nullif(left(j ->> 'start_time', 16), ''));

  begin
    perform public.fanout_class_notification(
      j ->> 'academy_id', j ->> 'class_name',
      'model_test', 'নতুন মডেল টেস্ট', v_body,
      'model_test', j ->> 'id',
      'model_test:' || coalesce(j ->> 'id', '')
    );
  exception when others then
    null; -- notification problems must never roll back a published test
  end;
  return null;
end; $$;

drop trigger if exists trg_model_test_push on public.exam_schedules;
create trigger trg_model_test_push
  after insert or update on public.exam_schedules
  for each row execute function public.trg_model_test_push();

-- Drop the legacy overload(s) before recreating. The old signature put
-- p_test_id (DEFAULT) first, which PostgreSQL rejects with 42P13, and a
-- leftover copy would also make PostgREST's named-argument call ambiguous.
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

-- Every parameter with a DEFAULT is now at the end of the list.
create or replace function public.save_model_test(
  p_academy_id text, p_class_name text, p_subject_name text,
  p_exam_title text, p_chapter_name text,
  p_selected_question_ids text,
  p_start_time timestamptz, p_end_time timestamptz, p_status text,
  p_duration_minutes integer,
  p_marks_per_question numeric, p_total_marks numeric,
  p_negative_marks numeric, p_pass_percent numeric,
  p_creator_id text default null, p_creator_name text default null,
  p_test_id text default null
) returns text language plpgsql security definer
set search_path = public as $$
declare
  v_id text;
  -- Only a verified jsonb ARRAY ever leaves this parser. The only text->jsonb
  -- cast in this script is INSIDE that exception-guarded helper.
  v_ids_json jsonb := public.safe_jsonb_from_text(p_selected_question_ids);
  v_duration integer := greatest(
    1, floor(extract(epoch from (p_end_time - p_start_time)) / 60)::integer);
  v_marks numeric := greatest(1, coalesce(p_marks_per_question, 1));
  v_payload jsonb;
  v_row public.exam_schedules%rowtype;
  v_ids_col_type text;
begin
  if coalesce(public.current_user_role(), '') not in
     ('teacher','staff','super_admin','admin') then
    raise exception 'শিক্ষক বা প্রশাসকরাই মডেল টেস্ট তৈরি করতে পারেন।';
  end if;
  if coalesce(p_academy_id,'')='' or p_academy_id <> public.current_academy_id() then
    raise exception 'প্রতিষ্ঠানের তথ্য মিলেনি। আবার লগইন করুন।';
  end if;
  if btrim(coalesce(p_exam_title,''))='' then raise exception 'পরীক্ষার নাম লিখুন।'; end if;
  if p_start_time is null or p_end_time is null or p_end_time <= p_start_time then
    raise exception 'শেষের সময় শুরুর সময়ের পরে হতে হবে।'; end if;
  if (p_end_time - p_start_time) < interval '1 minute' then
    raise exception 'পরীক্ষার সময়কাল কমপক্ষে ১ মিনিট হতে হবে।'; end if;
  if p_end_time < now() then
    raise exception 'অতীতের সময়ে পরীক্ষা তৈরি করা যাবে না।'; end if;
  if p_test_id is null and p_start_time < now() - interval '1 minute' then
    raise exception 'শুরুর সময় অতীত হতে পারে না।'; end if;
  if coalesce(p_status,'published') not in ('draft','published') then
    raise exception 'অবস্থা শুধু খসড়া বা প্রকাশিত হতে পারে।'; end if;
  if jsonb_array_length(v_ids_json)=0 then
    raise exception 'কোনো প্রশ্ন নির্বাচন করা হয়নি।'; end if;

  if exists (select 1 from public.exam_schedules o
     where (p_test_id is null or o.id::text <> p_test_id)
       and o.academy_id::text=p_academy_id
       and lower(btrim(coalesce(o.class_name::text,'')))=lower(btrim(coalesce(p_class_name,'')))
       and coalesce(o.status,'published') in ('draft','published')
       and public.safe_timestamptz(to_jsonb(o)->>'start_time') < p_end_time
       and public.safe_timestamptz(to_jsonb(o)->>'end_time') > p_start_time) then
    raise exception 'OVERLAP:এই শ্রেণিতে নির্ধারিত সময়ে অন্য পরীক্ষা আছে।';
  end if;

  -- A json/jsonb/array column receives a JSON array value; a text column
  -- receives the JSON text of that same array. jsonb_populate_record then
  -- converts every field to the REAL column type. No dynamic SQL, no
  -- text-to-json cast, and no opportunity for a separator token to leak in.
  select data_type into v_ids_col_type
    from information_schema.columns
   where table_schema='public' and table_name='exam_schedules'
     and column_name='selected_question_ids';

  v_payload := jsonb_build_object(
    'academy_id', p_academy_id,
    'class_name', p_class_name,
    'subject_name', p_subject_name,
    'exam_title', btrim(p_exam_title),
    'chapter_name', nullif(btrim(coalesce(p_chapter_name,'')),''),
    'selected_question_ids', case
      when coalesce(v_ids_col_type,'text') in ('json','jsonb','ARRAY')
        then to_jsonb(v_ids_json)
      else to_jsonb(v_ids_json::text)
    end,
    'question_count', jsonb_array_length(v_ids_json),
    'start_time', p_start_time,
    'end_time', p_end_time,
    'status', coalesce(p_status,'published'),
    'duration_minutes', v_duration,
    'marks_per_question', v_marks,
    'total_marks', jsonb_array_length(v_ids_json) * v_marks,
    'negative_marks', greatest(0, coalesce(p_negative_marks,0)),
    'pass_percent', least(100, greatest(0, coalesce(p_pass_percent,33))),
    'question_creator_id', nullif(btrim(coalesce(p_creator_id,'')),''),
    'question_creator_name', coalesce(nullif(btrim(p_creator_name),''),'Teacher'),
    'questions_snapshot', '[]'::jsonb);

  v_row := jsonb_populate_record(null::public.exam_schedules, v_payload);

  if p_test_id is null then
    insert into public.exam_schedules (
      academy_id, class_name, subject_name, exam_title, chapter_name,
      selected_question_ids, question_count, start_time, end_time, status,
      duration_minutes, marks_per_question, total_marks, negative_marks,
      pass_percent, question_creator_id, question_creator_name, questions_snapshot
    ) values (
      (v_row).academy_id, (v_row).class_name, (v_row).subject_name,
      (v_row).exam_title, (v_row).chapter_name,
      (v_row).selected_question_ids, (v_row).question_count,
      (v_row).start_time, (v_row).end_time, (v_row).status,
      (v_row).duration_minutes, (v_row).marks_per_question,
      (v_row).total_marks, (v_row).negative_marks, (v_row).pass_percent,
      (v_row).question_creator_id, (v_row).question_creator_name,
      (v_row).questions_snapshot
    ) returning id::text into v_id;
  else
    if not public.can_manage_model_test(
         (select question_creator_id::text from public.exam_schedules
           where id::text=p_test_id)) then
      raise exception 'এই পরীক্ষাটি সম্পাদনা করার অনুমতি নেই।';
    end if;
    update public.exam_schedules set
      academy_id = (v_row).academy_id,
      class_name = (v_row).class_name,
      subject_name = (v_row).subject_name,
      exam_title = (v_row).exam_title,
      chapter_name = (v_row).chapter_name,
      selected_question_ids = (v_row).selected_question_ids,
      question_count = (v_row).question_count,
      start_time = (v_row).start_time,
      end_time = (v_row).end_time,
      status = (v_row).status,
      duration_minutes = (v_row).duration_minutes,
      marks_per_question = (v_row).marks_per_question,
      total_marks = (v_row).total_marks,
      negative_marks = (v_row).negative_marks,
      pass_percent = (v_row).pass_percent,
      question_creator_id = (v_row).question_creator_id,
      question_creator_name = (v_row).question_creator_name,
      questions_snapshot = (v_row).questions_snapshot
    where id::text = p_test_id
    returning id::text into v_id;
  end if;
  return v_id;
exception when others then
  raise exception 'save_model_test failed (SQLSTATE %): %. Inputs: selected_question_ids=%, status=%, exam_title=%',
    sqlstate, sqlerrm,
    left(coalesce(p_selected_question_ids,''), 120),
    left(coalesce(p_status,''), 40),
    left(coalesce(p_exam_title,''), 80);
end; $$;

-- ---------------------------------------------------------------------------
-- 6b. Student progress + aggregate-only class positions
-- ---------------------------------------------------------------------------
create or replace function public.student_model_test_progress(
  p_academy_id text,
  p_class_name text
)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_sid text := public.current_actor_id();
  v_academy text := public.current_academy_id();
  v_student_class text;
  v_class text;
  v_result jsonb;
begin
  if coalesce(public.current_user_role(),'') <> 'student' then
    raise exception 'Only students can view progress';
  end if;
  if p_academy_id is null or btrim(p_academy_id) = ''
     or btrim(p_academy_id) <> coalesce(v_academy, '') then
    raise exception 'প্রতিষ্ঠানের তথ্য মেলেনি।';
  end if;

  -- Prefer the signed-in student's own stored class; p_class_name is only a
  -- fallback for older sessions. A forged class name cannot widen the scope.
  select r."class"::text into v_student_class
    from public.students r
   where r.id::text = v_sid and r.academy_id::text = v_academy
   limit 1;
  v_class := coalesce(nullif(btrim(v_student_class),''), btrim(coalesce(p_class_name,'')));

  if coalesce(v_class,'') = '' then
    return jsonb_build_object(
      'student_id', v_sid, 'class_name', '',
      'overall', '{}'::jsonb, 'subjects', '[]'::jsonb, 'history', '[]'::jsonb);
  end if;

  with submitted as (
    select a.student_id, a.test_id,
      coalesce(nullif(btrim(e.subject_name),''), 'অনির্দিষ্ট') as subject_name,
      coalesce(nullif(btrim(e.exam_title),''), 'পরীক্ষা') as exam_title,
      a.score, a.total_marks, a.percentage, a.correct_count, a.wrong_count,
      a.unanswered_count, a.passed, a.submitted_at, a.id
    from public.model_test_attempts a
    left join public.exam_schedules e
      on e.id::text = a.test_id and e.academy_id::text = a.academy_id
    where a.academy_id = v_academy
      and a.status in ('submitted','auto_submitted')
      and lower(coalesce(nullif(btrim(a.class_name),''), nullif(btrim(e.class_name),''), '')) = lower(v_class)
      and (e.class_name is null or btrim(e.class_name) = '' or lower(btrim(e.class_name)) = lower(v_class))
  ),
  ranked_scores as (
    select s.*,
      row_number() over (
        partition by s.student_id, s.subject_name
        order by s.percentage desc, s.submitted_at desc nulls last, s.id) as best_rn,
      row_number() over (
        partition by s.student_id, s.subject_name
        order by s.submitted_at desc nulls last, s.id) as latest_rn
    from submitted s
  ),
  student_totals as (
    select student_id, count(*) as tests_taken,
      sum(score) as total_score, sum(total_marks) as max_score,
      round(avg(score),2) as average_score,
      round(avg(percentage),2) as average_percentage,
      round(count(*) filter (where passed) * 100.0 / count(*),2) as pass_rate,
      sum(correct_count) as correct, sum(wrong_count) as wrong,
      sum(unanswered_count) as unanswered
    from submitted group by student_id
  ),
  ranked_overall as (
    select st.*,
      rank() over (order by st.total_score desc, st.average_percentage desc, st.tests_taken desc) as rank,
      count(*) over () as total_students
    from student_totals st
  ),
  subject_totals as (
    select subject_name, student_id, count(*) as tests_taken,
      sum(score) as total_score, sum(total_marks) as max_score,
      round(avg(score),2) as average_score,
      round(avg(percentage),2) as average_percentage,
      round(count(*) filter (where passed) * 100.0 / count(*),2) as pass_rate,
      sum(correct_count) as correct, sum(wrong_count) as wrong,
      sum(unanswered_count) as unanswered
    from submitted group by subject_name, student_id
  ),
  ranked_subjects as (
    select st.*,
      rank() over (partition by st.subject_name
        order by st.total_score desc, st.average_percentage desc, st.tests_taken desc) as rank,
      count(*) over (partition by st.subject_name) as total_students
    from subject_totals st
  )
  select jsonb_build_object(
    'student_id', v_sid,
    'class_name', v_class,
    'overall', coalesce((
      select jsonb_build_object(
        'rank', ro.rank, 'total_students', ro.total_students,
        'tests_taken', ro.tests_taken, 'total_score', ro.total_score,
        'max_score', ro.max_score, 'average_score', ro.average_score,
        'average_percentage', ro.average_percentage, 'pass_rate', ro.pass_rate,
        'correct', ro.correct, 'wrong', ro.wrong, 'unanswered', ro.unanswered)
      from ranked_overall ro where ro.student_id = v_sid
    ), '{}'::jsonb),
    'subjects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'subject_name', rs.subject_name, 'rank', rs.rank,
        'total_students', rs.total_students, 'tests_taken', rs.tests_taken,
        'total_score', rs.total_score, 'max_score', rs.max_score,
        'average_score', rs.average_score,
        'average_percentage', rs.average_percentage, 'pass_rate', rs.pass_rate,
        'correct', rs.correct, 'wrong', rs.wrong, 'unanswered', rs.unanswered,
        'best_score', best.score, 'best_total', best.total_marks,
        'best_percentage', best.percentage,
        'latest_score', latest.score, 'latest_total', latest.total_marks,
        'latest_percentage', latest.percentage) order by rs.subject_name)
      from ranked_subjects rs
      left join lateral (
        select r.score, r.total_marks, r.percentage from ranked_scores r
         where r.student_id = rs.student_id and r.subject_name = rs.subject_name
           and r.best_rn = 1 limit 1
      ) best on true
      left join lateral (
        select r.score, r.total_marks, r.percentage from ranked_scores r
         where r.student_id = rs.student_id and r.subject_name = rs.subject_name
           and r.latest_rn = 1 limit 1
      ) latest on true
      where rs.student_id = v_sid
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'test_id', h.test_id, 'title', h.exam_title,
        'subject_name', h.subject_name, 'submitted_at', h.submitted_at,
        'score', h.score, 'total_marks', h.total_marks,
        'percentage', h.percentage, 'passed', h.passed)
        order by h.submitted_at desc nulls last)
      from (
        select s.* from submitted s where s.student_id = v_sid
         order by s.submitted_at desc nulls last limit 10
      ) h
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end; $$;

-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------
revoke all on function public.finalize_model_test_attempt(uuid,boolean) from public;
revoke all on function public.start_model_test_attempt(text) from public;
revoke all on function public.save_model_test_answer(uuid,text,text) from public;
revoke all on function public.submit_model_test_attempt(uuid,boolean) from public;
revoke all on function public.expire_model_tests() from public;
revoke all on function public.student_model_test_progress(text,text) from public;
revoke all on function public.save_academy_question(
  text,text,text,text,text,text,text,text,text,text,text,text) from public;
revoke all on function public.save_model_test(
  text,text,text,text,text,text,timestamptz,timestamptz,text,integer,
  numeric,numeric,numeric,numeric,text,text,text) from public;
grant execute on function public.start_model_test_attempt(text) to authenticated;
grant execute on function public.save_model_test_answer(uuid,text,text) to authenticated;
grant execute on function public.submit_model_test_attempt(uuid,boolean) to authenticated;
grant execute on function public.expire_model_tests() to authenticated;
grant execute on function public.student_model_test_progress(text,text) to authenticated;
grant execute on function public.save_academy_question(
  text,text,text,text,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.save_model_test(
  text,text,text,text,text,text,timestamptz,timestamptz,text,integer,
  numeric,numeric,numeric,numeric,text,text,text) to authenticated;

-- Reload PostgREST so the new function bodies are used immediately.
notify pgrst, 'reload schema';

-- Done. Drafts are hidden from students by both RLS and the app query.
-- Published tests notify students, but a notification failure can never
-- roll back the model-test write.
--
-- Verification query (expected model-test triggers):
-- select tgname, p.proname
--   from pg_trigger t join pg_proc p on p.oid=t.tgfoid
--  where t.tgrelid='public.exam_schedules'::regclass and not t.tgisinternal
--  order by tgname;

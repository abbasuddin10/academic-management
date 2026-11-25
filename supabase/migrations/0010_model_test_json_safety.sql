-- ============================================================================
-- 0010 Model test: never fail on malformed / double-encoded JSON ids
-- Apply with:  supabase db push   (or paste into the Supabase SQL editor)
--
-- The 0007 snapshot trigger used:
--     coalesce((to_jsonb(NEW) ->> 'selected_question_ids'), '[]')::jsonb
-- coalesce() only replaces NULL. An empty string, a legacy comma-separated
-- value, or a double-encoded JSON string all reach the ::jsonb cast and raise
--     ERROR: invalid input syntax for type json
-- on INSERT/UPDATE of exam_schedules (i.e. when creating a model test).
--
-- This migration replaces that cast with a normaliser that always returns a
-- jsonb ARRAY, whatever the stored representation or column type.
-- ============================================================================

create or replace function public.safe_jsonb_array(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_catalog
as $$
declare
  v_text   text;
  v_parsed jsonb;
begin
  if p_value is null or p_value = 'null'::jsonb then
    return '[]'::jsonb;
  end if;

  -- Already an array (jsonb column, or a text column holding a JSON array).
  if jsonb_typeof(p_value) = 'array' then
    return p_value;
  end if;

  -- A string: either the JSON text itself ("["id"]" stored in a text column)
  -- or a double-encoded array (a jsonb column holding a JSON string).
  if jsonb_typeof(p_value) = 'string' then
    v_text := btrim(coalesce(p_value #>> '{}', ''));
    -- Reject non-array tokens (e.g. the legacy em-dash placeholder) before
    -- any cast so `22P02 Token "—" is invalid` can never be raised here.
    if v_text = '' or left(v_text, 1) <> '[' then
      return '[]'::jsonb;
    end if;
    begin
      v_parsed := v_text::jsonb;
      if jsonb_typeof(v_parsed) = 'array' then
        return v_parsed;
      end if;
    exception when others then
      return '[]'::jsonb;
    end;
  end if;

  -- Numbers, booleans, objects, legacy non-JSON text — all become an empty
  -- array instead of aborting the whole INSERT/UPDATE.
  return '[]'::jsonb;
end;
$$;

revoke all on function public.safe_jsonb_array(jsonb) from public;
grant execute on function public.safe_jsonb_array(jsonb) to authenticated;

-- Malformed legacy timestamps must never abort a model-test write.
create or replace function public.safe_timestamptz(p_value text)
returns timestamptz language plpgsql immutable
set search_path = pg_catalog as $$
begin
  return nullif(btrim(coalesce(p_value, '')), '')::timestamptz;
exception when others then return null;
end;
$$;
revoke all on function public.safe_timestamptz(text) from public;
grant execute on function public.safe_timestamptz(text) to authenticated;

-- Rebuild the snapshot trigger with the safe normaliser. Everything else
-- (immutability guard, marks/duration derivation) is unchanged.
create or replace function public.build_model_test_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids      text[];
  v_snap     jsonb;
  v_ids_json jsonb;
begin
  if TG_OP = 'UPDATE'
     and (to_jsonb(NEW) ->> 'selected_question_ids') is distinct from
         (to_jsonb(OLD) ->> 'selected_question_ids')
     and exists (select 1 from public.model_test_attempts a
                  where a.test_id = NEW.id::text)
  then
    raise exception 'Question set cannot change after students have started this test';
  end if;

  if TG_OP = 'INSERT'
     or (TG_OP = 'UPDATE' and (
          (to_jsonb(NEW) ->> 'selected_question_ids') is distinct from
          (to_jsonb(OLD) ->> 'selected_question_ids')
          or coalesce(NEW.questions_snapshot, '[]'::jsonb) = '[]'::jsonb
        ))
  then
    -- Safe normalisation: never cast raw text straight to jsonb.
    NEW.questions_snapshot := '[]'::jsonb;
    v_ids_json := public.safe_jsonb_array(
      to_jsonb(NEW) -> 'selected_question_ids'
    );
    if jsonb_typeof(v_ids_json) <> 'array' then
      v_ids_json := '[]'::jsonb;
    end if;

    select coalesce(array_agg(elem #>> '{}'), '{}'::text[])
      into v_ids
      from jsonb_array_elements(v_ids_json) as elem;

    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'id',             q.id::text,
                 'question',       coalesce(to_jsonb(q) ->> 'question_text',
                                           to_jsonb(q) ->> 'question', ''),
                 'option_a',       coalesce(to_jsonb(q) ->> 'option_a', ''),
                 'option_b',       coalesce(to_jsonb(q) ->> 'option_b', ''),
                 'option_c',       coalesce(to_jsonb(q) ->> 'option_c', ''),
                 'option_d',       coalesce(to_jsonb(q) ->> 'option_d', ''),
                 'correct_option', coalesce(upper(btrim(coalesce(to_jsonb(q) ->> 'correct_option', ''))), ''),
                 'explanation',    coalesce(to_jsonb(q) ->> 'explanation', ''),
                 'chapter_name',   coalesce(to_jsonb(q) ->> 'chapter_name', '')
               ) order by x.ord
             ), '[]'::jsonb)
      into v_snap
      from unnest(v_ids) with ordinality as x(qid, ord)
      join public.academy_questions q
        on q.id::text = x.qid
       and q.academy_id::text = NEW.academy_id::text;

    NEW.questions_snapshot := coalesce(v_snap, '[]'::jsonb);
    if jsonb_typeof(NEW.questions_snapshot) <> 'array' then
      NEW.questions_snapshot := '[]'::jsonb;
    end if;
    NEW.question_count := jsonb_array_length(NEW.questions_snapshot);
    if coalesce(NEW.total_marks, 0) <= 0 then
      NEW.total_marks := jsonb_array_length(v_snap) * coalesce(NEW.marks_per_question, 1);
    end if;
    if NEW.duration_minutes is null or NEW.duration_minutes <= 0 then
      NEW.duration_minutes := greatest(
        1,
        floor(extract(epoch from (
          public.safe_timestamptz(to_jsonb(NEW) ->> 'end_time')
          - public.safe_timestamptz(to_jsonb(NEW) ->> 'start_time'))) / 60)::integer
      );
    end if;
  end if;

  NEW.negative_marks := greatest(0, coalesce(NEW.negative_marks, 0));
  NEW.marks_per_question := greatest(0, coalesce(NEW.marks_per_question, 1));
  return NEW;
end;
$$;

drop trigger if exists trg_model_test_snapshot on public.exam_schedules;
create trigger trg_model_test_snapshot
  before insert or update on public.exam_schedules
  for each row execute function public.build_model_test_snapshot();

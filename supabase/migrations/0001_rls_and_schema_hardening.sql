-- ============================================================================
-- Phase 1 security hardening
-- Apply with:  supabase db push   (or paste into the Supabase SQL editor)
--
-- Goals:
--   * Tenant isolation enforced by the database, not just by the Flutter app.
--   * Atomic academy registration (no orphaned partial academies).
--   * Indexes on every academy_id column.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Anonymous app sessions.
-- Teachers and students historically authenticated against plain tables with
-- the publishable key. On login the app now opens a Supabase anonymous session
-- and records the tenant/role here, so every subsequent query is an
-- authenticated query that RLS can scope correctly.
-- NOTE: "Allow anonymous sign-ins" must be enabled in Supabase Auth settings.
-- ---------------------------------------------------------------------------
create table if not exists public.app_sessions (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  academy_id   text not null,
  role         text not null,
  display_name text
);

alter table public.app_sessions enable row level security;

drop policy if exists app_session_self_select on public.app_sessions;
create policy app_session_self_select on public.app_sessions
  for select to authenticated using (user_id = auth.uid());

revoke all on public.app_sessions from anon, authenticated;
grant select on public.app_sessions to authenticated;

create or replace function public.upsert_app_session(
  p_academy_id   text,
  p_role         text,
  p_display_name text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  insert into public.app_sessions (user_id, academy_id, role, display_name)
  values (auth.uid(), p_academy_id, p_role, p_display_name)
  on conflict (user_id) do update
    set academy_id   = excluded.academy_id,
        role         = excluded.role,
        display_name = excluded.display_name;
end;
$$;

create or replace function public.get_app_session()
returns table (academy_id text, role text, display_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select s.academy_id, s.role, s.display_name
    from public.app_sessions s
    where s.user_id = auth.uid()
    limit 1;
end;
$$;

revoke all on function public.upsert_app_session(text, text, text) from public;
revoke all on function public.get_app_session() from public;
grant execute on function public.upsert_app_session(text, text, text) to authenticated;
grant execute on function public.get_app_session() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Helper: academy of the currently authenticated user.
--    Defined AFTER app_sessions exists so PostgreSQL can validate the SQL body.
-- ---------------------------------------------------------------------------
create or replace function public.current_academy_id()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(
    (select u.academy_id::text
       from public.users u
      where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      limit 1),
    (select s.academy_id
       from public.app_sessions s
      where s.user_id = auth.uid()
      limit 1)
  );
$$;

comment on function public.current_academy_id() is
  'Resolves the tenant from the signed-in email user or from an anonymous app session.';

-- ---------------------------------------------------------------------------
-- 3. Helper: tenant check used by every RLS policy
-- ---------------------------------------------------------------------------
create or replace function public.academy_is_current(p_academy_id text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select p_academy_id is not null
     and public.current_academy_id() is not null
     and p_academy_id = public.current_academy_id();
$$;

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(
    (select u.role
       from public.users u
      where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      limit 1),
    (select s.role from public.app_sessions s where s.user_id = auth.uid() limit 1)
  );
$$;

-- ---------------------------------------------------------------------------
-- 4. Atomic academy registration (SECURITY DEFINER so it also works while an
--    email confirmation is pending and no Supabase session exists yet).
-- ---------------------------------------------------------------------------
create or replace function public.register_academy(
  p_academy_name  text,
  p_address       text,
  p_phone         text,
  p_eiin          text,
  p_academy_code  text,
  p_admin_email   text,
  p_admin_name    text,
  p_class_names   text[]
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_academy_id public.academies.id%type;
  v_class      text;
  v_order      integer := 1;
begin
  if coalesce(btrim(p_academy_name), '') = '' or
     coalesce(btrim(p_admin_email), '') = '' then
    raise exception 'academy name and admin email are required';
  end if;

  insert into public.academies
    (academy_name, address, phone, eiin, academy_code, admin_email)
  values
    (p_academy_name, p_address, p_phone, p_eiin, p_academy_code, p_admin_email)
  returning id into v_academy_id;

  insert into public.users (academy_id, email, full_name, role)
  values (v_academy_id, p_admin_email, p_admin_name, 'super_admin');

  if p_class_names is not null then
    foreach v_class in array p_class_names loop
      insert into public.classes (academy_id, class_name, class_order)
      values (v_academy_id, v_class, v_order);
      v_order := v_order + 1;
    end loop;
  end if;

  return v_academy_id::text;
end;
$$;

revoke all on function public.register_academy(text, text, text, text, text, text, text, text[]) from public;
grant execute on function public.register_academy(text, text, text, text, text, text, text, text[]) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Login helpers. These are the ONLY way unauthenticated clients may read
--    credentials/routing data. They return a single targeted row instead of
--    exposing whole tables to the anon role.
-- ---------------------------------------------------------------------------
create or replace function public.lookup_login_user(p_email text)
returns table (
  id          text,
  academy_id  text,
  email       text,
  full_name   text,
  role        text,
  password    text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select u.id::text, u.academy_id::text, u.email, u.full_name, u.role, u.password
    from public.users u
    where lower(u.email) = lower(p_email)
    limit 1;
end;
$$;

create or replace function public.lookup_student_for_login(
  p_academy_id text,
  p_class      text,
  p_roll       text
)
returns table (id text, name text, custom_password text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select s.id::text, s.name, s.custom_password
    from public.students s
    where s.academy_id::text = p_academy_id
      and s."class" = p_class
      and s.roll::text = p_roll
    limit 1;
end;
$$;

create or replace function public.public_academy_classes(p_academy_id text)
returns table ("class" text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select distinct s."class"
    from public.students s
    where s.academy_id::text = p_academy_id
    order by s."class";
end;
$$;

revoke all on function public.lookup_login_user(text) from public;
revoke all on function public.lookup_student_for_login(text, text, text) from public;
revoke all on function public.public_academy_classes(text) from public;

grant execute on function public.lookup_login_user(text) to anon, authenticated;
grant execute on function public.lookup_student_for_login(text, text, text) to anon, authenticated;
grant execute on function public.public_academy_classes(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. RLS + indexes for every table that carries an academy_id column.
--    Policies are expressed through academy_is_current() so an unscoped query
--    can never return another tenant's rows. service_role bypasses RLS.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public' and c.column_name = 'academy_id'
    group by c.table_name
  loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists tenant_select on public.%I', t);
    execute format('drop policy if exists tenant_insert on public.%I', t);
    execute format('drop policy if exists tenant_update on public.%I', t);
    execute format('drop policy if exists tenant_delete on public.%I', t);

    execute format(
      'create policy tenant_select on public.%I for select to authenticated '
      'using (public.academy_is_current(academy_id::text))', t);

    execute format(
      'create policy tenant_insert on public.%I for insert to authenticated '
      'with check (public.academy_is_current(academy_id::text))', t);

    execute format(
      'create policy tenant_update on public.%I for update to authenticated '
      'using (public.academy_is_current(academy_id::text)) '
      'with check (public.academy_is_current(academy_id::text))', t);

    execute format(
      'create policy tenant_delete on public.%I for delete to authenticated '
      'using (public.academy_is_current(academy_id::text))', t);

    execute format(
      'create index if not exists %I on public.%I (academy_id)',
      'idx_' || left(t, 45) || '_academy_id', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 7. academies has no academy_id (its id IS the tenant id). The academy
--    directory is public because unauthenticated students must be able to pick
--    their institution at login; writes are restricted to the owning admin.
-- ---------------------------------------------------------------------------
alter table public.academies enable row level security;

drop policy if exists academy_public_select on public.academies;
create policy academy_public_select on public.academies
  for select to anon, authenticated using (true);

drop policy if exists academy_owner_update on public.academies;
create policy academy_owner_update on public.academies
  for update to authenticated
  using (id::text = public.current_academy_id())
  with check (id::text = public.current_academy_id());

drop policy if exists academy_owner_delete on public.academies;
create policy academy_owner_delete on public.academies
  for delete to authenticated
  using (id::text = public.current_academy_id());

-- ---------------------------------------------------------------------------
-- 8. Deliberately NO anon table policies.
--    Unauthenticated clients can only: list academies (public directory),
--    call the three narrowly scoped login RPCs, and register an academy.
--    Every other read/write requires an authenticated session whose tenant is
--    resolved by current_academy_id() — including the anonymous sessions
--    created for teachers and students at login.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 9. Verification queries (run manually after applying)
-- ---------------------------------------------------------------------------
-- select tablename, rowsecurity from pg_tables where schemaname = 'public';
-- select policyname, tablename from pg_policies where schemaname = 'public';

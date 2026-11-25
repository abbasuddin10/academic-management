-- ============================================================================
-- 0002 Notification read tracking (per-recipient unread badge)
-- Apply with:  supabase db push   (or paste into the Supabase SQL editor)
--
-- Depends on 0001_rls_and_schema_hardening.sql for:
--   * public.current_academy_id()
--   * public.academy_is_current(text)
--   * public.app_sessions (anonymous teacher/student sessions)
--
-- Design notes:
--   * Read state is stored PER RECIPIENT, never on `notices` itself. One notice
--     addressed to a whole academy can therefore be read by one user and still
--     remain unread for everybody else.
--   * The same `reader_key` the Flutter app sends is resolved by the database
--     through current_reader_key(), so RLS rejects forged keys:
--       - admin (email session)      -> auth.uid()
--       - teacher (anonymous session) -> teacher:<id>  (stored in app_sessions)
--       - student (anonymous session) -> student:<id>  (stored in app_sessions)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Teach the database which reader key belongs to the current session.
--    Teacher/student logins persist it through set_app_session_reader_key().
-- ---------------------------------------------------------------------------
alter table public.app_sessions add column if not exists reader_key text;

create or replace function public.current_reader_key()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select case
    -- Email/password admins are identified directly by their auth uid.
    when nullif(coalesce(auth.jwt() ->> 'email', ''), '') is not null
      then auth.uid()::text
    -- Anonymous teacher/student sessions carry their stable reader key here.
    else coalesce(
      (select s.reader_key
         from public.app_sessions s
        where s.user_id = auth.uid()
        limit 1),
      auth.uid()::text
    )
  end;
$$;

comment on function public.current_reader_key() is
  'Stable per-recipient key used by notice_reads: auth.uid() for admins, teacher:<id>/student:<id> for anonymous sessions.';

create or replace function public.set_app_session_reader_key(p_reader_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if coalesce(btrim(p_reader_key), '') = '' then
    raise exception 'reader key is required';
  end if;

  update public.app_sessions
     set reader_key = p_reader_key
   where user_id = auth.uid();
end;
$$;

revoke all on function public.current_reader_key() from public;
revoke all on function public.set_app_session_reader_key(text) from public;
grant execute on function public.current_reader_key() to authenticated;
grant execute on function public.set_app_session_reader_key(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Per-user read records.
--    NOTE: if your pre-existing `notices.id` column is TEXT rather than UUID,
--    change notice_id below to TEXT before applying this migration.
-- ---------------------------------------------------------------------------
create table if not exists public.notice_reads (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references public.academies(id) on delete cascade,
  notice_id   uuid not null references public.notices(id) on delete cascade,
  reader_key  text not null,
  read_at     timestamptz not null default now(),
  constraint notice_reads_unique unique (notice_id, reader_key)
);

comment on table public.notice_reads is
  'One row per (notice, recipient). Deleting a notice or academy cascades automatically.';

alter table public.notice_reads enable row level security;

-- A recipient may only see their own read markers, inside their own tenant.
drop policy if exists notice_reads_select_own on public.notice_reads;
create policy notice_reads_select_own on public.notice_reads
  for select to authenticated
  using (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key()
  );

-- A recipient may only insert their own read markers, inside their own tenant.
drop policy if exists notice_reads_insert_own on public.notice_reads;
create policy notice_reads_insert_own on public.notice_reads
  for insert to authenticated
  with check (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key()
  );

-- Cleanup (e.g. when a reader is removed) is likewise self-scoped.
drop policy if exists notice_reads_delete_own on public.notice_reads;
create policy notice_reads_delete_own on public.notice_reads
  for delete to authenticated
  using (
    public.academy_is_current(academy_id::text)
    and reader_key = public.current_reader_key()
  );

-- No anon access: read markers require an authenticated tenant session.
revoke all on public.notice_reads from anon;
grant select, insert, delete on public.notice_reads to authenticated;

create index if not exists idx_notice_reads_academy_reader
  on public.notice_reads (academy_id, reader_key);
create index if not exists idx_notice_reads_reader_notice
  on public.notice_reads (reader_key, notice_id);

-- ---------------------------------------------------------------------------
-- 3. Realtime: broadcast notice inserts/deletes and read markers so the badge
--    can update live on every open screen without polling.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'notice_reads'
    ) then
      alter publication supabase_realtime add table public.notice_reads;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'notices'
    ) then
      alter publication supabase_realtime add table public.notices;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Verification (run manually after applying)
-- ---------------------------------------------------------------------------
-- select tablename, rowsecurity from pg_tables where tablename = 'notice_reads';
-- select policyname, cmd from pg_policies where tablename = 'notice_reads';
-- select reader_key, current_reader_key() from public.app_sessions limit 1;

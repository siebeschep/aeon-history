-- Aeon schema. Run in Supabase: SQL Editor -> New query -> paste -> Run. Then run seed.sql.

create table public.chapters (
  id text primary key, sort int not null, emoji text, color text,
  name_en text not null, name_nl text not null, range_en text, range_nl text
);

create table public.lessons (
  id text primary key,
  chapter text not null references public.chapters(id) on delete cascade,
  sort int not null,
  en jsonb, nl jsonb,                       -- {w, ti, tx, q, o:[correct, wrong, wrong, wrong], x}
  created_at timestamptz not null default now()
);

create table public.user_roles (
  user_id uuid references auth.users(id) on delete cascade,
  role text not null,
  primary key (user_id, role)
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'admin');
$$;

create table public.progress (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  lesson_id text not null references public.lessons(id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create table public.stats (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  xp int not null default 0, streak int not null default 0,
  last_day date, day date, today_n int not null default 0
);

alter table public.chapters   enable row level security;
alter table public.lessons    enable row level security;
alter table public.user_roles enable row level security;
alter table public.progress   enable row level security;
alter table public.stats      enable row level security;

-- Only logged-in users can read content; only admins change it.
create policy "read chapters" on public.chapters for select to authenticated using (true);
create policy "read lessons"  on public.lessons  for select to authenticated using (true);
create policy "admin writes chapters" on public.chapters for all using (public.is_admin()) with check (public.is_admin());
create policy "admin writes lessons"  on public.lessons  for all using (public.is_admin()) with check (public.is_admin());

-- Roles: users may see their own role; nobody can write roles from the website.
create policy "read own role" on public.user_roles for select using (user_id = auth.uid());

-- Progress and stats: each user only sees and changes their own rows.
create policy "own progress" on public.progress for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own stats"    on public.stats    for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant usage on schema public to anon, authenticated;
grant select on public.chapters, public.lessons to authenticated;
grant insert, update, delete on public.chapters, public.lessons to authenticated;
grant select on public.user_roles to authenticated;
grant select, insert, update, delete on public.progress, public.stats to authenticated;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

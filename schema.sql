-- =====================================================================
-- Aeon – database schema (v2)
-- Idempotent: run it on an empty Supabase project or on top of v1.
-- Supabase: SQL Editor -> New query -> paste -> Run.
-- Afterwards import content.json (Admin -> Import in the website).
-- =====================================================================

-- ---------- content ----------
create table if not exists public.chapters (
  id text primary key, sort int not null, emoji text, color text,
  name_en text not null, name_nl text not null, range_en text, range_nl text
);
alter table public.chapters add column if not exists yr_from double precision;  -- year (negative = BCE / years ago)
alter table public.chapters add column if not exists yr_to double precision;    -- null = today

create table if not exists public.lessons (
  id text primary key,
  chapter text not null references public.chapters(id) on delete cascade,
  sort int not null,
  en jsonb, nl jsonb,                       -- {w: when, ti: title, tx: text}
  created_at timestamptz not null default now()
);
alter table public.lessons add column if not exists yr double precision;
alter table public.lessons add column if not exists emoji text;
alter table public.lessons add column if not exists rarity text not null default 'common';
alter table public.lessons add column if not exists img text;
alter table public.lessons drop constraint if exists lessons_rarity_check;
alter table public.lessons add constraint lessons_rarity_check check (rarity in ('common','rare','epic','legendary'));

-- Questions: the visible part (prompt + options in a shuffled order) ...
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  lesson_id text not null references public.lessons(id) on delete cascade,
  sort int not null default 0,
  type text not null check (type in ('mc','tf','year','order')),
  en jsonb, nl jsonb,                       -- {q, o:[...]}  (tf: {q})
  created_at timestamptz not null default now()
);
create index if not exists questions_lesson_idx on public.questions(lesson_id);

-- ... and the hidden part: only admins and the server-side functions can read it.
create table if not exists public.question_keys (
  question_id uuid primary key references public.questions(id) on delete cascade,
  answer jsonb not null,                    -- mc/year: index, tf: true/false, order: [indexes]
  x_en text, x_nl text                      -- explanation
);

-- ---------- users ----------
create table if not exists public.user_roles (
  user_id uuid references auth.users(id) on delete cascade,
  role text not null,
  primary key (user_id, role)
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'admin');
$$;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (username ~ '^[A-Za-z0-9_]{3,20}$'),
  avatar text not null default '🚀' check (char_length(avatar) between 1 and 8),
  goal int not null default 30 check (goal in (10, 20, 30, 50)),
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_idx on public.profiles (lower(username));

create table if not exists public.progress (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  lesson_id text not null references public.lessons(id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create table if not exists public.stats (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  xp int not null default 0, streak int not null default 0,
  last_day date, day date, today_n int not null default 0
);
alter table public.stats add column if not exists best_streak int not null default 0;
alter table public.stats add column if not exists freezes int not null default 1;
alter table public.stats add column if not exists today_xp int not null default 0;
alter table public.stats add column if not exists week_start date;
alter table public.stats add column if not exists week_xp int not null default 0;

-- Per user and question: how often right/wrong, and when it is due again (spaced repetition).
create table if not exists public.q_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  right_n int not null default 0, wrong_n int not null default 0,
  box int not null default 0, due date not null,
  last_at timestamptz not null default now(), last_ok boolean not null default false,
  xp_day date,
  primary key (user_id, question_id)
);

create table if not exists public.chapter_tests (
  user_id uuid not null references auth.users(id) on delete cascade,
  chapter text not null references public.chapters(id) on delete cascade,
  best int not null default 0, tries int not null default 0, passed_at timestamptz,
  primary key (user_id, chapter)
);

create table if not exists public.follows (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  target_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, target_id),
  check (user_id <> target_id)
);

create table if not exists public.heartbeat (
  id int primary key default 1 check (id = 1),
  at timestamptz not null default now(), n bigint not null default 0
);
insert into public.heartbeat(id) values (1) on conflict do nothing;

-- ---------- row level security ----------
alter table public.chapters      enable row level security;
alter table public.lessons       enable row level security;
alter table public.questions     enable row level security;
alter table public.question_keys enable row level security;
alter table public.user_roles    enable row level security;
alter table public.profiles      enable row level security;
alter table public.progress      enable row level security;
alter table public.stats         enable row level security;
alter table public.q_state       enable row level security;
alter table public.chapter_tests enable row level security;
alter table public.follows       enable row level security;
alter table public.heartbeat     enable row level security;

-- Content: every logged-in user reads, only admins write. Answers: admins only.
drop policy if exists "read chapters" on public.chapters;
create policy "read chapters" on public.chapters for select to authenticated using (true);
drop policy if exists "admin writes chapters" on public.chapters;
create policy "admin writes chapters" on public.chapters for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "read lessons" on public.lessons;
create policy "read lessons" on public.lessons for select to authenticated using (true);
drop policy if exists "admin writes lessons" on public.lessons;
create policy "admin writes lessons" on public.lessons for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "read questions" on public.questions;
create policy "read questions" on public.questions for select to authenticated using (true);
drop policy if exists "admin writes questions" on public.questions;
create policy "admin writes questions" on public.questions for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin keys" on public.question_keys;
create policy "admin keys" on public.question_keys for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Roles: users see their own role; nobody can write roles from the website.
drop policy if exists "read own role" on public.user_roles;
create policy "read own role" on public.user_roles for select to authenticated using (user_id = (select auth.uid()));

-- Profiles: names and avatars are visible to logged-in users (leaderboard); you only change your own.
drop policy if exists "read profiles" on public.profiles;
create policy "read profiles" on public.profiles for select to authenticated using (true);
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Progress, points and review state: read your own rows. Writing happens only
-- through the server-side functions below, so points cannot be faked.
drop policy if exists "own progress" on public.progress;
drop policy if exists "read own progress" on public.progress;
create policy "read own progress" on public.progress for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "own stats" on public.stats;
drop policy if exists "read own stats" on public.stats;
create policy "read own stats" on public.stats for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "read own q_state" on public.q_state;
create policy "read own q_state" on public.q_state for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "read own tests" on public.chapter_tests;
create policy "read own tests" on public.chapter_tests for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "read own follows" on public.follows;
create policy "read own follows" on public.follows for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "add own follows" on public.follows;
create policy "add own follows" on public.follows for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "remove own follows" on public.follows;
create policy "remove own follows" on public.follows for delete to authenticated using (user_id = (select auth.uid()));

revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.chapters, public.lessons, public.questions, public.question_keys, public.user_roles, public.profiles,
  public.progress, public.stats, public.q_state, public.chapter_tests, public.follows to authenticated;
grant insert, update, delete on public.chapters, public.lessons, public.questions, public.question_keys to authenticated;
grant update (username, avatar, goal) on public.profiles to authenticated;
grant insert, delete on public.follows to authenticated;

-- ---------- helpers ----------
create or replace function public.today() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'Europe/Brussels')::date;
$$;

-- Adds points and keeps day, week and streak up to date. Internal.
create or replace function public._award(p_uid uuid, p_xp int, p_lesson boolean) returns public.stats
language plpgsql security definer set search_path = public as $$
declare
  v_s public.stats; v_d date := public.today();
  v_w date := date_trunc('week', public.today()::timestamp)::date; v_gap int;
begin
  insert into public.stats(user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into v_s from public.stats where user_id = p_uid for update;
  if v_s.day is distinct from v_d then v_s.day := v_d; v_s.today_xp := 0; v_s.today_n := 0; end if;
  if v_s.week_start is distinct from v_w then v_s.week_start := v_w; v_s.week_xp := 0; end if;
  if (p_xp > 0 or p_lesson) and v_s.last_day is distinct from v_d then
    v_gap := v_d - v_s.last_day - 1;                       -- missed days in between
    if v_gap is null then v_s.streak := 1;
    elsif v_gap <= 0 then v_s.streak := v_s.streak + 1;
    elsif v_gap <= v_s.freezes then v_s.freezes := v_s.freezes - v_gap; v_s.streak := v_s.streak + 1;
    else v_s.streak := 1;
    end if;
    v_s.last_day := v_d;
    if v_s.streak % 7 = 0 and v_s.freezes < 2 then v_s.freezes := v_s.freezes + 1; end if;
    v_s.best_streak := greatest(v_s.best_streak, v_s.streak);
  end if;
  v_s.xp := v_s.xp + p_xp; v_s.today_xp := v_s.today_xp + p_xp; v_s.week_xp := v_s.week_xp + p_xp;
  if p_lesson then v_s.today_n := v_s.today_n + 1; end if;
  update public.stats set xp = v_s.xp, streak = v_s.streak, best_streak = v_s.best_streak, last_day = v_s.last_day,
    freezes = v_s.freezes, day = v_s.day, today_xp = v_s.today_xp, today_n = v_s.today_n,
    week_start = v_s.week_start, week_xp = v_s.week_xp
  where user_id = p_uid;
  return v_s;
end $$;

-- ---------- profiles ----------
create or replace function public._new_profile(p_uid uuid, p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare v_base text; v_name text; v_i int := 0;
begin
  if exists (select 1 from public.profiles where user_id = p_uid) then return; end if;
  v_base := left(regexp_replace(coalesce(p_name, ''), '[^A-Za-z0-9_]', '', 'g'), 16);
  if length(v_base) < 3 then
    v_base := 'Explorer'; v_name := v_base || (1000 + floor(random() * 9000))::int;
  else v_name := v_base;
  end if;
  while v_i < 30 and exists (select 1 from public.profiles where lower(username) = lower(v_name)) loop
    v_i := v_i + 1; v_name := v_base || (1000 + floor(random() * 9000))::int;
  end loop;
  insert into public.profiles(user_id, username) values (p_uid, v_name) on conflict (user_id) do nothing;
  insert into public.stats(user_id) values (p_uid) on conflict (user_id) do nothing;
end $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform public._new_profile(new.id, new.raw_user_meta_data->>'username');
  exception when others then null;   -- never block a sign-up; ensure_profile() repairs it later
  end;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.ensure_profile() returns public.profiles
language plpgsql security definer set search_path = public as $$
declare v_p public.profiles;
begin
  if auth.uid() is null then raise exception 'not logged in'; end if;
  perform public._new_profile(auth.uid(), null);
  select * into v_p from public.profiles where user_id = auth.uid();
  return v_p;
end $$;

do $$ declare r record; begin
  for r in select u.id from auth.users u where not exists (select 1 from public.profiles p where p.user_id = u.id) loop
    perform public._new_profile(r.id, null);
  end loop;
end $$;

-- ---------- learning ----------
-- Checks an answer on the server, updates the review state and awards points.
create or replace function public.answer_question(p_question uuid, p_answer jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_q public.questions; v_k public.question_keys; v_st public.q_state; v_s public.stats;
  v_ok boolean; v_gain int := 0; v_d date := public.today(); v_box int; v_due date;
  v_first boolean := false; v_done boolean := false;
  v_iv int[] := array[1, 3, 7, 16, 35];                   -- days until the next review, per box
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select * into v_q from public.questions where id = p_question;
  if not found then raise exception 'unknown question'; end if;
  select * into v_k from public.question_keys where question_id = p_question;
  if not found then raise exception 'question has no answer key'; end if;
  v_ok := coalesce(p_answer = v_k.answer, false);

  select * into v_st from public.q_state where user_id = v_uid and question_id = p_question for update;
  if not found then
    if v_ok then v_gain := 10; v_box := 2; v_due := v_d + v_iv[2]; v_first := true;
    else v_box := 0; v_due := v_d;
    end if;
    insert into public.q_state(user_id, question_id, right_n, wrong_n, box, due, last_ok, xp_day)
    values (v_uid, p_question, v_ok::int, (not v_ok)::int, v_box, v_due, v_ok, case when v_ok then v_d end);
  elsif v_ok then
    if v_st.right_n = 0 then
      v_gain := 5; v_first := true; v_box := 1; v_due := v_d + v_iv[1];
    elsif v_st.due <= v_d then
      v_box := least(v_st.box + 1, 5); v_due := v_d + v_iv[v_box];
      if v_st.xp_day is distinct from v_d then v_gain := 2; end if;   -- review points: once a day per question
    else
      v_box := v_st.box; v_due := v_st.due;                           -- not due yet: nothing changes
    end if;
    update public.q_state set right_n = right_n + 1, box = v_box, due = v_due, last_at = now(), last_ok = true,
      xp_day = case when v_gain > 0 then v_d else xp_day end
    where user_id = v_uid and question_id = p_question;
  else
    update public.q_state set wrong_n = wrong_n + 1, box = 0, due = v_d, last_at = now(), last_ok = false
    where user_id = v_uid and question_id = p_question;
  end if;

  -- lesson finished: every question of the lesson answered right at least once
  if v_first
     and not exists (select 1 from public.progress where user_id = v_uid and lesson_id = v_q.lesson_id)
     and not exists (select 1 from public.questions q
                     left join public.q_state t on t.question_id = q.id and t.user_id = v_uid
                     where q.lesson_id = v_q.lesson_id and coalesce(t.right_n, 0) = 0) then
    insert into public.progress(user_id, lesson_id) values (v_uid, v_q.lesson_id) on conflict do nothing;
    v_done := true; v_gain := v_gain + 5;
  end if;

  v_s := public._award(v_uid, v_gain, v_done);
  return jsonb_build_object('ok', v_ok, 'answer', v_k.answer, 'x_en', v_k.x_en, 'x_nl', v_k.x_nl,
    'gain', v_gain, 'lesson_done', v_done, 'stats', to_jsonb(v_s),
    'state', (select to_jsonb(t) from public.q_state t where t.user_id = v_uid and t.question_id = p_question));
end $$;

-- A lesson without questions is finished by reading it.
create or replace function public.complete_lesson(p_lesson text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_n int; v_s public.stats;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  if not exists (select 1 from public.lessons where id = p_lesson) then raise exception 'unknown lesson'; end if;
  if exists (select 1 from public.questions where lesson_id = p_lesson) then raise exception 'lesson has questions'; end if;
  insert into public.progress(user_id, lesson_id) values (v_uid, p_lesson) on conflict do nothing;
  get diagnostics v_n = row_count;
  v_s := public._award(v_uid, case when v_n > 0 then 5 else 0 end, v_n > 0);
  return jsonb_build_object('gain', case when v_n > 0 then 5 else 0 end, 'lesson_done', v_n > 0, 'stats', to_jsonb(v_s));
end $$;

-- Chapter test: the questions must just have been answered through answer_question().
create or replace function public.finish_test(p_chapter text, p_questions uuid[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_total int; v_n int; v_good int; v_pct int;
  v_prev timestamptz; v_gain int := 0; v_s public.stats;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select count(*) into v_total from public.questions q join public.lessons l on l.id = q.lesson_id where l.chapter = p_chapter;
  select count(*), count(*) filter (where t.last_ok and t.last_at > now() - interval '60 minutes') into v_n, v_good
  from (select distinct x from unnest(p_questions) x) u
  join public.questions q on q.id = u.x
  join public.lessons l on l.id = q.lesson_id and l.chapter = p_chapter
  left join public.q_state t on t.question_id = q.id and t.user_id = v_uid;
  if v_total = 0 or v_n < least(8, v_total) then raise exception 'incomplete test'; end if;
  v_pct := round(100.0 * v_good / v_n);
  select passed_at into v_prev from public.chapter_tests where user_id = v_uid and chapter = p_chapter;
  if v_pct >= 75 and v_prev is null then v_gain := 20; end if;
  insert into public.chapter_tests(user_id, chapter, best, tries, passed_at)
  values (v_uid, p_chapter, v_pct, 1, case when v_pct >= 75 then now() end)
  on conflict (user_id, chapter) do update set
    best = greatest(public.chapter_tests.best, excluded.best),
    tries = public.chapter_tests.tries + 1,
    passed_at = coalesce(public.chapter_tests.passed_at, excluded.passed_at);
  v_s := public._award(v_uid, v_gain, false);
  return jsonb_build_object('pct', v_pct, 'passed', v_pct >= 75, 'gain', v_gain, 'stats', to_jsonb(v_s),
    'test', (select to_jsonb(c) from public.chapter_tests c where c.user_id = v_uid and c.chapter = p_chapter));
end $$;

-- ---------- leaderboard and friends ----------
create or replace function public.leaderboard(p_period text, p_friends boolean)
returns table (user_id uuid, username text, avatar text, xp int, total_xp int, streak int, me boolean)
language sql stable security definer set search_path = public as $$
  select p.user_id, p.username, p.avatar,
    case when p_period = 'week'
      then case when s.week_start = date_trunc('week', public.today()::timestamp)::date then s.week_xp else 0 end
      else coalesce(s.xp, 0) end,
    coalesce(s.xp, 0),
    case when s.last_day >= public.today() - 1 then s.streak else 0 end,
    p.user_id = auth.uid()
  from public.profiles p left join public.stats s on s.user_id = p.user_id
  where auth.uid() is not null
    and (not coalesce(p_friends, false) or p.user_id = auth.uid()
         or p.user_id in (select f.target_id from public.follows f where f.user_id = auth.uid()))
  order by 4 desc, 5 desc, p.username
  limit 50;
$$;

create or replace function public.follow_user(p_username text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_t public.profiles;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select * into v_t from public.profiles where lower(username) = lower(trim(coalesce(p_username, '')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'notfound'); end if;
  if v_t.user_id = v_uid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  insert into public.follows(user_id, target_id) values (v_uid, v_t.user_id) on conflict do nothing;
  return jsonb_build_object('ok', true, 'user_id', v_t.user_id, 'username', v_t.username);
end $$;

-- ---------- admin: saving, importing and exporting content ----------
-- A lesson in "canonical" form:
-- {id?, chapter, sort?, yr, emoji, rarity, img, en:{w,ti,tx}, nl:{w,ti,tx},
--  questions:[{id?, type:'mc'|'year', en:{q, o:[correct, wrong, ...], x}, nl:{...}},
--             {type:'tf', answer:true|false, en:{q,x}, nl:{q,x}},
--             {type:'order', en:{q, o:[items in the right order], x}, nl:{...}}]}
-- The options are shuffled on save; the key goes to question_keys.
create or replace function public._upsert_lesson(p jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_id text := nullif(p->>'id', ''); v_qj jsonb; v_qid uuid; v_keep uuid[] := '{}'; v_i int := 0;
  v_n int; v_perm int[]; v_en jsonb; v_nl jsonb; v_ans jsonb; v_typ text; v_len jsonb; v_lnl jsonb;
begin
  if v_id is null then v_id := 'l' || substr(md5(random()::text || clock_timestamp()::text), 1, 10); end if;
  if not exists (select 1 from public.chapters where id = p->>'chapter') then
    raise exception 'unknown chapter: %', coalesce(p->>'chapter', '(none)');
  end if;
  v_len := case when coalesce(p->'en'->>'ti', '') = '' then null
           else jsonb_build_object('w', coalesce(p->'en'->>'w', ''), 'ti', p->'en'->>'ti', 'tx', coalesce(p->'en'->>'tx', '')) end;
  v_lnl := case when coalesce(p->'nl'->>'ti', '') = '' then null
           else jsonb_build_object('w', coalesce(p->'nl'->>'w', ''), 'ti', p->'nl'->>'ti', 'tx', coalesce(p->'nl'->>'tx', '')) end;
  if v_len is null and v_lnl is null then raise exception 'a lesson needs a title in at least one language'; end if;

  insert into public.lessons(id, chapter, sort, en, nl, yr, emoji, rarity, img)
  values (v_id, p->>'chapter',
    coalesce((p->>'sort')::int, (select coalesce(max(sort), -1) + 1 from public.lessons)),
    v_len, v_lnl, (p->>'yr')::double precision, nullif(p->>'emoji', ''),
    coalesce(nullif(p->>'rarity', ''), 'common'), nullif(p->>'img', ''))
  on conflict (id) do update set chapter = excluded.chapter,
    sort = case when p ? 'sort' and p->>'sort' is not null then excluded.sort else public.lessons.sort end,
    en = excluded.en, nl = excluded.nl, yr = excluded.yr, emoji = excluded.emoji, rarity = excluded.rarity, img = excluded.img;

  for v_qj in select * from jsonb_array_elements(coalesce(p->'questions', '[]'::jsonb)) loop
    v_typ := coalesce(nullif(v_qj->>'type', ''), 'mc');
    if v_typ not in ('mc', 'tf', 'year', 'order') then raise exception 'unknown question type: %', v_typ; end if;
    v_en := case when coalesce(v_qj->'en'->>'q', '') = '' then null else v_qj->'en' end;
    v_nl := case when coalesce(v_qj->'nl'->>'q', '') = '' then null else v_qj->'nl' end;
    if v_en is null and v_nl is null then continue; end if;

    if v_typ = 'tf' then
      v_ans := to_jsonb(coalesce((v_qj->>'answer')::boolean, true));
      if v_en is not null then v_en := jsonb_build_object('q', v_en->>'q'); end if;
      if v_nl is not null then v_nl := jsonb_build_object('q', v_nl->>'q'); end if;
    else
      v_n := jsonb_array_length(coalesce(v_en->'o', v_nl->'o', '[]'::jsonb));
      if v_n < 2 then raise exception 'a question needs at least 2 options: %', coalesce(v_en->>'q', v_nl->>'q'); end if;
      if (v_en is not null and jsonb_array_length(coalesce(v_en->'o', '[]'::jsonb)) <> v_n)
         or (v_nl is not null and jsonb_array_length(coalesce(v_nl->'o', '[]'::jsonb)) <> v_n) then
        raise exception 'EN and NL need the same number of options: %', coalesce(v_en->>'q', v_nl->>'q');
      end if;
      select array_agg(g order by random()) into v_perm from generate_series(0, v_n - 1) g;
      -- stored[j] = given[perm[j]]
      if v_en is not null then
        v_en := jsonb_build_object('q', v_en->>'q', 'o',
          (select jsonb_agg(v_en->'o'->v_perm[j] order by j) from generate_subscripts(v_perm, 1) j));
      end if;
      if v_nl is not null then
        v_nl := jsonb_build_object('q', v_nl->>'q', 'o',
          (select jsonb_agg(v_nl->'o'->v_perm[j] order by j) from generate_subscripts(v_perm, 1) j));
      end if;
      if v_typ = 'order' then
        v_ans := (select jsonb_agg(array_position(v_perm, g) - 1 order by g) from generate_series(0, v_n - 1) g);
      else
        v_ans := to_jsonb(array_position(v_perm, 0) - 1);
      end if;
    end if;

    -- keep the question id when possible, so nobody loses review state after an edit
    v_qid := null;
    if coalesce(v_qj->>'id', '') <> '' then
      select id into v_qid from public.questions where id = (v_qj->>'id')::uuid and lesson_id = v_id;
    end if;
    if v_qid is null then
      select id into v_qid from public.questions where lesson_id = v_id and sort = v_i and not (id = any(v_keep));
    end if;
    if v_qid is null then
      insert into public.questions(lesson_id, sort, type, en, nl) values (v_id, v_i, v_typ, v_en, v_nl) returning id into v_qid;
    else
      update public.questions set sort = v_i, type = v_typ, en = v_en, nl = v_nl where id = v_qid;
    end if;
    insert into public.question_keys(question_id, answer, x_en, x_nl)
    values (v_qid, v_ans, nullif(v_qj->'en'->>'x', ''), nullif(v_qj->'nl'->>'x', ''))
    on conflict (question_id) do update set answer = excluded.answer, x_en = excluded.x_en, x_nl = excluded.x_nl;
    v_keep := v_keep || v_qid; v_i := v_i + 1;
  end loop;
  delete from public.questions where lesson_id = v_id and not (id = any(v_keep));
  return v_id;
end $$;

-- p = {chapters:[...], lessons:[...]} or just an array of lessons.
create or replace function public._import(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_c jsonb; v_l jsonb; v_nc int := 0; v_nl int := 0; v_arr jsonb;
begin
  if jsonb_typeof(p) = 'array' then v_arr := p;
  else
    for v_c in select * from jsonb_array_elements(coalesce(p->'chapters', '[]'::jsonb)) loop
      if coalesce(v_c->>'id', '') = '' then raise exception 'a chapter needs an id'; end if;
      insert into public.chapters(id, sort, emoji, color, name_en, name_nl, range_en, range_nl, yr_from, yr_to)
      values (v_c->>'id',
        coalesce((v_c->>'sort')::int, (select coalesce(max(sort), -1) + 1 from public.chapters)),
        v_c->>'emoji', coalesce(nullif(v_c->>'color', ''), '#1cb0f6'),
        coalesce(nullif(v_c->>'name_en', ''), v_c->>'name_nl', v_c->>'id'),
        coalesce(nullif(v_c->>'name_nl', ''), v_c->>'name_en', v_c->>'id'),
        v_c->>'range_en', v_c->>'range_nl', (v_c->>'yr_from')::double precision, (v_c->>'yr_to')::double precision)
      on conflict (id) do update set
        sort = case when v_c->>'sort' is not null then excluded.sort else public.chapters.sort end,
        emoji = excluded.emoji, color = excluded.color, name_en = excluded.name_en, name_nl = excluded.name_nl,
        range_en = excluded.range_en, range_nl = excluded.range_nl, yr_from = excluded.yr_from, yr_to = excluded.yr_to;
      v_nc := v_nc + 1;
    end loop;
    v_arr := coalesce(p->'lessons', '[]'::jsonb);
  end if;
  for v_l in select * from jsonb_array_elements(v_arr) loop
    perform public._upsert_lesson(v_l); v_nl := v_nl + 1;
  end loop;
  return jsonb_build_object('chapters', v_nc, 'lessons', v_nl);
end $$;

create or replace function public.save_lesson(p jsonb) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return public._upsert_lesson(p);
end $$;

create or replace function public.import_content(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return public._import(p);
end $$;

-- Options back in canonical order (correct answer first / right order).
create or replace function public._canon_o(p_type text, p_o jsonb, p_answer jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select case
    when p_o is null or p_type = 'tf' then null
    when p_type = 'order' then
      (select jsonb_agg(p_o->(a.v::int) order by a.ord) from jsonb_array_elements_text(p_answer) with ordinality a(v, ord))
    else
      (select jsonb_agg(e.v order by (e.ord - 1 = (p_answer #>> '{}')::int) desc, e.ord)
       from jsonb_array_elements(p_o) with ordinality e(v, ord))
  end;
$$;

create or replace function public.export_content() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return jsonb_build_object(
    'chapters', (select coalesce(jsonb_agg(to_jsonb(c) order by c.sort), '[]'::jsonb) from public.chapters c),
    'lessons', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id, 'chapter', l.chapter, 'sort', l.sort, 'yr', l.yr, 'emoji', l.emoji, 'rarity', l.rarity, 'img', l.img,
        'en', l.en, 'nl', l.nl,
        'questions', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
            'id', q.id, 'type', q.type,
            'answer', case when q.type = 'tf' then k.answer end,
            'en', case when q.en is null then null else jsonb_strip_nulls(jsonb_build_object(
                    'q', q.en->>'q', 'o', public._canon_o(q.type, q.en->'o', k.answer), 'x', k.x_en)) end,
            'nl', case when q.nl is null then null else jsonb_strip_nulls(jsonb_build_object(
                    'q', q.nl->>'q', 'o', public._canon_o(q.type, q.nl->'o', k.answer), 'x', k.x_nl)) end
          )) order by q.sort), '[]'::jsonb)
          from public.questions q join public.question_keys k on k.question_id = q.id where q.lesson_id = l.id)
      ) order by l.sort), '[]'::jsonb) from public.lessons l));
end $$;

create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'active7', (select count(*) from public.stats where last_day >= public.today() - 6),
    'lessons_done', (select count(*) from public.progress),
    'answers', (select coalesce(sum(right_n + wrong_n), 0) from public.q_state),
    'tests_passed', (select count(*) from public.chapter_tests where passed_at is not null),
    'hardest', (select coalesce(jsonb_agg(to_jsonb(h)), '[]'::jsonb) from (
        select q.lesson_id, q.en->>'q' as q_en, q.nl->>'q' as q_nl,
               sum(s.right_n)::int as right_n, sum(s.wrong_n)::int as wrong_n
        from public.q_state s join public.questions q on q.id = s.question_id
        group by q.id having sum(s.wrong_n) > 0
        order by sum(s.wrong_n)::float / sum(s.right_n + s.wrong_n) desc, sum(s.wrong_n) desc
        limit 10) h));
end $$;

-- ---------- keep-alive (called once a day by a GitHub Action) ----------
create or replace function public.ping() returns timestamptz
language sql security definer set search_path = public as $$
  update public.heartbeat set at = now(), n = n + 1 where id = 1 returning at;
$$;

-- ---------- who may call what ----------
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.is_admin(), public.ensure_profile(), public.answer_question(uuid, jsonb),
  public.complete_lesson(text), public.finish_test(text, uuid[]), public.leaderboard(text, boolean),
  public.follow_user(text), public.save_lesson(jsonb), public.import_content(jsonb), public.export_content(),
  public.admin_stats() to authenticated;
grant execute on function public.ping() to anon, authenticated;

-- ---------- images for lessons (admins upload, everyone can view) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('lesson-images', 'lesson-images', true, 2097152, array['image/png', 'image/jpeg', 'image/webp', 'image/gif'])
on conflict (id) do nothing;
drop policy if exists "admin adds lesson images" on storage.objects;
create policy "admin adds lesson images" on storage.objects for insert to authenticated
  with check (bucket_id = 'lesson-images' and public.is_admin());
drop policy if exists "admin removes lesson images" on storage.objects;
create policy "admin removes lesson images" on storage.objects for delete to authenticated
  using (bucket_id = 'lesson-images' and public.is_admin());

-- Make yourself admin (once, replace the e-mail address):
-- insert into public.user_roles(user_id, role) select id, 'admin' from auth.users where email = 'you@example.com';

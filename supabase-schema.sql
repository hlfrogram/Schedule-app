create extension if not exists pgcrypto;

create table boards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '내 일정 핀보드',
  share_code text not null unique,
  invite_code text not null unique,
  created_at timestamptz not null default now()
);

create table events (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references boards(id) on delete cascade,
  event_date date not null,
  title text,
  time text,
  location text,
  memo text,
  checklist jsonb not null default '[]',
  docs jsonb not null default '[]',
  photos jsonb not null default '[]',
  created_at timestamptz not null default now()
);

create table board_members (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references boards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'editor' check (role in ('owner','editor')),
  created_at timestamptz not null default now(),
  unique(board_id, user_id)
);

alter table boards enable row level security;
alter table events enable row level security;
alter table board_members enable row level security;

create or replace function is_board_member(p_board_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from board_members where board_id = p_board_id and user_id = auth.uid());
$$;

create or replace function is_board_owner(p_board_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from board_members where board_id = p_board_id and user_id = auth.uid() and role = 'owner');
$$;

create policy "boards_select" on boards for select using (owner_id = auth.uid() or is_board_member(id));
create policy "boards_insert" on boards for insert with check (owner_id = auth.uid());
create policy "boards_update" on boards for update using (is_board_owner(id));
create policy "boards_delete" on boards for delete using (owner_id = auth.uid());

create policy "events_select" on events for select using (is_board_member(board_id));
create policy "events_insert" on events for insert with check (is_board_member(board_id));
create policy "events_update" on events for update using (is_board_member(board_id));
create policy "events_delete" on events for delete using (is_board_member(board_id));

create policy "members_select" on board_members for select using (is_board_member(board_id));
create policy "members_insert" on board_members for insert with check (user_id = auth.uid());
create policy "members_delete" on board_members for delete using (user_id = auth.uid() or is_board_owner(board_id));

create or replace function join_board_by_invite_code(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_board_id uuid;
begin
  select id into v_board_id from boards where invite_code = p_code;
  if v_board_id is null then
    raise exception '잘못된 초대 코드입니다.';
  end if;
  insert into board_members (board_id, user_id, role)
  values (v_board_id, auth.uid(), 'editor')
  on conflict (board_id, user_id) do nothing;
end;
$$;

create or replace function get_board_members(p_board_id uuid)
returns table (user_id uuid, email text, role text)
language sql security definer set search_path = public as $$
  select bm.user_id, u.email::text, bm.role
  from board_members bm
  join auth.users u on u.id = bm.user_id
  where bm.board_id = p_board_id
    and exists (select 1 from board_members me where me.board_id = p_board_id and me.user_id = auth.uid());
$$;

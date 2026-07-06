-- Supabase SQL Editor 에서 그대로 실행하세요.

create extension if not exists pgcrypto;

-- 일정표(보드) 1개 = 편집자(소유자) 1명 + 공유 코드 1개
create table if not exists boards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '내 일정 핀보드',
  share_code text not null unique,
  created_at timestamptz not null default now()
);

-- 일정
create table if not exists events (
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

-- 3단계: 그룹(공동 편집) — 초대 코드로 로그인한 다른 사용자를 "editor"로 board에 합류시킴
alter table boards add column if not exists invite_code text unique;

create table if not exists board_members (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references boards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'editor' check (role in ('owner','editor')),
  created_at timestamptz not null default now(),
  unique(board_id, user_id)
);

-- 마이그레이션: 2단계에서 이미 만들어진 board가 있다면(owner_id만 있고 board_members/invite_code가 없음)
-- 여기서 owner를 board_members에 등록하고 invite_code를 발급해줍니다.
-- (완전히 새 프로젝트라면 boards/board_members가 비어있으니 그냥 아무 일도 하지 않습니다)
insert into board_members (board_id, user_id, role)
select b.id, b.owner_id, 'owner' from boards b
on conflict (board_id, user_id) do nothing;

update boards
set invite_code = substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)
where invite_code is null;

alter table boards enable row level security;
alter table events enable row level security;
alter table board_members enable row level security;

-- 헬퍼 함수: 현재 로그인 사용자가 해당 board의 구성원(owner 또는 editor)인지.
-- security definer로 만들어서 board_members 자체에 대한 RLS를 우회해 순환 참조 없이 체크합니다.
create or replace function is_board_member(bid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from board_members m where m.board_id = bid and m.user_id = auth.uid()
  );
$$;

-- 2단계에서 만든 "owner만 for all" 정책은 이번 단계의 세분화된 정책으로 대체합니다.
-- (이미 2단계 SQL을 실행한 프로젝트에 이번 SQL을 추가로 실행하는 경우를 위한 정리)
drop policy if exists "owner manage own boards" on boards;
drop policy if exists "owner manage own events" on events;

-- 헬퍼 함수: 현재 로그인 사용자가 해당 board의 owner인지.
-- (board_members 정책 안에서 boards를 직접 서브쿼리하면 boards의 SELECT RLS에 다시 걸려
--  "방금 만든 board라 아직 board_members에 owner가 없는" 시점엔 통과하지 못하는 문제가 생깁니다.
--  security definer로 RLS를 우회해 이 순환 문제를 없앱니다.)
create or replace function is_board_owner(bid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(select 1 from boards b where b.id = bid and b.owner_id = auth.uid());
$$;

-- ---- boards ----
drop policy if exists "members can view their boards" on boards;
drop policy if exists "user can create own board" on boards;
drop policy if exists "owner can update own board" on boards;
drop policy if exists "owner can delete own board" on boards;

-- 구성원(owner+editor)은 board를 조회 가능
create policy "members can view their boards" on boards
  for select
  using (is_board_member(id));

-- board 생성은 본인을 owner로 하는 경우만
create policy "user can create own board" on boards
  for insert
  with check (owner_id = auth.uid());

-- board 수정/삭제(제목, 공유코드/초대코드 재발급 등)는 owner만
create policy "owner can update own board" on boards
  for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "owner can delete own board" on boards
  for delete
  using (owner_id = auth.uid());

-- ---- events ----
drop policy if exists "members manage board events" on events;

-- board 구성원(owner+editor)이면 누구나 조회/생성/수정/삭제 가능
create policy "members manage board events" on events
  for all
  using (is_board_member(board_id))
  with check (is_board_member(board_id));

-- ---- board_members ----
drop policy if exists "members can view board_members" on board_members;
drop policy if exists "owner can register self as owner member" on board_members;
drop policy if exists "leave or owner can remove member" on board_members;

-- 같은 board 구성원끼리는 서로 멤버 목록을 볼 수 있음
create policy "members can view board_members" on board_members
  for select
  using (is_board_member(board_id));

-- owner가 board 생성 직후 "자기 자신을 owner로" 등록하는 것만 클라이언트에서 허용
-- (다른 사람을 초대해서 합류시키는 것은 join_board_by_invite_code() RPC로만 가능)
create policy "owner can register self as owner member" on board_members
  for insert
  with check (
    user_id = auth.uid()
    and role = 'owner'
    and is_board_owner(board_id)
  );

-- 삭제: 본인이 스스로 그룹을 나가거나(leave), owner가 다른 멤버를 내보낼 수 있음(kick)
create policy "leave or owner can remove member" on board_members
  for delete
  using (
    user_id = auth.uid()
    or is_board_owner(board_members.board_id)
  );

-- 주의: anon(비로그인) 역할에는 위 어떤 테이블에도 정책을 부여하지 않습니다.
-- "코드로 보기"는 /api/view-board 서버 함수가 service_role 키로 별도 조회하므로
-- 여기서 anon에게 read 권한을 열 필요가 없습니다. (오히려 열면 코드 없이도 전체 열람 가능해져 위험합니다)

-- ---- RPC: 초대 코드로 그룹(board)에 editor로 합류 ----
-- security definer로 실행되어, 호출자는 board_members에 직접 insert 권한이 없어도
-- "유효한 초대 코드를 아는 로그인 사용자"라는 조건 하나로만 합류할 수 있게 합니다.
create or replace function join_board_by_invite_code(p_code text)
returns table(board_id uuid, title text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_board boards%rowtype;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select * into v_board from boards where invite_code = p_code;
  if not found then
    raise exception '유효하지 않은 초대 코드입니다.';
  end if;

  insert into board_members(board_id, user_id, role)
  values (v_board.id, auth.uid(), 'editor')
  on conflict (board_id, user_id) do nothing;

  return query select v_board.id, v_board.title;
end;
$$;

grant execute on function join_board_by_invite_code(text) to authenticated;

-- ---- RPC: board 구성원 이메일 목록 조회 ----
-- auth.users는 클라이언트(anon/authenticated 키)에서 직접 select할 수 없으므로,
-- "이 board 구성원만" 서로의 이메일+역할을 볼 수 있도록 security definer 함수로 노출합니다.
create or replace function get_board_members(p_board_id uuid)
returns table(user_id uuid, email text, role text, joined_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_board_member(p_board_id) then
    raise exception '이 board의 구성원만 멤버 목록을 볼 수 있습니다.';
  end if;

  return query
    select bm.user_id, u.email::text, bm.role, bm.created_at
    from board_members bm
    join auth.users u on u.id = bm.user_id
    where bm.board_id = p_board_id
    order by bm.created_at asc;
end;
$$;

grant execute on function get_board_members(uuid) to authenticated;

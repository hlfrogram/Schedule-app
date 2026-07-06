-- ===== 그룹(공동편집) 구조 — 전체 스키마 (버그 수정판) =====

-- 0단계: 잔재 정리 (이미 실행했었다면 정리 후 재생성)
drop function if exists get_board_members(uuid);
drop function if exists join_board_by_invite_code(text);
drop function if exists create_board(text);
drop function if exists is_board_owner(uuid);
drop function if exists is_board_member(uuid);
drop table if exists board_members cascade;
drop table if exists events cascade;
drop table if exists boards cascade;

create extension if not exists pgcrypto;

-- 1단계: 테이블
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

-- 2단계: 헬퍼 함수 (security definer로 순환참조 없이 멤버십 체크)
create or replace function

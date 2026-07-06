# 일정 핀보드 — 3단계: 그룹(공동 편집) + 권한(RLS)

## 이번 단계에서 생긴 것
- **그룹 참여(초대 코드)**: 일정표 소유자가 발급한 **초대 코드**로 다른 로그인 사용자가 같은 board의
  **editor(공동 편집자)**로 합류할 수 있음. 로그인 화면에서 "초대 코드로 그룹 참여하기" 선택 →
  로그인/회원가입 → 초대 코드 입력 → 합류 즉시 같은 캘린더를 함께 편집
  (`https://내도메인/?join=xxxx` 링크로 공유하면 로그인 후 자동으로 합류 시도)
- **그룹 관리 패널**: 캘린더 화면에서 "👥 그룹" 버튼 → 구성원 목록(이메일 + 역할) 확인
  - 소유자: 초대 코드 확인/복사, **재발급**(기존 코드 무효화), 다른 구성원 **내보내기**
  - 편집자: 구성원 목록 확인, **그룹 나가기**
- **RLS 세분화**: "본인 소유만 접근 가능" → "board_members에 속한 구성원(owner/editor)이면 접근 가능"으로 확장.
  누가 무엇을 할 수 있는지는 DB(Postgres RLS) 레벨에서 강제되며, 프론트 코드가 아니라 정책이 최종 방어선입니다.

## 이전 단계 기능 (계속 유지)
- **편집자(로그인)**: 회원가입/로그인 → 본인의 일정표(board) 자동 생성 → 프롬프트로 일정 추가/편집 →
  모두 Supabase DB에 저장되어 새로고침해도 유지됨
- **뷰어(비로그인)**: "공유 코드로 보기" → 코드 입력 → 읽기 전용으로 캘린더 확인 (편집 UI 전부 숨김)
- 소유자 화면 상단에 자신의 **공유 코드 + 공유 링크 복사 버튼**이 표시됨
  (`https://내도메인/?code=xxxx` 형태 링크로 공유하면 뷰어는 코드 입력 없이 바로 진입)

## 역할(role) 정리
| 역할 | 진입 방법 | 캘린더 편집 | 그룹 관리 |
|---|---|---|---|
| **소유자(owner)** | 로그인해서 만들기/편집하기 | ✅ | 초대코드 발급/재발급, 구성원 내보내기 |
| **편집자(editor)** | 초대 코드로 그룹 참여하기 | ✅ | 구성원 목록 확인, 그룹 나가기 |
| **뷰어(viewer)** | 공유 코드로 보기 (비로그인) | ❌ (읽기 전용) | 접근 불가 |

**공유 코드(share_code)**와 **초대 코드(invite_code)**는 서로 다른 코드입니다.
공유 코드는 "읽기 전용 링크"용, 초대 코드는 "로그인해서 같이 편집할 사람"용입니다.

## 폴더 구조
```
schedule-app/
├── index.html              ← 프론트 (모드 선택 / 로그인 / 코드 보기 / 캘린더)
├── api/
│   ├── claude.js            ← (1단계) Claude API 프록시
│   └── view-board.js        ← (2단계) 공유 코드로 읽기 전용 조회 (service_role 키 사용)
├── supabase-schema.sql       ← Supabase에 실행할 테이블/RLS 스크립트
├── package.json              ← @supabase/supabase-js 의존성
└── vercel.json
```

## 설정 순서

### 1. Supabase 프로젝트 생성
- https://supabase.com → New Project

### 2. 테이블 생성
- Supabase 대시보드 → SQL Editor → `supabase-schema.sql` 내용 붙여넣고 실행
- 이미 2단계 SQL을 실행한 프로젝트라면, 이 파일을 그대로 다시 실행하면 됩니다.
  `board_members` 테이블/`invite_code` 컬럼 추가, 기존 board에 대한 owner 등록 및 초대 코드 발급까지
  자동으로 처리하는 마이그레이션이 포함되어 있어요 (여러 번 실행해도 안전합니다).

### 3. 이메일 인증 설정 확인
- Authentication → Providers → Email이 켜져 있는지 확인
- 데모를 빠르게 하고 싶다면 Authentication → Settings에서
  "Confirm email"을 꺼두면 가입 즉시 로그인 가능 (운영 전환 시엔 다시 켜는 걸 권장)

### 4. 키 3개 확보 (Settings > API)
| 키 | 용도 | 넣는 곳 |
|---|---|---|
| Project URL | 공통 | `index.html`의 `SUPABASE_URL`, Vercel 환경변수 `SUPABASE_URL` |
| anon public key | 프론트에서 사용 (RLS로 보호됨, 노출돼도 됨) | `index.html`의 `SUPABASE_ANON_KEY` |
| service_role key | 뷰어 조회 전용 서버 함수에서만 사용 (⚠️ 절대 프론트/코드에 넣지 말 것) | Vercel 환경변수 `SUPABASE_SERVICE_ROLE_KEY` |

`index.html` 상단 스크립트에서 이 두 줄을 실제 값으로 바꿔주세요:
```js
const SUPABASE_URL = 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_PUBLIC_KEY';
```

### 5. Vercel 환경변수 등록 (Settings > Environment Variables)
- `ANTHROPIC_API_KEY` (1단계에서 이미 등록했다면 유지)
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` ← service_role 키. 이 값은 절대 유출되면 안 됩니다 (DB 전체 접근 가능)

등록 후 반드시 **Redeploy** 하세요.

### 6. 배포 및 확인
- 배포된 주소 접속 → "로그인해서 만들기/편집하기"로 회원가입 → 일정 프롬프트 입력해서 정상 저장되는지 확인
- 상단 공유 코드를 복사해서 시크릿창(로그인 안 된 상태)에서 "공유 코드로 보기"로 들어가 읽기 전용으로 잘 보이는지 확인
- 새로고침해도 일정이 남아있는지 확인 (DB 저장 확인)

## 보안 설계 요약
- 편집자(owner+editor)의 모든 DB 접근은 Supabase RLS로 "자신이 board_members에 속한 board만" 허용됩니다.
  (기존 "본인 소유만"에서 "구성원이면"으로 확장됐지만, 여전히 소속되지 않은 board는 절대 조회/수정 불가)
- board 자체의 수정/삭제(제목, 공유코드·초대코드 재발급, board 삭제)는 **owner만** 가능하도록 별도 정책으로 제한했습니다.
  editor는 events(일정)는 자유롭게 다룰 수 있지만 board 설정은 건드릴 수 없습니다.
- 그룹 합류는 `join_board_by_invite_code()` DB 함수(security definer)로만 가능합니다.
  클라이언트가 board_members에 "아무나 초대"하는 insert를 직접 할 수 있는 경로는 없습니다 —
  오직 "유효한 초대 코드를 아는 로그인 사용자 본인"만 자신을 editor로 등록할 수 있습니다.
- 구성원 이메일 목록은 `get_board_members()` 함수로만 노출됩니다. `auth.users` 테이블은 클라이언트 키로
  직접 조회할 수 없고, 이 함수는 호출자가 해당 board 구성원인지 먼저 확인한 뒤에만 결과를 돌려줍니다.
- 뷰어는 Supabase에 직접 연결하지 않고, `/api/view-board` 서버 함수만 거칩니다.
  이 함수는 service_role 키로 "공유 코드가 일치하는 board 1개"만 조회해서 반환하며, 수정 기능은 아예 존재하지 않습니다.
- anon 역할에는 boards/events/board_members에 대한 어떤 RLS 정책도 부여하지 않았습니다 — 그래서 프론트가 실수로든
  악의적으로든 Supabase에 직접 anon key로 접근해도 아무 데이터도 읽을 수 없습니다.

## 알아둘 점 / 다음 단계 후보
- 지금은 사진을 base64로 DB(jsonb)에 저장합니다. 데모 규모에선 괜찮지만, 사진이 많아지면
  Supabase Storage(파일 저장소)로 옮기는 게 좋습니다.
- 현재는 "사용자 1인당 board 1개 소속"만 가정합니다(가입 시 자동 생성, 초대 수락 시 그 board에 합류).
  한 사용자가 여러 board를 오가며 관리하고 싶다면 board 선택/전환 UI를 추가하면 됩니다.
- 초대 코드·공유 코드 둘 다 "코드 하나만 알면" 동작하는 구조라, 코드 자체가 비밀번호 역할을 합니다.
  더 강한 보안이 필요하면 접속 시도에 rate limit을 걸거나, 코드 만료 기능을 추가할 수 있습니다.
- editor 권한은 지금 "일정 전체 편집 가능"으로 통일되어 있습니다. 세분화된 권한(예: 읽기만 가능한 멤버,
  특정 날짜만 편집 가능한 멤버 등)이 필요하면 `board_members.role`에 값을 추가하고 정책을 더 나누면 됩니다.

// /api/view-board.js
// 로그인하지 않은 "뷰어"가 공유 코드로 일정표를 읽기 전용 조회하는 전용 엔드포인트.
// service_role 키를 사용해 RLS를 우회하지만, 이 함수는 오직 "코드로 조회"만 하고
// 어떤 수정(insert/update/delete)도 하지 않습니다. 이 키는 절대 프론트 코드에 넣지 마세요.

import { createClient } from '@supabase/supabase-js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: { message: 'POST만 허용됩니다.' } });
  }

  const { code } = req.body || {};
  if (!code || typeof code !== 'string') {
    return res.status(400).json({ error: { message: '공유 코드가 필요합니다.' } });
  }

  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return res.status(500).json({ error: { message: '서버 환경변수(SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)가 설정되지 않았습니다.' } });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  try {
    const { data: board, error: boardErr } = await admin
      .from('boards')
      .select('id, title, share_code')
      .eq('share_code', code.trim())
      .single();

    if (boardErr || !board) {
      return res.status(404).json({ error: { message: '해당 코드의 일정표를 찾을 수 없어요.' } });
    }

    const { data: events, error: evErr } = await admin
      .from('events')
      .select('id, event_date, title, time, location, memo, checklist, docs, photos')
      .eq('board_id', board.id);

    if (evErr) {
      return res.status(500).json({ error: { message: '일정 조회 중 오류가 발생했어요.' } });
    }

    // 프론트에는 board id/title과 events만 반환 (owner_id 등 민감 정보 제외)
    return res.status(200).json({
      board: { id: board.id, title: board.title },
      events: events || []
    });
  } catch (err) {
    console.error('view-board error:', err);
    return res.status(500).json({ error: { message: '서버 오류: ' + err.message } });
  }
}

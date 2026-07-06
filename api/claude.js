// /api/claude.js
// 프론트엔드가 보낸 Messages API 요청을 Anthropic으로 중계하는 프록시.
// API 키는 서버 환경변수(ANTHROPIC_API_KEY)로만 주입 — 절대 프론트 코드에 넣지 마세요.

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: { message: 'POST만 허용됩니다.' } });
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: { message: '서버 환경변수 ANTHROPIC_API_KEY가 설정되지 않았습니다.' } });
  }

  const { model, max_tokens, messages } = req.body || {};
  if (!model || !messages) {
    return res.status(400).json({ error: { message: 'model과 messages가 필요합니다.' } });
  }

  try {
    const anthropicRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({ model, max_tokens: max_tokens || 1000, messages }),
    });

    const data = await anthropicRes.json();
    return res.status(anthropicRes.status).json(data);
  } catch (err) {
    console.error('claude proxy error:', err);
    return res.status(500).json({ error: { message: '서버 오류: ' + err.message } });
  }
}

// /api/claude.js
// 프론트엔드는 Anthropic(클로드) 형식으로 요청을 보내지만,
// 이 프록시가 그것을 Google Gemini(무료) 형식으로 변환해 호출하고,
// 응답을 다시 프론트엔드가 이해하는 형식으로 되돌려줍니다.
// 키는 서버 환경변수 GEMINI_API_KEY 로만 사용 — 절대 프론트 코드에 넣지 마세요.

const GEMINI_MODEL = 'gemini-2.0-flash'; // 무료 티어 지원 모델

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: { message: 'POST만 허용됩니다.' } });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: { message: '서버 환경변수 GEMINI_API_KEY가 설정되지 않았습니다.' } });
  }

  const { max_tokens, messages } = req.body || {};
  if (!messages || !Array.isArray(messages)) {
    return res.status(400).json({ error: { message: 'messages가 필요합니다.' } });
  }

  // --- 1) 프론트가 보낸 Anthropic 형식 messages → Gemini contents 로 변환 ---
  const contents = messages.map((m) => {
    const parts = [];
    if (typeof m.content === 'string') {
      parts.push({ text: m.content });
    } else if (Array.isArray(m.content)) {
      for (const block of m.content) {
        if (block.type === 'text') {
          parts.push({ text: block.text || '' });
        } else if (block.type === 'image' && block.source) {
          parts.push({
            inline_data: {
              mime_type: block.source.media_type,
              data: block.source.data,
            },
          });
        }
      }
    }
    return { role: m.role === 'assistant' ? 'model' : 'user', parts };
  });

  try {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
    const geminiRes = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents,
        generationConfig: { maxOutputTokens: max_tokens || 1000 },
      }),
    });

    const data = await geminiRes.json();

    // Gemini 오류를 그대로 전달
    if (!geminiRes.ok || data.error) {
      const msg = data.error?.message || `Gemini 요청 실패 (status ${geminiRes.status})`;
      return res.status(geminiRes.status || 500).json({ error: { message: msg } });
    }

    // 안전필터 등으로 후보가 없을 때
    const candidate = data.candidates && data.candidates[0];
    if (!candidate || !candidate.content || !candidate.content.parts) {
      const blocked = data.promptFeedback?.blockReason;
      return res.status(200).json({
        error: { message: blocked ? `요청이 차단되었어요 (${blocked})` : 'AI 응답이 비어 있어요.' },
      });
    }

    // --- 2) Gemini 응답 → Anthropic 형식(content 배열)으로 되돌림 ---
    const text = candidate.content.parts.map((p) => p.text || '').join('');
    return res.status(200).json({ content: [{ type: 'text', text }] });
  } catch (err) {
    console.error('gemini proxy error:', err);
    return res.status(500).json({ error: { message: '서버 오류: ' + err.message } });
  }
}

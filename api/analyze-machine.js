/* Vercel Serverless Function — gym machine recognition.
 *
 * The Anthropic API key lives here, on the server. It must never reach the
 * browser bundle, which is the whole reason this endpoint exists.
 *
 * Without ANTHROPIC_API_KEY configured we answer 501 and the client says so
 * plainly. We never invent a detection result: a made-up answer is worse than
 * no answer, because the user cannot tell it apart from a real one.
 */

import Anthropic from '@anthropic-ai/sdk';

/* Must match MUSCLES in app.js so the returned group maps onto a real filter. */
const MUSCLES = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core', 'cardio', 'other'];

const RESULT_SCHEMA = {
  type: 'object',
  properties: {
    machine:    { type: 'string', description: 'Name of the machine or equipment shown.' },
    exercise:   { type: 'string', description: 'Name of the main exercise performed on it.' },
    muscle:     { type: 'string', enum: MUSCLES, description: 'Primary muscle group worked.' },
    howTo:      { type: 'string', description: 'Two or three sentences on correct form and setup.' },
    suggestion: { type: 'string', description: 'A suggested set and rep scheme for a general trainee.' }
  },
  required: ['machine', 'exercise', 'muscle', 'howTo', 'suggestion'],
  additionalProperties: false
};

const PROMPT_HE =
  'התמונה צולמה בחדר כושר. זהה את המכשיר והסבר בעברית איך משתמשים בו נכון. ' +
  'אם בתמונה אין מכשיר כושר, כתוב זאת במפורש בשדה machine ובחר muscle="other".';

const PROMPT_EN =
  'This photo was taken in a gym. Identify the machine and explain in English how to use it correctly. ' +
  'If the photo does not show gym equipment, say so plainly in the machine field and set muscle="other".';

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'method_not_allowed' });
  }

  // Not configured is a distinct, honest state — not a failure to paper over.
  if (!process.env.ANTHROPIC_API_KEY) {
    return res.status(501).json({ error: 'not_configured' });
  }

  const { image, lang } = req.body || {};
  if (typeof image !== 'string' || image.indexOf('data:image/') !== 0) {
    return res.status(400).json({ error: 'bad_image' });
  }

  const match = /^data:(image\/(?:jpeg|png|webp));base64,(.+)$/.exec(image);
  if (!match) return res.status(400).json({ error: 'bad_image' });
  const [, mediaType, base64] = match;

  // ~4MB of base64 is well past what a phone photo needs after client downscaling.
  if (base64.length > 5_500_000) return res.status(413).json({ error: 'image_too_large' });

  try {
    const client = new Anthropic();
    const message = await client.messages.create({
      model: 'claude-opus-5',
      max_tokens: 1024,
      // A single-image identification does not need deep reasoning; low effort
      // keeps the per-photo cost and latency down. Thinking stays on (disabling
      // it on Opus 5 has its own failure modes).
      output_config: {
        effort: 'low',
        format: { type: 'json_schema', schema: RESULT_SCHEMA }
      },
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: mediaType, data: base64 } },
          { type: 'text', text: lang === 'en' ? PROMPT_EN : PROMPT_HE }
        ]
      }]
    });

    // Safety classifiers can decline with HTTP 200 — check before reading content.
    if (message.stop_reason === 'refusal') {
      return res.status(422).json({ error: 'refused' });
    }

    const text = (message.content || []).find(b => b.type === 'text');
    if (!text) return res.status(502).json({ error: 'empty_response' });

    // output_config.format guarantees the text block is valid JSON for the schema.
    return res.status(200).json(JSON.parse(text.text));
  } catch (err) {
    if (err instanceof Anthropic.AuthenticationError) {
      return res.status(501).json({ error: 'not_configured' });
    }
    if (err instanceof Anthropic.RateLimitError) {
      return res.status(429).json({ error: 'rate_limited' });
    }
    console.error('analyze-machine failed', err);
    return res.status(502).json({ error: 'upstream_failed' });
  }
}

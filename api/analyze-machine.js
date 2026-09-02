/* Vercel Serverless Function — gym machine recognition.
 *
 * The Anthropic API key lives here, on the server. It must never reach the
 * browser bundle, which is the whole reason this endpoint exists.
 *
 * Without ANTHROPIC_API_KEY configured we answer 501 and the client says so
 * plainly. We never invent a detection result: a made-up answer is worse than
 * no answer, because the user cannot tell it apart from a real one. That rule
 * is why `identified`, `confidence` and `needsQr` are part of the schema —
 * the model is given an honest way to say "I cannot tell from this photo",
 * instead of being cornered into guessing a brand and model.
 *
 * Two tools are available to fill gaps the photo alone cannot:
 *   web_search — reaches for manufacturer/model detail the image lacks.
 *   web_fetch  — only when the client sends a URL decoded from the QR sticker
 *                on the machine. web_fetch can only retrieve URLs already
 *                present in the conversation, so the URL is stated in the
 *                prompt below and nothing else is reachable.
 */

import Anthropic from '@anthropic-ai/sdk';

/* Must match MUSCLES in app.js so the returned group maps onto a real filter. */
const MUSCLES = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core', 'cardio', 'other'];

const RESULT_SCHEMA = {
  type: 'object',
  properties: {
    identified: { type: 'boolean', description: 'True only if the photo really shows gym equipment you can name. False for anything else.' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'], description: 'How sure you are of the identification.' },
    needsQr:    { type: 'boolean', description: 'True when the photo (and any search) left you unsure, and scanning the QR sticker on the machine would settle it.' },
    machine:    { type: 'string', description: 'Name of the machine or equipment shown.' },
    exercise:   { type: 'string', description: 'Name of the main exercise performed on it.' },
    brand:      { type: 'string', description: 'Manufacturer, e.g. Technogym, Life Fitness, Hammer Strength. Empty string if genuinely unknown — never guess.' },
    model:      { type: 'string', description: 'Model or product line, e.g. Selection Pro Chest Press. Empty string if genuinely unknown — never guess.' },
    muscle:     { type: 'string', enum: MUSCLES, description: 'Primary muscle group worked.' },
    secondaryMuscles: { type: 'array', items: { type: 'string', enum: MUSCLES }, description: 'Supporting muscle groups, most significant first. Empty array if none worth naming.' },
    setup:      { type: 'string', description: 'How to set the machine up for this trainee: seat height, pad and lever positions, range limiters.' },
    howTo:      { type: 'string', description: 'How to perform the movement, in two or three sentences.' },
    mistakes:   { type: 'array', items: { type: 'string' }, description: 'Common form mistakes and safety points, one short sentence each. Two to four items.' },
    suggestion: { type: 'string', description: 'Suggested set and rep scheme for this specific trainee.' },
    suggestedKg: { type: 'number', description: 'Suggested working weight in kg for this trainee. 0 when a load makes no sense (bodyweight or cardio machines) or when the stack is not in kg.' },
    suggestionWhy: { type: 'string', description: 'One or two sentences on why this load and rep scheme, referring to the trainee data you were given. Say plainly when it is only a conservative starting estimate.' },
    sources:    { type: 'array', items: { type: 'string' }, description: 'URLs you actually used from search or the QR page. Empty array when you answered from the photo alone.' }
  },
  required: ['identified', 'confidence', 'needsQr', 'machine', 'exercise', 'brand', 'model',
             'muscle', 'secondaryMuscles', 'setup', 'howTo', 'mistakes', 'suggestion',
             'suggestedKg', 'suggestionWhy', 'sources'],
  additionalProperties: false
};

/* The trainee block is what turns a generic manual page into a recommendation
   for this person. It is assembled from data the app already holds; nothing is
   asked of the user twice. */
function traineeBlock(profile, lang) {
  if (!profile || typeof profile !== 'object') return '';
  const parts = [];
  if (profile.gender) parts.push(`gender: ${profile.gender}`);
  if (profile.age) parts.push(`age: ${profile.age}`);
  if (profile.bodyKg) parts.push(`body weight: ${profile.bodyKg} kg`);
  if (profile.goal) parts.push(`goal: ${profile.goal}`);
  if (profile.workoutsLogged !== undefined) parts.push(`workouts logged in this app: ${profile.workoutsLogged}`);
  if (profile.bestE1RM) parts.push(`best estimated 1RM recorded in this app across all exercises: ${profile.bestE1RM} kg (a rough strength proxy, not this machine)`);
  if (!parts.length) return '';
  return (lang === 'en'
    ? '\n\nTrainee data from the app, use it for the weight and rep suggestion: '
    : '\n\nנתוני המתאמן מהאפליקציה, השתמש בהם להמלצת המשקל והחזרות: ') + parts.join('; ') +
    (lang === 'en'
      ? '\nIf this data is thin, say so in suggestionWhy and stay conservative.'
      : '\nאם הנתונים דלים, ציין זאת ב-suggestionWhy והישאר שמרני.');
}

const PROMPT_HE =
  'התמונה צולמה בחדר כושר. זהה את המכשיר ובנה כרטיס מידע מלא עליו בעברית: יצרן ודגם, ' +
  'שריר ראשי ושרירים משניים, כיוון והגדרת המכשיר, אופן הביצוע, טעויות נפוצות ובטיחות, ' +
  'והמלצת משקל וחזרות למתאמן שנתוניו למטה.\n' +
  'אם התמונה לבדה לא מספיקה כדי לקבוע יצרן ודגם — חפש ברשת. אל תמציא יצרן או דגם: ' +
  'שדה שאינך יודע יישאר מחרוזת ריקה.\n' +
  'אם גם אחרי חיפוש אינך בטוח בזיהוי, החזר needsQr=true כדי שהמשתמש יסרוק את קוד ה-QR שעל המכשיר.\n' +
  'אם בתמונה אין מכשיר כושר, החזר identified=false, כתוב זאת במפורש בשדה machine ובחר muscle="other".';

const PROMPT_EN =
  'This photo was taken in a gym. Identify the machine and build a full information card in English: ' +
  'manufacturer and model, primary and secondary muscles, how to set it up, how to perform the movement, ' +
  'common mistakes and safety points, and a weight and rep recommendation for the trainee described below.\n' +
  'If the photo alone is not enough to pin down manufacturer and model, search the web. Never invent a ' +
  'brand or model: leave a field you do not know as an empty string.\n' +
  'If you are still unsure after searching, return needsQr=true so the user can scan the QR sticker on the machine.\n' +
  'If the photo does not show gym equipment, return identified=false, say so plainly in the machine field, and set muscle="other".';

/* A URL the user physically scanned off the machine is the strongest evidence
   available, so it outranks both the photo and anything search turns up. */
function qrBlock(url, lang) {
  return lang === 'en'
    ? `\n\nThe user scanned the QR sticker on this machine. It points to: ${url}\n` +
      'Fetch that page with web_fetch and prefer what it says over your reading of the photo — ' +
      'it is the manufacturer\'s own identification of this exact unit. If the page turns out to be ' +
      'unrelated to gym equipment, ignore it and say so in suggestionWhy.'
    : `\n\nהמשתמש סרק את קוד ה-QR שעל המכשיר. הוא מוביל אל: ${url}\n` +
      'שלוף את הדף באמצעות web_fetch והעדף את מה שכתוב בו על פני קריאת התמונה — ' +
      'זהו הזיהוי של היצרן למכשיר הספציפי הזה. אם מתברר שהדף אינו קשור לציוד כושר, ' +
      'התעלם ממנו וציין זאת ב-suggestionWhy.';
}

function isHttpUrl(v) {
  if (typeof v !== 'string' || v.length > 2000) return false;
  try {
    const u = new URL(v);
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch (e) { return false; }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'method_not_allowed' });
  }

  // Not configured is a distinct, honest state — not a failure to paper over.
  if (!process.env.ANTHROPIC_API_KEY) {
    return res.status(501).json({ error: 'not_configured' });
  }

  const { image, lang, profile, qrUrl } = req.body || {};
  if (typeof image !== 'string' || image.indexOf('data:image/') !== 0) {
    return res.status(400).json({ error: 'bad_image' });
  }

  const match = /^data:(image\/(?:jpeg|png|webp));base64,(.+)$/.exec(image);
  if (!match) return res.status(400).json({ error: 'bad_image' });
  const [, mediaType, base64] = match;

  // ~4MB of base64 is well past what a phone photo needs after client downscaling.
  if (base64.length > 5_500_000) return res.status(413).json({ error: 'image_too_large' });

  // A QR that does not decode to a real http(s) URL is dropped rather than
  // passed through: web_fetch would only be able to reach it if we quoted it.
  const scannedUrl = isHttpUrl(qrUrl) ? qrUrl : null;
  const isEn = lang === 'en';

  const prompt = (isEn ? PROMPT_EN : PROMPT_HE) +
    traineeBlock(profile, isEn ? 'en' : 'he') +
    (scannedUrl ? qrBlock(scannedUrl, isEn ? 'en' : 'he') : '');

  const tools = [{ type: 'web_search_20260209', name: 'web_search', max_uses: 4 }];
  if (scannedUrl) {
    // web_fetch can only retrieve URLs already in the conversation, and the
    // only one there is the scanned sticker — so this cannot wander the web.
    tools.push({ type: 'web_fetch_20260209', name: 'web_fetch', max_uses: 2 });
  }

  try {
    const client = new Anthropic();
    const messages = [{
      role: 'user',
      content: [
        { type: 'image', source: { type: 'base64', media_type: mediaType, data: base64 } },
        { type: 'text', text: prompt }
      ]
    }];

    /* Server tools can stop a turn with `pause_turn` when they hit an internal
       iteration limit. That is not an error and not a final answer — the turn
       has to be handed back to continue. Without this loop a paused turn looks
       like a silently truncated result. */
    let message = null;
    for (let turn = 0; turn < 5; turn++) {
      message = await client.messages.create({
        model: 'claude-opus-5',
        max_tokens: 8192,
        // Identification plus a short search is not deep reasoning, but it is
        // more than the single-glance call this used to be.
        output_config: {
          effort: 'medium',
          format: { type: 'json_schema', schema: RESULT_SCHEMA }
        },
        tools: tools,
        messages: messages
      });

      if (message.stop_reason !== 'pause_turn') break;
      messages.push({ role: 'assistant', content: message.content });
    }

    // Safety classifiers can decline with HTTP 200 — check before reading content.
    if (message.stop_reason === 'refusal') {
      return res.status(422).json({ error: 'refused' });
    }
    if (message.stop_reason === 'pause_turn') {
      // Still paused after the loop: better to say the analysis did not finish
      // than to return whatever partial text is sitting there.
      return res.status(502).json({ error: 'incomplete' });
    }

    /* With server tools in play a turn can carry several text blocks — the
       model may narrate before it searches. The schema-shaped answer is the
       last one, so walk backwards and take the first block that actually
       parses rather than assuming block 0 is the result. */
    const texts = (message.content || []).filter(b => b.type === 'text' && b.text);
    for (let i = texts.length - 1; i >= 0; i--) {
      try {
        const parsed = JSON.parse(texts[i].text);
        if (parsed && typeof parsed === 'object') return res.status(200).json(parsed);
      } catch (e) { /* narration, not the answer — keep looking */ }
    }
    return res.status(502).json({ error: 'empty_response' });
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

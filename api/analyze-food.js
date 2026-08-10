/* Vercel Serverless Function — meal photo → estimated macros.
 *
 * Same shape and same guarantees as analyze-machine.js: the Anthropic API
 * key stays server-side, and without it configured we answer 501 and the
 * client says so plainly rather than fabricating a nutrition estimate.
 */

import Anthropic from '@anthropic-ai/sdk';

const MEAL_TAGS = ['breakfast', 'lunch', 'dinner', 'snack'];

const RESULT_SCHEMA = {
  type: 'object',
  properties: {
    food:     { type: 'string', description: 'Name of the dish or food item shown.' },
    tag:      { type: 'string', enum: MEAL_TAGS, description: 'Best guess for meal type, based on the food and typical eating occasion.' },
    calories: { type: 'integer', description: 'Estimated total calories (kcal) for the portion visible in the photo.' },
    protein:  { type: 'number', description: 'Estimated protein in grams for the visible portion.' },
    carbs:    { type: 'number', description: 'Estimated carbohydrates in grams for the visible portion.' },
    fats:     { type: 'number', description: 'Estimated fat in grams for the visible portion.' },
    notes:    { type: 'string', description: 'One or two sentences on portion-size assumptions and how uncertain the estimate is.' }
  },
  required: ['food', 'tag', 'calories', 'protein', 'carbs', 'fats', 'notes'],
  additionalProperties: false
};

const PROMPT_HE =
  'התמונה מציגה מנה או ארוחה. זהה את המאכל והערך את הערכים התזונתיים למנה הנראית בתמונה: ' +
  'קלוריות, חלבון, פחמימות ושומן בגרמים. זו הערכה חזותית בלבד ולא מדידה מדויקת — ' +
  'ציין זאת בשדה notes יחד עם הנחות לגבי גודל המנה. ' +
  'אם התמונה אינה מציגה אוכל, כתוב זאת במפורש בשדה food והחזר 0 בכל השדות המספריים.';

const PROMPT_EN =
  'This photo shows a dish or meal. Identify the food and estimate its nutritional values for the ' +
  'portion visible in the photo: calories, protein, carbohydrates and fat in grams. This is a visual ' +
  'estimate, not a precise measurement — say so in the notes field along with your portion-size ' +
  'assumptions. If the photo does not show food, say so plainly in the food field and return 0 for ' +
  'every numeric field.';

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'method_not_allowed' });
  }

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

  if (base64.length > 5_500_000) return res.status(413).json({ error: 'image_too_large' });

  try {
    const client = new Anthropic();
    const message = await client.messages.create({
      model: 'claude-opus-5',
      max_tokens: 1024,
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

    if (message.stop_reason === 'refusal') {
      return res.status(422).json({ error: 'refused' });
    }

    const text = (message.content || []).find(b => b.type === 'text');
    if (!text) return res.status(502).json({ error: 'empty_response' });

    return res.status(200).json(JSON.parse(text.text));
  } catch (err) {
    if (err instanceof Anthropic.AuthenticationError) {
      return res.status(501).json({ error: 'not_configured' });
    }
    if (err instanceof Anthropic.RateLimitError) {
      return res.status(429).json({ error: 'rate_limited' });
    }
    console.error('analyze-food failed', err);
    return res.status(502).json({ error: 'upstream_failed' });
  }
}

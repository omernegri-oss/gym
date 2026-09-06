/* Vercel Serverless Function — is the vision feature usable at all?
 *
 * The analyse endpoints already answer 501 when the key is missing, but only
 * after the user has opened the camera, granted permission, framed a shot and
 * pressed analyse. That is a long walk to a closed door. This endpoint lets
 * the client say so the moment the camera opens.
 *
 * It deliberately does no model call and reads no request body, so probing is
 * free: it reports only whether the key is present, never any part of it.
 */

export default function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'method_not_allowed' });
  }
  // Not cached: the key can be added in Vercel without the client reloading.
  res.setHeader('Cache-Control', 'no-store');
  return res.status(200).json({ configured: !!process.env.ANTHROPIC_API_KEY });
}

# Key art renderer

`thumbnail.png` (1920×1080) and `icon.png` (512×512) are rendered from the real game:
the headless harness boots the server, stages the scene (`tests/harness/export_thumbnail.luau`),
and this page renders it with three.js + bloom. Characters are enlarged 2.6× for readability,
as usual for Roblox key art.

```bash
cd marketing/render
npm install
luau ../../tests/harness/export_thumbnail.luau | tail -n 1 > thumb.json
echo "window.SCENE = $(cat thumb.json);" > thumb-scene.js
PW=./node_modules/playwright node render.js   # writes thumbnail.png and icon.png here
```

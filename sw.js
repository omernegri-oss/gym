/* FitPro service worker — offline shell.
   Gyms have poor reception, so the app itself must load without the network.
   User data lives in localStorage, which is always local anyway. */

const CACHE = 'fitpro-v3';
const ASSETS = [
  '.',
  'index.html',
  'styles.css',
  'app.js',
  'manifest.webmanifest',
  'icon.svg'
];

self.addEventListener('install', function(e){
  e.waitUntil(
    caches.open(CACHE)
      .then(function(c){ return c.addAll(ASSETS); })
      .then(function(){ return self.skipWaiting(); })
      .catch(function(){ /* a missing asset must not block installation */ })
  );
});

self.addEventListener('activate', function(e){
  e.waitUntil(
    caches.keys()
      .then(function(keys){
        return Promise.all(keys.filter(function(k){ return k !== CACHE; })
                              .map(function(k){ return caches.delete(k); }));
      })
      .then(function(){ return self.clients.claim(); })
  );
});

/* The page asks for the update when it judges the moment safe — mid-set is
   not that moment. skipWaiting() also runs on install, so this is the path
   for a build that arrives while an older worker is still controlling pages. */
self.addEventListener('message', function(e){
  if(e.data && e.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', function(e){
  const req = e.request;
  if(req.method !== 'GET') return;

  const url = new URL(req.url);
  // Never cache the vision endpoint — it must always hit the network.
  if(url.pathname.indexOf('/api/') === 0) return;
  if(url.origin !== self.location.origin) return;

  // Network-first so a deploy is picked up immediately, cache as the fallback.
  e.respondWith(
    fetch(req)
      .then(function(res){
        const copy = res.clone();
        caches.open(CACHE).then(function(c){ c.put(req, copy); }).catch(function(){});
        return res;
      })
      .catch(function(){
        return caches.match(req).then(function(hit){
          return hit || caches.match('index.html');
        });
      })
  );
});

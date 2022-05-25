self.addEventListener("install", (e) => {
  e.waitUntil(
    caches
      .open("planner")
      .then((cache) =>
        cache.addAll([
          "/planner/",
          "/planner/index.html",
          "/planner/b-button.png",
          "/planner/planner.wasm",
        ])
      )
  );
});

self.addEventListener("fetch", (e) => {
  console.log("A1LIU-fetch:", e.request.url);

  e.respondWith(
    caches.match(e.request).then((response) => response || fetch(e.request))
  );
});
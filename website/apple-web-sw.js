self.addEventListener("install", (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("push", (event) => {
  const payload = (() => {
    try {
      return event.data ? event.data.json() : {};
    } catch (_error) {
      return { title: "Atlas Masa", body: event.data ? event.data.text() : "" };
    }
  })();

  const title = payload.title || "Atlas Masa";
  const options = {
    body: payload.body || "Apple web push is connected.",
    icon: payload.icon || "/favicon.svg",
    badge: payload.badge || "/favicon.svg",
    data: payload.url || "/apple-ecosystem.html",
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = event.notification.data || "/apple-ecosystem.html";
  event.waitUntil(self.clients.openWindow(target));
});

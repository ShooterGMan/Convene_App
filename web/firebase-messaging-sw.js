// Firebase Cloud Messaging service worker - handles push notifications while
// the web app is in the background or closed. Must live at the web root so it
// is served from /firebase-messaging-sw.js. The config below is public client
// config (identifiers, not secrets - same values as firebase_options.dart).
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAt0ICabtheJ18dW3Gzb4VqwWXHg_LaJ1Y',
  appId: '1:348324056471:web:1504a95f58008598c608d2',
  messagingSenderId: '348324056471',
  projectId: 'meeting-app-844aa',
  authDomain: 'meeting-app-844aa.firebaseapp.com',
  storageBucket: 'meeting-app-844aa.firebasestorage.app',
});

const messaging = firebase.messaging();

// Show the notification when a background/data message arrives.
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || payload.data?.title || 'Convene';
  const options = {
    body: payload.notification?.body || payload.data?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: { route: payload.data?.route || '/' },
  };
  self.registration.showNotification(title, options);
});

// Focus/open the app (at the notification's route) when tapped.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const route = event.notification.data?.route || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((wins) => {
      for (const client of wins) {
        if ('focus' in client) {
          client.focus();
          if ('navigate' in client) client.navigate(route);
          return;
        }
      }
      if (clients.openWindow) return clients.openWindow(route);
    })
  );
});

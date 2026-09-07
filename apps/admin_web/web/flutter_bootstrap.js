{{flutter_js}}
{{flutter_build_config}}

(function () {
  const RESET_KEY = 'admin-web-sw-reset-v1';

  async function clearFlutterCaches() {
    if (!('caches' in window)) {
      return;
    }

    const cacheKeys = await caches.keys();
    await Promise.all(cacheKeys.map((key) => caches.delete(key)));
  }

  async function unregisterServiceWorkers() {
    if (!('serviceWorker' in navigator)) {
      return false;
    }

    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((registration) => registration.unregister()));
    return registrations.length > 0 || !!navigator.serviceWorker.controller;
  }

  window.addEventListener('load', async function () {
    const hadServiceWorker = await unregisterServiceWorkers();
    await clearFlutterCaches();

    if (hadServiceWorker && !sessionStorage.getItem(RESET_KEY)) {
      sessionStorage.setItem(RESET_KEY, '1');
      window.location.reload();
      return;
    }

    sessionStorage.removeItem(RESET_KEY);
    _flutter.loader.load({});
  });
}());

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

  async function boot() {
    const hadServiceWorker = await unregisterServiceWorkers();
    await clearFlutterCaches();

    if (hadServiceWorker && !sessionStorage.getItem(RESET_KEY)) {
      sessionStorage.setItem(RESET_KEY, '1');
      window.location.reload();
      return;
    }

    sessionStorage.removeItem(RESET_KEY);
    _flutter.loader.load({});
  }

  // index.html loads this with `async`, so there is no guarantee it runs
  // before `load` fires — a warm cache on a fast connection routinely
  // finishes loading first. Registering a `load` listener at that point
  // waits for an event that has already happened, `_flutter.loader.load` is
  // never called, and the dashboard is a blank white page with a clean
  // console. Nothing errors; the app is simply never started.
  //
  // So: run now if the document is already done, and only wait otherwise.
  if (document.readyState === 'complete') {
    boot();
  } else {
    window.addEventListener('load', boot);
  }
}());

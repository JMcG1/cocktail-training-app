{{flutter_js}}
{{flutter_build_config}}

(function () {
  const cachePrefixes = ['flutter-app-', 'flutter-temp-cache', 'flutter-app-cache'];

  async function clearLegacyFlutterCaches() {
    if (!('caches' in window)) {
      return;
    }
    try {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) => cachePrefixes.some((prefix) => name.startsWith(prefix)))
          .map((name) => caches.delete(name)),
      );
    } catch (error) {
      console.warn('Unable to clear legacy Flutter caches.', error);
    }
  }

  async function unregisterFlutterServiceWorkers() {
    if (!('serviceWorker' in navigator)) {
      return;
    }
    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.map((registration) => registration.unregister()));
    } catch (error) {
      console.warn('Unable to unregister legacy service workers.', error);
    }
  }

  window.__barVarianceStartup = {
    hostname: window.location.hostname,
    browserUserAgent: navigator.userAgent,
    platform: navigator.platform,
    viewport: `${window.innerWidth || 0}x${window.innerHeight || 0}`,
    startedAt: new Date().toISOString(),
  };

  Promise.all([
    unregisterFlutterServiceWorkers(),
    clearLegacyFlutterCaches(),
  ]).finally(() => {
    _flutter.loader.load({
      onEntrypointLoaded: async function (engineInitializer) {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
      },
    });
  });
})();

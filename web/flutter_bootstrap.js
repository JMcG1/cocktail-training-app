{{flutter_js}}
{{flutter_build_config}}

(function () {
  const currentBuild = '__APP_BUILD__';
  const buildKey = 'bar-variance-training.build';
  const reloadKey = 'bar-variance-training.build-reloaded';

  async function clearLegacyFlutterCaches() {
    if ('serviceWorker' in navigator) {
      try {
        const registrations = await navigator.serviceWorker.getRegistrations();
        await Promise.all(registrations.map((registration) => registration.unregister()));
      } catch (error) {
        console.warn('Unable to unregister legacy service workers.', error);
      }
    }

    if ('caches' in window) {
      try {
        const cacheKeys = await caches.keys();
        await Promise.all(cacheKeys.map((key) => caches.delete(key)));
      } catch (error) {
        console.warn('Unable to clear legacy browser caches.', error);
      }
    }
  }

  function buildDiagnostics() {
    return [
      `build=${currentBuild}`,
      `url=${window.location.href}`,
      `online=${navigator.onLine}`,
      `userAgent=${navigator.userAgent}`,
      `viewport=${window.innerWidth}x${window.innerHeight}`,
    ].join('\n');
  }

  async function refreshApp() {
    await clearLegacyFlutterCaches();
    window.location.reload();
  }

  async function clearSavedAppData() {
    try {
      window.localStorage.clear();
    } catch (_) {}
    try {
      window.sessionStorage.clear();
    } catch (_) {}
    await clearLegacyFlutterCaches();
    const url = new URL(window.location.href);
    url.searchParams.set('_cb', currentBuild);
    window.location.replace(url.toString());
  }

  window.barVarianceRecovery = {
    refreshApp,
    clearSavedAppData,
    diagnostics: buildDiagnostics,
  };

  async function startFlutter() {
    const previousBuild = window.localStorage.getItem(buildKey);
    const reloadedBuild = window.sessionStorage.getItem(reloadKey);

    if (previousBuild && previousBuild !== currentBuild && reloadedBuild !== currentBuild) {
      window.localStorage.setItem(buildKey, currentBuild);
      window.sessionStorage.setItem(reloadKey, currentBuild);
      await clearLegacyFlutterCaches();
      const url = new URL(window.location.href);
      url.searchParams.set('_cb', currentBuild);
      window.location.replace(url.toString());
      return;
    }

    window.localStorage.setItem(buildKey, currentBuild);
    if (reloadedBuild === currentBuild) {
      window.sessionStorage.removeItem(reloadKey);
    }

    await clearLegacyFlutterCaches();
    await _flutter.loader.load({
      serviceWorkerSettings: null,
    });
  }

  startFlutter();
})();

{{flutter_js}}
{{flutter_build_config}}

(function () {
  const currentBuild = '__APP_BUILD__';
  const versionUrl = 'version.json';
  const buildKey = 'bar-variance-training.build';
  const cleanupKey = 'bar-variance-training.cache-cleanup';
  const reloadKeyPrefix = 'bar-variance-training.reload.';
  const diagnostics = [];

  function log(message, details) {
    const line = details === undefined ? message : `${message} ${String(details)}`;
    diagnostics.push(line);
    console.info('[BarVarianceBootstrap]', line);
  }

  function warn(message, error) {
    diagnostics.push(`${message} ${String(error)}`);
    console.warn('[BarVarianceBootstrap]', message, error);
  }

  function createSafeStorage(storage) {
    return {
      get(key) {
        try {
          return storage.getItem(key);
        } catch (_) {
          return null;
        }
      },
      set(key, value) {
        try {
          storage.setItem(key, value);
        } catch (_) {}
      },
      remove(key) {
        try {
          storage.removeItem(key);
        } catch (_) {}
      },
      clear() {
        try {
          storage.clear();
        } catch (_) {}
      },
    };
  }

  const safeLocalStorage = createSafeStorage(window.localStorage);
  const safeSessionStorage = createSafeStorage(window.sessionStorage);

  function buildDiagnostics() {
    return [
      `build=${currentBuild}`,
      `url=${window.location.href}`,
      `online=${navigator.onLine}`,
      `userAgent=${navigator.userAgent}`,
      `viewport=${window.innerWidth}x${window.innerHeight}`,
      `serviceWorker=${'serviceWorker' in navigator}`,
      `cacheStorage=${'caches' in window}`,
      ...diagnostics,
    ].join('\n');
  }

  async function clearLegacyFlutterState(reason) {
    log('Clearing legacy Flutter state.', reason);

    if ('serviceWorker' in navigator) {
      try {
        const registrations = await navigator.serviceWorker.getRegistrations();
        if (registrations.length > 0) {
          await Promise.all(
            registrations.map((registration) => registration.unregister()),
          );
          log('Unregistered legacy service workers.', registrations.length);
        }
      } catch (error) {
        warn('Unable to unregister legacy service workers.', error);
      }
    }

    if ('caches' in window) {
      try {
        const cacheKeys = await caches.keys();
        if (cacheKeys.length > 0) {
          await Promise.all(cacheKeys.map((key) => caches.delete(key)));
          log('Deleted legacy browser caches.', cacheKeys.length);
        }
      } catch (error) {
        warn('Unable to clear legacy browser caches.', error);
      }
    }
  }

  async function fetchServerBuild() {
    try {
      const response = await fetch(versionUrl, {
        cache: 'no-store',
        headers: {
          'cache-control': 'no-cache',
        },
      });
      if (!response.ok) {
        log('Version fetch returned non-OK response.', response.status);
        return null;
      }
      const payload = await response.json();
      return typeof payload.build === 'string' && payload.build.length > 0
        ? payload.build
        : null;
    } catch (error) {
      warn('Unable to fetch version.json.', error);
      return null;
    }
  }

  async function maybeReloadForBuildMismatch() {
    const serverBuild = await fetchServerBuild();
    log('Bootstrap build state.', `current=${currentBuild} server=${serverBuild ?? 'unknown'}`);
    if (!serverBuild || serverBuild === currentBuild) {
      safeLocalStorage.set(buildKey, currentBuild);
      return false;
    }

    const reloadKey = `${reloadKeyPrefix}${serverBuild}`;
    if (safeSessionStorage.get(reloadKey) === '1') {
      warn('Build mismatch remained after one forced reload.', serverBuild);
      safeLocalStorage.set(buildKey, serverBuild);
      return false;
    }

    safeSessionStorage.set(reloadKey, '1');
    safeLocalStorage.set(buildKey, serverBuild);
    await clearLegacyFlutterState(`build-mismatch:${currentBuild}->${serverBuild}`);
    window.location.reload();
    return true;
  }

  async function ensureLegacyCleanupRanOnce() {
    if (safeSessionStorage.get(cleanupKey) === currentBuild) {
      return;
    }
    await clearLegacyFlutterState(`session-cleanup:${currentBuild}`);
    safeSessionStorage.set(cleanupKey, currentBuild);
  }

  async function refreshApp() {
    safeSessionStorage.remove(cleanupKey);
    await clearLegacyFlutterState('manual-refresh');
    window.location.reload();
  }

  async function clearSavedAppData() {
    safeLocalStorage.clear();
    safeSessionStorage.clear();
    await clearLegacyFlutterState('manual-clear');
    window.location.reload();
  }

  window.barVarianceRecovery = {
    refreshApp,
    clearSavedAppData,
    diagnostics: buildDiagnostics,
  };

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', (event) => {
      if (event.data && event.data.type === 'legacy-sw-cleaned') {
        log('Legacy Flutter service worker cleaned itself up.');
      }
    });
  }

  async function startFlutter() {
    await ensureLegacyCleanupRanOnce();
    const reloaded = await maybeReloadForBuildMismatch();
    if (reloaded) {
      return;
    }

    await _flutter.loader.load({
      serviceWorkerSettings: null,
    });
    log('Flutter loader started.', currentBuild);
  }

  startFlutter().catch((error) => {
    warn('Flutter bootstrap failed.', error);
    throw error;
  });
})();

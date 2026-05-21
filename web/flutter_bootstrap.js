{{flutter_js}}
{{flutter_build_config}}

(function () {
  const currentBuild = '__APP_BUILD__';
  const currentBuildTime = '__APP_BUILD_TIME__';
  const currentVersionLabel = '__APP_VERSION_LABEL__';
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

  function createSafeStorage(getter) {
    function resolveStorage() {
      try {
        return getter();
      } catch (_) {
        return null;
      }
    }

    return {
      get(key) {
        const storage = resolveStorage();
        if (!storage) {
          return null;
        }
        try {
          return storage.getItem(key);
        } catch (_) {
          return null;
        }
      },
      set(key, value) {
        const storage = resolveStorage();
        if (!storage) {
          return;
        }
        try {
          storage.setItem(key, value);
        } catch (_) {}
      },
      remove(key) {
        const storage = resolveStorage();
        if (!storage) {
          return;
        }
        try {
          storage.removeItem(key);
        } catch (_) {}
      },
      clear() {
        const storage = resolveStorage();
        if (!storage) {
          return;
        }
        try {
          storage.clear();
        } catch (_) {}
      },
    };
  }

  const safeLocalStorage = createSafeStorage(() => window.localStorage);
  const safeSessionStorage = createSafeStorage(() => window.sessionStorage);

  function diagnosticsText() {
    return [
      `build=${currentBuild}`,
      `buildTime=${currentBuildTime}`,
      `version=${currentVersionLabel}`,
      `url=${window.location.href}`,
      `online=${navigator.onLine}`,
      `userAgent=${navigator.userAgent}`,
      `viewport=${window.innerWidth}x${window.innerHeight}`,
      `serviceWorker=${'serviceWorker' in navigator}`,
      `cacheStorage=${'caches' in window}`,
      ...diagnostics,
    ].join('\n');
  }

  function withBuildQuery(buildLabel) {
    const url = new URL(window.location.href);
    url.searchParams.set('_appBuild', buildLabel);
    return url.toString();
  }

  function showBootstrapFailure(message) {
    document.body.innerHTML = `
      <main style="min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;background:#f6f1e7;color:#1f2933;font-family:Manrope,Arial,sans-serif;">
        <section style="max-width:560px;width:100%;background:#fff;border-radius:24px;padding:28px;box-shadow:0 24px 60px rgba(15,23,42,0.12);">
          <h1 style="margin:0 0 12px;font-size:28px;line-height:1.1;">We couldn't load the latest app update</h1>
          <p style="margin:0 0 18px;font-size:16px;line-height:1.6;">${message}</p>
          <p style="margin:0 0 18px;font-size:14px;line-height:1.6;color:#52606d;">Try refreshing the app. If it still does not open, copy the diagnostics and share them with your admin or support contact.</p>
          <div style="display:flex;flex-wrap:wrap;gap:12px;">
            <button id="bootstrap-refresh" style="border:0;border-radius:999px;padding:12px 18px;background:#0f766e;color:#fff;font-size:14px;cursor:pointer;">Refresh app</button>
            <button id="bootstrap-reset" style="border:1px solid #cbd2d9;border-radius:999px;padding:12px 18px;background:#fff;color:#1f2933;font-size:14px;cursor:pointer;">Clear saved app data</button>
            <button id="bootstrap-copy" style="border:1px solid #cbd2d9;border-radius:999px;padding:12px 18px;background:#fff;color:#1f2933;font-size:14px;cursor:pointer;">Copy diagnostics</button>
          </div>
          <p style="margin:18px 0 0;font-size:12px;color:#7b8794;">Build ${currentBuild}</p>
          <p style="margin:6px 0 0;font-size:12px;color:#7b8794;">${currentBuildTime} • ${currentVersionLabel}</p>
        </section>
      </main>
    `;

    document.getElementById('bootstrap-refresh')?.addEventListener('click', () => {
      refreshApp();
    });
    document.getElementById('bootstrap-reset')?.addEventListener('click', () => {
      clearSavedAppData();
    });
    document.getElementById('bootstrap-copy')?.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(diagnosticsText());
      } catch (_) {}
    });
  }

  async function clearLegacyFlutterState(reason) {
    log('Clearing legacy Flutter state.', reason);

    if ('serviceWorker' in navigator) {
      try {
        const registrations = await navigator.serviceWorker.getRegistrations();
        if (registrations.length > 0) {
          await Promise.all(registrations.map((registration) => registration.unregister()));
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

  async function navigateToFreshShell(targetBuild, reason) {
    await clearLegacyFlutterState(reason);
    window.location.replace(withBuildQuery(targetBuild));
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
      warn('Build mismatch remained after one forced refresh.', serverBuild);
      safeLocalStorage.set(buildKey, serverBuild);
      return false;
    }

    safeSessionStorage.set(reloadKey, '1');
    safeLocalStorage.set(buildKey, serverBuild);
    await navigateToFreshShell(serverBuild, `build-mismatch:${currentBuild}->${serverBuild}`);
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
    await navigateToFreshShell(currentBuild, 'manual-refresh');
  }

  async function clearSavedAppData() {
    safeLocalStorage.clear();
    safeSessionStorage.clear();
    await navigateToFreshShell(`${currentBuild}-${Date.now()}`, 'manual-clear');
  }

  window.barVarianceRecovery = {
    refreshApp,
    clearSavedAppData,
    diagnostics: diagnosticsText,
  };

  log('Build marker.', `${currentBuild} ${currentBuildTime} ${currentVersionLabel}`);

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
    showBootstrapFailure(
      'The latest app files could not be loaded just now. Try a refresh so the newest build can be picked up.',
    );
  });
})();

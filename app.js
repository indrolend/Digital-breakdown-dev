(() => {
  "use strict";

  const config = window.DIGITAL_BREAKDOWN_DEV_CONFIG;
  if (!config) {
    document.body.innerHTML = "<pre>Missing config.js</pre>";
    return;
  }

  const $ = (id) => document.getElementById(id);
  const setHref = (id, href) => { const el = $(id); if (el) el.href = href; };

  function formatBytes(value) {
    if (!Number.isFinite(value) || value <= 0) return "--";
    const units = ["B", "KB", "MB", "GB"];
    let size = value;
    let unit = 0;
    while (size >= 1024 && unit < units.length - 1) { size /= 1024; unit += 1; }
    return `${size.toFixed(unit < 2 ? 0 : 1)} ${units[unit]}`;
  }

  function updateNetworkState() {
    const online = navigator.onLine;
    $("network-label").textContent = online ? "ONLINE" : "OFFLINE";
    $("network-dot").classList.toggle("offline", !online);
  }

  function updateClock() {
    $("clock").textContent = new Date().toLocaleTimeString([], {
      hour: "2-digit", minute: "2-digit", second: "2-digit"
    });
  }

  function describeDevice() {
    const ua = navigator.userAgent;
    if (/Android/i.test(ua)) {
      $("device-note").textContent = "Android detected. Download the latest APK, then open it to update.";
      $("download-android").classList.add("device-primary");
    } else if (/iPad|iPhone|iPod/i.test(ua)) {
      $("device-note").textContent = "Use PLAY WEB, then Add to Home Screen for app-like access.";
      $("play-web").classList.add("device-primary");
    } else {
      $("device-note").textContent = "Play in the browser or download the current Android APK.";
    }
  }

  function setAvailability(id, available) {
    const el = $(id);
    if (!el) return;
    el.classList.toggle("unavailable", !available);
    el.setAttribute("aria-disabled", available ? "false" : "true");
  }

  async function loadManifest() {
    $("manifest-status").textContent = "CHECKING";
    try {
      const response = await fetch(`${config.manifestUrl}?t=${Date.now()}`, { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const manifest = await response.json();
      const published = Boolean(manifest.commit);
      const androidAvailable = Boolean(manifest.android?.available);
      const webAvailable = Boolean(manifest.web?.available);

      $("source-commit").textContent = manifest.shortCommit || manifest.commit?.slice(0, 7) || "--";
      $("branch-name").textContent = manifest.branch || config.authoritativeBranch;
      $("built-at").textContent = manifest.builtAt ? new Date(manifest.builtAt).toLocaleString() : "--";
      $("android-size").textContent = formatBytes(manifest.android?.size);
      $("web-size").textContent = formatBytes(manifest.web?.size);
      $("research-size").textContent = formatBytes(manifest.research?.size);
      setAvailability("download-android", androidAvailable);
      setAvailability("play-web", webAvailable);

      if (manifest.shortCommit) {
        $("android-detail").textContent = `APK · ${manifest.shortCommit}`;
        $("web-detail").textContent = `ZIP · ${manifest.shortCommit}`;
        $("research-detail").textContent = `ZIP · ${manifest.shortCommit}`;
        $("play-detail").textContent = `PUBLISHED ${manifest.shortCommit}`;
      }
      $("manifest-status").textContent = published ? "CURRENT" : "NOT PUBLISHED";
    } catch (error) {
      $("manifest-status").textContent = "UNAVAILABLE";
      console.warn("Build manifest unavailable:", error);
    }
    $("last-refresh").textContent = new Date().toLocaleString();
  }

  const portProgress = Math.max(0, Math.min(100, Number(config.nativePortProgress) || 0));
  $("port-progress-label").textContent = `${portProgress}%`;
  $("port-progress-bar").style.width = `${portProgress}%`;

  setHref("play-web", config.playWebUrl);
  setHref("download-android", config.downloads.android);
  setHref("download-web", config.downloads.web);
  setHref("download-research", config.downloads.research);
  setHref("game-repo", config.urls.repository);
  setHref("publish-latest", config.urls.publishPortal);
  setHref("build-native", config.urls.nativeAndroid);
  setHref("releases", config.urls.releases);
  setHref("commits", config.urls.commits);

  $("branch-name").textContent = config.authoritativeBranch;
  $("control-version").textContent = config.controlVersion;
  window.addEventListener("online", updateNetworkState);
  window.addEventListener("offline", updateNetworkState);

  describeDevice();
  updateNetworkState();
  updateClock();
  loadManifest();
  setInterval(updateClock, 1000);
  setInterval(loadManifest, 30000);

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => navigator.serviceWorker.register("./service-worker.js").catch(() => {}));
  }
})();

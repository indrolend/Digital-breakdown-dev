(() => {
  "use strict";

  const config = window.DIGITAL_BREAKDOWN_DEV_CONFIG;
  if (!config) {
    document.body.innerHTML = "<pre>Missing config.js</pre>";
    return;
  }

  const $ = (id) => document.getElementById(id);

  function setHref(id, href) {
    const element = $(id);
    if (element) element.href = href;
  }

  function formatBytes(value) {
    if (!Number.isFinite(value) || value <= 0) return "--";
    const units = ["B", "KB", "MB", "GB"];
    let size = value;
    let unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    return `${size.toFixed(unit < 2 ? 0 : 1)} ${units[unit]}`;
  }

  function updateNetworkState() {
    const online = navigator.onLine;
    $("network-label").textContent = online ? "ONLINE" : "OFFLINE";
    $("network-dot").classList.toggle("offline", !online);
  }

  function updateClock() {
    $("clock").textContent = new Date().toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit"
    });
  }

  function describeDevice() {
    const ua = navigator.userAgent;
    const note = $("device-note");
    if (/Android/i.test(ua)) {
      note.textContent = "Android detected. The APK download is prioritized for direct installation.";
      $("download-android").classList.add("device-primary");
    } else if (/iPad|iPhone|iPod/i.test(ua)) {
      note.textContent = "iPhone or iPad detected. Use PLAY WEB, then Add to Home Screen for app-like access.";
      $("play-web").classList.add("device-primary");
    } else if (/Windows/i.test(ua)) {
      note.textContent = "Windows detected. Use PLAY WEB now; downloadable desktop builds can be added later.";
    } else if (/Macintosh|Mac OS X/i.test(ua)) {
      note.textContent = "macOS detected. Use PLAY WEB now; downloadable macOS builds can be added later.";
    } else {
      note.textContent = "All published formats are shown for this device.";
    }
  }

  async function loadManifest() {
    $("manifest-status").textContent = "LOADING";
    try {
      const response = await fetch(`${config.manifestUrl}?t=${Date.now()}`, { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const manifest = await response.json();

      $("source-commit").textContent = manifest.shortCommit || manifest.commit?.slice(0, 7) || "--";
      $("branch-name").textContent = manifest.branch || config.authoritativeBranch;
      $("built-at").textContent = manifest.builtAt
        ? new Date(manifest.builtAt).toLocaleString()
        : "--";
      $("android-size").textContent = formatBytes(manifest.android?.size);
      $("web-size").textContent = formatBytes(manifest.web?.size);
      $("research-size").textContent = formatBytes(manifest.research?.size);

      if (manifest.shortCommit) {
        $("android-detail").textContent = `APK · ${manifest.shortCommit}`;
        $("web-detail").textContent = `ZIP · ${manifest.shortCommit}`;
        $("research-detail").textContent = `ZIP · ${manifest.shortCommit}`;
        $("play-detail").textContent = `PUBLISHED ${manifest.shortCommit}`;
      }

      $("manifest-status").textContent = "CURRENT";
    } catch (error) {
      $("manifest-status").textContent = "NOT PUBLISHED";
      $("built-at").textContent = "Run BUILD + PUBLISH LATEST";
      console.warn("Build manifest unavailable:", error);
    }
  }

  async function refreshPanel() {
    $("last-refresh").textContent = new Date().toLocaleString();
    updateNetworkState();
    await loadManifest();
  }

  setHref("play-web", config.playWebUrl);
  setHref("download-android", config.downloads.android);
  setHref("download-web", config.downloads.web);
  setHref("download-research", config.downloads.research);
  setHref("game-repo", config.urls.repository);
  setHref("publish-latest", config.urls.publishPortal);
  setHref("build-native", config.urls.nativeAndroid);
  setHref("build-research", config.urls.researchPacket);
  setHref("releases", config.urls.releases);
  setHref("commits", config.urls.commits);

  $("branch-name").textContent = config.authoritativeBranch;
  $("control-version").textContent = config.controlVersion;
  $("refresh").addEventListener("click", refreshPanel);

  window.addEventListener("online", updateNetworkState);
  window.addEventListener("offline", updateNetworkState);

  describeDevice();
  updateClock();
  refreshPanel();
  setInterval(updateClock, 1000);

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => {
      navigator.serviceWorker.register("./service-worker.js").catch(() => {});
    });
  }
})();
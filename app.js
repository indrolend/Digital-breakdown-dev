(() => {
  "use strict";

  const config = window.DIGITAL_BREAKDOWN_DEV_CONFIG;
  if (!config) { document.body.innerHTML = "<pre>Missing config.js</pre>"; return; }

  const $ = (id) => document.getElementById(id);
  const setHref = (id, href) => { const el = $(id); if (el) el.href = href; };
  let currentManifest = null;

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
    $("clock").textContent = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  }

  function describeDevice() {
    const ua = navigator.userAgent;
    if (/Android/i.test(ua)) {
      $("device-note").textContent = "Android detected. The APK and native WebAssembly build are produced from the same C++ commit.";
      $("download-android").classList.add("device-primary");
    } else {
      $("device-note").textContent = "PLAY NATIVE WEB runs the Android-equivalent C++ runtime. PLAY JS REFERENCE opens the behavioral source of truth.";
      $("play-web").classList.add("device-primary");
    }
  }

  function setAvailability(id, available) {
    const el = $(id);
    if (!el) return;
    el.classList.toggle("unavailable", !available);
    el.setAttribute("aria-disabled", available ? "false" : "true");
  }

  function exactSourceUrl(manifest) {
    if (manifest?.sourceCommitUrl) return manifest.sourceCommitUrl;
    if (manifest?.commit) return `${config.urls.repository}/commit/${manifest.commit}`;
    return config.urls.repository;
  }

  function applyManifest(manifest) {
    currentManifest = manifest;
    const published = Boolean(manifest.commit);
    const androidAvailable = Boolean(manifest.android?.available);
    const webAvailable = Boolean(manifest.web?.available);
    const referenceAvailable = Boolean(manifest.reference?.available);

    $("source-commit").textContent = manifest.shortCommit || manifest.commit?.slice(0, 7) || "--";
    $("branch-name").textContent = manifest.branch || config.authoritativeBranch;
    $("built-at").textContent = manifest.builtAt ? new Date(manifest.builtAt).toLocaleString() : "--";
    $("android-size").textContent = formatBytes(manifest.android?.size);
    $("web-size").textContent = formatBytes(manifest.web?.size);
    $("research-size").textContent = formatBytes(manifest.research?.size);
    $("run-id").textContent = manifest.runId ? String(manifest.runId) : "--";
    $("source-message").textContent = manifest.sourceMessage || (published ? "Published build metadata loaded." : "No build has been published yet.");

    setAvailability("download-android", androidAvailable);
    setAvailability("play-web", webAvailable);
    setAvailability("download-web", webAvailable);
    setAvailability("play-reference", referenceAvailable);
    setAvailability("download-reference", referenceAvailable);

    if (manifest.shortCommit) {
      $("android-detail").textContent = `APK · ${manifest.shortCommit}`;
      $("web-detail").textContent = `WASM ZIP · ${manifest.shortCommit}`;
      $("research-detail").textContent = `ZIP · ${manifest.shortCommit}`;
      $("play-detail").textContent = `NATIVE C++ · ${manifest.shortCommit}`;
      $("reference-detail").textContent = `JAVASCRIPT REFERENCE · ${manifest.shortCommit}`;
      $("source-detail").textContent = manifest.shortCommit;
      $("copy-detail").textContent = manifest.shortCommit;
    }

    setHref("open-source-commit", exactSourceUrl(manifest));
    $("manifest-status").textContent = published ? "PUBLISHED" : "NOT PUBLISHED";
  }

  async function loadManifest() {
    $("manifest-status").textContent = "CHECKING";
    try {
      const response = await fetch(`${config.manifestUrl}?t=${Date.now()}`, { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      applyManifest(await response.json());
    } catch (error) {
      $("manifest-status").textContent = "UNAVAILABLE";
      $("source-message").textContent = "Published build metadata could not be loaded.";
      console.warn("Build manifest unavailable:", error);
    }
    $("last-refresh").textContent = new Date().toLocaleString();
  }

  async function copyBuildId(event) {
    event.preventDefault();
    const value = currentManifest?.commit;
    if (!value) { $("copy-detail").textContent = "NO BUILD"; return; }
    try {
      await navigator.clipboard.writeText(value);
      $("copy-detail").textContent = "COPIED";
      setTimeout(() => { $("copy-detail").textContent = currentManifest?.shortCommit || value.slice(0, 7); }, 1200);
    } catch { window.prompt("Build commit SHA", value); }
  }

  setHref("play-web", config.playWebUrl);
  setHref("play-reference", config.referenceWebUrl);
  setHref("download-android", config.downloads.android);
  setHref("download-web", config.downloads.web);
  setHref("download-reference", config.downloads.reference);
  setHref("download-research", config.downloads.research);
  setHref("game-repo", config.urls.repository);
  setHref("publish-latest", config.urls.publishPortal);
  setHref("build-native", config.urls.nativeAndroid);
  setHref("releases", config.urls.releases);
  setHref("commits", config.urls.commits);
  setHref("open-source-commit", config.urls.repository);

  $("copy-build-id").addEventListener("click", copyBuildId);
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

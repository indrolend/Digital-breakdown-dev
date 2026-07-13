(() => {
  "use strict";

  const config = window.DIGITAL_BREAKDOWN_DEV_CONFIG;
  if (!config) { document.body.innerHTML = "<pre>Missing config.js</pre>"; return; }

  const $ = (id) => document.getElementById(id);
  const setHref = (id, href) => { const el = $(id); if (el) el.href = href; };

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
    const published = Boolean(manifest.commit);
    const shortCommit = manifest.shortCommit || manifest.commit?.slice(0, 7) || "--";

    $("source-commit").textContent = shortCommit;
    $("built-at").textContent = manifest.builtAt
      ? new Date(manifest.builtAt).toLocaleString([], { dateStyle: "short", timeStyle: "short" })
      : "--";
    $("manifest-status").textContent = published ? "READY" : "UNAVAILABLE";
    $("source-message").textContent = published
      ? `Android and native web are published from ${shortCommit}.`
      : "No completed native build is currently available.";

    const androidAvailable = Boolean(manifest.android?.available);
    const webAvailable = Boolean(manifest.web?.available);
    const referenceAvailable = Boolean(manifest.reference?.available);

    setAvailability("download-android", androidAvailable);
    setAvailability("play-web", webAvailable);
    setAvailability("download-web", webAvailable);
    setAvailability("play-reference", referenceAvailable);
    setAvailability("download-reference", referenceAvailable);

    if (published) {
      $("android-detail").textContent = `Android · ${shortCommit}`;
      $("play-detail").textContent = `Native C++ · ${shortCommit}`;
      $("reference-detail").textContent = "JavaScript behavior reference";
    }

    setHref("open-source-commit", exactSourceUrl(manifest));
  }

  async function loadManifest() {
    $("manifest-status").textContent = "CHECKING";
    try {
      const response = await fetch(`${config.manifestUrl}?t=${Date.now()}`, { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      applyManifest(await response.json());
    } catch (error) {
      $("manifest-status").textContent = "OFFLINE";
      $("source-message").textContent = "Could not read the published build status.";
      console.warn("Build manifest unavailable:", error);
    }
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
  setHref("open-source-commit", config.urls.repository);

  window.addEventListener("online", updateNetworkState);
  window.addEventListener("offline", updateNetworkState);
  updateNetworkState();
  updateClock();
  loadManifest();
  setInterval(updateClock, 1000);
  setInterval(loadManifest, 30000);
})();

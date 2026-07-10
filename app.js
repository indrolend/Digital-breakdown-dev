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

  function refreshPanel() {
    $("last-refresh").textContent = new Date().toLocaleString();
    updateNetworkState();
  }

  setHref("play-web", config.playWebUrl);
  setHref("game-repo", config.urls.repository);
  setHref("latest-actions", config.urls.actions);
  setHref("build-native", config.urls.nativeAndroid);
  setHref("build-webview", config.urls.webviewAndroid);
  setHref("build-research", config.urls.researchPacket);
  setHref("workflow-runs", config.urls.actions);
  setHref("releases", config.urls.releases);
  setHref("commits", config.urls.commits);

  $("repo-name").textContent = `${config.owner}/${config.gameRepository}`;
  $("branch-name").textContent = config.authoritativeBranch;
  $("control-version").textContent = config.controlVersion;
  $("refresh").addEventListener("click", refreshPanel);

  window.addEventListener("online", updateNetworkState);
  window.addEventListener("offline", updateNetworkState);

  updateClock();
  refreshPanel();
  setInterval(updateClock, 1000);

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => {
      navigator.serviceWorker.register("./service-worker.js").catch(() => {});
    });
  }
})();

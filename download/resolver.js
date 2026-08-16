(() => {
  "use strict";

  const script = document.currentScript;
  const manifestUrl = new URL(script.dataset.manifest, window.location.href);
  const requestedPlatform = document.body.dataset.platform || "";
  const status = document.getElementById("status");

  const platformOrder = () => {
    const value = `${navigator.userAgentData?.platform || ""} ${navigator.platform || ""} ${navigator.userAgent || ""}`.toLowerCase();
    if (value.includes("android")) return "android-armeabi-v7a";
    if (value.includes("mac")) return "macos-universal";
    return "windows-x64";
  };

  const label = (key) => ({
    "windows-x64": "Windows x64",
    "android-armeabi-v7a": "Android",
    "macos-universal": "macOS universal"
  })[key] || key;

  function validate(manifest, key) {
    if (manifest?.schemaVersion !== 3 || manifest?.project?.id !== "indrolend/data" || manifest?.channel !== "latest-native") {
      throw new Error("The canonical manifest identity is invalid.");
    }
    if (!/^[0-9a-f]{40}$/i.test(manifest.commit) || /^0+$/.test(manifest.commit)) {
      throw new Error("The canonical manifest provenance is invalid.");
    }
    const artifact = manifest.artifacts?.[key];
    if (!artifact?.available || !artifact.url || !/^[0-9a-f]{64}$/i.test(artifact.sha256)) {
      throw new Error(`${label(key)} is not available in the canonical release.`);
    }
    if (key === "windows-x64" && artifact.portable !== true) {
      throw new Error("The Windows release is not verified portable.");
    }
    return artifact;
  }

  async function resolve() {
    const response = await fetch(`${manifestUrl.href}?t=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`Manifest request failed with HTTP ${response.status}.`);
    const manifest = await response.json();

    document.querySelectorAll("[data-platform-link]").forEach((anchor) => {
      const key = anchor.dataset.platformLink;
      const artifact = validate(manifest, key);
      anchor.querySelector("small").textContent = `${manifest.shortCommit} · SHA-256 ${artifact.sha256.slice(0, 12)}…`;
    });

    if (requestedPlatform) {
      const artifact = validate(manifest, requestedPlatform);
      status.textContent = `Verified ${label(requestedPlatform)} · ${manifest.shortCommit} · redirecting to ${artifact.filename}`;
      window.location.replace(artifact.url);
      return;
    }

    const recommended = platformOrder();
    const link = document.querySelector(`[data-platform-link="${recommended}"]`);
    if (link) {
      link.querySelector("strong").textContent += " · RECOMMENDED";
      link.focus({ preventScroll: true });
    }
    status.textContent = `Canonical latest-native · ${manifest.shortCommit} · run ${manifest.runId}`;
  }

  resolve().catch((error) => {
    status.textContent = error.message;
    status.classList.add("error");
  });
})();

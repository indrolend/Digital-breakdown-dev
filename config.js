window.DIGITAL_BREAKDOWN_DEV_CONFIG = Object.freeze({
  controlVersion: "0.3.0",
  nativePortProgress: 28,
  owner: "indrolend",
  gameRepository: "digital-breakdown-apk",
  portalRepository: "Digital-breakdown-dev",
  authoritativeBranch: "main",

  playWebUrl: "./play/",
  manifestUrl: "./build-info.json",

  downloads: {
    android: "https://github.com/indrolend/Digital-breakdown-dev/releases/download/latest-dev/DigitalBreakdown-Android.apk",
    web: "https://github.com/indrolend/Digital-breakdown-dev/releases/download/latest-dev/DigitalBreakdown-Web.zip",
    research: "https://github.com/indrolend/Digital-breakdown-dev/releases/download/latest-dev/DigitalBreakdown-Research.zip"
  },

  urls: {
    repository: "https://github.com/indrolend/digital-breakdown-apk",
    portalRepository: "https://github.com/indrolend/Digital-breakdown-dev",
    actions: "https://github.com/indrolend/digital-breakdown-apk/actions",
    publishPortal: "https://github.com/indrolend/digital-breakdown-apk/actions/workflows/publish-dev-portal.yml",
    nativeAndroid: "https://github.com/indrolend/digital-breakdown-apk/actions/workflows/native-android.yml",
    webviewAndroid: "https://github.com/indrolend/digital-breakdown-apk/actions/workflows/android-apk.yml",
    researchPacket: "https://github.com/indrolend/digital-breakdown-apk/actions/workflows/research-packet.yml",
    releases: "https://github.com/indrolend/Digital-breakdown-dev/releases/tag/latest-dev",
    commits: "https://github.com/indrolend/digital-breakdown-apk/commits/main"
  }
});
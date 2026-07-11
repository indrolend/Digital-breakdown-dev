const START_MS = performance.now();

const state = {
  enabled: true,
  frameCount: 0,
  lastReportMs: START_MS,
  lastFrameMs: START_MS,
  fps: 0,
  avgFrameMs: 0,
  worstFrameMs: 0,
  firstFrameLogged: false,
  firstInputLogged: false
};

function nowMs() {
  return performance.now();
}

function sinceStart() {
  return Math.round(nowMs() - START_MS);
}

function emit(event, fields = {}) {
  if (!state.enabled) return;

  const parts = [`[DBTEL]`, `t=${sinceStart()}`, `event=${event}`];

  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined || value === null || value === "") continue;
    parts.push(`${key}=${String(value).replace(/\s+/g, "_")}`);
  }

  console.log(parts.join(" "));
}

function mark(event, fields = {}) {
  emit(event, fields);
}

function error(event, err, fields = {}) {
  emit(event, {
    ...fields,
    error: err && err.message ? err.message : String(err),
    name: err && err.name ? err.name : undefined
  });
}

function frame(fields = {}) {
  const now = nowMs();
  const dt = now - state.lastFrameMs;
  state.lastFrameMs = now;

  state.frameCount += 1;
  state.worstFrameMs = Math.max(state.worstFrameMs, dt);

  if (!state.firstFrameLogged) {
    state.firstFrameLogged = true;
    emit("first_frame", { frame_ms: Math.round(dt), ...fields });
  }

  const elapsed = now - state.lastReportMs;
  if (elapsed >= 3000) {
    state.fps = Math.round((state.frameCount * 1000) / elapsed);
    state.avgFrameMs = Math.round(elapsed / Math.max(1, state.frameCount));

    const memory = performance.memory;
    const used_mb = memory && memory.usedJSHeapSize
      ? Math.round(memory.usedJSHeapSize / 1024 / 1024)
      : undefined;

    emit("perf", {
      fps: state.fps,
      avg_ms: state.avgFrameMs,
      worst_ms: Math.round(state.worstFrameMs),
      heap_mb: used_mb,
      ...fields
    });

    state.frameCount = 0;
    state.lastReportMs = now;
    state.worstFrameMs = 0;
  }
}

function startHeartbeat() {
  let last = performance.now();
  let frames = 0;
  let worst = 0;
  let first = false;
  let reportStart = performance.now();

  function tick() {
    const now = performance.now();
    const dt = now - last;
    last = now;
    frames += 1;
    worst = Math.max(worst, dt);

    if (!first) {
      first = true;
      emit("first_frame", { source: "heartbeat", frame_ms: Math.round(dt) });
    }

    if (now - reportStart >= 3000 && frames > 0) {
      const elapsed = now - reportStart;
      const fps = Math.round((frames * 1000) / elapsed);
      const avg = Math.round(elapsed / frames);

      emit("perf", {
        source: "heartbeat",
        fps,
        avg_ms: avg,
        worst_ms: Math.round(worst)
      });

      frames = 0;
      worst = 0;
      reportStart = now;
    }

    requestAnimationFrame(tick);
  }

  requestAnimationFrame(tick);
}

function bindInputMarkers() {
  const onInput = (type) => {
    if (state.firstInputLogged) return;
    state.firstInputLogged = true;
    emit("first_input", { type });
  };

  window.addEventListener("pointerdown", () => onInput("pointerdown"), { once: true, passive: true });
  window.addEventListener("touchstart", () => onInput("touchstart"), { once: true, passive: true });
  window.addEventListener("keydown", () => onInput("keydown"), { once: true, passive: true });
}

function installGlobalErrorHandlers() {
  window.addEventListener("error", (ev) => {
    error("window_error", ev.error || ev.message, {
      file: ev.filename,
      line: ev.lineno,
      col: ev.colno
    });
  });

  window.addEventListener("unhandledrejection", (ev) => {
    error("unhandled_rejection", ev.reason);
  });

  window.addEventListener("webglcontextlost", () => {
    emit("webgl_context_lost");
  }, true);

  window.addEventListener("webglcontextrestored", () => {
    emit("webgl_context_restored");
  }, true);
}

function init() {
  emit("boot", {
    href: location.pathname || "/",
    ua: navigator.userAgent.includes("Android") ? "android" : "browser"
  });

  installGlobalErrorHandlers();
  bindInputMarkers();
  startHeartbeat();

  document.addEventListener("visibilitychange", () => {
    emit("visibility", { state: document.visibilityState });
  });
}

export const MobileTelemetry = {
  init,
  mark,
  frame,
  error,
  emit
};

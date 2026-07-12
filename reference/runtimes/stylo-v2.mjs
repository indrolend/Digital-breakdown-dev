import { MobileTelemetry } from "../mobile-telemetry.mjs";
MobileTelemetry.mark("runtime_loaded", { runtime: "stylo-v2" });
﻿import * as THREE from "three";

window.__ANDROID_LOW_POWER_MODE__ = true;
window.__ANDROID_ULTRA_LOW_MODE__ = true;
window.__DISABLE_HEAVY_FBX__ = true;
window.__DISABLE_DATAMOSH__ = true;
window.__DISABLE_MOBILE_AUDIO_PRELOAD__ = true;
window.__ANDROID_PIXEL_RATIO_CAP__ = 0.38;

console.log("[STYLO-V2] boot");

const ROOM_WIDTH = 30;
const ROOM_DEPTH = 42;
const ROOM_WALL_HEIGHT = 7.2;

const ROOM_REQUIRED_SOULS = 5;
const ACTIVE_TARGETS = 5;
const MAX_STORED_SOULS = 5;

const WALK_SPEED = 7.0;
const SPRINT_SPEED = 11.5;
const ACCEL = 34.0;
const AIR_ACCEL = 13.0;
const FRICTION = 13.0;
const GRAVITY = 24.0;
const JUMP_SPEED = 9.2;

const BATTERY_MAX = 100;
const BATTERY_IDLE_REGEN = 22.0;
const BATTERY_ACTIVE_REGEN = 3.0;
const BATTERY_WALK_DRAIN = 0.45;
const BATTERY_SPRINT_DRAIN = 3.0;
const BATTERY_AIR_DRAIN = 0.9;
const BATTERY_VACUUM_DRAIN = 1.35;
const BATTERY_JUMP_COST = 4.5;
const BATTERY_CAPTURE_GAIN = 6.0;

const VACUUM_RANGE = 6.0;
const VACUUM_LATCH_RADIUS = 1.0;
const VACUUM_PULL = 14.0;
const VACUUM_CAPTURE_TIME = 0.55;
const VACUUM_MOVE_MULT = 0.35;

const CAPTURE_RADIUS = 1.75;

let renderer;
let scene;
let camera;
let clock;

let hud;
let errorBox;

let lastFpsTime = performance.now();
let frames = 0;
let fps = 0;

const input = {
  forward: false,
  back: false,
  left: false,
  right: false,
  sprint: false,
  jumpPressed: false,
  jumpHeld: false,
  vacuum: false,
  lookX: 0,
  lookY: 0,
  last: "none"
};

const player = {
  pos: new THREE.Vector3(0, 0.55, 12),
  vel: new THREE.Vector3(),
  yaw: Math.PI,
  targetYaw: Math.PI,
  grounded: true,
  battery: BATTERY_MAX,
  souls: 0,
  alive: true
};

const cameraRig = {
  yaw: Math.PI,
  pitch: 0.42,
  targetPitch: 0.42,
  distance: 8.2,
  height: 2.2,
  pos: new THREE.Vector3()
};

const targets = [];
const captures = [];
const bullets = [];

let roomIndex = 1;
let roomClear = false;
let mouseDragging = false;
let mouseLastX = 0;
let mouseLastY = 0;

function showError(msg) {
  console.log("[STYLO-V2-ERROR]", msg);
  if (errorBox) {
    errorBox.style.display = "block";
    errorBox.textContent = "ERROR\n" + msg;
  }
}

window.addEventListener("error", function (e) {
  showError((e.message || "runtime error") + " @ " + (e.filename || "") + ":" + (e.lineno || ""));
});

window.addEventListener("unhandledrejection", function (e) {
  const reason = e.reason && (e.reason.stack || e.reason.message || String(e.reason));
  showError(reason || "unhandled promise rejection");
});

function makeHud() {
  document.body.innerHTML = "";

  const root = document.createElement("div");
  root.style.position = "fixed";
  root.style.left = "0";
  root.style.top = "0";
  root.style.right = "0";
  root.style.bottom = "0";
  root.style.margin = "0";
  root.style.overflow = "hidden";
  root.style.background = "#020402";
  document.body.appendChild(root);

  hud = document.createElement("div");
  hud.style.position = "fixed";
  hud.style.left = "10px";
  hud.style.top = "8px";
  hud.style.zIndex = "5";
  hud.style.fontFamily = "monospace";
  hud.style.fontSize = "12px";
  hud.style.lineHeight = "15px";
  hud.style.color = "#8cff9b";
  hud.style.background = "rgba(0,0,0,0.45)";
  hud.style.padding = "8px";
  hud.style.whiteSpace = "pre";
  hud.textContent = "STYLO V2";
  document.body.appendChild(hud);

  errorBox = document.createElement("div");
  errorBox.style.position = "fixed";
  errorBox.style.left = "12px";
  errorBox.style.right = "12px";
  errorBox.style.bottom = "12px";
  errorBox.style.zIndex = "10";
  errorBox.style.display = "none";
  errorBox.style.fontFamily = "monospace";
  errorBox.style.fontSize = "13px";
  errorBox.style.whiteSpace = "pre-wrap";
  errorBox.style.color = "#ffb0b0";
  errorBox.style.background = "rgba(80,0,0,0.9)";
  errorBox.style.padding = "10px";
  document.body.appendChild(errorBox);

  return root;
}

function createRenderer(root) {
  renderer = new THREE.WebGLRenderer({
    antialias: false,
    alpha: false,
    powerPreference: "low-power",
    preserveDrawingBuffer: false
  });

  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, window.__ANDROID_PIXEL_RATIO_CAP__ || 0.38));
  renderer.setSize(window.innerWidth, window.innerHeight, false);
  renderer.shadowMap.enabled = false;
  renderer.domElement.style.width = "100vw";
  renderer.domElement.style.height = "100vh";
  renderer.domElement.style.display = "block";
  renderer.domElement.style.touchAction = "none";
  root.appendChild(renderer.domElement);
}

function initScene() {
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x020402);
  scene.fog = new THREE.Fog(0x020402, 18, 60);

  camera = new THREE.PerspectiveCamera(62, window.innerWidth / window.innerHeight, 0.05, 90);

  const ambient = new THREE.AmbientLight(0xffffff, 0.85);
  scene.add(ambient);

  const light = new THREE.DirectionalLight(0xffffff, 0.55);
  light.position.set(4, 8, 5);
  scene.add(light);

  const groundGeo = new THREE.PlaneGeometry(ROOM_WIDTH, ROOM_DEPTH, 1, 1);
  const groundMat = new THREE.MeshBasicMaterial({ color: 0x071107 });
  const ground = new THREE.Mesh(groundGeo, groundMat);
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);

  const grid = new THREE.GridHelper(ROOM_DEPTH, 14, 0x125c20, 0x0b3012);
  grid.scale.x = ROOM_WIDTH / ROOM_DEPTH;
  grid.position.y = 0.012;
  scene.add(grid);

  const wallMat = new THREE.MeshBasicMaterial({ color: 0x061806, wireframe: true });
  const back = new THREE.Mesh(new THREE.BoxGeometry(ROOM_WIDTH, ROOM_WALL_HEIGHT, 0.2), wallMat);
  back.position.set(0, ROOM_WALL_HEIGHT / 2, -ROOM_DEPTH / 2);
  scene.add(back);

  const front = new THREE.Mesh(new THREE.BoxGeometry(ROOM_WIDTH, ROOM_WALL_HEIGHT, 0.2), wallMat);
  front.position.set(0, ROOM_WALL_HEIGHT / 2, ROOM_DEPTH / 2);
  scene.add(front);

  const left = new THREE.Mesh(new THREE.BoxGeometry(0.2, ROOM_WALL_HEIGHT, ROOM_DEPTH), wallMat);
  left.position.set(-ROOM_WIDTH / 2, ROOM_WALL_HEIGHT / 2, 0);
  scene.add(left);

  const right = new THREE.Mesh(new THREE.BoxGeometry(0.2, ROOM_WALL_HEIGHT, ROOM_DEPTH), wallMat);
  right.position.set(ROOM_WIDTH / 2, ROOM_WALL_HEIGHT / 2, 0);
  scene.add(right);
}

let phone;

function makePhone() {
  phone = new THREE.Group();

  const body = new THREE.Mesh(
    new THREE.BoxGeometry(0.85, 1.35, 0.16),
    new THREE.MeshBasicMaterial({ color: 0x101410 })
  );
  body.position.y = 0.15;
  phone.add(body);

  const screen = new THREE.Mesh(
    new THREE.BoxGeometry(0.66, 1.02, 0.03),
    new THREE.MeshBasicMaterial({ color: 0x54ff73 })
  );
  screen.position.set(0, 0.16, -0.095);
  phone.add(screen);

  const rim = new THREE.Mesh(
    new THREE.BoxGeometry(0.92, 1.42, 0.08),
    new THREE.MeshBasicMaterial({ color: 0x020802, wireframe: true })
  );
  rim.position.y = 0.15;
  phone.add(rim);

  scene.add(phone);
}

function makeTarget(i, x, z) {
  const group = new THREE.Group();

  const body = new THREE.Mesh(
    new THREE.BoxGeometry(0.65, 1.25, 0.42),
    new THREE.MeshBasicMaterial({ color: 0x2aff55 })
  );
  body.position.y = 0.65;
  group.add(body);

  const head = new THREE.Mesh(
    new THREE.BoxGeometry(0.42, 0.32, 0.36),
    new THREE.MeshBasicMaterial({ color: 0x9cffaa })
  );
  head.position.y = 1.45;
  group.add(head);

  group.position.set(x, 0, z);
  scene.add(group);

  return {
    id: i,
    group: group,
    pos: new THREE.Vector3(x, 0, z),
    vel: new THREE.Vector3(),
    alive: true,
    capture: 0,
    phase: Math.random() * Math.PI * 2
  };
}

function resetTargets() {
  for (let i = 0; i < targets.length; i++) {
    scene.remove(targets[i].group);
  }
  targets.length = 0;

  const spots = [
    [-8, -12],
    [8, -13],
    [-9, 0],
    [9, -1],
    [0, -17]
  ];

  for (let i = 0; i < ACTIVE_TARGETS; i++) {
    targets.push(makeTarget(i, spots[i][0], spots[i][1]));
  }
}

function makeCapture(i, x, z) {
  const group = new THREE.Group();

  const ring = new THREE.Mesh(
    new THREE.CylinderGeometry(CAPTURE_RADIUS, CAPTURE_RADIUS, 0.09, 18, 1, true),
    new THREE.MeshBasicMaterial({ color: 0x2266ff, wireframe: true })
  );
  ring.position.y = 0.07;
  group.add(ring);

  const core = new THREE.Mesh(
    new THREE.CylinderGeometry(0.32, 0.32, 0.18, 12),
    new THREE.MeshBasicMaterial({ color: 0x88aaff })
  );
  core.position.y = 0.15;
  group.add(core);

  group.position.set(x, 0, z);
  scene.add(group);

  return {
    id: i,
    group: group,
    pos: new THREE.Vector3(x, 0, z),
    filled: false
  };
}

function resetCaptures() {
  for (let i = 0; i < captures.length; i++) {
    scene.remove(captures[i].group);
  }
  captures.length = 0;

  captures.push(makeCapture(0, -8, -17));
  captures.push(makeCapture(1, 8, -17));
  captures.push(makeCapture(2, 0, -5));
}

function resetRoom() {
  roomClear = false;
  player.pos.set(0, 0.55, 12);
  player.vel.set(0, 0, 0);
  player.battery = BATTERY_MAX;
  player.souls = 0;
  resetTargets();
  resetCaptures();
  console.log("[STYLO-V2] room reset", roomIndex);
}

function keyName(e) {
  return e.code || e.key || String(e.keyCode);
}

function setKey(e, down) {
  const k = e.code || e.key;

  if (k === "KeyW" || k === "ArrowUp") input.forward = down;
  if (k === "KeyS" || k === "ArrowDown") input.back = down;
  if (k === "KeyA" || k === "ArrowLeft") input.left = down;
  if (k === "KeyD" || k === "ArrowRight") input.right = down;
  if (k === "ShiftLeft" || k === "ShiftRight") input.sprint = down;
  if (k === "KeyQ") input.vacuum = down;

  if (k === "Space") {
    if (down && !input.jumpHeld) input.jumpPressed = true;
    input.jumpHeld = down;
  }

  input.last = (down ? "down:" : "up:") + keyName(e);
}

function bindInput() {
  window.addEventListener("keydown", function (e) {
    setKey(e, true);
    e.preventDefault();
  }, true);

  window.addEventListener("keyup", function (e) {
    setKey(e, false);
    e.preventDefault();
  }, true);

  window.addEventListener("blur", function () {
    input.forward = false;
    input.back = false;
    input.left = false;
    input.right = false;
    input.sprint = false;
    input.jumpHeld = false;
    input.jumpPressed = false;
    input.vacuum = false;
  });

  renderer.domElement.addEventListener("mousedown", function (e) {
    mouseDragging = true;
    mouseLastX = e.clientX;
    mouseLastY = e.clientY;
    input.last = "mouse:down";
    e.preventDefault();
  }, false);

  window.addEventListener("mousemove", function (e) {
    if (!mouseDragging) return;

    const dx = e.clientX - mouseLastX;
    const dy = e.clientY - mouseLastY;
    mouseLastX = e.clientX;
    mouseLastY = e.clientY;

    cameraRig.yaw -= dx * 0.008;
    cameraRig.targetPitch += dy * 0.005;
    cameraRig.targetPitch = Math.max(0.18, Math.min(0.92, cameraRig.targetPitch));
    input.last = "mouse:drag";
  }, false);

  window.addEventListener("mouseup", function () {
    mouseDragging = false;
  }, false);

  window.addEventListener("contextmenu", function (e) {
    e.preventDefault();
  }, false);
}

function clampRoom(pos) {
  const pad = 0.8;
  pos.x = Math.max(-ROOM_WIDTH / 2 + pad, Math.min(ROOM_WIDTH / 2 - pad, pos.x));
  pos.z = Math.max(-ROOM_DEPTH / 2 + pad, Math.min(ROOM_DEPTH / 2 - pad, pos.z));
}

function updatePlayer(dt) {
  let mx = 0;
  let mz = 0;

  if (input.forward) mz -= 1;
  if (input.back) mz += 1;
  if (input.left) mx -= 1;
  if (input.right) mx += 1;

  const moving = mx !== 0 || mz !== 0;
  const vacuuming = input.vacuum && player.battery > 1;
  const sprinting = input.sprint && moving && !vacuuming && player.battery > 5;

  const desiredSpeedBase = sprinting ? SPRINT_SPEED : WALK_SPEED;
  const desiredSpeed = vacuuming ? desiredSpeedBase * VACUUM_MOVE_MULT : desiredSpeedBase;

  if (moving) {
    const len = Math.sqrt(mx * mx + mz * mz);
    mx /= len;
    mz /= len;

    const desired = new THREE.Vector3(mx * desiredSpeed, 0, mz * desiredSpeed);
    const accel = player.grounded ? ACCEL : AIR_ACCEL;

    player.vel.x += (desired.x - player.vel.x) * Math.min(1, accel * dt);
    player.vel.z += (desired.z - player.vel.z) * Math.min(1, accel * dt);

    player.targetYaw = Math.atan2(mx, mz);
  } else {
    const damp = Math.max(0, 1 - FRICTION * dt);
    player.vel.x *= damp;
    player.vel.z *= damp;
  }

  if (input.jumpPressed && player.grounded && player.battery >= BATTERY_JUMP_COST) {
    player.vel.y = JUMP_SPEED;
    player.grounded = false;
    player.battery -= BATTERY_JUMP_COST;
    input.last = "jump";
  }
  input.jumpPressed = false;

  player.vel.y -= GRAVITY * dt;

  player.pos.x += player.vel.x * dt;
  player.pos.y += player.vel.y * dt;
  player.pos.z += player.vel.z * dt;

  if (player.pos.y <= 0.55) {
    player.pos.y = 0.55;
    player.vel.y = 0;
    player.grounded = true;
  }

  clampRoom(player.pos);

  let drain = 0;
  if (moving) drain += BATTERY_WALK_DRAIN;
  if (sprinting) drain += BATTERY_SPRINT_DRAIN;
  if (!player.grounded) drain += BATTERY_AIR_DRAIN;
  if (vacuuming) drain += BATTERY_VACUUM_DRAIN;

  const regen = drain > 0 ? BATTERY_ACTIVE_REGEN : BATTERY_IDLE_REGEN;
  player.battery += (regen - drain) * dt;
  player.battery = Math.max(0, Math.min(BATTERY_MAX, player.battery));

  const yawDiff = Math.atan2(Math.sin(player.targetYaw - player.yaw), Math.cos(player.targetYaw - player.yaw));
  player.yaw += yawDiff * Math.min(1, dt * 10);
}

function updateTargets(dt) {
  const playerXZ = new THREE.Vector3(player.pos.x, 0, player.pos.z);

  for (let i = 0; i < targets.length; i++) {
    const t = targets[i];
    if (!t.alive) continue;

    const toPlayer = new THREE.Vector3().subVectors(playerXZ, t.pos);
    const dist = toPlayer.length();

    if (input.vacuum && player.battery > 1 && dist < VACUUM_RANGE) {
      if (dist > 0.001) toPlayer.multiplyScalar(1 / dist);
      t.vel.x += toPlayer.x * VACUUM_PULL * dt;
      t.vel.z += toPlayer.z * VACUUM_PULL * dt;

      if (dist < VACUUM_LATCH_RADIUS) {
        t.capture += dt / VACUUM_CAPTURE_TIME;
        t.group.scale.setScalar(1 + Math.sin(performance.now() * 0.025) * 0.08);
      } else {
        t.capture = Math.max(0, t.capture - dt * 1.5);
        t.group.scale.setScalar(1);
      }

      if (t.capture >= 1 && player.souls < MAX_STORED_SOULS) {
        t.alive = false;
        t.group.visible = false;
        player.souls++;
        player.battery = Math.min(BATTERY_MAX, player.battery + 3);
        input.last = "captured";
      }
    } else {
      t.capture = Math.max(0, t.capture - dt * 1.5);

      t.phase += dt;
      t.vel.x += Math.sin(t.phase * 0.7 + i) * 0.6 * dt;
      t.vel.z += Math.cos(t.phase * 0.55 + i) * 0.6 * dt;
      t.group.scale.setScalar(1);
    }

    t.vel.multiplyScalar(Math.max(0, 1 - 5.5 * dt));
    t.pos.x += t.vel.x * dt;
    t.pos.z += t.vel.z * dt;
    clampRoom(t.pos);

    t.group.position.x = t.pos.x;
    t.group.position.z = t.pos.z;
    t.group.rotation.y += dt * 0.8;
    t.group.position.y = Math.sin(performance.now() * 0.004 + i) * 0.05;
  }
}

function updateCaptures(dt) {
  let filled = 0;

  for (let i = 0; i < captures.length; i++) {
    const c = captures[i];
    if (c.filled) {
      filled++;
      continue;
    }

    const dx = player.pos.x - c.pos.x;
    const dz = player.pos.z - c.pos.z;
    const dist = Math.sqrt(dx * dx + dz * dz);

    if (dist < CAPTURE_RADIUS && player.souls > 0) {
      c.filled = true;
      player.souls--;
      player.battery = Math.min(BATTERY_MAX, player.battery + BATTERY_CAPTURE_GAIN);
      c.group.children[1].material.color.setHex(0xffffff);
      c.group.scale.setScalar(1.2);
      input.last = "deposit";
      filled++;
    }

    c.group.rotation.y += dt;
  }

  if (!roomClear && filled >= captures.length) {
    roomClear = true;
    roomIndex++;
    input.last = "room-clear";
    console.log("[STYLO-V2] room clear");
    setTimeout(resetRoom, 900);
  }
}

function updatePhoneVisual(dt) {
  phone.position.copy(player.pos);
  phone.rotation.y = player.yaw;

  const speed = Math.sqrt(player.vel.x * player.vel.x + player.vel.z * player.vel.z);
  phone.rotation.z = Math.sin(performance.now() * 0.012) * Math.min(0.25, speed * 0.025);
  phone.rotation.x = -Math.min(0.28, speed * 0.02);

  const batteryScale = 0.75 + player.battery / BATTERY_MAX * 0.25;
  phone.children[1].scale.set(batteryScale, batteryScale, 1);
}

function updateCamera(dt) {
  cameraRig.pitch += (cameraRig.targetPitch - cameraRig.pitch) * Math.min(1, dt * 8);

  const desired = new THREE.Vector3(
    player.pos.x + Math.sin(cameraRig.yaw) * cameraRig.distance,
    player.pos.y + cameraRig.height + cameraRig.pitch * 5.4,
    player.pos.z + Math.cos(cameraRig.yaw) * cameraRig.distance
  );

  cameraRig.pos.lerp(desired, Math.min(1, dt * 8));
  camera.position.copy(cameraRig.pos);
  camera.lookAt(player.pos.x, player.pos.y + 0.7, player.pos.z);
}

function updateHud() {
  frames++;
  const now = performance.now();
  if (now - lastFpsTime > 500) {
    fps = Math.round(frames * 1000 / (now - lastFpsTime));
    frames = 0;
    lastFpsTime = now;
  }

  let alive = 0;
  for (let i = 0; i < targets.length; i++) if (targets[i].alive) alive++;

  hud.textContent =
    "DIGITAL BREAKDOWN / STYLO V2\n" +
    "FPS " + fps + "\n" +
    "ROOM " + roomIndex + (roomClear ? " CLEAR" : "") + "\n" +
    "BAT " + Math.round(player.battery) + "\n" +
    "SOULS " + player.souls + "/" + MAX_STORED_SOULS + "\n" +
    "TARGETS " + alive + "/" + ACTIVE_TARGETS + "\n" +
    "INPUT " + input.last + "\n" +
    "WASD MOVE  SHIFT SPRINT  SPACE JUMP  Q VACUUM";
}

function resize() {
  if (!renderer || !camera) return;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, window.__ANDROID_PIXEL_RATIO_CAP__ || 0.38));
  renderer.setSize(window.innerWidth, window.innerHeight, false);
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
}

function loop() {
MobileTelemetry.mark("runtime_ready");
  MobileTelemetry.frame();
  requestAnimationFrame(loop);

  const dt = Math.min(0.033, clock.getDelta());

  updatePlayer(dt);
  updateTargets(dt);
  updateCaptures(dt);
  updatePhoneVisual(dt);
  updateCamera(dt);
  updateHud();

  renderer.render(scene, camera);
}

function boot() {
  const root = makeHud();
  createRenderer(root);
  initScene();
  makePhone();
  resetRoom();
  bindInput();

  clock = new THREE.Clock();

  window.addEventListener("resize", resize);
  resize();

  console.log("[STYLO-V2] READY");
  requestAnimationFrame(loop);
  console.log("[STYLO-V2] RUNNING");
}

boot();

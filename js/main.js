/**
 * Notch — Native macOS Utility Marketing Site
 * Complete Client-Side Controller (ES Module)
 *
 * Hosting-safe: zero external runtime network requests,
 * vendored Three.js r128, GSAP & ScrollTrigger.
 */

import * as THREE from './vendor/three.module.min.js';

/* ─────────────────────────────────────────────────────────────────────────
   Config (All URLs and domain in one place)
   ───────────────────────────────────────────────────────────────────────── */
export const CONFIG = {
  siteDomain: 'https://notch.app',
  downloadUrl: 'https://github.com/Wub796/Notch/releases',
  sourceUrl: 'https://github.com/Wub796/Notch',
  version: 'v1.0.2',
  minMacOS: 'macOS 14.0+',
  repoName: 'Wub796/Notch'
};

/* ─────────────────────────────────────────────────────────────────────────
   Analytics & Privacy Slot
   No cookies or trackers by default (no consent banner required).
   Uncomment below to enable Cloudflare Web Analytics or Plausible:

   // window.addEventListener('DOMContentLoaded', () => {
   //   const script = document.createElement('script');
   //   script.defer = true;
   //   script.dataset.domain = 'notch.app';
   //   script.src = 'https://plausible.io/js/script.js';
   //   document.head.appendChild(script);
   // });
   ───────────────────────────────────────────────────────────────────────── */

/* ─────────────────────────────────────────────────────────────────────────
   1. Mathematical Continuous Squircle (Ported from NotchShape.swift)
   ───────────────────────────────────────────────────────────────────────── */
const REACH = 1.5286649466;
const FIRST = [0.0749114, 0.6314939];
const INNER_FIRST = [0.1690600, 0.3728240];
const INNER_SECOND = [0.3728240, 0.1690600];
const SECOND = [0.6314939, 0.0749114];
const OUTER = [0.96, 0.2430462];
const INNER = [0.82, 0.0915639];

export function clamp(v, min, max) { return Math.max(min, Math.min(v, max)); }
export function lerp(a, b, t) { return a + (b - a) * t; }

export function generateNotchPath(w, h, topR, bottomR) {
  const f = v => Math.round(v * 100) / 100;
  const top = clamp(topR, 0, w / 2);
  const bottom = clamp(bottomR, 0, w / 2 - top);
  const bodyLeft = top;
  const bodyRight = w - top;
  const sideRoom = h / 2;
  const bottomRoom = w / 2 - top;

  const corners = [
    { at: [bodyLeft, 0],  u: [0, 1],  v: [-1, 0], r: top,    roomU: sideRoom,   roomV: top },
    { at: [bodyLeft, h],  u: [1, 0],  v: [0, -1], r: bottom, roomU: bottomRoom, roomV: sideRoom },
    { at: [bodyRight, h], u: [0, -1], v: [-1, 0], r: bottom, roomU: sideRoom,   roomV: bottomRoom },
    { at: [bodyRight, 0], u: [1, 0],  v: [0, 1],  r: top,    roomU: top,        roomV: sideRoom },
  ];

  let d = '';
  corners.forEach((c, index) => {
    const roomU = Math.max(c.roomU, 0);
    const roomV = Math.max(c.roomV, 0);
    const er = Math.min(Math.max(c.r, 0), roomU, roomV);
    const reachU = Math.min(REACH * er, roomU);
    const reachV = Math.min(REACH * er, roomV);
    const limitU = er > 0 ? reachU / er : 0;
    const limitV = er > 0 ? reachV / er : 0;

    const control = (line, limit) =>
      (limit <= 1 ? line[0] * limit : line[0] + line[1] * (limit - 1)) * er;
    const P = (u, v) => [c.at[0] + c.u[0] * u + c.v[0] * v, c.at[1] + c.u[1] * u + c.v[1] * v];
    const I = o => P(o[0] * er, o[1] * er);

    const start = P(0, reachV);
    const arcs = [
      [P(0, control(OUTER, limitV)), P(0, control(INNER, limitV)), I(FIRST)],
      [I(INNER_FIRST), I(INNER_SECOND), I(SECOND)],
      [P(control(INNER, limitU), 0), P(control(OUTER, limitU), 0), P(reachU, 0)],
    ];

    d += (index === 0 ? 'M' : 'L') + f(start[0]) + ' ' + f(start[1]);
    for (const a of arcs) {
      d += 'C' + f(a[0][0]) + ' ' + f(a[0][1]) + ' ' + f(a[1][0]) + ' ' + f(a[1][1]) + ' ' + f(a[2][0]) + ' ' + f(a[2][1]);
    }
  });
  return d + 'Z';
}

/* ─────────────────────────────────────────────────────────────────────────
   2. Accessible Live Region Announcer
   ───────────────────────────────────────────────────────────────────────── */
const announcer = document.getElementById('aria-announcer');
export function announce(msg) {
  if (announcer) {
    announcer.textContent = msg;
  }
}

/* ─────────────────────────────────────────────────────────────────────────
   3. Interactive Hero Notch Component (Spring Physics & States)
   ───────────────────────────────────────────────────────────────────────── */
const CLOSED_METRICS = { w: 156, h: 32, topR: 16, bottomR: 18 };
const OPEN_METRICS   = { w: 384, h: 130, topR: 26, bottomR: 30 };

const notchState = {
  t: 0,
  target: 0,
  velocity: 0,
  pinned: false,
  clickCount: 0,
  clickTimer: null
};

const notchEl = document.getElementById('notch');
const notchSvg = document.getElementById('notch-svg');
const notchPath = document.getElementById('notch-path');
const closedView = document.getElementById('closed-view');
const openView = document.getElementById('open-view');
const pinToggleBtn = document.getElementById('pin-toggle-btn');

function updateNotchFrame(dt = 0.016) {
  // Critically damped spring simulation (~0.34s natural response)
  const omega = 18;
  const zeta = 0.94;
  const f = -omega * omega * (notchState.t - notchState.target) - 2 * zeta * omega * notchState.velocity;
  notchState.velocity += f * dt;
  notchState.t += notchState.velocity * dt;

  const clampedT = clamp(notchState.t, 0, 1);
  const curW = lerp(CLOSED_METRICS.w, OPEN_METRICS.w, clampedT);
  const curH = lerp(CLOSED_METRICS.h, OPEN_METRICS.h, clampedT);
  const curTop = lerp(CLOSED_METRICS.topR, OPEN_METRICS.topR, clampedT);
  const curBottom = lerp(CLOSED_METRICS.bottomR, OPEN_METRICS.bottomR, clampedT);

  if (notchEl && notchSvg && notchPath) {
    notchEl.style.width = curW + 'px';
    notchEl.style.height = curH + 'px';
    notchSvg.setAttribute('viewBox', `0 0 ${curW} ${curH}`);
    notchPath.setAttribute('d', generateNotchPath(curW, curH, curTop, curBottom));
  }

  // Cross-fade internal contents
  if (clampedT > 0.5) {
    if (closedView) { closedView.style.opacity = '0'; closedView.style.pointerEvents = 'none'; }
    if (openView) { openView.style.opacity = '1'; openView.style.pointerEvents = 'auto'; }
  } else {
    if (closedView) { closedView.style.opacity = '1'; closedView.style.pointerEvents = 'auto'; }
    if (openView) { openView.style.opacity = '0'; openView.style.pointerEvents = 'none'; }
  }

  requestAnimationFrame(() => updateNotchFrame(0.016));
}
requestAnimationFrame(() => updateNotchFrame(0.016));

// Hover to peek, click to pin, Esc to dismiss
if (notchEl) {
  notchEl.addEventListener('mouseenter', () => {
    if (!notchState.pinned) {
      notchState.target = 1;
      notchEl.setAttribute('aria-expanded', 'true');
    }
  });

  notchEl.addEventListener('mouseleave', () => {
    if (!notchState.pinned) {
      notchState.target = 0;
      notchEl.setAttribute('aria-expanded', 'false');
    }
  });

  notchEl.addEventListener('click', (e) => {
    if (e.target.closest('.ctrl-btn') || e.target.closest('.open-pin-btn') || e.target.closest('.open-scrubber-bar')) {
      return;
    }

    // Easter egg check: 5 rapid clicks
    notchState.clickCount++;
    clearTimeout(notchState.clickTimer);
    notchState.clickTimer = setTimeout(() => { notchState.clickCount = 0; }, 1200);

    if (notchState.clickCount >= 5) {
      triggerConfettiEasterEgg();
      notchState.clickCount = 0;
      return;
    }

    notchState.pinned = !notchState.pinned;
    notchState.target = notchState.pinned ? 1 : 0;
    notchEl.setAttribute('aria-expanded', notchState.pinned ? 'true' : 'false');
    if (pinToggleBtn) pinToggleBtn.classList.toggle('pinned', notchState.pinned);
    announce(notchState.pinned ? 'Notch workspace pinned open' : 'Notch unpinned');
  });
}

if (pinToggleBtn) {
  pinToggleBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    notchState.pinned = !notchState.pinned;
    notchState.target = notchState.pinned ? 1 : 0;
    pinToggleBtn.classList.toggle('pinned', notchState.pinned);
    announce(notchState.pinned ? 'Notch workspace pinned' : 'Notch unpinned');
  });
}

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    notchState.pinned = false;
    notchState.target = 0;
    if (notchEl) notchEl.setAttribute('aria-expanded', 'false');
    if (pinToggleBtn) pinToggleBtn.classList.remove('pinned');
    announce('Notch closed');
  }
});

/* ─────────────────────────────────────────────────────────────────────────
   4. Easter Egg: Wobble Physics & Squircle Confetti
   ───────────────────────────────────────────────────────────────────────── */
function triggerConfettiEasterEgg() {
  announce('Notch celebration unlocked!');
  if (notchEl) {
    notchEl.style.transition = 'transform 0.1s ease';
    notchEl.style.transform = 'scale(1.1) rotate(4deg)';
    setTimeout(() => {
      notchEl.style.transform = 'scale(0.95) rotate(-3deg)';
      setTimeout(() => {
        notchEl.style.transform = 'none';
      }, 100);
    }, 100);
  }

  const colors = ['#30D158', '#0A84FF', '#FF9F0A', '#BF5AF2', '#FF453A'];
  for (let i = 0; i < 48; i++) {
    const p = document.createElement('div');
    p.style.position = 'fixed';
    p.style.top = '36px';
    p.style.left = '50%';
    p.style.width = Math.random() * 8 + 6 + 'px';
    p.style.height = Math.random() * 6 + 4 + 'px';
    p.style.borderRadius = '2px 2px 4px 4px';
    p.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)];
    p.style.zIndex = '9999';
    p.style.pointerEvents = 'none';
    document.body.appendChild(p);

    const angle = Math.random() * Math.PI + Math.PI / 6;
    const speed = Math.random() * 320 + 140;
    const vx = Math.cos(angle) * speed * (Math.random() > 0.5 ? 1 : -1);
    const vy = Math.sin(angle) * speed;

    let posX = 0, posY = 0, gravity = 600, rot = 0;
    const startT = performance.now();

    function stepConfetti(now) {
      const elapsed = (now - startT) / 1000;
      if (elapsed > 1.8) {
        p.remove();
        return;
      }
      posX = vx * elapsed;
      posY = vy * elapsed + 0.5 * gravity * elapsed * elapsed;
      rot += 6;
      p.style.transform = `translate(${posX}px, ${posY}px) rotate(${rot}deg)`;
      p.style.opacity = (1 - elapsed / 1.8).toString();
      requestAnimationFrame(stepConfetti);
    }
    requestAnimationFrame(stepConfetti);
  }
}

/* ─────────────────────────────────────────────────────────────────────────
   5. Procedural Canvas Art Generator
   ───────────────────────────────────────────────────────────────────────── */
export function renderProceduralArt(canvas, hueA = '#112211', hueB = '#30D158') {
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const w = canvas.width, h = canvas.height;

  const grad = ctx.createLinearGradient(0, 0, w, h);
  grad.addColorStop(0, hueA);
  grad.addColorStop(0.5, '#1b4d3e');
  grad.addColorStop(0.8, hueB);
  grad.addColorStop(1, '#0A84FF');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, w, h);

  ctx.strokeStyle = 'rgba(255,255,255,0.22)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.arc(w * 0.7, h * 0.3, w * 0.45, 0, Math.PI * 2);
  ctx.stroke();

  ctx.fillStyle = 'rgba(255,255,255,0.12)';
  ctx.beginPath();
  ctx.arc(w * 0.3, h * 0.8, w * 0.3, 0, Math.PI * 2);
  ctx.fill();
}
renderProceduralArt(document.getElementById('open-art-canvas'));
renderProceduralArt(document.getElementById('stage-art-canvas'));

/* ─────────────────────────────────────────────────────────────────────────
   6. Lazy-Initialized Three.js 3D Floating MacBook Scene
   ───────────────────────────────────────────────────────────────────────── */
let scene, camera, renderer, macbookGroup, displayMesh;
const webglContainer = document.getElementById('webgl-container');
const webglFallback = document.getElementById('webgl-fallback');
let isReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
let isSceneActive = true;

function initThreeScene() {
  try {
    scene = new THREE.Scene();
    camera = new THREE.PerspectiveCamera(45, window.innerWidth / window.innerHeight, 0.1, 100);
    camera.position.set(0, 0.1, 4.4);

    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
    renderer.setSize(window.innerWidth, window.innerHeight);

    // Performance caps: cap dpr at 2, reduce on mobile or low-power cores
    const isMobileOrLowPower = window.innerWidth < 768 || (navigator.hardwareConcurrency && navigator.hardwareConcurrency < 4);
    const dprCap = isMobileOrLowPower ? 1 : Math.min(window.devicePixelRatio || 1, 2);
    renderer.setPixelRatio(dprCap);
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    webglContainer.appendChild(renderer.domElement);

    // Lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.7);
    scene.add(ambientLight);

    const dirLight = new THREE.DirectionalLight(0xffffff, 1.4);
    dirLight.position.set(2, 4, 3);
    scene.add(dirLight);

    const blueRim = new THREE.DirectionalLight(0x0a84ff, 1.2);
    blueRim.position.set(-3, -1, -2);
    scene.add(blueRim);

    const greenAccent = new THREE.PointLight(0x30d158, 0.9, 10);
    greenAccent.position.set(0, 1.2, 1);
    scene.add(greenAccent);

    // Build Floating MacBook Display Assembly
    macbookGroup = new THREE.Group();

    // Aluminum display lid
    const lidGeo = new THREE.BoxGeometry(3.6, 2.3, 0.08);
    const lidMat = new THREE.MeshStandardMaterial({
      color: 0x18181b,
      metalness: 0.85,
      roughness: 0.3
    });
    const lidMesh = new THREE.Mesh(lidGeo, lidMat);
    macbookGroup.add(lidMesh);

    // Glass front screen
    const screenGeo = new THREE.PlaneGeometry(3.46, 2.18);
    const screenMat = new THREE.MeshStandardMaterial({
      color: 0x070709,
      metalness: 0.2,
      roughness: 0.1
    });
    displayMesh = new THREE.Mesh(screenGeo, screenMat);
    displayMesh.position.z = 0.042;
    macbookGroup.add(displayMesh);

    // Notch cutout geometry
    const notchGeo = new THREE.PlaneGeometry(0.5, 0.09);
    const notchMat = new THREE.MeshBasicMaterial({ color: 0x000000 });
    const notch3d = new THREE.Mesh(notchGeo, notchMat);
    notch3d.position.set(0, 1.045, 0.044);
    macbookGroup.add(notch3d);

    // Camera green status dot LED on MacBook
    const ledGeo = new THREE.CircleGeometry(0.008, 16);
    const ledMat = new THREE.MeshBasicMaterial({ color: 0x112211 });
    const ledMesh = new THREE.Mesh(ledGeo, ledMat);
    ledMesh.position.set(0.04, 1.055, 0.045);
    macbookGroup.add(ledMesh);

    // Ambient floating particles
    const partCount = isMobileOrLowPower ? 40 : 120;
    const partGeo = new THREE.BufferGeometry();
    const posArray = new Float32Array(partCount * 3);
    for (let i = 0; i < partCount * 3; i++) {
      posArray[i] = (Math.random() - 0.5) * 10;
    }
    partGeo.setAttribute('position', new THREE.BufferAttribute(posArray, 3));
    const partMat = new THREE.PointsMaterial({
      size: 0.025,
      color: 0x30d158,
      transparent: true,
      opacity: 0.3
    });
    const particles = new THREE.Points(partGeo, partMat);
    scene.add(particles);

    scene.add(macbookGroup);
    macbookGroup.rotation.x = 0.16;

    window.addEventListener('resize', onWindowResize);
    window.addEventListener('mousemove', onMouseMoveParallax);

    // Pause rendering when tab is hidden
    document.addEventListener('visibilitychange', () => {
      isSceneActive = !document.hidden;
    });

    animateThreeLoop();
    setupScrollChoreography();
  } catch (err) {
    console.warn('WebGL init error, using flat fallback:', err);
    if (webglFallback) webglFallback.style.display = 'block';
  }
}

function onWindowResize() {
  if (!camera || !renderer) return;
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
}

let mouseX = 0, mouseY = 0;
function onMouseMoveParallax(e) {
  if (isReducedMotion) return;
  mouseX = (e.clientX / window.innerWidth - 0.5) * 2;
  mouseY = (e.clientY / window.innerHeight - 0.5) * 2;
}

function animateThreeLoop() {
  requestAnimationFrame(animateThreeLoop);
  if (!isSceneActive || !renderer || !scene || !camera) return;

  if (!isReducedMotion && macbookGroup) {
    macbookGroup.rotation.y += (mouseX * 0.14 - macbookGroup.rotation.y) * 0.05;
    macbookGroup.rotation.x += (0.16 + mouseY * 0.08 - macbookGroup.rotation.x) * 0.05;
  }
  renderer.render(scene, camera);
}

// Lazy-initialize 3D scene after first paint
if ('requestIdleCallback' in window) {
  requestIdleCallback(() => initThreeScene(), { timeout: 800 });
} else {
  setTimeout(initThreeScene, 300);
}

/* ─────────────────────────────────────────────────────────────────────────
   7. GSAP Scroll Choreography (Camera Gliding Through 3D World)
   ───────────────────────────────────────────────────────────────────────── */
function setupScrollChoreography() {
  if (!window.gsap || !window.ScrollTrigger || !camera) return;
  gsap.registerPlugin(ScrollTrigger);

  // Section 1: Dead space macro camera glide
  gsap.timeline({
    scrollTrigger: {
      trigger: '#sec-deadspace',
      start: 'top 80%',
      end: 'bottom 20%',
      scrub: 1.2
    }
  }).to(camera.position, {
    z: 3.2,
    y: 0.5,
    ease: 'power1.out'
  });

  // Section 2: Music pull back & depth tilt
  gsap.timeline({
    scrollTrigger: {
      trigger: '#sec-music',
      start: 'top 80%',
      end: 'bottom 20%',
      scrub: 1.2
    }
  }).to(camera.position, {
    z: 4.2,
    y: 0.1,
    ease: 'power1.out'
  });

  // Section 8: Audio mixer rack angle
  gsap.timeline({
    scrollTrigger: {
      trigger: '#sec-mixer',
      start: 'top 80%',
      end: 'bottom 20%',
      scrub: 1.2
    }
  }).to(camera.position, {
    z: 3.6,
    y: -0.2,
    ease: 'power1.out'
  });

  // Final CTA settle
  gsap.timeline({
    scrollTrigger: {
      trigger: '#sec-cta',
      start: 'top 80%',
      end: 'bottom 20%',
      scrub: 1.2
    }
  }).to(camera.position, {
    z: 4.4,
    y: 0.1,
    ease: 'power1.out'
  });
}

/* ─────────────────────────────────────────────────────────────────────────
   8. Web Audio Engine & Synthesized Process Tap Loop
   ───────────────────────────────────────────────────────────────────────── */
let audioCtx = null;
let isPlayingAudio = false;
let masterGain = null;
let analyser = null;
let synthTimer = null;
let eqFilters = [];

const audioDemoBtn = document.getElementById('audio-demo-btn');
const audioBtnTxt = document.getElementById('audio-btn-txt');
const closedMeterBars = document.querySelectorAll('#closed-meter .bar');
const meterLow = document.getElementById('meter-low');
const meterMid = document.getElementById('meter-mid');
const meterHigh = document.getElementById('meter-high');

function initWebAudio() {
  if (audioCtx) return;
  const AudioContext = window.AudioContext || window.webkitAudioContext;
  audioCtx = new AudioContext();

  analyser = audioCtx.createAnalyser();
  analyser.fftSize = 256;

  masterGain = audioCtx.createGain();
  masterGain.gain.setValueAtTime(0.7, audioCtx.currentTime);

  // Build 10-band EQ chain (32Hz to 16kHz)
  const freqs = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
  let prevNode = masterGain;
  eqFilters = freqs.map((freq) => {
    const filter = audioCtx.createBiquadFilter();
    filter.type = 'peaking';
    filter.frequency.value = freq;
    filter.Q.value = 1.4;
    filter.gain.value = 0;
    prevNode.connect(filter);
    prevNode = filter;
    return filter;
  });

  prevNode.connect(analyser);
  analyser.connect(audioCtx.destination);
}

function playSynthChord(freqs, duration = 0.5) {
  if (!audioCtx || audioCtx.state !== 'running') return;
  freqs.forEach(f => {
    const osc = audioCtx.createOscillator();
    const g = audioCtx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(f, audioCtx.currentTime);

    g.gain.setValueAtTime(0.001, audioCtx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.08, audioCtx.currentTime + 0.05);
    g.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration);

    osc.connect(g);
    g.connect(masterGain);
    osc.start();
    osc.stop(audioCtx.currentTime + duration);
  });
}

function playSynthKick() {
  if (!audioCtx || audioCtx.state !== 'running') return;
  const osc = audioCtx.createOscillator();
  const g = audioCtx.createGain();
  osc.frequency.setValueAtTime(140, audioCtx.currentTime);
  osc.frequency.exponentialRampToValueAtTime(38, audioCtx.currentTime + 0.14);

  g.gain.setValueAtTime(0.4, audioCtx.currentTime);
  g.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.2);

  osc.connect(g);
  g.connect(masterGain);
  osc.start();
  osc.stop(audioCtx.currentTime + 0.22);
}

function toggleLiveAudio() {
  initWebAudio();
  if (audioCtx.state === 'suspended') {
    audioCtx.resume();
  }

  isPlayingAudio = !isPlayingAudio;
  if (isPlayingAudio) {
    if (audioBtnTxt) audioBtnTxt.textContent = 'Pause Synthesized Loop';
    let beat = 0;
    synthTimer = setInterval(() => {
      beat = (beat + 1) % 4;
      if (beat === 0 || beat === 2) {
        playSynthKick();
      }
      if (beat === 1) {
        playSynthChord([220, 277.18, 329.63, 440], 0.7); // A Major
      } else if (beat === 3) {
        playSynthChord([246.94, 293.66, 369.99, 493.88], 0.7); // B Minor
      }
    }, 340);
    announce('Audio playback started');
  } else {
    if (audioBtnTxt) audioBtnTxt.textContent = 'Play Synthesized Test Loop';
    clearInterval(synthTimer);
    announce('Audio playback paused');
  }
}

if (audioDemoBtn) audioDemoBtn.addEventListener('click', toggleLiveAudio);

const heroPlayBtn = document.getElementById('btn-play');
if (heroPlayBtn) {
  heroPlayBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    toggleLiveAudio();
  });
}

// 3-Band Meter Render Loop
const freqData = new Uint8Array(128);
function renderAudioMeters() {
  requestAnimationFrame(renderAudioMeters);
  if (analyser && isPlayingAudio) {
    analyser.getByteFrequencyData(freqData);

    let lowSum = 0, midSum = 0, highSum = 0;
    for (let i = 1; i <= 5; i++) lowSum += freqData[i];
    for (let i = 6; i <= 22; i++) midSum += freqData[i];
    for (let i = 23; i <= 60; i++) highSum += freqData[i];

    const lowVal = Math.min(28, (lowSum / 5 / 255) * 32);
    const midVal = Math.min(28, (midSum / 17 / 255) * 32);
    const highVal = Math.min(28, (highSum / 38 / 255) * 32);

    if (closedMeterBars[0]) closedMeterBars[0].style.height = Math.max(3, lowVal * 0.45) + 'px';
    if (closedMeterBars[1]) closedMeterBars[1].style.height = Math.max(4, midVal * 0.45) + 'px';
    if (closedMeterBars[2]) closedMeterBars[2].style.height = Math.max(2, highVal * 0.45) + 'px';

    if (meterLow) meterLow.style.height = (lowVal / 28) * 100 + '%';
    if (meterMid) meterMid.style.height = (midVal / 28) * 100 + '%';
    if (meterHigh) meterHigh.style.height = (highVal / 28) * 100 + '%';
  } else {
    if (closedMeterBars[0]) closedMeterBars[0].style.height = '4px';
    if (closedMeterBars[1]) closedMeterBars[1].style.height = '7px';
    if (closedMeterBars[2]) closedMeterBars[2].style.height = '5px';
  }
}
renderAudioMeters();

/* ─────────────────────────────────────────────────────────────────────────
   9. Section Interactions (Faders, Dead Space, Shelf, System, Face ID, etc.)
   ───────────────────────────────────────────────────────────────────────── */
// Dead space toggle
const toggleHighlightPixels = document.getElementById('toggle-highlight-pixels');
const wastedStrip = document.getElementById('wasted-strip');
if (toggleHighlightPixels && wastedStrip) {
  toggleHighlightPixels.addEventListener('click', () => {
    wastedStrip.classList.toggle('active');
    announce('Toggled wasted pixels visualization');
  });
}

// Fader controller
function setupFader(id, initialPct) {
  const track = document.getElementById('fader-track-' + id);
  const fill = document.getElementById('fill-' + id);
  const thumb = document.getElementById('thumb-' + id);
  const readout = document.getElementById('gain-' + id);
  if (!track || !fill || !thumb || !readout) return;

  let isDragging = false;

  function updateFromPos(clientY) {
    const rect = track.getBoundingClientRect();
    const offset = clamp(rect.bottom - clientY, 0, rect.height);
    const pct = (offset / rect.height) * 100;
    fill.style.height = pct + '%';
    thumb.style.bottom = pct + '%';

    const isBoosted = pct > 62;
    fill.classList.toggle('boosted', isBoosted);
    readout.classList.toggle('boost', isBoosted);

    const gainMultiplier = pct <= 62 ? (pct / 62) * 100 : 100 + ((pct - 62) / 38) * 300;
    const db = (20 * Math.log10(Math.max(0.01, gainMultiplier / 100))).toFixed(1);
    readout.textContent = `${Math.round(gainMultiplier)}% (${db > 0 ? '+' : ''}${db} dB)`;
  }

  thumb.addEventListener('mousedown', (e) => {
    isDragging = true;
    e.preventDefault();
  });

  window.addEventListener('mousemove', (e) => {
    if (isDragging) updateFromPos(e.clientY);
  });

  window.addEventListener('mouseup', () => { isDragging = false; });
}
setupFader('spotify', 60);
setupFader('safari', 48);
setupFader('zoom', 82);

// Interactive EQ Curve
const eqCanvas = document.getElementById('eq-canvas');
if (eqCanvas) {
  const ctx = eqCanvas.getContext('2d');
  const eqPoints = [0, 2, 4, 1, -2, -1, 3, 5, 2, 0];

  function drawEqCurve() {
    const w = eqCanvas.width, h = eqCanvas.height;
    ctx.clearRect(0, 0, w, h);

    ctx.strokeStyle = 'rgba(255,255,255,0.12)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, h / 2);
    ctx.lineTo(w, h / 2);
    ctx.stroke();

    ctx.strokeStyle = '#30D158';
    ctx.lineWidth = 2.5;
    ctx.beginPath();

    const step = w / (eqPoints.length - 1);
    eqPoints.forEach((val, i) => {
      const x = i * step;
      const y = h / 2 - (val * 4);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();

    eqPoints.forEach((val, i) => {
      const x = i * step;
      const y = h / 2 - (val * 4);
      ctx.fillStyle = '#fff';
      ctx.beginPath();
      ctx.arc(x, y, 4, 0, Math.PI * 2);
      ctx.fill();
    });
  }
  drawEqCurve();

  eqCanvas.addEventListener('click', (e) => {
    const rect = eqCanvas.getBoundingClientRect();
    const clickX = ((e.clientX - rect.left) / rect.width) * eqCanvas.width;
    const clickY = ((e.clientY - rect.top) / rect.height) * eqCanvas.height;
    const step = eqCanvas.width / (eqPoints.length - 1);
    const closestIdx = Math.round(clickX / step);
    if (closestIdx >= 0 && closestIdx < eqPoints.length) {
      eqPoints[closestIdx] = (eqCanvas.height / 2 - clickY) / 4;
      drawEqCurve();
    }
  });
}

// Shelf Drag & Drop
const dropzone = document.getElementById('shelf-dropzone');
const dropMsg = document.getElementById('shelf-drop-msg');
const shelfActions = document.getElementById('shelf-actions');
const fileChips = document.querySelectorAll('.draggable-file-chip');

fileChips.forEach(chip => {
  chip.addEventListener('dragstart', (e) => {
    e.dataTransfer.setData('text/plain', chip.innerText.trim());
    chip.style.opacity = '0.5';
  });
  chip.addEventListener('dragend', () => {
    chip.style.opacity = '1';
  });
});

if (dropzone) {
  dropzone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropzone.classList.add('hovered');
  });

  dropzone.addEventListener('dragleave', () => {
    dropzone.classList.remove('hovered');
  });

  dropzone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropzone.classList.remove('hovered');
    dropzone.classList.add('dropped');
    const fileName = e.dataTransfer.getData('text/plain') || 'Dropped item';
    if (dropMsg) dropMsg.textContent = 'Held in Notch Shelf: ' + fileName;
    if (shelfActions) shelfActions.classList.add('visible');
    announce(fileName + ' dropped into the Notch Shelf');
  });
}

// Live Activities Carousel
const actChips = document.querySelectorAll('.act-chip');
const actViews = {
  music: document.getElementById('act-music-view'),
  vol: document.getElementById('act-vol-view'),
  charge: document.getElementById('act-charge-view'),
  meet: document.getElementById('act-meet-view'),
  timer: document.getElementById('act-timer-view'),
};

actChips.forEach(chip => {
  chip.addEventListener('click', () => {
    actChips.forEach(c => c.classList.remove('active'));
    chip.classList.add('active');
    const mode = chip.getAttribute('data-mode');

    Object.keys(actViews).forEach(k => {
      if (actViews[k]) actViews[k].classList.remove('active');
    });
    if (actViews[mode]) actViews[mode].classList.add('active');
    announce('Switched live activity to ' + chip.textContent);
  });
});

// System CPU Load Spike Simulator
const simulateLoadBtn = document.getElementById('simulate-load-btn');
const cpuCircle = document.getElementById('circle-cpu');
const cpuTxt = document.getElementById('txt-cpu');

if (simulateLoadBtn && cpuCircle && cpuTxt) {
  simulateLoadBtn.addEventListener('click', () => {
    cpuCircle.style.strokeDashoffset = '35';
    cpuCircle.style.stroke = '#FF453A';
    cpuTxt.textContent = '88%';
    announce('Simulating CPU compile load: 88%');

    setTimeout(() => {
      cpuCircle.style.strokeDashoffset = '140';
      cpuCircle.style.stroke = '#30D158';
      cpuTxt.textContent = '38%';
      announce('CPU load normalized to 38%');
    }, 2600);
  });
}

// Face ID Lock Screen Simulation
const triggerScanBtn = document.getElementById('trigger-scan-btn');
const scanLaser = document.getElementById('scan-laser');
const tallyLed = document.getElementById('faceid-tally');
const pwBullets = [
  document.getElementById('pw-b1'), document.getElementById('pw-b2'),
  document.getElementById('pw-b3'), document.getElementById('pw-b4'),
  document.getElementById('pw-b5'), document.getElementById('pw-b6'),
  document.getElementById('pw-b7'), document.getElementById('pw-b8'),
];

if (triggerScanBtn) {
  triggerScanBtn.addEventListener('click', () => {
    triggerScanBtn.disabled = true;
    if (tallyLed) tallyLed.classList.add('scanning');
    if (scanLaser) scanLaser.classList.add('active');
    announce('Face ID scanning face from notch sensor');

    pwBullets.forEach(b => b && b.classList.remove('typed'));

    setTimeout(() => {
      if (scanLaser) scanLaser.classList.remove('active');
      if (tallyLed) tallyLed.classList.remove('scanning');

      pwBullets.forEach((bullet, index) => {
        setTimeout(() => {
          if (bullet) bullet.classList.add('typed');
          if (index === pwBullets.length - 1) {
            announce('Mac unlocked by Face ID');
            setTimeout(() => {
              triggerScanBtn.disabled = false;
            }, 600);
          }
        }, index * 60);
      });
    }, 1400);
  });
}

// Privacy Flip Tiles
const privacyTiles = document.querySelectorAll('.privacy-tile');
privacyTiles.forEach(tile => {
  function toggleTile() {
    tile.classList.toggle('flipped');
    const isFlipped = tile.classList.contains('flipped');
    tile.setAttribute('aria-expanded', isFlipped ? 'true' : 'false');
  }
  tile.addEventListener('click', toggleTile);
  tile.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      toggleTile();
    }
  });
});

// Custom Cursor
const cursor = document.getElementById('custom-cursor');
if (cursor && !isReducedMotion) {
  window.addEventListener('mousemove', (e) => {
    cursor.style.left = e.clientX + 'px';
    cursor.style.top = e.clientY + 'px';
  });

  const hoverables = document.querySelectorAll('button, a, .notch-container, .draggable-file-chip, .privacy-tile, .orbiting-node');
  hoverables.forEach(el => {
    el.addEventListener('mouseenter', () => cursor.classList.add('hovering'));
    el.addEventListener('mouseleave', () => cursor.classList.remove('hovering'));
  });

  window.addEventListener('mousedown', () => cursor.classList.add('clicking'));
  window.addEventListener('mouseup', () => cursor.classList.remove('clicking'));
}

// Floating Dock Navigation
const dockBtns = document.querySelectorAll('.dock-pill-btn');
dockBtns.forEach(btn => {
  btn.addEventListener('click', () => {
    const targetId = btn.getAttribute('data-target');
    const targetEl = document.querySelector(targetId);
    if (targetEl) {
      targetEl.scrollIntoView({ behavior: isReducedMotion ? 'auto' : 'smooth' });
      dockBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
    }
  });
});

// Arrow Keys Keyboard Navigation Across Sections
const sections = Array.from(document.querySelectorAll('.story-section'));
window.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;
  if (e.key === 'ArrowDown' || e.key === 'PageDown') {
    const scrollPos = window.scrollY + 100;
    const nextSec = sections.find(s => s.offsetTop > scrollPos);
    if (nextSec) {
      e.preventDefault();
      nextSec.scrollIntoView({ behavior: isReducedMotion ? 'auto' : 'smooth' });
    }
  } else if (e.key === 'ArrowUp' || e.key === 'PageUp') {
    const scrollPos = window.scrollY - 100;
    const prevSec = [...sections].reverse().find(s => s.offsetTop < scrollPos);
    if (prevSec) {
      e.preventDefault();
      prevSec.scrollIntoView({ behavior: isReducedMotion ? 'auto' : 'smooth' });
    }
  }
});

// Remove Loader after first paint
window.addEventListener('load', () => {
  const loader = document.getElementById('loader');
  if (loader) {
    setTimeout(() => {
      loader.classList.add('loaded');
    }, 350);
  }
});

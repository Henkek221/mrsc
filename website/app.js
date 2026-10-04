/* MRSC website */
(() => {
  'use strict';

  // Fill these in once they exist. Until then the buttons say "Coming soon to TestFlight" and the Discord button stays hidden.
  const LINKS = {
    testflight: null, // 'https://testflight.apple.com/join/XXXXXXXX'
    discord: 'https://discord.gg/kZTTJxjvQW', // change everywhere with tools/set_discord.py
    github: 'https://github.com/Henkek221/mrsc', // change everywhere with tools/set_links.py
    kofi: 'https://ko-fi.com/henrikkk',
  };

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const SVGNS = 'http://www.w3.org/2000/svg';
  const LETTERS = window.MRSC_LETTERS || [];
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
  };
  function rng(seed) {
    let a = seed >>> 0;
    return () => {
      a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const pick = (arr, r = Math.random) => arr[Math.floor(r() * arr.length)];
  const lum = hex => {
    const n = parseInt(hex.slice(1), 16);
    return (0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255)) / 255;
  };

  // Elements that are on screen right now. Loops wait for their tile before they animate.
  const visible = new WeakSet();
  const visIO = new IntersectionObserver(es => es.forEach(e => (e.isIntersecting ? visible.add(e.target) : visible.delete(e.target))), { rootMargin: '80px' });
  const watch = el => { visIO.observe(el); return el; };
  async function untilVisible(el) { while (!visible.has(el) || document.hidden) await wait(300); }

  // ---------------------------------------------------------------------------
  // Brand colour (Startup.swift BrandStyle): drives the splash, the icon and the page accent.

  const BRAND = [
    { id: 'red', name: 'Red', c: '#FF3B5C' },
    { id: 'orange', name: 'Orange', c: '#FF7A1A' },
    { id: 'green', name: 'Green', c: '#18B56A' },
    { id: 'blue', name: 'Blue', c: '#2F6BFF' },
    { id: 'violet', name: 'Violet', c: '#7C4DFF' },
    { id: 'black', name: 'Ink', c: '#111114' },
  ];
  const iconSVG = (bg, rx) => `<svg xmlns="${SVGNS}" viewBox="0 0 1024 1024"><rect width="1024" height="1024" rx="${rx}" fill="${bg}"/><g fill="#fff">${LETTERS.map(d => `<path d="${d}"/>`).join('')}</g></svg>`;
  const svgURL = s => 'data:image/svg+xml,' + encodeURIComponent(s);
  let brand = store.get('mrsc-brand');
  if (!BRAND.some(b => b.id === brand)) brand = 'red';

  function applyBrand(id) {
    const c = BRAND.find(b => b.id === id).c;
    document.documentElement.style.setProperty('--accent', c);
    $('meta[name="theme-color"]').setAttribute('content', c);
    if (!LETTERS.length) return;
    const rounded = svgURL(iconSVG(c, 230));
    $('link[rel="icon"][type="image/svg+xml"]').href = rounded;
    $$('.nav-brand img, .footer-brand img').forEach(i => (i.src = rounded));
    const hero = $('.hero-icon');
    if (hero) hero.src = svgURL(iconSVG(c, 0));
  }
  if (brand !== 'red') applyBrand(brand);

  // ---------------------------------------------------------------------------
  // The stamp: big, tilted letters land one after another with a bounce and a ring of ink.

  function spring(stiffness, damping) {
    const w0 = Math.sqrt(stiffness), z = damping / (2 * w0), wd = w0 * Math.sqrt(1 - z * z);
    return t => 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + (z * w0 / wd) * Math.sin(wd * t));
  }
  const springRD = (response, fraction) => { const w0 = (2 * Math.PI) / response; return spring(w0 * w0, 2 * fraction * w0); };

  const TILT = [-7, 6, 5, -6];
  const stampCurve = spring(520, 22);
  const STAMP_FRAMES = TILT.map(tilt => {
    const frames = [];
    for (let k = 0; k <= 42; k++) {
      const v = stampCurve((k / 42) * 0.7);
      frames.push({ transform: `rotate(${(tilt * (1 - v)).toFixed(3)}deg) scale(${(1.9 - 0.9 * v).toFixed(4)})`, opacity: clamp(v, 0, 1) });
    }
    return frames;
  });
  const SHAKE = [[-5, 4], [5, 4], [-4, -3], [4, -3]];
  const shakeCurve = springRD(0.25, 0.45);

  function buildLogo(svg) {
    svg.textContent = '';
    return LETTERS.map(d => {
      const g = document.createElementNS(SVGNS, 'g');
      g.setAttribute('class', 'stamp-letter');
      const ghost = document.createElementNS(SVGNS, 'path');
      ghost.setAttribute('d', d);
      ghost.setAttribute('class', 'stamp-ghost');
      ghost.setAttribute('fill', '#fff');
      const p = document.createElementNS(SVGNS, 'path');
      p.setAttribute('d', d);
      p.setAttribute('fill', '#fff');
      g.append(ghost, p);
      svg.append(g);
      return { g, ghost };
    });
  }
  const cancelAll = el => el.getAnimations().forEach(a => a.cancel());
  function resetLetters(letters) { letters.forEach(L => { cancelAll(L.g); cancelAll(L.ghost); L.g.style.opacity = ''; }); }
  function showLetters(letters) { letters.forEach(L => { cancelAll(L.g); L.g.style.opacity = '1'; }); }
  function stamp(L, i) {
    L.g.animate(STAMP_FRAMES[i % 4], { duration: 700, fill: 'forwards' });
    L.ghost.animate([{ opacity: 0.5, transform: 'scale(1)' }, { opacity: 0, transform: 'scale(1.12)' }], { duration: 350, easing: 'ease-out', fill: 'forwards' });
  }
  function shake(el, i, scale = 1) {
    const [dx, dy] = SHAKE[i % 4].map(v => v * scale);
    const hold = 55, D = 600;
    const f = [{ transform: `translate(${dx}px,${dy}px)`, offset: 0 }, { transform: `translate(${dx}px,${dy}px)`, offset: hold / D }];
    for (let k = 1; k <= 30; k++) {
      const v = shakeCurve(((k / 30) * (D - hold)) / 1000);
      f.push({ transform: `translate(${(dx * (1 - v)).toFixed(2)}px,${(dy * (1 - v)).toFixed(2)}px)`, offset: (hold + (k / 30) * (D - hold)) / D });
    }
    el.animate(f, { duration: D });
  }
  async function playStamps(letters, { gap = 330, shakeEl = null, shakeScale = 1, cancelled = () => false } = {}) {
    for (let i = 0; i < letters.length; i++) {
      if (cancelled()) return;
      stamp(letters[i], i);
      if (shakeEl) shake(shakeEl, i, shakeScale);
      await wait(gap);
    }
  }

  function runSplash() {
    const splash = $('#splash');
    const body = document.body;
    let done = false;
    const reveal = () => { body.classList.remove('is-splashing'); requestAnimationFrame(() => body.classList.add('ready')); };
    const finish = () => {
      if (done) return;
      done = true;
      reveal();
      splash.animate([{ opacity: 1, transform: 'scale(1)' }, { opacity: 0, transform: 'scale(1.04)' }], { duration: 320, easing: 'ease-in', fill: 'forwards' })
        .finished.then(() => splash.classList.add('is-gone'));
    };
    if (!splash || !LETTERS.length || /[?&]nosplash/.test(location.search)) {
      if (splash) splash.classList.add('is-gone');
      reveal();
      return;
    }
    splash.addEventListener('click', finish);
    addEventListener('keydown', finish, { once: true });
    setTimeout(finish, 5000);

    const svg = $('.splash-logo', splash);
    const letters = buildLogo(svg);
    $('.splash-flood', splash).animate([{ opacity: 0 }, { opacity: 1 }], { duration: 250, easing: 'ease-out', fill: 'forwards' });
    (async () => {
      if (reduceMotion) { showLetters(letters); await wait(700); finish(); return; }
      await wait(320);
      await playStamps(letters, { shakeEl: svg, cancelled: () => done });
      await wait(520);
      finish();
    })();
  }

  // ---------------------------------------------------------------------------
  // Icons (SF Symbols-ish)

  const fill = '<g fill="currentColor" stroke="none">';
  const ICON = {
    play: '<svg viewBox="0 0 24 24" class="fill"><path d="M7 4.6v14.8a1 1 0 0 0 1.5.86l12.3-7.4a1 1 0 0 0 0-1.72L8.5 3.74A1 1 0 0 0 7 4.6z"/></svg>',
    pause: '<svg viewBox="0 0 24 24" class="fill"><rect x="5.5" y="4" width="4.6" height="16" rx="1.4"/><rect x="13.9" y="4" width="4.6" height="16" rx="1.4"/></svg>',
    next: '<svg viewBox="0 0 24 24" class="fill"><path d="M1.8 6.3v11.4a.9.9 0 0 0 1.4.75l8.6-5.7a.9.9 0 0 0 0-1.5L3.2 5.55a.9.9 0 0 0-1.4.75zM11.6 6.3v11.4a.9.9 0 0 0 1.4.75l8.6-5.7a.9.9 0 0 0 0-1.5L13 5.55a.9.9 0 0 0-1.4.75z"/></svg>',
    prev: '<svg viewBox="0 0 24 24" class="fill"><g transform="matrix(-1 0 0 1 24 0)"><path d="M1.8 6.3v11.4a.9.9 0 0 0 1.4.75l8.6-5.7a.9.9 0 0 0 0-1.5L3.2 5.55a.9.9 0 0 0-1.4.75zM11.6 6.3v11.4a.9.9 0 0 0 1.4.75l8.6-5.7a.9.9 0 0 0 0-1.5L13 5.55a.9.9 0 0 0-1.4.75z"/></g></svg>',
    shuffle: '<svg viewBox="0 0 24 24"><path d="M3 7h3.2c2.1 0 3.3 1 4.4 2.8l2.6 4.4c1.1 1.8 2.3 2.8 4.4 2.8H21M3 17h3.2c1.3 0 2.3-.4 3.1-1.2M14.6 8.2c.8-.8 1.8-1.2 3-1.2H21M18 4l3 3-3 3M18 14l3 3-3 3"/></svg>',
    repeat: '<svg viewBox="0 0 24 24"><path d="M4 12V9.5A3.5 3.5 0 0 1 7.5 6H20M17 3l3 3-3 3M20 12v2.5a3.5 3.5 0 0 1-3.5 3.5H4M7 21l-3-3 3-3"/></svg>',
    airplay: `<svg viewBox="0 0 24 24"><path d="M6.5 17H4.5A2.5 2.5 0 0 1 2 14.5v-9A2.5 2.5 0 0 1 4.5 3h15A2.5 2.5 0 0 1 22 5.5v9a2.5 2.5 0 0 1-2.5 2.5h-2"/>${fill}<path d="M12 14l5.2 7H6.8z"/></g></svg>`,
    quote: `<svg viewBox="0 0 24 24"><path d="M4.5 3.5h15A2.5 2.5 0 0 1 22 6v9a2.5 2.5 0 0 1-2.5 2.5H12l-5 4v-4H4.5A2.5 2.5 0 0 1 2 15V6a2.5 2.5 0 0 1 2.5-2.5z"/>${fill}<path d="M8 8.2h2.6v2.2c0 1.5-.7 2.5-2 3l-.5-.9c.6-.3.9-.8 1-1.4H8zM13.4 8.2H16v2.2c0 1.5-.7 2.5-2 3l-.5-.9c.6-.3.9-.8 1-1.4h-1.1z"/></g></svg>`,
    list: `<svg viewBox="0 0 24 24"><path d="M9 6h12M9 12h12M9 18h12"/>${fill}<circle cx="4" cy="6" r="1.4"/><circle cx="4" cy="12" r="1.4"/><circle cx="4" cy="18" r="1.4"/></g></svg>`,
    note: `<svg viewBox="0 0 24 24"><path d="M9 18V5.5l11-2.4v12.4"/>${fill}<circle cx="6.4" cy="18" r="2.9"/><circle cx="17.4" cy="15.5" r="2.9"/></g></svg>`,
    moon: '<svg viewBox="0 0 24 24"><path d="M20.5 14.3A8.6 8.6 0 1 1 9.7 3.5a7 7 0 0 0 10.8 10.8z"/></svg>',
    star: '<svg viewBox="0 0 24 24"><path d="M12 3.2l2.7 5.5 6 .9-4.35 4.2 1 6L12 17l-5.35 2.8 1-6L3.3 9.6l6-.9z"/></svg>',
    more: '<svg viewBox="0 0 24 24" class="fill"><circle cx="5.5" cy="12" r="1.9"/><circle cx="12" cy="12" r="1.9"/><circle cx="18.5" cy="12" r="1.9"/></svg>',
    heart: '<svg viewBox="0 0 24 24"><path d="M12 20.2s-7.6-4.6-9.3-9.4C1.5 7.4 3.7 4 7.2 4c2 0 3.6 1.1 4.8 2.8C13.2 5.1 14.8 4 16.8 4c3.5 0 5.7 3.4 4.5 6.8-1.7 4.8-9.3 9.4-9.3 9.4z"/></svg>',
    share: '<svg viewBox="0 0 24 24"><path d="M12 3v12M7.5 7.5L12 3l4.5 4.5M5 11v8.5A1.5 1.5 0 0 0 6.5 21h11a1.5 1.5 0 0 0 1.5-1.5V11"/></svg>',
    eq: '<svg viewBox="0 0 24 24"><path d="M4 10v4M8 6v12M12 9v6M16 4v16M20 10v4"/></svg>',
    search: '<svg viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5L21 21"/></svg>',
    plus: '<svg viewBox="0 0 24 24"><path d="M12 4v16M4 12h16"/></svg>',
    gear: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M12 2.5v2.4M12 19.1v2.4M2.5 12h2.4M19.1 12h2.4M5.3 5.3L7 7M17 17l1.7 1.7M5.3 18.7L7 17M17 7l1.7-1.7"/><circle cx="12" cy="12" r="6.6"/></svg>',
    wand: '<svg viewBox="0 0 24 24"><path d="M4 20L14.5 9.5M16 3v3M14.5 4.5h3M20 8v2.5M18.75 9.25h2.5M12.8 7.8l3.4 3.4"/></svg>',
    house: '<svg viewBox="0 0 24 24"><path d="M3.5 10.4L12 3.5l8.5 6.9V20a1 1 0 0 1-1 1H15v-6.5H9V21H4.5a1 1 0 0 1-1-1z"/></svg>',
    chevron: '<svg viewBox="0 0 9 14" class="ch"><path d="M1.5 1.5L7 7l-5.5 5.5"/></svg>',
    clock: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
    mic: '<svg viewBox="0 0 24 24"><circle cx="15" cy="8.5" r="4.5"/><path d="M11.8 11.7L4 19.5 5.5 21l7.8-7.8"/></svg>',
    albums: '<svg viewBox="0 0 24 24"><rect x="3.5" y="7.5" width="13" height="13" rx="2"/><path d="M7.5 4h11a2 2 0 0 1 2 2v11"/></svg>',
    radio: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="2"/><path d="M7.8 7.8a6 6 0 0 0 0 8.4M16.2 7.8a6 6 0 0 1 0 8.4M4.9 4.9a10 10 0 0 0 0 14.2M19.1 4.9a10 10 0 0 1 0 14.2"/></svg>',
    phone: '<svg viewBox="0 0 24 24"><rect x="6.5" y="2.5" width="11" height="19" rx="2.6"/><path d="M10.5 18.5h3"/></svg>',
    folder: '<svg viewBox="0 0 24 24"><path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h4l2 2.5h7A2.5 2.5 0 0 1 21 10v7.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/></svg>',
    server: '<svg viewBox="0 0 24 24"><rect x="3.5" y="4" width="17" height="7" rx="2"/><rect x="3.5" y="13" width="17" height="7" rx="2"/><path d="M7.5 7.5h.01M7.5 16.5h.01"/></svg>',
    textlist: '<svg viewBox="0 0 24 24"><rect x="4.5" y="3" width="15" height="18" rx="2.5"/><path d="M8.5 8h7M8.5 12h7M8.5 16h4"/></svg>',
    check: '<svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
    signal: '<svg viewBox="0 0 18 12" class="fill"><rect y="8" width="3" height="4" rx=".8"/><rect x="5" y="5.5" width="3" height="6.5" rx=".8"/><rect x="10" y="3" width="3" height="9" rx=".8"/><rect x="15" width="3" height="12" rx=".8"/></svg>',
    wifi: '<svg viewBox="0 0 16 12" class="fill"><path d="M8 2.3c2.4 0 4.6.9 6.2 2.5l1.2-1.2A10.4 10.4 0 0 0 8 .6 10.4 10.4 0 0 0 .6 3.6l1.2 1.2A8.7 8.7 0 0 1 8 2.3zm0 3.4c1.5 0 2.9.6 3.9 1.6l1.2-1.2A7.2 7.2 0 0 0 8 4a7.2 7.2 0 0 0-5.1 2.1l1.2 1.2A5.5 5.5 0 0 1 8 5.7zM8 9c.6 0 1.1.2 1.5.6L8 11.4 6.5 9.6C6.9 9.2 7.4 9 8 9z"/></svg>',
    battery: '<svg viewBox="0 0 27 12"><rect x=".6" y=".6" width="23" height="10.8" rx="3.2" fill="none" stroke="currentColor" stroke-opacity=".4" stroke-width="1"/><rect x="2.3" y="2.3" width="19.6" height="7.4" rx="1.8" fill="currentColor" stroke="none"/><path d="M25 4v4c.8-.3 1.4-1.1 1.4-2S25.8 4.3 25 4z" fill="currentColor" fill-opacity=".45" stroke="none"/></svg>',
  };

  // ---------------------------------------------------------------------------
  // Generated covers (CoverDesigner.swift styles and palettes)

  const PAL = {
    night: ['#12103A', '#3B2F9E', '#7B6CF6', '#1D3A6B'],
    sunset: ['#5B1A3A', '#F0503C', '#FFB347', '#2B1B5A'],
    ocean: ['#062A44', '#0E7C9B', '#5EE1D0', '#123F73'],
    neon: ['#1A0B3B', '#E63DAF', '#3DE0F5', '#5B2BD9'],
    forest: ['#0B2A1C', '#2E8B57', '#B7E36B', '#153F3A'],
    rose: ['#3D0F22', '#D6336C', '#FFB3C7', '#6A1B4D'],
    mono: ['#0E0E10', '#3A3A40', '#C9C9D0', '#1C1C20'],
    gold: ['#2B1A05', '#B9770E', '#FFD976', '#5C3A0C'],
  };
  const STYLES = ['mesh', 'orbs', 'rings', 'waves', 'sunburst', 'stripes', 'halftone', 'aurora'];

  function coverHTML(style, palName, seed = 1) {
    const [a, b, c, d] = PAL[palName];
    const r = rng(seed * 9973 + style.length * 101);
    const P = () => Math.round(r() * 100);
    let bg = a, inner = '';
    switch (style) {
      case 'mesh':
        bg = `radial-gradient(at ${P()}% ${P()}%, ${c} 0, transparent 55%), radial-gradient(at ${P()}% ${P()}%, ${d} 0, transparent 50%), radial-gradient(at ${P()}% ${P()}%, ${b} 0, transparent 60%), linear-gradient(135deg, ${a}, ${b})`;
        break;
      case 'orbs': {
        const orbs = [c, b, d, c].map(col => { const s = 16 + r() * 24; return `radial-gradient(circle at ${P()}% ${P()}%, ${col} 0 ${s.toFixed(1)}%, transparent ${(s + 1.5).toFixed(1)}%)`; });
        bg = `${orbs.join(', ')}, linear-gradient(160deg, ${a}, ${d})`;
        break;
      }
      case 'rings':
        bg = `repeating-radial-gradient(circle at ${20 + P() * 0.6}% ${20 + P() * 0.6}%, ${c} 0 3.5%, ${b} 3.5% 8%, ${a} 8% 12%)`;
        break;
      case 'waves':
        inner = '<svg viewBox="0 0 100 100" preserveAspectRatio="none">' + [d, b, c, a].map((col, i) => {
          const y = 28 + i * 18, amp = 5 + r() * 9;
          return `<path d="M0 ${y} C 25 ${y - amp}, 25 ${y + amp}, 50 ${y} S 75 ${y - amp}, 100 ${y} V100 H0Z" fill="${col}" stroke="none"/>`;
        }).join('') + '</svg>';
        break;
      case 'sunburst':
        bg = `radial-gradient(circle at 50% 108%, ${c} 0 22%, transparent 22.5%), repeating-conic-gradient(from ${P()}deg at 50% 108%, ${b} 0 7deg, ${a} 7deg 14deg)`;
        break;
      case 'stripes':
        bg = `repeating-linear-gradient(${-30 - Math.round(P() * 0.6)}deg, ${a} 0 11%, ${b} 11% 20%, ${c} 20% 26%, ${d} 26% 37%)`;
        break;
      case 'halftone':
        bg = `linear-gradient(135deg, transparent 25%, ${a} 92%), radial-gradient(circle, ${c} 30%, transparent 33%) 0 0 / 9% 9%, linear-gradient(135deg, ${b}, ${d})`;
        break;
      case 'aurora':
        bg = `radial-gradient(ellipse 90% 28% at ${30 + Math.round(P() * 0.3)}% 38%, ${c}, transparent 70%), radial-gradient(ellipse 80% 25% at ${50 + Math.round(P() * 0.3)}% 58%, ${b}, transparent 70%), radial-gradient(ellipse 70% 22% at 40% 76%, ${d}, transparent 70%), linear-gradient(180deg, ${a}, ${d})`;
        break;
    }
    return `<div class="cover" style="background:${bg}">${inner}</div>`;
  }

  // The demo library (DemoContent.swift)
  const SONGS = [
    { t: 'Glass Horizon', a: 'Aurora Vale', style: 'aurora', pal: 'night', seed: 3 },
    { t: 'Midnight Ferry', a: 'Neon Harbor', style: 'waves', pal: 'ocean', seed: 7 },
    { t: 'Chrome Rain', a: 'Neon Harbor', style: 'stripes', pal: 'neon', seed: 11 },
    { t: 'Backyard Thunder', a: 'Paper Tigers', style: 'sunburst', pal: 'sunset', seed: 5 },
    { t: 'Golden Hour', a: 'Lumen', style: 'orbs', pal: 'gold', seed: 9 },
    { t: 'Paper Moons', a: 'Aurora Vale', style: 'halftone', pal: 'rose', seed: 2 },
    { t: 'Soft Echoes', a: 'Lumen', style: 'rings', pal: 'ocean', seed: 4 },
    { t: 'Runaway Kite', a: 'Paper Tigers', style: 'mesh', pal: 'forest', seed: 8 },
    { t: 'Last Train Home', a: 'Neon Harbor', style: 'rings', pal: 'night', seed: 6 },
    { t: 'Small Sun', a: 'Lumen', style: 'sunburst', pal: 'gold', seed: 12 },
    { t: 'Sunday Static', a: 'Paper Tigers', style: 'mesh', pal: 'mono', seed: 10 },
    { t: 'Slow Signal', a: 'Aurora Vale', style: 'waves', pal: 'rose', seed: 1 },
  ].map(s => ({ ...s, tint: PAL[s.pal][1] }));
  const coverOf = s => coverHTML(s.style, s.pal, s.seed);

  const LYRICS = [
    ['Lights are fading over the harbor', 'Die Lichter verblassen über dem Hafen'],
    ['I hear the static turning into song', 'Ich höre, wie das Rauschen zum Lied wird'],
    ['Hold on to the color of the evening', 'Halt die Farbe des Abends fest'],
    ['We were never meant to stay this long', 'Wir wollten nie so lange bleiben'],
    ['Paper moons above the empty street', 'Papiermonde über der leeren Straße'],
    ['Every signal finds a way back home', 'Jedes Signal findet den Weg nach Hause'],
    ['Carry me through the quiet hours', 'Trag mich durch die stillen Stunden'],
    ['Let the whole world fall away', 'Lass die ganze Welt verschwinden'],
  ];

  // ---------------------------------------------------------------------------
  // Themes (Themes.swift built-ins). Each has img/home-<id>.webp and img/player-<id>.webp.

  const DEF = {
    accent: '#FF3B5C', np: 'artworkTint', layout: 'classic', corner: 1, shape: 'rounded', frame: 'none',
    font: 'standard', width: 'standard', caps: false, texture: 'none', play: 'glass', playScale: 1,
    align: 'leading', titleAbove: false, modes: true, bar: ['airplay', 'views', 'sleep'], icons: 'standard',
    glow: false, eqBadge: true, gap: 20, ink: null, bg: null, song: 0,
  };
  const THEMES = [
    { id: 'mrsc', name: 'MRSC', song: 3, cap: 'The original. Red, white and a little loud.' },
    { id: 'green-room', name: 'Green Room', accent: '#1DB954', layout: 'large', corner: 0.35, bar: ['airplay', 'sp', 'lyrics', 'share', 'queue'], song: 7, cap: 'Near-black, bright green, big covers. Reminds you of something? Weird.' },
    { id: 'crimson', name: 'Crimson', accent: '#FA2D48', np: 'blurredArtwork', corner: 1.1, play: 'plain', playScale: 1.1, modes: false, glow: true, bar: ['lyrics', 'sp', 'airplay', 'sp', 'queue'], song: 5, cap: 'Soft glass, blurred covers, glowing lyrics. Feels very Cupertino.' },
    { id: 'tube', name: 'Tube', accent: '#FF0033', np: 'blurredArtwork', layout: 'large', corner: 0.5, align: 'center', gap: 30, bar: ['sp', 'views', 'sp'], song: 2, cap: 'Pitch black, red highlights. Zero ads before your song. We checked.' },
    { id: 'cloud', name: 'Cloud', accent: '#FF5500', np: 'blurredArtwork', layout: 'large', corner: 0.3, titleAbove: true, play: 'accent', bar: ['favorite', 'sp', 'lyrics', 'sp', 'queue', 'sp', 'more'], song: 4, cap: 'Loud orange, everything at a glance. Visible from space.' },
    { id: 'tide', name: 'Tide', accent: '#F2F2F2', np: 'black', layout: 'large', corner: 0.15, shape: 'sharp', width: 'expanded', icons: 'outline', play: 'plain', align: 'center', gap: 30, eqBadge: false, bar: ['airplay', 'sp', 'lyrics', 'queue'], song: 10, cap: 'Black, white, wide letters. Takes itself extremely seriously.' },
    { id: 'pulse', name: 'Pulse', accent: '#A238FF', font: 'rounded', play: 'accent', playScale: 1.05, bar: ['favorite', 'views', 'sleep'], song: 0, cap: 'Deep purple, rounded letters. 2 a.m. energy at any time of day.' },
  ].map(t => ({ ...DEF, ...t }));
  const themeById = id => THEMES.find(t => t.id === id) || THEMES[0];

  // ---------------------------------------------------------------------------
  // Phone mockups. Only drawn when a screenshot is missing.

  const FONTS = {
    standard: 'var(--font)',
    rounded: "ui-rounded, 'SF Pro Rounded', Nunito, var(--font)",
    serif: "ui-serif, 'New York', 'Iowan Old Style', Georgia, serif",
    mono: "ui-monospace, 'SF Mono', Menlo, monospace",
  };
  const WIDTHS = { standard: ['normal', '-0.01em'], condensed: ['condensed', '-0.04em'], expanded: ['expanded', '0.06em'] };

  const bgCSS = bg => {
    const [a, b = a, c = b] = bg.colors;
    if (bg.type === 'gradient') return `linear-gradient(180deg, ${a}, ${b})`;
    if (bg.type === 'mesh') return `radial-gradient(at 20% 20%, ${b} 0, transparent 55%), radial-gradient(at 80% 70%, ${c} 0, transparent 55%), ${a}`;
    return a;
  };
  const isLightNP = t => t.np === 'themeColors' && t.bg && lum(t.bg.colors[0]) > 0.55;

  function mockAttrs(t, light) {
    const [stretch, track] = WIDTHS[t.width] || WIDTHS.standard;
    const ink = t.np === 'themeColors' && t.ink ? t.ink : light ? '#111111' : '#ffffff';
    const cls = [`layout-${t.layout}`, `shape-${t.shape}`, `frame-${t.frame}`, `play-${t.play}`, `align-${t.align}`, `icons-${t.icons}`, t.glow ? 'glow' : '', light ? 'is-light' : ''].join(' ');
    const vars = `--m-ink:${ink};--m-accent:${t.accent};--m-corner:${t.corner};--m-font:${FONTS[t.font]};--m-stretch:${stretch};--m-track:${track};--m-case:${t.caps ? 'uppercase' : 'none'};--m-playscale:${t.playScale};--m-gap:calc(${t.gap} * var(--pt))`;
    return `class="mock ${cls}" style="${vars}"`;
  }
  const statusBar = () => `<div class="m-status"><span>9:41</span><span class="icons">${ICON.signal}${ICON.wifi}${ICON.battery}</span></div>`;
  const tex = t => (t.texture !== 'none' ? `<div class="m-tex ${t.texture}"></div>` : '');

  function npBackground(t, s) {
    switch (t.np) {
      case 'blurredArtwork': return `<div class="m-bg" style="background:#000;--m-scrim:linear-gradient(180deg, rgba(0,0,0,.15), rgba(0,0,0,.65))">${coverOf(s)}</div>`;
      case 'themeColors': return `<div class="m-bg" style="background:${t.bg ? bgCSS(t.bg) : '#101014'}"></div>`;
      case 'black': return '<div class="m-bg" style="background:#000"></div>';
      default: return `<div class="m-bg" style="background:linear-gradient(180deg, ${s.tint} 0%, color-mix(in srgb, ${s.tint} 60%, #000) 55%, #000 100%)"></div>`;
    }
  }
  function barItem(k, view = 0) {
    if (k === 'sp') return '<span class="sp"></span>';
    if (k === 'views') return `<span class="views gl">${[ICON.note, ICON.quote, ICON.list].map((ic, i) => `<span class="${i === view ? 'on' : ''}">${ic}</span>`).join('')}</span>`;
    const map = { airplay: ICON.airplay, lyrics: ICON.quote, queue: ICON.list, sleep: ICON.moon, favorite: ICON.heart, share: ICON.share, more: ICON.more, eq: ICON.eq };
    return `<span class="b gl">${map[k]}</span>`;
  }
  const progress = t => `<div class="np-prog"><div class="track"><div class="fill"></div></div><div class="times"><span>1:24</span>${t.eqBadge ? `<span class="badge">${ICON.eq}Vocal Booster</span>` : ''}<span>-2:18</span></div></div>`;
  const controls = t => `<div class="np-ctrl ${t.modes ? '' : 'no-modes'}">${t.modes ? `<span class="mode">${ICON.shuffle}</span>` : ''}<span class="skip" data-act="prev">${ICON.prev}</span><span class="play" data-act="play">${ICON.pause}</span><span class="skip" data-act="next">${ICON.next}</span>${t.modes ? `<span class="mode">${ICON.repeat}</span>` : ''}</div>`;
  function waveBars(seed) {
    const r = rng(seed * 17);
    return Array.from({ length: 34 }, () => `<i style="--h:${Math.round(35 + r() * 65)}%;animation-delay:-${(r() * 1.1).toFixed(2)}s"></i>`).join('');
  }

  function npHTML(t, songIdx) {
    const s = SONGS[((songIdx % SONGS.length) + SONGS.length) % SONGS.length];
    const light = isLightNP(t);
    const cov = coverOf(s);
    let art;
    if (t.layout === 'vinyl') art = `<div class="np-art-wrap"><div class="np-vinyl"><div class="disc"><div class="label">${cov}</div></div><div class="spindle"></div></div></div>`;
    else if (t.layout === 'minimal') art = `<div class="np-min"><div class="np-art">${cov}</div><div class="np-wave">${waveBars(s.seed)}</div></div>`;
    else art = `<div class="np-art-wrap"><div class="np-art">${cov}</div></div>`;
    const title = `<div class="np-title"><div class="tt"><div class="t1">${s.t}</div><div class="t2">${s.a}</div></div><span class="gc gl">${ICON.star}</span><span class="gc gl">${ICON.more}</span></div>`;
    const rows = (t.titleAbove ? [title, art] : [art, title]).concat(progress(t), controls(t), `<div class="np-bar">${t.bar.map(k => barItem(k)).join('')}</div>`);
    return `<div ${mockAttrs(t, light)}>${npBackground(t, s)}${tex(t)}${statusBar()}<div class="np-grab"></div><div class="np-col">${rows.join('')}</div><div class="m-home"></div></div>`;
  }

  function lyricsHTML(t, songIdx) {
    const s = SONGS[songIdx];
    const head = `<div class="ly-head"><div class="mini">${coverOf(s)}</div><div><div class="t1">${s.t}</div><div class="t2">${s.a}</div></div><div class="chips"><span class="gl">${ICON.quote}</span><span class="gl">${ICON.more}</span></div></div>`;
    const lines = `<div class="ly-lines"><div class="ly-track" data-i="1">${LYRICS.map(([l], i) => `<div class="ly-line${i === 1 ? ' on' : ''}">${l}</div>`).join('')}</div></div>`;
    const bottom = `<div class="ly-bottom">${progress(t)}${controls(t)}<div class="np-bar">${['airplay', 'views', 'sleep'].map(k => barItem(k, 1)).join('')}</div></div>`;
    return `<div ${mockAttrs(t, false)}>${npBackground(t, s)}${statusBar()}${head}${lines}${bottom}<div class="m-home"></div></div>`;
  }

  function libraryHTML(t) {
    const rows = [
      ['Songs', '#FF9500', '#FF991A', ICON.note, '1,284'], ['Playlists', '#8C78FF', '#4D40E6', ICON.list, '23'],
      ['Artists', '#F266F7', '#B326E0', ICON.mic, '312'], ['Albums', '#FF6680', '#F52659', ICON.albums, '146'],
      ['Favorites', '#FFCC33', '#F28C1A', ICON.star, '87'], ['Recently Played', '#73BFFF', '#3373F2', ICON.clock, ''],
      ['Radio', '#FF598C', '#BF1A80', ICON.radio, ''],
    ].map(([n, c1, c2, ic, ct]) => `<div class="lib-row"><span class="ic" style="background:linear-gradient(135deg, ${c1}, ${c2})">${ic}</span><span class="nm">${n}</span><span class="ct">${ct}</span>${ICON.chevron}</div>`).join('');
    const pins = [['Late Night', 8], ['Demo Mix', 4], ['Fields of Light', 9]].map(([n, i]) => `<div class="pin"><div class="cv">${coverOf(SONGS[i])}</div><div>${n}</div></div>`).join('');
    const s = SONGS[3];
    return `<div ${mockAttrs({ ...t, np: 'artworkTint' }, true).replace('class="mock', 'class="mock is-light')}>${statusBar()}
      <div class="lib-tools"><span class="gl">${ICON.wand}</span><span class="gl">${ICON.gear}</span></div>
      <div class="lib-title">Library</div><div class="lib-pins">${pins}</div><div class="lib-rows">${rows}</div>
      <div class="lib-mini gl"><div class="cv">${coverOf(s)}</div><div class="tt"><div class="t1">${s.t}</div><div class="t2">${s.a}</div></div><span class="pl">${ICON.pause}</span>${ICON.next}</div>
      <div class="lib-bar"><span class="round gl">${ICON.plus}</span><span class="tabs gl"><span>${ICON.house}Home</span><span class="on">${ICON.note}Library</span></span><span class="round gl">${ICON.search}</span></div>
      <div class="m-home"></div></div>`;
  }

  // Status bar colour per screenshot, written by tools/build_shots.py
  const SHOT_INK = fetch('img/shots.json').then(r => r.json()).catch(() => ({}));
  const phoneHTML = inner => `<div class="phone"><div class="phone-bezel"><div class="screen">${inner}<div class="di"></div></div></div></div>`;
  const drawMock = (mock, t, s) => (mock === 'lyrics' ? lyricsHTML(t, s) : mock === 'library' ? libraryHTML(t) : npHTML(t, s));
  function mountPhone(host, { mock = 'np', theme, song, shot, label, lazy = false }) {
    const t = theme || THEMES[0];
    const s = song ?? t.song;
    const alt = label || `MRSC music player for iPhone in the ${t.name} theme`;
    if (!shot) {
      host.setAttribute('role', 'img');
      host.setAttribute('aria-label', alt);
      host.innerHTML = phoneHTML(drawMock(mock, t, s));
      return;
    }
    host.innerHTML = phoneHTML(`<img class="shot" alt="${alt}" width="720" height="1565" decoding="async"${lazy ? ' loading="lazy"' : ''} src="img/${shot}.webp">`);
    const screen = $('.screen', host);
    const img = $('img.shot', screen);
    img.addEventListener('error', () => { img.remove(); screen.insertAdjacentHTML('afterbegin', drawMock(mock, t, s)); }, { once: true });
    // The real status bar was erased from the screenshot; draw a clean 9:41 one.
    SHOT_INK.then(inks => {
      if (inks[shot] && img.isConnected) img.insertAdjacentHTML('afterend', `<div class="m-status shot-status" style="color:${inks[shot]}"><span>9:41</span><span class="icons">${ICON.signal}${ICON.wifi}${ICON.battery}</span></div>`);
    });
  }

  // Lyrics mocks scroll on their own.
  function tickLyricMocks() {
    $$('.ly-track').forEach(tr => {
      const lines = tr.children;
      const i = ((+tr.dataset.i || 0) + 1) % lines.length;
      tr.dataset.i = i;
      Array.from(lines).forEach((l, k) => l.classList.toggle('on', k === i));
      tr.style.transform = `translateY(${-lines[i].offsetTop + tr.parentElement.clientHeight * 0.3}px)`;
    });
  }

  // ---------------------------------------------------------------------------
  // Hero

  function setupHero() {
    $$('#heroPhones [data-mock]').forEach(el => {
      const t = themeById(el.dataset.theme);
      const labels = { np: 'MRSC Now Playing screen on iPhone with Liquid Glass controls', lyrics: 'MRSC synced, word-by-word lyrics in full screen', library: 'MRSC Home screen on iPhone' };
      mountPhone(el, { mock: el.dataset.mock, theme: t, shot: el.dataset.shot, label: labels[el.dataset.mock] });
    });
  }

  // ---------------------------------------------------------------------------
  // Carousel

  function setupCarousel() {
    const track = $('#carouselTrack');
    const dots = $('#carouselDots');
    const playBtn = $('#carPlay');
    const flipIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19.5 10.5A7.6 7.6 0 0 0 6 6.8M4.5 3.5v3.8h3.8M4.5 13.5A7.6 7.6 0 0 0 18 17.2M19.5 20.5v-3.8h-3.8"/></svg>';
    track.innerHTML = THEMES.map(t => `<div class="car-card" role="group" aria-roledescription="slide" aria-label="${t.name}">
        <div class="car-flip" role="button" tabindex="-1" aria-pressed="false" aria-label="Flip ${t.name} to see the player">
          <div class="flip-inner"><div class="flip-face flip-front" data-id="${t.id}"></div><div class="flip-face flip-back" data-id="${t.id}"></div></div>
        </div>
        <div class="car-cap"><div class="nm"><i style="--sw:${t.accent}"></i>${t.name}</div><p>${t.cap}</p><button class="flip-hint" type="button" tabindex="-1">${flipIcon}<span>See the player</span></button></div>
      </div>`).join('');
    $$('.flip-front', track).forEach((el, i) => mountPhone(el, { mock: 'library', theme: THEMES[i], shot: `home-${THEMES[i].id}`, label: `MRSC music player Home screen in the ${THEMES[i].name} theme`, lazy: i > 2 }));
    $$('.flip-back', track).forEach((el, i) => mountPhone(el, { theme: THEMES[i], shot: `player-${THEMES[i].id}`, label: `MRSC Now Playing screen in the ${THEMES[i].name} theme`, lazy: true }));
    const cards = $$('.car-card', track);
    dots.innerHTML = cards.map((c, i) => `<button type="button" role="tab" aria-label="${THEMES[i].name}"></button>`).join('');
    const dotBtns = $$('button', dots);

    const flips = $$('.car-flip', track);
    const hints = $$('.flip-hint', track);
    const setFlip = (i, on) => {
      flips[i].setAttribute('aria-pressed', on);
      $('span', hints[i]).textContent = on ? 'Back to Home' : 'See the player';
    };
    let active = -1, raf = 0, paused = reduceMotion, dragged = false;
    const centerOf = i => cards[i].offsetLeft + cards[i].offsetWidth / 2 - track.clientWidth / 2;
    const goTo = (i, smooth = true) => track.scrollTo({ left: centerOf((i + cards.length) % cards.length), behavior: smooth && !reduceMotion ? 'smooth' : 'auto' });
    function update() {
      raf = 0;
      const mid = track.scrollLeft + track.clientWidth / 2;
      let best = 0, bestD = Infinity;
      cards.forEach((c, i) => {
        const d = (c.offsetLeft + c.offsetWidth / 2 - mid) / (c.offsetWidth * 1.1);
        const ad = Math.min(Math.abs(d), 1);
        c.style.setProperty('--s', (1 - ad * 0.13).toFixed(3));
        c.style.setProperty('--c', Math.max(0, 1 - Math.abs(d) * 1.8).toFixed(3));
        if (Math.abs(d) < bestD) { bestD = Math.abs(d); best = i; }
      });
      if (best !== active) {
        // Moving on flips the card you left back to its Home side.
        flips.forEach((f, k) => { if (k !== best && f.getAttribute('aria-pressed') === 'true') setFlip(k, false); });
        flips.forEach((f, k) => { f.tabIndex = k === best ? 0 : -1; hints[k].tabIndex = k === best ? 0 : -1; });
      }
      active = best;
      dotBtns.forEach((b, i) => b.setAttribute('aria-selected', i === active));
    }
    const schedule = () => { if (!raf) raf = requestAnimationFrame(update); };
    track.addEventListener('scroll', schedule, { passive: true });
    addEventListener('resize', () => { goTo(active, false); schedule(); });

    const setPaused = p => {
      paused = p;
      playBtn.classList.toggle('paused', p);
      playBtn.setAttribute('aria-label', p ? 'Play slideshow' : 'Pause slideshow');
    };
    setPaused(paused);
    const stopAuto = () => setPaused(true);
    const toggle = i => { stopAuto(); setFlip(i, flips[i].getAttribute('aria-pressed') !== 'true'); };
    flips.forEach((f, i) => {
      f.addEventListener('click', () => {
        if (dragged) return;
        if (i !== active) { stopAuto(); goTo(i); return; }
        toggle(i);
      });
      f.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(i); } });
    });
    hints.forEach((h, i) => h.addEventListener('click', () => (i === active ? toggle(i) : goTo(i))));
    playBtn.addEventListener('click', () => setPaused(!paused));
    $('#carPrev').addEventListener('click', () => { stopAuto(); goTo(active - 1); });
    $('#carNext').addEventListener('click', () => { stopAuto(); goTo(active + 1); });
    dotBtns.forEach((b, i) => b.addEventListener('click', () => { stopAuto(); goTo(i); }));
    track.addEventListener('wheel', e => { if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) stopAuto(); }, { passive: true });
    track.addEventListener('touchstart', stopAuto, { passive: true });
    track.tabIndex = 0;
    track.addEventListener('keydown', e => {
      if (e.key === 'ArrowRight') { stopAuto(); goTo(active + 1); e.preventDefault(); }
      if (e.key === 'ArrowLeft') { stopAuto(); goTo(active - 1); e.preventDefault(); }
    });

    // Mouse drag
    let drag = null;
    track.addEventListener('pointerdown', e => {
      if (e.pointerType !== 'mouse' || e.button !== 0) return;
      drag = { x: e.clientX, left: track.scrollLeft, moved: false };
      stopAuto();
    });
    addEventListener('pointermove', e => {
      if (!drag) return;
      const dx = e.clientX - drag.x;
      if (!drag.moved && Math.abs(dx) > 4) { drag.moved = true; track.classList.add('dragging'); }
      if (drag.moved) track.scrollLeft = drag.left - dx;
    });
    addEventListener('pointerup', () => {
      if (!drag) return;
      const moved = drag.moved;
      drag = null;
      track.classList.remove('dragging');
      if (moved) { dragged = true; setTimeout(() => (dragged = false), 0); update(); goTo(active); }
    });

    watch(track);
    setInterval(() => { if (!paused && visible.has(track) && !document.hidden) goTo(active + 1); }, 3800);
    requestAnimationFrame(() => { goTo(0, false); update(); });
  }

  // ---------------------------------------------------------------------------
  // Mom mode

  function setupMom() {
    const btn = $('#momToggle');
    const word = $('.swear-word');
    btn.addEventListener('click', () => {
      const on = btn.getAttribute('aria-pressed') !== 'true';
      btn.setAttribute('aria-pressed', on);
      word.classList.add('flip');
      setTimeout(() => { word.textContent = on ? 'heck' : 'shit'; word.classList.remove('flip'); }, 230);
    });
  }

  // ---------------------------------------------------------------------------
  // Every knob (Themes.swift, PlayerCustomize.swift, Customize.swift, AudioLab.swift, Collections.swift)

  function setupKnobs() {
    $$('#knobPhones [data-shot]').forEach(el => mountPhone(el, { mock: 'library', shot: el.dataset.shot, label: `MRSC ${el.nextElementSibling.textContent} settings on iPhone`, lazy: true }));
    const ROWS = [
      ['Accent Color', 'Appearance', 'Solid Color', 'Gradient', 'Animated Mesh', 'Letter Width', 'Condensed', 'Expanded', 'All Caps', 'Custom Text Color', 'Film Grain', 'Paper', 'Halftone', 'Scanlines', 'Cover Shape', 'Record', 'Arch', 'White Border', 'Ink Outline', 'Glow', 'Blur', 'Transparency', 'Glass Intensity', 'Corner Radius', 'Rounded Font', 'Serif', 'Monospaced', 'Outline Icons', 'Snappy Animations'],
      ['Classic Player', 'Large Artwork', 'Vinyl', 'Minimal', 'Blurred Artwork', 'Album Art Size', 'Reorder Player Rows', 'Button Row', 'Play Button Style', 'Play Button Size', 'Centered Title', 'Times Under Progress Bar', 'Spacing', 'Capsule Mini Player', 'Progress Bar Mini Player', 'Compact Queue', 'Lyrics Size', 'Centered Lyrics', 'Glow on Current Line', 'Word-by-Word', '13 Menu Items', 'Tab Bar', '31 Tab Icons', 'Rename Tabs', 'Home Sections', 'Shortcut Tiles', 'App Icon Color', 'Startup Animation'],
      ['10-Band EQ', 'Vocal Booster', 'EQ per Headphone', 'EQ per Song', 'EQ per Album', 'Preamp', 'Bass', 'Treble', 'Loudness Normalization', 'ReplayGain', 'Limiter', 'Compressor', 'Mono Audio', 'Balance', 'Spatial Audio', 'Head Tracking', 'DJ Mode', 'Crossfade 1–20 s', 'Filter Sweep', 'Bass Swap', 'Echo Out', 'Gapless', 'Beat Matching', 'Skip Silence', 'Smart Shuffle', 'Playback Speed', 'Sleep Timer Fade', 'Queue Presets'],
    ];
    $('#knobWall').innerHTML = ROWS.map((row, r) => {
      const items = row.map((k, i) => `<span class="knob${(i * 7 + r * 3) % 9 === 0 ? ' hot' : ''}">${k}</span>`).join('');
      return `<div class="knob-row${r % 2 ? ' rev' : ''}"><div class="knob-track">${items}${items.replace(/class="knob/g, 'aria-hidden="true" class="knob')}</div></div>`;
    }).join('');
  }

  // ---------------------------------------------------------------------------
  // Feature tiles

  function setupSleeves() {
    const SLEEVES = [
      ['This iPhone', 'Files & iCloud Drive', '#66CCD6', ICON.phone],
      ['A Folder', 'Stays in sync', '#F7A34D', ICON.folder],
      ['My Server', 'Jellyfin · Navidrome', '#9E8CFA', ICON.server],
      ['A Song List', 'Paste “Artist – Title”', '#F5738F', ICON.textlist],
    ];
    $('#sleeves').innerHTML = SLEEVES.map(([n, s, c, ic]) => `<div class="sleeve" style="--c:${c}"><div class="rec"></div><div class="jacket">${ic}<div><b>${n}</b><small>${s}</small></div></div></div>`).join('');
  }

  function setupLyricsDemo() {
    const root = $('#lyricsDemo');
    const s = SONGS[0];
    root.innerHTML = `<div class="ld-head"><div class="cv">${coverOf(s)}</div><div><b>${s.t}</b><small>${s.a}</small></div><button class="ld-tr" type="button" aria-pressed="false">Translate</button></div>
      <div class="ld-view"><div class="ld-track">${LYRICS.map(([en, de]) => `<div class="ld-line">${en.split(' ').map(w => `<span class="w">${w}</span>`).join(' ')}<small>${de}</small></div>`).join('')}</div></div>`;
    const track = $('.ld-track', root), view = $('.ld-view', root), lines = Array.from(track.children);
    let i = 0;
    const position = () => { track.style.transform = `translateY(${-lines[i].offsetTop + view.clientHeight * 0.16}px)`; };
    const btn = $('.ld-tr', root);
    btn.addEventListener('click', () => {
      const on = btn.getAttribute('aria-pressed') !== 'true';
      btn.setAttribute('aria-pressed', on);
      root.classList.toggle('translating', on);
      setTimeout(position, 520);
    });
    watch(root);
    (async () => {
      for (;;) {
        await untilVisible(root);
        lines.forEach((l, k) => { l.classList.toggle('on', k === i); l.classList.toggle('past', k < i); });
        position();
        const words = $$('.w', lines[i]);
        words.forEach(w => w.classList.remove('lit'));
        for (const w of words) { w.classList.add('lit'); await wait(reduceMotion ? 0 : 290); }
        await wait(1000);
        i = (i + 1) % lines.length;
      }
    })();
  }

  function setupSearch() {
    const QUERIES = [
      ['fast songs from 2016', [['120+ BPM', 1], ['2016', 0]]],
      ['favorites under 3 min', [['★ Favorites', 1], ['Under 3:00', 0]]],
      ['never played', [['0 plays', 1]]],
      ['nie gespielt', [['0 plays', 1], ['Deutsch? Klar.', 0]]],
      ['something calm for reading', [['Calm', 1], ['Slow', 0], ['On-device AI', 0]]],
    ];
    const text = $('#searchText'), tapes = $('#tapes'), tile = watch($('.tile--search'));
    (async () => {
      for (let q = 0; ; q = (q + 1) % QUERIES.length) {
        await untilVisible(tile);
        const [query, parts] = QUERIES[q];
        for (let k = 1; k <= query.length; k++) { text.textContent = query.slice(0, k); await wait(reduceMotion ? 0 : 55); }
        await wait(450);
        tapes.innerHTML = parts.map(([label, red], k) => `<span class="tape${red ? ' red' : ''}" style="--r:${[-2.5, 1.8, -1, 2.2][k % 4]}deg">${label}</span>`).join('');
        for (const tp of $$('.tape', tapes)) { await wait(170); tp.classList.add('in'); }
        await wait(2400);
        $$('.tape', tapes).forEach(tp => tp.classList.remove('in'));
        for (let k = query.length; k >= 0; k--) { text.textContent = query.slice(0, k); await wait(reduceMotion ? 0 : 22); }
        await wait(300);
      }
    })();
  }

  function setupMix() {
    const fillBars = (el, seed, fn) => {
      const r = rng(seed);
      el.innerHTML = Array.from({ length: 56 }, (_, i) => `<i style="--h:${fn(i, r).toFixed(1)}%"></i>`).join('');
    };
    fillBars($('.mix-wave--a'), 3, (i, r) => 18 + 78 * Math.abs(Math.sin(i * 0.45)) * (0.5 + r() * 0.5));
    fillBars($('.mix-wave--b'), 9, (i, r) => 16 + 80 * Math.abs(Math.sin(i * 0.31 + 1)) * (0.45 + r() * 0.55));
  }

  function setupEQ() {
    const PRESETS = [
      ['Vocal Booster', [-2, -3, -3, 1, 3, 4, 4, 3, 1, 0]],
      ['Headphones', [3, 2, 1, 0, -1, 0, 1, 2, 3, 2]],
      ['Car', [5, 4, 2, 0, -1, -1, 0, 2, 3, 4]],
      ['That one album', [-2, 0, 3, 5, 2, -1, -3, 0, 4, 6]],
      ['Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]],
    ];
    const BANDS = ['32', '64', '125', '250', '500', '1K', '2K', '4K', '8K', '16K'];
    const faders = $('#eqFaders'), chips = $('#eqChips'), tile = watch($('.tile--eq'));
    faders.innerHTML = BANDS.map(b => `<div class="eq-f"><div class="rail"><span class="knob"></span></div><small>${b}</small></div>`).join('');
    chips.innerHTML = PRESETS.map(([n], i) => `<button type="button" class="chip" data-i="${i}">${n}</button>`).join('');
    const knobs = $$('.knob', faders), btns = $$('.chip', chips);
    let cur = 0, auto = true;
    const set = i => {
      cur = i;
      PRESETS[i][1].forEach((db, k) => knobs[k].style.setProperty('--y', `${50 - (db / 12) * 46}%`));
      btns.forEach((b, k) => b.setAttribute('aria-pressed', k === i));
    };
    btns.forEach((b, i) => b.addEventListener('click', () => { auto = false; set(i); }));
    set(0);
    setInterval(() => { if (auto && visible.has(tile) && !reduceMotion) set((cur + 1) % (PRESETS.length - 1)); }, 2600);
  }

  let coverRound = 1;
  function fillCovers(animate) {
    const grid = $('#coverGrid');
    if (!grid.children.length) grid.innerHTML = STYLES.map(() => '<div class="cv"></div>').join('');
    const pals = Object.keys(PAL);
    const r = rng(coverRound++ * 31 + 7);
    Array.from(grid.children).forEach((cv, k) => {
      const style = animate ? pick(STYLES, r) : STYLES[k];
      const html = coverHTML(style, animate ? pick(pals, r) : pals[(k * 3) % pals.length], Math.floor(r() * 1000)) + `<span>${style[0].toUpperCase() + style.slice(1)}</span>`;
      if (!animate || reduceMotion) { cv.innerHTML = html; return; }
      setTimeout(() => {
        cv.classList.add('flip');
        setTimeout(() => { cv.innerHTML = html; cv.classList.remove('flip'); }, 230);
      }, k * 45);
    });
  }

  function setupIconPicker() {
    const root = $('#iconPicker');
    BRAND.forEach(b => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'icon-opt';
      btn.setAttribute('role', 'radio');
      btn.setAttribute('aria-checked', b.id === brand);
      btn.style.setProperty('--c', b.c);
      btn.innerHTML = `<span class="ico"><svg viewBox="0 0 1024 1024" aria-hidden="true"></svg></span>${b.name}`;
      const letters = buildLogo($('svg', btn));
      showLetters(letters);
      btn.addEventListener('click', async () => {
        brand = b.id;
        store.set('mrsc-brand', b.id);
        applyBrand(b.id);
        $$('.icon-opt', root).forEach(o => o.setAttribute('aria-checked', o === btn));
        if (reduceMotion) return;
        resetLetters(letters);
        await wait(40);
        playStamps(letters, { gap: 150, shakeEl: $('.ico', btn), shakeScale: 0.6 });
      });
      root.append(btn);
    });
  }

  function setupVinyl() {
    const disc = $('#vinyl');
    const label = $('.vinyl-label', disc);
    const IDLE = 120; // deg/s, a lazy idle spin
    let angle = 0, vel = IDLE, dragging = false, lastA = 0, lastT = 0, lastTick = 0, prev = performance.now();
    const angleAt = e => { const r = disc.getBoundingClientRect(); return (Math.atan2(e.clientY - (r.top + r.height / 2), e.clientX - (r.left + r.width / 2)) * 180) / Math.PI; };
    disc.addEventListener('pointerdown', e => {
      dragging = true;
      disc.setPointerCapture(e.pointerId);
      lastA = angleAt(e);
      lastT = performance.now();
      vel = 0;
    });
    disc.addEventListener('pointermove', e => {
      if (!dragging) return;
      const a = angleAt(e), now = performance.now();
      let d = a - lastA;
      if (d > 180) d -= 360;
      if (d < -180) d += 360;
      angle += d;
      const dt = Math.max(1, now - lastT) / 1000;
      vel = vel * 0.6 + (d / dt) * 0.4;
      lastA = a;
      lastT = now;
      // A haptic tick at every groove, like the app (Android only, iOS has no web vibration).
      if (Math.abs(angle - lastTick) >= 24) { lastTick = angle; navigator.vibrate?.(3); }
    });
    const release = () => { dragging = false; vel = clamp(vel, -2400, 2400); };
    disc.addEventListener('pointerup', release);
    disc.addEventListener('pointercancel', release);
    watch(disc);
    const loop = now => {
      const dt = Math.min(0.05, (now - prev) / 1000);
      prev = now;
      if (!dragging) {
        vel += (IDLE - vel) * (1 - Math.exp(-dt * 0.9));
        angle += vel * dt;
      }
      if (visible.has(disc)) label.style.setProperty('--rot', `${angle % 360}deg`);
      requestAnimationFrame(loop);
    };
    if (!reduceMotion) requestAnimationFrame(loop);
  }

  function setupIsland() {
    const text = $('#islandText');
    let i = 0;
    setInterval(() => {
      if (document.hidden || reduceMotion) return;
      text.classList.add('swap');
      setTimeout(() => { i = (i + 1) % LYRICS.length; text.textContent = LYRICS[i][0]; text.classList.remove('swap'); }, 300);
    }, 3200);
  }

  function setupOrganize() {
    const FIXES = [
      ['Misspelled artists', '4'],
      ['Duplicate albums', '2'],
      ['Missing covers', '14'],
      ['Swapped artist and title', '3'],
      ['Missing lyrics', '27'],
    ];
    const list = $('#orgList'), tile = watch($('.tile--organize'));
    list.innerHTML = FIXES.map(([n, d]) => `<div class="org-item"><span class="ck">${ICON.check}</span><span>${n}</span><em>${d}</em></div>`).join('') + '<div class="org-done">Everything looks tidy.</div>';
    const items = $$('.org-item', list), done = $('.org-done', list);
    (async () => {
      for (;;) {
        await untilVisible(tile);
        await wait(600);
        for (const it of items) { it.classList.add('done'); await wait(reduceMotion ? 0 : 420); }
        done.classList.add('show');
        await wait(3600);
        items.forEach(it => it.classList.remove('done'));
        done.classList.remove('show');
        await wait(900);
      }
    })();
  }

  // ---------------------------------------------------------------------------
  // Trusted by + reviews

  // Memoji faces from github.com/Wimell/Tapback-Memojis (MIT, see img/memoji/LICENSE)
  const face = id => `<img class="face" src="img/memoji/${id}.webp" alt="" width="72" height="72" loading="lazy" decoding="async">`;

  function setupMarquees() {
    const LOGOS = [
      ['l-serif', `${face(56)}Mom`, "<small>(5 stars, didn't ask what it does)</small>"],
      ['l-heavy', `${face(10)}The Developer`, '<small>daily</small>'],
      ['l-mono', `${face(49)}a_guy_with_a_NAS`],
      ['l-round', 'Several Group Chats'],
      ['l-strike', 'Zero VCs'],
      ['l-wide', `${face(52)}Your Future Self`],
      ['l-thin', 'the cat', '<small>(walked across the screen)</small>'],
      ['l-serif', `${face(40)}People With 400 GB of FLAC`],
      ['l-heavy', 'Not a Single Record Label'],
      ['l-round', `${face(21)}That Friend Who Still Burns CDs`],
      ['l-mono', 'localhost:3000'],
      ['l-wide', 'Our Discord'],
    ];
    const REVIEWS = [
      [5, "I spent three hours picking a font and didn't listen to a single song.", 'Probably you, next week', 18],
      [5, 'Finally, my music player matches my outfit.', 'Someone with a lot of outfits', 14],
      [5, "It's free? What's the catch?", 'Everyone. There is no catch.', 7],
      [5, 'My home server has never felt so seen.', 'A NAS in a closet', 49],
      [5, 'I flicked the record on the welcome screen for ten minutes. Then I flicked it some more.', 'A grown adult', 5],
      [5, 'I read the source code. There is a setting for the settings.', 'A developer, unfortunately', 10],
      [4, 'Took one star off because now my old music app looks boring.', 'A recovering subscriber', 22],
      [5, "It wrote lyrics for a song that doesn't have lyrics. I'm a little scared.", 'Impressed, slightly scared', 15],
      [5, 'Made it look exactly like my old app. Then made it look nothing like it.', 'A person with commitment issues', 37],
    ];
    const logos = LOGOS.map(([c, n, extra = '']) => `<span class="logo ${c}">${n}${extra}</span>`).join('');
    // Every few reviews a Discord or Ko-fi card rides along: same shape as a review, the logo where the stars go.
    const DISCORD = [
      'come for the testflight. stay for the theme wars.',
      '<span data-dc-count>it\'s early. like, really early.</span>',
      'we have a discord. it\'s mostly people arguing about fonts.',
    ];
    const discordCard = (text, copy) => `<a class="review dc-card" href="${LINKS.discord}" target="_blank" rel="noopener"${copy ? ' aria-hidden="true" tabindex="-1"' : ''}>
      <svg class="dc-logo" viewBox="0 0 24 24" aria-hidden="true"><use href="#i-discord"/></svg>
      <q>${text}</q>
      <span class="who"><img class="face" src="assets/icon.svg" alt="" width="40" height="40"><cite>MRSC on Discord<small>tap to join</small></cite><span class="dc-go" aria-hidden="true">→</span></span>
    </a>`;
    const KOFI = [
      'no ads means someone has to buy the coffee.',
      'every setting in this app was built on coffee. this is where the coffee comes from.',
    ];
    const kofiCard = (text, copy) => `<a class="review dc-card kf-card" href="${LINKS.kofi}" target="_blank" rel="noopener"${copy ? ' aria-hidden="true" tabindex="-1"' : ''}>
      <svg class="dc-logo" viewBox="0 0 24 24" aria-hidden="true"><use href="#i-kofi"/></svg>
      <q>${text}</q>
      <span class="who"><img class="face" src="assets/icon.svg" alt="" width="40" height="40"><cite>MRSC on Ko-fi<small>buy a coffee</small></cite><span class="dc-go" aria-hidden="true">→</span></span>
    </a>`;
    const reviewCard = ([s, q, who, id], copy) => `<figure class="review"${copy ? ' aria-hidden="true"' : ''}><div class="stars" aria-label="${s} stars">${'★'.repeat(s)}${'☆'.repeat(5 - s)}</div><q>${q}</q><div class="who">${face(id)}<cite>${who}</cite></div></figure>`;
    const reviewRow = copy => REVIEWS.map((r, i) => reviewCard(r, copy) + (i % 3 === 1 ? (Math.floor(i / 3) % 2 ? kofiCard(KOFI[Math.floor(i / 6) % KOFI.length], copy) : discordCard(DISCORD[Math.floor(i / 6) % DISCORD.length], copy)) : '')).join('');
    $('#logoTrack').innerHTML = logos + logos.replace(/class="logo/g, 'aria-hidden="true" class="logo');
    $('#reviewTrack').innerHTML = reviewRow(false) + reviewRow(true);
    // Member counts are fetched at build time (tools/discord_counts.py), so visitors never talk to Discord.
    fetch('img/discord.json').then(r => r.json()).then(d => {
      if (d.members) $$('[data-dc-count]').forEach(el => (el.textContent = `there are ${d.members} of us. be number ${d.members + 1}.`));
    }).catch(() => {});
  }

  // ---------------------------------------------------------------------------
  // Scroll effects, reveals, links

  function setupScroll() {
    const hero = $('#heroPhones');
    const lines = $$('#leftoutLines p');
    let raf = 0;
    const update = () => {
      raf = 0;
      const vh = innerHeight;
      if (!reduceMotion) hero.style.setProperty('--py', `${(-Math.min(scrollY, 900) * 0.07).toFixed(1)}px`);
      lines.forEach(p => {
        const r = p.getBoundingClientRect();
        const o = clamp((vh * 0.82 - (r.top + r.height / 2)) / (vh * 0.3), 0, 1);
        p.style.setProperty('--o', (0.28 + 0.72 * o).toFixed(3));
      });
    };
    addEventListener('scroll', () => { if (!raf) raf = requestAnimationFrame(update); }, { passive: true });
    update();
  }

  function setupReveals() {
    const io = new IntersectionObserver(es => es.forEach(e => {
      if (!e.isIntersecting) return;
      e.target.classList.add('in');
      io.unobserve(e.target);
    }), { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
    $$('.reveal').forEach(el => io.observe(el));
  }

  function setupFinale() {
    const svg = $('#finaleLogo');
    const letters = buildLogo(svg);
    if (reduceMotion) { showLetters(letters); return; }
    const io = new IntersectionObserver(es => {
      if (!es.some(e => e.isIntersecting)) return;
      io.disconnect();
      playStamps(letters, { gap: 300, shakeEl: svg });
    }, { threshold: 0.6 });
    io.observe(svg);
  }

  function setupLinks() {
    if (LINKS.testflight) {
      $$('[data-store-link]').forEach(a => { a.href = LINKS.testflight; a.target = '_blank'; a.rel = 'noopener'; });
      $$('[data-store-label]').forEach(s => (s.textContent = 'Join the TestFlight beta'));
    }
    if (LINKS.discord) {
      $$('[data-discord-link]').forEach(a => { a.href = LINKS.discord; a.hidden = false; a.target = '_blank'; a.rel = 'noopener'; });
    }
    // The light on Liquid Glass follows the pointer.
    document.addEventListener('pointermove', e => {
      const b = e.target.closest?.('.glass-btn');
      if (!b) return;
      const r = b.getBoundingClientRect();
      b.style.setProperty('--mx', `${e.clientX - r.left}px`);
      b.style.setProperty('--my', `${e.clientY - r.top}px`);
    }, { passive: true });
  }

  // ---------------------------------------------------------------------------

  runSplash();
  setupHero();
  setupCarousel();
  setupMom();
  setupKnobs();
  setupSleeves();
  setupLyricsDemo();
  setupSearch();
  setupMix();
  setupEQ();
  fillCovers(false);
  $('#coverShuffle').addEventListener('click', () => fillCovers(true));
  setupIconPicker();
  setupVinyl();
  setupIsland();
  setupOrganize();
  setupMarquees();
  setupScroll();
  setupReveals();
  setupFinale();
  setupLinks();
  setInterval(() => { if (!document.hidden && !reduceMotion) tickLyricMocks(); }, 2600);
})();

// Utilitários dos modelos. VARS vem do app. O texto entra por textContent, nunca como HTML.
var V = window.VARS || {};
function val(k, d) { return (V[k] !== undefined && V[k] !== '') ? V[k] : d; }
function txt(id, k, d) { var e = document.getElementById(id); if (e) e.textContent = val(k, d); return e; }
function cssVars() {
  var s = document.documentElement.style;
  s.setProperty('--c1', val('cor1', '#1F6FEB'));
  s.setProperty('--c2', val('cor2', '#FFFFFF'));
}
function words(id, k, d) {
  var e = document.getElementById(id);
  var list = String(val(k, d)).trim().split(/\s+/);
  e.textContent = '';
  list.forEach(function (w, i) {
    var s = document.createElement('span');
    s.className = 'word';
    s.textContent = w;
    e.appendChild(s);
    if (i < list.length - 1) e.appendChild(document.createTextNode(' '));
  });
  return e.querySelectorAll('.word');
}
function logo(id) {
  var e = document.getElementById(id);
  if (!e) return false;
  if (val('logo', '')) { e.src = val('logo', ''); e.style.display = 'block'; return true; }
  e.style.display = 'none';
  return false;
}
function comp(dur) {
  var id = document.querySelector('[data-composition-id]').dataset.compositionId;
  var tl = gsap.timeline({ paused: true });
  window.__timelines[id] = tl;
  return tl;
}

// Molas no estilo do Remotion, em forma fechada: o mesmo tempo sempre dá o mesmo quadro.
function spring(stiffness, damping) {
  var k = stiffness || 120, c = damping || 12;
  var w0 = Math.sqrt(k), z = c / (2 * w0), wd = w0 * Math.sqrt(Math.max(0.0001, 1 - z * z));
  return function (p) {
    if (p <= 0) return 0;
    if (p >= 1) return 1;
    var t = p * 1.4;
    return 1 - Math.exp(-z * w0 * t * 4) * (Math.cos(wd * t * 4) + (z * w0 / wd) * Math.sin(wd * t * 4));
  };
}
// Equivalente ao interpolate do Remotion.
function interpolate(v, a, b, c, d) {
  var p = Math.max(0, Math.min(1, (v - a) / (b - a)));
  return c + (d - c) * p;
}
// Número pseudoaleatório com semente, para o render ser repetível.
function seeded(seed) {
  var a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    var t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

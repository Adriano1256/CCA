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

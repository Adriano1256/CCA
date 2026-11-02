// Contrato igual ao do HyperFrames: raiz com data-composition-id e data-duration,
// e uma timeline GSAP pausada em window.__timelines[id]. O app chama __seek(t) quadro a quadro.
(function () {
  window.__timelines = window.__timelines || {};
  function root() { return document.querySelector('[data-composition-id]'); }
  window.__duration = function () {
    var r = root();
    if (r && r.dataset.duration) return parseFloat(r.dataset.duration);
    var tl = r && window.__timelines[r.dataset.compositionId];
    return tl ? tl.duration() : 5;
  };
  window.__seek = function (t) {
    // Composições em canvas, como as do motor MotionIA, expõem window.seek(t).
    if (typeof window.seek === 'function') { window.seek(t); }
    var r = root();
    if (!r) return !!window.seek;
    var tl = window.__timelines[r.dataset.compositionId];
    if (tl) { tl.pause(); tl.totalTime(Math.min(t, tl.totalDuration()), false); }
    document.querySelectorAll('.clip[data-start]').forEach(function (el) {
      var s = parseFloat(el.dataset.start) || 0;
      var d = parseFloat(el.dataset.duration);
      var on = t >= s && (isNaN(d) || t < s + d);
      el.style.visibility = on ? 'visible' : 'hidden';
    });
    return true;
  };
  window.__ready = function () {
    return (document.fonts ? document.fonts.status === 'loaded' : true) && (!!root() || typeof window.seek === 'function');
  };
})();

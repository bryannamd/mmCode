(function (root) {
  var PHASES = ['queued', 'build', 'verify', 'review', 'done'];
  var PHASE_KO = { queued: '대기', build: '구현', verify: '검증', review: '검수', done: '완료' };
  var HALT_KO = { decision: '결정 대기', 'stop-after': '단위 후 정지', interrupt: '즉시 중단' };

  function isObj(x) { return x !== null && typeof x === 'object' && !Array.isArray(x); }

  function parse(text) {
    var events = [], skipped = 0;
    String(text).split('\n').forEach(function (line) {
      if (!line.trim()) return;
      var v;
      try { v = JSON.parse(line); } catch (e) { skipped++; return; }
      if (isObj(v)) events.push(v); else skipped++;
    });
    return { events: events, skipped: skipped };
  }

  // 규칙의 정본: phase.sh 의 unit_state
  function reduce(events) {
    var plans = new Map();
    events.forEach(function (e) {
      if (typeof e.plan !== 'string' || typeof e.unit !== 'string' || e.unit === '-') return;
      var p = plans.get(e.plan);
      if (!p) { p = { plan: e.plan, units: new Map(), hasPhase: false }; plans.set(e.plan, p); }
      var u = p.units.get(e.unit);
      if (!u) { u = { unit: e.unit, phase: 'queued', halt: null }; p.units.set(e.unit, u); }
      var d = isObj(e.data) ? e.data : {};
      if (e.type === 'unit.phase') {
        p.hasPhase = true;
        if (PHASES.indexOf(d.to) >= 0) u.phase = d.to;
      } else if (e.type === 'unit.halt') {
        u.halt = typeof d.reason === 'string' && d.reason ? d.reason : 'halt';
      } else if (e.type === 'unit.resume') {
        u.halt = null;
      }
    });
    var out = [], halted = [];
    plans.forEach(function (p) {
      if (!p.hasPhase) return;
      var units = Array.from(p.units.values());
      out.push({ plan: p.plan, units: units });
      units.forEach(function (u) {
        if (u.halt) halted.push({ plan: p.plan, unit: u.unit, halt: u.halt });
      });
    });
    return { plans: out, halted: halted };
  }

  // blocked:<단위> 의 뒤는 그 단위 자신의 이름이다
  function haltLabel(reason) {
    if (HALT_KO[reason]) return HALT_KO[reason];
    if (reason === 'halt' || reason.indexOf('blocked:') === 0) return '막힘';
    return '막힘 (' + reason + ')';
  }

  function summarize(halted) {
    if (!halted.length) return '';
    return '멈춘 단위 ' + halted.length + '개: ' + halted.map(function (h) {
      return h.plan + ' ' + h.unit + ' (' + haltLabel(h.halt) + ')';
    }).join(', ');
  }

  function render(el, result, skipped) {
    el.textContent = '';
    function node(tag, cls, text) {
      var n = document.createElement(tag);
      if (cls) n.className = cls;
      if (text !== undefined) n.textContent = text;
      return n;
    }
    if (skipped) el.appendChild(node('p', 'note', '건너뛴 줄 ' + skipped + '개 (깨졌거나 객체가 아님)'));
    if (!result.plans.length) { el.appendChild(node('p', 'note', '표시할 단위가 없다.')); return; }
    result.plans.forEach(function (p) {
      var sec = node('section', 'plan');
      sec.appendChild(node('h2', '', '계획 ' + p.plan));
      var cols = node('div', 'cols');
      PHASES.forEach(function (ph) {
        var units = p.units.filter(function (u) { return u.phase === ph; });
        units = units.filter(function (u) { return u.halt; }).concat(units.filter(function (u) { return !u.halt; }));
        var col = node('div', 'col' + (units.length ? '' : ' empty'));
        col.appendChild(node('h3', '', PHASE_KO[ph] + ' ' + units.length));
        units.forEach(function (u) {
          var card = node('div', 'unit' + (u.halt ? ' halted' : '') + (ph === 'done' ? ' done' : ''));
          card.appendChild(node('span', 'name', u.unit));
          if (u.halt) card.appendChild(node('span', 'halt', '멈춤: ' + haltLabel(u.halt)));
          col.appendChild(card);
        });
        cols.appendChild(col);
      });
      sec.appendChild(cols);
      el.appendChild(sec);
    });
  }

  var api = { parse: parse, reduce: reduce, render: render, summarize: summarize };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.board = api;
})(typeof window !== 'undefined' ? window : globalThis);

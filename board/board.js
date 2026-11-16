(function (root) {
  var PHASES = ['queued', 'build', 'verify', 'review', 'done'];
  var PHASE_KO = { queued: '대기', build: '구현', verify: '검증', review: '검수', done: '완료' };
  var BY_KO = { user: '사용자', planner: '계획자', 'cross-review': '교차 검토' };
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

  function str(v) { return typeof v === 'string' ? v : ''; }

  // 정본: phase.sh 의 decisions. 결정 ID 는 파일 전체에서 하나이고 요청 없는 답은 무시한다.
  function reduceDecisions(events) {
    var byId = new Map();
    events.forEach(function (e) {
      var d = isObj(e.data) ? e.data : {};
      if (typeof d.id !== 'string' || !d.id) return;
      if (e.type === 'decision.ask') {
        byId.set(d.id, { ask: d, plan: str(e.plan) || '-', unit: str(e.unit) || '-', answer: null });
      } else if (e.type === 'decision.answer' && byId.has(d.id)) {
        byId.get(d.id).answer = d;
      }
    });
    var res = { open: [], answered: [] };
    byId.forEach(function (x, id) {
      var base = { id: id, plan: x.plan, unit: x.unit, question: str(x.ask.question) };
      if (x.answer) {
        base.answer = str(x.answer.answer); base.by = str(x.answer.by); base.undo = str(x.answer.undo);
        res.answered.push(base);
      } else {
        base.recommend = str(x.ask.recommend); base.impact = str(x.ask.impact);
        base.options = Array.isArray(x.ask.options) ? x.ask.options.filter(function (o) { return typeof o === 'string'; }) : [];
        res.open.push(base);
      }
    });
    return res;
  }

  // 정본: phase.sh 의 directives. 열린 지시 = 막는 중이거나 닫히지 않은 지시. resume 지시는 나오지 않는다.
  function reduceDirectives(events) {
    var byId = new Map();
    events.forEach(function (e) {
      var d = isObj(e.data) ? e.data : {};
      if (typeof d.id !== 'string' || !d.id) return;
      if (e.type === 'directive.received') {
        byId.set(d.id, { id: d.id, plan: str(e.plan) || '-', kind: str(d.kind), text: str(d.text), terminal: str(d.terminal),
          applied: false, rejected: false, closed: false });
        (Array.isArray(d.closes) ? d.closes : []).forEach(function (x) {
          if (byId.has(x)) byId.get(x).closed = true;
        });
      } else if ((e.type === 'directive.applied' || e.type === 'directive.rejected') && byId.has(d.id)) {
        byId.get(d.id)[e.type === 'directive.applied' ? 'applied' : 'rejected'] = true;
      }
    });
    var out = [];
    byId.forEach(function (x) {
      var blocking = (x.kind === 'stop-after' || x.kind === 'interrupt') && !x.closed;
      var done = x.applied || x.rejected || x.closed || x.kind === 'resume';
      if (blocking || !done) {
        out.push({ id: x.id, plan: x.plan, kind: x.kind, text: x.text, terminal: x.terminal, applied: x.applied, blocking: blocking });
      }
    });
    return out;
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
    return { plans: out, halted: halted, decisions: reduceDecisions(events), directives: reduceDirectives(events) };
  }

  // blocked:<단위> 의 뒤는 그 단위 자신의 이름이다
  function haltLabel(reason) {
    if (HALT_KO[reason]) return HALT_KO[reason];
    if (reason === 'halt' || reason.indexOf('blocked:') === 0) return '막힘';
    return '막힘 (' + reason + ')';
  }

  function sq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

  function answerPrefix(id) {
    return 'bash plugins/mmcode/skills/relay/scripts/phase.sh answer . ' + (/^[\w.-]+$/.test(id) ? id : sq(id)) + ' --answer ';
  }

  function answerCommand(id, answer) { return answerPrefix(id) + sq(answer); }

  // 선택지가 없는 결정에 보여 주는 글자. 따옴표가 없어서 그대로 붙여 넣으면 셸에서 실패한다.
  function answerTemplate(id) { return answerPrefix(id) + '<답>'; }

  function resumeCommand() { return 'bash plugins/mmcode/skills/relay/scripts/phase.sh direct . resume'; }

  function summarize(halted) {
    if (!halted.length) return '';
    return '멈춘 단위 ' + halted.length + '개: ' + halted.map(function (h) {
      return h.plan + ' ' + h.unit + ' (' + haltLabel(h.halt) + ')';
    }).join(', ');
  }

  function render(el, result, skipped) {
    el.textContent = '';
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

  function node(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  }

  function whereText(d) { return '계획 ' + d.plan + (d.unit === '-' ? '' : ' · 단위 ' + d.unit); }

  // 복사 버튼, 결과 문구, 접힌 명령 글자. 복사에 실패하면 명령 글자를 펼쳐서 고르게 한다.
  function cmdCopy(cmd) {
    var btn = node('button', 'btn', '명령 복사');
    btn.type = 'button';
    var msg = node('span', 'copied');
    msg.setAttribute('role', 'status');
    var det = node('details', 'cmddet');
    det.appendChild(node('summary', '', '명령 보기'));
    var pre = node('pre', 'cmd', cmd);
    det.appendChild(pre);
    btn.addEventListener('click', function () {
      function failed() {
        det.open = true;
        window.getSelection().selectAllChildren(pre);
        msg.textContent = '복사하지 못했다. 명령을 직접 복사한다';
      }
      if (!navigator.clipboard) return failed();
      navigator.clipboard.writeText(cmd).then(function () {
        msg.textContent = '복사했다';
        setTimeout(function () { msg.textContent = ''; }, 2000);
      }, failed);
    });
    return { btn: btn, msg: msg, det: det };
  }

  // 선택지 한 줄(글자와 복사 버튼)
  function optionRow(parent, id, answer, recommended) {
    var opt = node('div', 'option');
    var row = node('div', 'optrow');
    var t = node('p', 'opt', answer);
    if (recommended) t.appendChild(node('span', 'tag', '추천'));
    var c = cmdCopy(answerCommand(id, answer));
    row.appendChild(t);
    row.appendChild(c.btn);
    row.appendChild(c.msg);
    opt.appendChild(row);
    opt.appendChild(c.det);
    parent.appendChild(opt);
  }

  // 열린 결정은 openEl 에, 답한 결정은 접어서 answeredEl 에 그린다. 없으면 구역을 만들지 않는다.
  function renderDecisions(openEl, answeredEl, dec) {
    openEl.textContent = '';
    answeredEl.textContent = '';
    openEl.hidden = !dec.open.length;
    answeredEl.hidden = !dec.answered.length;
    if (dec.open.length) openEl.appendChild(node('p', 'opencount', '열린 결정 ' + dec.open.length + '개'));
    dec.open.forEach(function (d) {
      var sec = node('section', 'decision');
      sec.appendChild(node('h2', '', '결정 필요 ' + d.id));
      sec.appendChild(node('p', 'where', whereText(d)));
      sec.appendChild(node('p', 'question', d.question));
      if (d.recommend) sec.appendChild(node('p', '', '추천: ' + d.recommend));
      if (d.impact) sec.appendChild(node('p', '', '영향: ' + d.impact));
      if (d.options.length) {
        d.options.forEach(function (o) { optionRow(sec, d.id, o, o === d.recommend); });
      } else {
        var opt = node('div', 'option');
        opt.appendChild(node('p', 'opt', '아래 명령의 <답> 자리에 답을 작은따옴표로 감싸 적어 실행한다'));
        opt.appendChild(node('pre', 'cmd', answerTemplate(d.id)));
        sec.appendChild(opt);
      }
      openEl.appendChild(sec);
    });
    if (dec.answered.length) {
      var det = node('details', 'answered');
      det.appendChild(node('summary', '', '답한 결정 ' + dec.answered.length + '개'));
      dec.answered.forEach(function (d) {
        var it = node('div', 'adec');
        it.appendChild(node('p', 'name', d.id + ' · ' + whereText(d)));
        it.appendChild(node('p', '', '질문: ' + d.question));
        it.appendChild(node('p', '', '답: ' + d.answer));
        it.appendChild(node('p', '', '정한 쪽: ' + (BY_KO[d.by] || d.by)));
        if (d.undo) it.appendChild(node('p', '', '되돌리는 방법: ' + d.undo));
        det.appendChild(it);
      });
      answeredEl.appendChild(det);
    }
  }

  var KIND_KO = { message: '메시지', reorder: '순서 변경' };
  var BLOCK_KO = {
    'stop-after': '단위 후 정지|지금 단위가 끝나면 다음 단위를 시작하지 않는다',
    interrupt: '즉시 중단|에이전트의 도구 사용을 막는다',
  };

  function targetText(plan) { return plan === '-' ? '모든 계획' : '계획 ' + plan; }

  // 막는 지시는 stopsEl 의 띠로, 막지 않는 지시는 receivedEl 의 접힌 목록으로 그린다. 없으면 구역을 만들지 않는다.
  function renderDirectives(stopsEl, receivedEl, list) {
    var blocking = list.filter(function (d) { return d.blocking; });
    var others = list.filter(function (d) { return !d.blocking; });
    stopsEl.textContent = '';
    receivedEl.textContent = '';
    stopsEl.hidden = !blocking.length;
    receivedEl.hidden = !others.length;
    if (blocking.length) {
      stopsEl.appendChild(node('h2', '', '정지 지시'));
      blocking.forEach(function (d) {
        var parts = (BLOCK_KO[d.kind] || d.kind).split('|');
        var line = parts[0] + ' ' + d.id + ' (' + targetText(d.plan) + ')' + (parts[1] ? ': ' + parts[1] : '');
        if (d.terminal) line += ' · 터미널 ' + d.terminal;
        if (d.applied) line += ' · 적용됨';
        stopsEl.appendChild(node('p', '', line));
      });
      stopsEl.appendChild(node('p', '', '계속하려면 아래 명령을 터미널에서 실행한다. 이 명령은 정지 지시 ' + blocking.length + '개를 모두 푼다.'));
      var c = cmdCopy(resumeCommand());
      var row = node('div', 'optrow');
      row.appendChild(c.btn);
      row.appendChild(c.msg);
      stopsEl.appendChild(row);
      stopsEl.appendChild(c.det);
    }
    if (others.length) {
      var det = node('details', 'answered');
      det.appendChild(node('summary', '', '받은 지시 ' + others.length + '개'));
      others.forEach(function (d) {
        var it = node('div', 'adec');
        it.appendChild(node('p', 'name', d.id + ' · ' + (KIND_KO[d.kind] || d.kind)));
        it.appendChild(node('p', '', '내용: ' + d.text));
        it.appendChild(node('p', '', '대상: ' + targetText(d.plan)));
        it.appendChild(node('p', '', '상태: 접수됨. 아직 적용 전'));
        det.appendChild(it);
      });
      receivedEl.appendChild(det);
    }
  }

  var api = { parse: parse, reduce: reduce, render: render, summarize: summarize, answerCommand: answerCommand, answerTemplate: answerTemplate, resumeCommand: resumeCommand, renderDecisions: renderDecisions, renderDirectives: renderDirectives };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.board = api;
})(typeof window !== 'undefined' ? window : globalThis);

import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import board from './board.js';

const ph = (plan, unit, to) => ({ type: 'unit.phase', plan, unit, data: { to } });
const halt = (plan, unit, reason) => ({ type: 'unit.halt', plan, unit, data: { reason } });
const resume = (plan, unit) => ({ type: 'unit.resume', plan, unit, data: {} });
const unitOf = (r, plan, unit) => r.plans.find((p) => p.plan === plan).units.find((u) => u.unit === unit);

test('다른 계획의 같은 이름 단위가 섞이지 않는다', () => {
  const r = board.reduce([ph('a', 'U1', 'build'), ph('b', 'U1', 'verify'), halt('a', 'U1', 'decision')]);
  assert.equal(unitOf(r, 'a', 'U1').phase, 'build');
  assert.equal(unitOf(r, 'a', 'U1').halt, 'decision');
  assert.equal(unitOf(r, 'b', 'U1').phase, 'verify');
  assert.equal(unitOf(r, 'b', 'U1').halt, null);
});

test('되돌아간 단위는 마지막 단계에 있다', () => {
  const r = board.reduce([ph('a', 'U1', 'build'), ph('a', 'U1', 'verify'), ph('a', 'U1', 'review'), ph('a', 'U1', 'build')]);
  assert.equal(unitOf(r, 'a', 'U1').phase, 'build');
});

test('resume 뒤에는 멈춤이 없다', () => {
  const r = board.reduce([ph('a', 'U1', 'build'), halt('a', 'U1', 'stop-after'), resume('a', 'U1')]);
  assert.equal(unitOf(r, 'a', 'U1').halt, null);
  const r2 = board.reduce([ph('a', 'U1', 'build'), halt('a', 'U1', 'stop-after'), resume('a', 'U1'), halt('a', 'U1', 'interrupt')]);
  assert.equal(unitOf(r2, 'a', 'U1').halt, 'interrupt');
});

test('깨진 줄과 객체가 아닌 줄을 건너뛰고 센다', () => {
  const text = [JSON.stringify(ph('a', 'U1', 'build')), '{깨짐', '42', 'null', '[1]', '', JSON.stringify(ph('a', 'U1', 'verify'))].join('\n');
  const p = board.parse(text);
  assert.equal(p.events.length, 2);
  assert.equal(p.skipped, 4);
});

test('단계 이벤트가 없는 계획과 단위 -는 나오지 않는다', () => {
  const r = board.reduce([
    { type: 'decision.ask', plan: '-', unit: '-', data: {} },
    { type: 'check.result', plan: 'x', unit: 'U1', data: {} },
    ph('a', 'U1', 'build'),
    { type: 'check.result', plan: 'a', unit: '-', data: {} },
  ]);
  assert.deepEqual(r.plans.map((p) => p.plan), ['a']);
  assert.deepEqual(r.plans[0].units.map((u) => u.unit), ['U1']);
});

test('계획과 단위는 처음 나온 순서를 지킨다', () => {
  const r = board.reduce([ph('b', 'U2', 'build'), ph('a', 'U1', 'build'), ph('b', 'U1', 'build'), ph('b', 'U2', 'verify')]);
  assert.deepEqual(r.plans.map((p) => p.plan), ['b', 'a']);
  assert.deepEqual(r.plans[0].units.map((u) => u.unit), ['U2', 'U1']);
});

test('멈춘 단위만 halted 에 나온다', () => {
  const r = board.reduce([
    ph('a', 'U1', 'build'), ph('a', 'U2', 'build'), ph('b', 'U1', 'verify'),
    halt('a', 'U2', 'decision'), halt('b', 'U1', 'blocked:U1'),
  ]);
  assert.deepEqual(r.halted, [
    { plan: 'a', unit: 'U2', halt: 'decision' },
    { plan: 'b', unit: 'U1', halt: 'blocked:U1' },
  ]);
});

test('resume 된 단위는 halted 에서 빠진다', () => {
  const r = board.reduce([ph('a', 'U1', 'build'), halt('a', 'U1', 'interrupt'), resume('a', 'U1')]);
  assert.deepEqual(r.halted, []);
});

test('이유가 문자열이 아닌 멈춤은 막힘으로 나온다', () => {
  const r = board.reduce([ph('a', 'U1', 'build'), halt('a', 'U1', { x: 1 })]);
  assert.equal(r.halted?.[0]?.halt, 'halt');
  assert.equal(board.summarize(r.halted), '멈춘 단위 1개: a U1 (막힘)');
});

test('요약 문구: 멈춘 단위가 없으면 빈 문자열, 있으면 이유를 붙인다', () => {
  assert.equal(board.summarize([]), '');
  const r = board.reduce([
    ph('alpha', 'A4', 'build'), ph('alpha', 'A6', 'build'),
    halt('alpha', 'A4', 'decision'), halt('alpha', 'A6', 'blocked:A6'),
  ]);
  assert.equal(board.summarize(r.halted), '멈춘 단위 2개: alpha A4 (결정 대기), alpha A6 (막힘)');
});

const ask = (plan, unit, id, extra = {}) => ({ type: 'decision.ask', plan, unit, data: { id, question: id + ' 질문', options: [], ...extra } });
const answer = (plan, unit, id, a, extra = {}) => ({ type: 'decision.answer', plan, unit, data: { id, answer: a, by: 'user', ...extra } });
const ids = (list) => list.map((d) => d.id);

test('답한 결정은 열린 목록에 남지 않고 답한 목록으로 간다', () => {
  const r = board.reduce([ask('a', '-', 'D1'), ask('a', '-', 'D2'), answer('a', '-', 'D1', '가', { by: 'planner', undo: '되돌림' })]);
  assert.deepEqual(ids(r.decisions.open), ['D2']);
  assert.deepEqual(r.decisions.answered, [
    { id: 'D1', plan: 'a', unit: '-', question: 'D1 질문', answer: '가', by: 'planner', undo: '되돌림' },
  ]);
});

test('다른 계획의 결정이 ID 로 올바로 짝지어진다', () => {
  const r = board.reduce([
    ask('a', 'U1', 'D1'), ask('b', 'U1', 'D2', { recommend: '나', impact: '영향', options: ['가', '나'] }),
    answer('b', 'U1', 'D1', '가'),
  ]);
  assert.deepEqual(ids(r.decisions.open), ['D2']);
  assert.equal(r.decisions.answered[0].id, 'D1');
  assert.equal(r.decisions.answered[0].plan, 'a');
  assert.deepEqual(r.decisions.open[0], {
    id: 'D2', plan: 'b', unit: 'U1', question: 'D2 질문', recommend: '나', impact: '영향', options: ['가', '나'],
  });
});

test('요청 없는 답은 무시한다', () => {
  const r = board.reduce([answer('a', '-', 'D9', '가'), ask('a', '-', 'D1')]);
  assert.deepEqual(ids(r.decisions.open), ['D1']);
  assert.deepEqual(r.decisions.answered, []);
});

test('단계 이벤트가 없는 계획의 결정도 나오고 순서는 요청 순서다', () => {
  const r = board.reduce([ask('-', '-', 'D2'), ask('x', '-', 'D1'), ph('a', 'U1', 'build')]);
  assert.deepEqual(ids(r.decisions.open), ['D2', 'D1']);
  assert.deepEqual(r.plans.map((p) => p.plan), ['a']);
});

test('답 명령은 따옴표 등이 든 답도 셸에서 글자 그대로 전달된다', () => {
  const answers = ["그대로", "it's \"x\"", "$HOME `date` \\n", "줄1\n줄2", "'", "''a''"];
  for (const a of answers) {
    const cmd = board.answerCommand('D4', a);
    assert.ok(cmd.startsWith('bash plugins/mmcode/skills/relay/scripts/phase.sh answer . D4 --answer '), cmd);
    const arg = cmd.slice(cmd.indexOf('--answer ') + '--answer '.length);
    assert.equal(execFileSync('sh', ['-c', 'printf %s ' + arg]).toString(), a);
  }
});

test('선택지 없는 결정의 표시 문자열에는 따옴표로 감싼 <답> 이 없다', () => {
  const t = board.answerTemplate('D8');
  assert.ok(t.startsWith('bash plugins/mmcode/skills/relay/scripts/phase.sh answer . D8 --answer '), t);
  assert.ok(t.endsWith('--answer <답>'), t);
  assert.ok(!t.includes("'"), t);
});

const recv = (plan, id, kind, extra = {}) => ({ type: 'directive.received', plan, unit: '-', data: { id, kind, ...extra } });
const dapplied = (id) => ({ type: 'directive.applied', plan: '-', unit: '-', data: { id } });
const drejected = (id) => ({ type: 'directive.rejected', plan: '-', unit: '-', data: { id, reason: '안 함' } });

test('적용된 정지 지시는 resume 이 닫기 전까지 열려 있고 blocking 이다', () => {
  const r = board.reduce([recv('a', 'I1', 'stop-after', { terminal: 't1' }), dapplied('I1')]);
  assert.deepEqual(r.directives, [
    { id: 'I1', plan: 'a', kind: 'stop-after', text: '', terminal: 't1', applied: true, blocking: true },
  ]);
});

test('resume 이 닫은 지시는 사라지고 resume 지시 자신도 나오지 않는다', () => {
  const r = board.reduce([
    recv('a', 'I1', 'stop-after'), recv('a', 'I2', 'interrupt'), recv('a', 'I3', 'message', { text: '안녕' }),
    recv('a', 'I4', 'resume', { closes: ['I1', 'I2'] }),
  ]);
  assert.deepEqual(r.directives.map((d) => d.id), ['I3']);
});

test('거부된 메시지와 적용된 메시지는 사라진다', () => {
  const r = board.reduce([recv('a', 'I1', 'message', { text: 'x' }), recv('a', 'I2', 'message', { text: 'y' }), recv('a', 'I3', 'reorder', { text: 'z' }), drejected('I1'), dapplied('I2')]);
  assert.deepEqual(r.directives.map((d) => d.id), ['I3']);
  assert.equal(r.directives[0].blocking, false);
  assert.equal(r.directives[0].applied, false);
  assert.equal(r.directives[0].text, 'z');
});

test('열린 지시는 접수 순서를 지키고 plan - 은 그대로 나온다', () => {
  const r = board.reduce([recv('-', 'I2', 'interrupt'), recv('a', 'I1', 'message', { text: 'm' })]);
  assert.deepEqual(r.directives.map((d) => [d.id, d.plan]), [['I2', '-'], ['I1', 'a']]);
});

test('resumeCommand 는 모든 계획용 resume 명령이다', () => {
  assert.equal(board.resumeCommand(), 'bash plugins/mmcode/skills/relay/scripts/phase.sh direct . resume');
});

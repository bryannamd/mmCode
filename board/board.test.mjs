import test from 'node:test';
import assert from 'node:assert/strict';
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

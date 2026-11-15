// mmCode 픽셀 사무실: 장면 그리기. fillRect 만 쓴다(캔버스와 SVG 기록기 양쪽에서 돈다).
(function (G) {
const W = 240, H = 108;
const PAL = {
  day: { ink:'#232845', slab:'#232845', hatch:'#4a548c', wall:'#c8eee0', dot:'#b2e3d2', wall2:'#8fd6c2', base:'#5aa896',
    floor:'#f4bd6c', plank:'#dd9c47', wood:'#cf7c3c', wood2:'#a35a26', back:'#f1d3a2', metal:'#a9bbd8', metal2:'#6f83a8', tower:'#39406b',
    screen:'#232845', on:'#eafcff', code:'#2f8fe8', off:'#55608a', box:'#eab85f', box2:'#b9822f', boxD:'#93dba8', boxD2:'#3f9a5f',
    door:'#ef6a45', door2:'#c2492a', sofa:'#4e7df0', sofa2:'#345bc4', paper:'#fffdf4', pink:'#ff4f9a', red:'#ef4b4b', amber:'#ffc23d',
    green:'#3fc46f', leaf:'#3fae6a', leaf2:'#2b8a52', pot:'#d9683a', sky:'#8fd0ff', cloud:'#ffffff', sun:'#ffd84d', lampOn:'#ffe27a',
    lampOff:'#e7a04a', cone:'rgba(255,226,122,0)', shadow:'rgba(35,40,69,.2)', grass:'#5fbf6b', dimFloor:'rgba(35,40,69,.42)', white:'#ffffff' },
  night: { ink:'#141833', slab:'#0f1228', hatch:'#2a3266', wall:'#2f3b76', dot:'#374486', wall2:'#253066', base:'#1b2452',
    floor:'#8a6248', plank:'#6f4a34', wood:'#a9683a', wood2:'#7a4424', back:'#5a4a68', metal:'#7f8fb8', metal2:'#4f5d86', tower:'#1d2248',
    screen:'#141833', on:'#d9fbff', code:'#2f8fe8', off:'#3a446f', box:'#dfaa55', box2:'#9c6b22', boxD:'#84cf9a', boxD2:'#2f7f4c',
    door:'#c9573a', door2:'#9a3d24', sofa:'#4a70d8', sofa2:'#2f4fa8', paper:'#fffdf4', pink:'#ff4f9a', red:'#ef4b4b', amber:'#ffc23d',
    green:'#3fc46f', leaf:'#2f9358', leaf2:'#1f6d40', pot:'#b9552e', sky:'#141a3c', cloud:'#2a3266', sun:'#f4f1d0', lampOn:'#ffe27a',
    lampOff:'#6b5a3a', cone:'rgba(255,226,122,.13)', shadow:'rgba(0,0,0,.3)', grass:'#2f6a4a', dimFloor:'rgba(8,10,28,.5)', white:'#ffffff' }
};
const SPECIES = {
  cat: { body:'#f79a3e', shade:'#cf6f1c', name:'고양이', head:[
    'oo........oo','obo......obo','obboooooobbo','obbbbbbbbbbo','ohhhhhhhhhho','ohhhhhhhhhho','obbbbbbbbbbo','obbbbbbbbbbo','obpbbwwbbpbo','.obbbwwbbbo.','..oooooooo..'] },
  bear: { body:'#b07a4e', shade:'#825432', name:'곰', head:[
    '.oo......oo.','obbo....obbo','obboooooobbo','obbbbbbbbbbo','ohhhhhhhhhho','ohhhhhhhhhho','obbbbbbbbbbo','obbbbbbbbbbo','obbbwwwwbbbo','.obbwnnwbbo.','..oooooooo..'] },
  rabbit: { body:'#f8f5ef', shade:'#cfc8bb', name:'토끼', head:[
    '..oo....oo..','.obbo..obbo.','.obpo..opbo.','.obpo..opbo.','.obbo..obbo.','oobboooobboo','obbbbbbbbbbo','ohhhhhhhhhho','ohhhhhhhhhho','obbbbbbbbbbo','obbbbbbbbbbo','obpbbwwbbpbo','.obbbbbbbbo.','..oooooooo..'] }
};
const FONT = { A:['010','101','111','101','101'], '0':['111','101','101','101','111'], '1':['010','110','010','010','111'], '2':['110','001','010','100','111'],
  '3':['110','001','010','001','110'], '4':['101','101','111','001','001'], '5':['111','100','110','001','110'], '6':['011','100','110','101','010'],
  '7':['111','001','010','010','010'], '8':['010','101','010','101','010'], '9':['010','101','011','001','110'] };
const DESKS = [80, 108, 136];
const SPOT = { door:[16,84], backlog:[44,84], desk1:[80,84], desk2:[108,84], desk3:[136,84], test:[167,84], test2:[176,85], ui:[197,84], done:[224,84],
  sofa:[21,98], sofa2:[33,98], bell:[107,100] };
const SIGNS = [['대기',31,26],['구현',95,26],['검증',154,26],['검수',185,26],['완료',212,26]];

const R = (c, x, y, w, h, col) => { c.fillStyle = col; c.fillRect(Math.round(x), Math.round(y), w, h); };
const B = (c, x, y, w, h, fill, ink) => { R(c, x, y, w, h, ink); R(c, x+1, y+1, w-2, h-2, fill); };
function map(c, rows, x, y, col) {
  for (let r = 0; r < rows.length; r++) { const row = rows[r]; let i = 0;
    while (i < row.length) { const ch = row[i]; let j = i; while (j < row.length && row[j] === ch) j++;
      if (ch !== '.' && col[ch]) R(c, x + i, y + r, j - i, 1, col[ch]); i = j; } }
}
function text(c, s, x, y, col) { for (const ch of s) { const g = FONT[ch]; if (g) for (let r = 0; r < 5; r++) for (let k = 0; k < 3; k++) if (g[r][k] === '1') R(c, x + k, y + r, 1, 1, col); x += 4; } }

// 말풍선 모양의 작은 상태 표시. kind: ask, error, sleep, think, stop, done
function glyph(c, P, kind, x, y, fr) {
  if (kind === 'sleep') { const o = fr ? 1 : 0; R(c, x+2, y+3-o, 4, 1, P.paper); R(c, x+4, y+4-o, 1, 1, P.paper); R(c, x+3, y+5-o, 1, 1, P.paper); R(c, x+2, y+6-o, 4, 1, P.paper);
    R(c, x+7, y-o, 3, 1, P.paper); R(c, x+8, y+1-o, 1, 1, P.paper); R(c, x+7, y+2-o, 3, 1, P.paper); return; }
  const hot = kind === 'ask' || kind === 'error', fill = hot ? P.pink : P.paper;
  B(c, x, y, 9, 8, fill, P.ink); R(c, x+3, y+8, 2, 1, P.ink); R(c, x+3, y+7, 1, 1, fill);
  const k = hot ? P.ink : P.ink;
  if (kind === 'ask') { R(c, x+3, y+2, 3, 1, k); R(c, x+5, y+3, 1, 1, k); R(c, x+4, y+4, 1, 1, k); R(c, x+4, y+6, 1, 1, P.ink); }
  else if (kind === 'error') { R(c, x+4, y+2, 1, 3, k); R(c, x+4, y+6, 1, 1, k); }
  else if (kind === 'think') { for (let i = 0; i < 3; i++) R(c, x+2+i*2, y+4 - ((fr + i) % 2 ? 0 : 1), 1, 1, P.ink); }
  else if (kind === 'stop') { R(c, x+3, y+2, 1, 4, P.ink); R(c, x+5, y+2, 1, 4, P.ink); }
  else if (kind === 'done') { R(c, x+2, y+4, 1, 1, P.boxD2); R(c, x+3, y+5, 1, 1, P.boxD2); R(c, x+4, y+4, 1, 1, P.boxD2); R(c, x+5, y+3, 1, 1, P.boxD2); R(c, x+6, y+2, 1, 1, P.boxD2); }
}
function box(c, P, x, y, u, selected) {
  const d = u.stage === 'done';
  B(c, x, y, 11, 8, d ? P.boxD : P.box, P.ink); R(c, x+1, y+6, 9, 1, d ? P.boxD2 : P.box2);
  text(c, u.id, x + 2, y + 1, P.ink);
  if (selected) { R(c, x-1, y+9, 13, 1, P.white); }
  u.hx = x; u.hy = y;
}
// a: {x,y,species,hat,shirt,state,moving,carry}. 발 가운데가 (x,y)다.
function sprite(c, P, a, fr, selected) {
  const s = SPECIES[a.species], hd = s.head, x = Math.round(a.x) - 6, st = a.state;
  const bob = st === 'work' && fr ? 1 : 0, sit = st === 'sleep' ? 2 : 0;
  const feet = Math.round(a.y), tt = feet - 5 + sit, ht = tt - hd.length + bob;
  if (!sit) R(c, x+1, feet, 10, 1, P.shadow);
  const col = { o:P.ink, b:s.body, d:s.shade, w:'#ffffff', p:'#ff9db0', n:P.ink, h:a.hat };
  if (!sit) {   // 다리
    const l = a.moving && fr === 0 ? 1 : 0, r = a.moving && fr === 1 ? 1 : 0;
    B(c, x+2, feet-3-l, 4, 3, s.shade, P.ink); B(c, x+6, feet-3-r, 4, 3, s.shade, P.ink);
  }
  B(c, x+2, tt, 8, 4 + (sit ? 0 : 0), a.shirt, P.ink);
  const arm = (side, top, len) => { const ax = side ? x+9 : x; B(c, ax, top, 3, len + 1, s.body, P.ink); };
  if (a.carry) { arm(0, tt-3, 5); arm(1, tt-3, 5); }
  else if (st === 'ask') { arm(0, tt, 3); arm(1, tt-6, 7); }
  else if (st === 'work') { arm(0, tt + (fr ? 0 : 1), 2); arm(1, tt + (fr ? 1 : 0), 2); }
  else { arm(0, tt, 3); arm(1, tt, 3); }
  map(c, hd, x, ht, col);
  const er = ht + hd.length - 5;
  if (st === 'sleep' || st === 'stopped') { R(c, x+2, er+1, 2, 1, P.ink); R(c, x+8, er+1, 2, 1, P.ink); }
  else if (st === 'done') { R(c, x+2, er+1, 1, 1, P.ink); R(c, x+3, er, 1, 1, P.ink); R(c, x+4, er+1, 1, 1, P.ink); R(c, x+7, er+1, 1, 1, P.ink); R(c, x+8, er, 1, 1, P.ink); R(c, x+9, er+1, 1, 1, P.ink); }
  else { R(c, x+3, er, 1, 2, P.ink); R(c, x+8, er, 1, 2, P.ink); }
  if (a.carry) box(c, P, x, ht - 9, a.carry, false);
  else { const k = { ask:'ask', error:'error', sleep:'sleep', think:'think', stopped:'stop', done:'done' }[st]; if (k) glyph(c, P, k, x + (k === 'sleep' ? 6 : 2), ht - 10, fr); }
  if (selected) { R(c, x, feet+2, 12, 1, P.white); R(c, x-1, feet+1, 1, 1, P.white); R(c, x+12, feet+1, 1, 1, P.white); }
  a.top = ht - 10;
}
function shelf(c, P, x, done) {
  B(c, x, 40, 26, 32, P.wood2, P.ink); R(c, x+1, 41, 24, 30, P.back); R(c, x+1, 55, 24, 2, P.wood); R(c, x+1, 56, 24, 1, P.wood2);
  if (done) { R(c, x+11, 34, 1, 6, P.ink); B(c, x+12, 33, 8, 6, P.green, P.ink); }
}
function room(c, P, sky) {
  R(c, 0, 0, W, H, P.wall);
  for (let y = 8; y < 48; y += 8) for (let x = (y % 16 ? 10 : 4); x < W; x += 12) R(c, x, y, 1, 1, P.dot);
  R(c, 0, 50, W, 20, P.wall2); for (let x = 5; x < W; x += 10) R(c, x, 52, 1, 16, P.wall);
  R(c, 0, 70, W, 2, P.base); R(c, 0, 72, W, 32, P.floor);
  for (let y = 80; y < 104; y += 8) { R(c, 0, y, W, 1, P.plank); for (let x = (y % 16 ? 14 : 44); x < W; x += 60) R(c, x, y - 8, 1, 8, P.plank); }
  R(c, 0, 0, W, 3, P.slab); R(c, 0, 104, W, 4, P.slab); R(c, 0, 0, 3, H, P.slab); R(c, 237, 0, 3, H, P.slab);
  for (let x = 6; x < W - 6; x += 7) { R(c, x, 105, 2, 1, P.hatch); R(c, x+1, 106, 2, 1, P.hatch); R(c, x, 1, 2, 1, P.hatch); }
  // 창, 시계, 액자(고양이가 좋아하는 생선)
  B(c, 60, 7, 26, 17, sky.col, P.ink); R(c, 72, 8, 1, 15, P.ink); R(c, 61, 15, 24, 1, P.ink); R(c, sky.night ? 77 : 64, 10, 4, 4, P.sun); R(c, 58, 24, 30, 2, P.ink);
  B(c, 124, 8, 11, 11, P.paper, P.ink); R(c, 129, 10, 1, 4, P.ink); R(c, 129, 13, 3, 1, P.ink);
  B(c, 140, 9, 15, 10, P.paper, P.ink); R(c, 144, 12, 6, 4, P.code); R(c, 150, 11, 2, 1, P.code); R(c, 150, 16, 2, 1, P.code); R(c, 151, 12, 1, 4, P.code); R(c, 145, 13, 1, 1, P.ink);
}
function drawOffice(c, st, P) {
  const fr = st.fr | 0, sky = st.sky || { col:P.sky, night:false };
  room(c, P, sky);
  // 표지판과 순서 화살표
  SIGNS.forEach((s, i) => { const w = 25; R(c, s[1]+5, 3, 1, s[2]-3, P.ink); R(c, s[1]+w-6, 3, 1, s[2]-3, P.ink); B(c, s[1], s[2], w, 10, P.paper, P.ink);
    if (i < SIGNS.length - 1) { const ax = (s[1] + w + SIGNS[i+1][1]) / 2 - 1, ay = s[2] + 4; if (SIGNS[i+1][1] - s[1] - w > 5) { R(c, ax-2, ay, 4, 1, P.ink); R(c, ax+1, ay-1, 1, 3, P.ink); } } });
  // 문
  B(c, 8, 36, 16, 36, st.doorOpen ? P.ink : P.door, P.ink);
  if (!st.doorOpen) { R(c, 9, 68, 14, 3, P.door2); B(c, 12, 41, 8, 8, sky.col, P.ink); R(c, 20, 56, 2, 2, P.amber); }
  shelf(c, P, 31, false); shelf(c, P, 211, true);
  // 책상, 모니터, 천장등
  DESKS.forEach(dx => {
    const on = st.actors.some(a => a.state === 'work' && Math.abs(a.x - dx) < 2 && Math.abs(a.y - 84) < 1);
    R(c, dx, 3, 1, 7, P.ink); B(c, dx-3, 10, 7, 4, on ? P.lampOn : P.lampOff, P.ink);
    if (on) for (let i = 0; i < 6; i++) R(c, dx-4-i*2, 14+i*8, 9+i*4, 8, P.cone);
    R(c, dx-11, 62, 2, 10, P.ink); R(c, dx+9, 62, 2, 10, P.ink); B(c, dx-12, 59, 24, 4, P.wood, P.ink); B(c, dx-12, 62, 9, 6, P.wood2, P.ink);
    R(c, dx-6, 56, 2, 3, P.ink); B(c, dx-10, 46, 11, 10, on ? P.on : P.off, P.screen);
    if (on) { R(c, dx-8, 48+fr, 5, 1, P.code); R(c, dx-8, 51-fr, 3, 1, P.code); R(c, dx-8, 53, 6, 1, P.off); }
  });
  // 시험대와 신호등
  R(c, 155, 62, 2, 10, P.ink); R(c, 177, 62, 2, 10, P.ink); B(c, 154, 59, 26, 4, P.metal, P.ink); R(c, 155, 61, 24, 1, P.metal2);
  B(c, 171, 35, 8, 24, P.tower, P.ink);
  const lit = { run:[0, fr ? 1 : 0, 0], ok:[0, 0, 1], fail:[1, 0, 0] }[st.lamp] || [0, 0, 0];
  [P.red, P.amber, P.green].forEach((col, i) => R(c, 173, 38 + i * 7, 4, 4, lit[i] ? col : P.off));
  // 검수 화면
  B(c, 186, 38, 23, 17, P.off, P.screen); R(c, 196, 55, 3, 3, P.ink); R(c, 192, 58, 11, 1, P.ink);
  if (st.units.some(u => u.place === 'ui')) { R(c, 187, 39, 21, 15, P.on); R(c, 188, 40, 19, 2, P.code); R(c, 188, 44, 8, 9, P.amber); R(c, 198, 44, 9, 4, P.pink === '' ? P.off : P.boxD); R(c, 198, 50, 9, 3, P.metal); }
  R(c, 191, 62, 2, 10, P.ink); R(c, 202, 62, 2, 10, P.ink); B(c, 189, 59, 16, 4, P.wood, P.ink);
  // 화분
  B(c, 222, 94, 9, 9, P.pot, P.ink); R(c, 224, 86, 5, 8, P.leaf); R(c, 221, 89, 4, 4, P.leaf); R(c, 228, 88, 4, 5, P.leaf2); R(c, 226, 83, 2, 4, P.leaf2);
  st.units.forEach(u => { const p = boxPos(u); if (p) box(c, P, p[0], p[1], u, st.sel === u); });
  if (st.stopReq) { R(c, 28, 62, 1, 10, P.ink); B(c, 25, 55, 7, 7, P.red, P.ink); R(c, 26, 58, 5, 1, P.white); }
  const items = st.actors.map(a => ({ y:a.y, f:() => sprite(c, P, a, fr, st.sel === a) }));
  items.push({ y:90, f:() => { B(c, 9, 84, 36, 10, P.sofa2, P.ink); B(c, 9, 92, 36, 9, P.sofa, P.ink); B(c, 6, 88, 6, 14, P.sofa2, P.ink); B(c, 42, 88, 6, 14, P.sofa2, P.ink); R(c, 10, 101, 2, 2, P.ink); R(c, 42, 101, 2, 2, P.ink); } });
  items.push({ y:103, f:() => { const ring = st.decision && fr ? 1 : 0;
    B(c, 114, 93, 14, 11, P.wood, P.ink); R(c, 115, 101, 12, 2, P.wood2);
    B(c, 117 + ring, 86, 8, 6, st.decision ? P.pink : P.amber, P.ink); R(c, 120 + ring, 84, 2, 2, P.ink); R(c, 116, 92, 10, 1, P.ink);
    if (st.decision && fr) { R(c, 113, 85, 1, 3, P.pink); R(c, 128, 85, 1, 3, P.pink); R(c, 111, 83, 1, 2, P.pink); R(c, 130, 83, 1, 2, P.pink); } } });
  items.sort((a, b) => a.y - b.y).forEach(i => i.f());
}
function boxPos(u) {
  const tier = (x0, s) => [x0 + (s % 2) * 12, 47 + (1 - Math.floor(s / 2) % 2) * 16];
  if (u.place === 'backlog') return [32 + (u.slot % 2) * 12, 47 + Math.floor(u.slot / 2) * 16];
  if (u.place === 'done') return tier(212, u.slot);
  if (u.place === 'desk1') return [DESKS[0] + 1, 51];
  if (u.place === 'desk2') return [DESKS[1] + 1, 51];
  if (u.place === 'desk3') return [DESKS[2] + 1, 51];
  if (u.place === 'test') return [157, 51];
  if (u.place === 'ui') return [192, 51];
  return null;
}
// 건물 단면도. floors: [{wall, agents:[{species,hat,shirt,state}], done, total, alert, lit}]
const FLOOR_H = 23, FLOOR_Y = 10;
function drawBuilding(c, st, P) {
  const fr = st.fr | 0, sky = st.sky || { col:P.sky, night:false };
  R(c, 0, 0, W, H, sky.col); R(c, sky.night ? 206 : 12, 5, 6, 6, P.sun);
  if (!sky.night) { R(c, 196, 16, 14, 3, P.cloud); R(c, 200, 14, 7, 2, P.cloud); R(c, 4, 30, 9, 2, P.cloud); }
  R(c, 0, 102, W, 6, P.grass); R(c, 0, 102, W, 1, P.ink);
  R(c, 14, 4, 212, 4, P.ink); R(c, 18, 8, 204, 94, P.ink);
  st.floors.forEach((f, i) => {
    const y = FLOOR_Y + i * FLOOR_H;
    R(c, 20, y, 200, 21, f.wall);
    for (let x = 26; x < 216; x += 10) R(c, x, y + 14, 1, 7, 'rgba(35,40,69,.08)');
    B(c, 22, y + 2, 62, 11, P.paper, P.ink);
    for (let k = 0; k < f.total; k++) B(c, 23 + k * 6, y + 15, 5, 5, k < f.done ? P.boxD : P.back, P.ink);
    f.agents.forEach((a, k) => sprite(c, P, Object.assign({ x:100 + k * 21, y:y + 20 }, a), fr, false));
    if (!f.agents.length) R(c, 20, y, 200, 21, P.dimFloor);
    if (st.sel === f) { R(c, 20, y, 200, 1, P.white); R(c, 20, y + 20, 200, 1, P.white); R(c, 20, y, 1, 21, P.white); R(c, 219, y, 1, 21, P.white); }
    if (f.alert) { R(c, 222, y + 6, 2, 2, P.ink); B(c, 224, y + 3, 9, 9, fr ? P.pink : P.tower, P.ink); }
  });
}
G.MM = { W, H, PAL, SPECIES, SPOT, DESKS, SIGNS, FLOOR_H, FLOOR_Y, R, B, sprite, glyph, box, boxPos, drawOffice, drawBuilding };
})(typeof window !== 'undefined' ? window : globalThis);

/* goInstaller · «Защита от сканеров» — экраны sh-a…sh-h, направление «Аркада».
   Строка — массив сегментов [текст, токен, выделено?]. Одна клетка — один символ.
   Два счётчика: ВХОД — сканеры остановлены, ВЫХОД — утечка IP к сетям ВК предотвращена. */
(function (root) {
'use strict';
let LANG = 'ru';
const t = (ru, en) => (LANG === 'en' ? en : ru);
const len = s => [...s].length;
const rep = (c, n) => c.repeat(Math.max(0, n));
const padR = (s, n) => { const a = [...s]; return a.length > n ? a.slice(0, n - 1).join('') + '…' : s + ' '.repeat(n - a.length); };
const padL = (s, n) => { const a = [...s]; return a.length > n ? a.slice(0, n - 1).join('') + '…' : ' '.repeat(n - a.length) + s; };
const padC = (s, n) => { const a = [...s]; if (a.length >= n) return a.slice(0, n).join(''); const l = Math.floor((n - a.length) / 2); return ' '.repeat(l) + s + ' '.repeat(n - a.length - l); };
const slen = segs => segs.reduce((a, s) => a + len(s[0]), 0);
const r = (segs, sel) => ({ segs: segs || [], sel: !!sel });
function fit(segs, w) {
  const out = []; let used = 0;
  for (const s of segs) {
    if (used >= w) break;
    let txt = s[0];
    if (used + len(txt) > w) txt = [...txt].slice(0, w - used - 1).join('') + '…';
    out.push([txt, s[1], s[2]]); used += len(txt);
  }
  return { segs: out, used };
}
const spread = (left, right, W) => { const g = W - slen(left) - slen(right); return g >= 1 ? [...left, [rep(' ', g), 'text'], ...right] : left; };
const padSegs = (segs, W) => { const f = fit(segs, W); return [...f.segs, [rep(' ', W - f.used), 'text']]; };
const merge = segs => segs.reduce((a, s) => { const l = a[a.length - 1]; if (l && l[1] === s[1] && l[2] === s[2]) l[0] += s[0]; else a.push([s[0], s[1], s[2]]); return a; }, []);
function wrap(text, w, keep) {
  const words = text.split(' ').reduce((a, x) => { if (x === '·' && a.length) a[a.length - 1] += ' ·'; else a.push(x); return a; }, []);
  const out = []; let line = '';
  for (const word of words) {
    const force = keep && keep.includes(word);
    if (!line) line = word;
    else if (!force && len(line) + 1 + len(word) <= w) line += ' ' + word;
    else { out.push(line); line = word; }
  }
  if (line) out.push(line);
  return out;
}
const nf = n => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, LANG === 'en' ? ',' : ' ');
const dec = x => (Math.round(x * 10) / 10).toFixed(1).replace('.', LANG === 'en' ? '.' : ',');
function pl(n, a, b, c, e1, eN) {
  if (LANG === 'en') return n === 1 ? e1 : eN;
  const d = n % 10, h = n % 100;
  return d === 1 && h !== 11 ? a : d >= 2 && d <= 4 && (h < 12 || h > 14) ? b : c;
}
const att = n => nf(n) + ' ' + pl(n, 'попытка', 'попытки', 'попыток', 'attempt', 'attempts');
const adr = n => nf(n) + ' ' + pl(n, 'адрес', 'адреса', 'адресов', 'address', 'addresses');
const nets = n => nf(n) + ' ' + pl(n, 'сеть', 'сети', 'сетей', 'network', 'networks');
const conn = n => nf(n) + ' ' + pl(n, 'соединение', 'соединения', 'соединений', 'connection', 'connections') + t(' к сетям ВК', ' to VK networks');
const IN_L = on => on ? t('Вход · сканеры остановлены', 'In · scanners stopped') : t('Вход · выкл · только считает', 'In · off · counting only');
const OUT_L = vk => vk ? t('Выход · утечка IP предотвращена', 'Out · IP leak prevented') : t('Выход · выкл · защита от утечки IP не работает', 'Out · off · IP leak protection is not working');
const G = ok => ok ? ['✓', 'ok'] : ['!', 'warn'];
const PRESUMED = () => t('предположительно, по названию сети', 'presumably, by network name');
const noLabel = () => t('без подписи в списке', 'no label in the list');

/* ---------- данные макета (условные, согласованы между собой) ---------- */
function lcg(seed) { let s = seed; return () => (s = (s * 1103515245 + 12345) % 2147483648) / 2147483648; }
const WD = { ru: ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'], en: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'] };
const MON = { ru: ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'], en: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] };
const D = (() => {
  const last7 = [1520, 1480, 1710, 1390, 1650, 2310, 1870], out7 = [11, 9, 18, 12, 14, 15, 17];
  const rnd = lcg(7), a = [], b = [];
  for (let i = 0; i < 23; i++) { a.push(1200 + rnd() * 560); b.push(7 + rnd() * 11); }
  const sa = a.reduce((x, y) => x + y, 0), sb = b.reduce((x, y) => x + y, 0);
  const ia = a.map(v => Math.round(v * 34280 / sa)), ib = b.map(v => Math.round(v * 292 / sb));
  ia[22] += 34280 - ia.reduce((x, y) => x + y, 0); ib[22] += 292 - ib.reduce((x, y) => x + y, 0);
  const days = [];
  for (let i = 0; i < 30; i++) {
    const d = new Date(Date.UTC(2026, 10, 3 - (29 - i)));
    days.push({ dd: String(d.getUTCDate()).padStart(2, '0'), mm: String(d.getUTCMonth() + 1).padStart(2, '0'), m: d.getUTCMonth(), wd: d.getUTCDay(), in: i < 23 ? ia[i] : last7[i - 23], out: i < 23 ? ib[i] : out7[i - 23] });
  }
  return {
    nets: 1172, excl: 3, since: () => t('02.11 18:40', '2 Nov 18:40'), list: () => t('03.11', '3 Nov'),
    away: { in: [1284, 37], out: [9, 7, 2] },
    per: { h24: { in: [2105, 52], out: [17, 14, 3], nw: 31, rp: 21 }, d7: { in: [11930, 214], out: [96, 81, 15], nw: 140, rp: 74 },
      m30: { in: [46210, 640], out: [388, 330, 58], nw: 410, rp: 230 }, all: { in: [169350, 2140], out: [1396, 1190, 206] } },
    hStart: 15,
    hours: [64, 71, 58, 83, 96, 88, 74, 69, 92, 118, 134, 121, 212, 136, 121, 77, 63, 55, 61, 72, 80, 59, 48, 53],
    outHours: [0, 1, 0, 2, 1, 0, 0, 1, 0, 0, 2, 0, 1, 0, 0, 0, 1, 2, 1, 0, 2, 1, 1, 1],
    days,
    months: [[5, 21300, 180], [6, 28900, 240], [7, 32400, 260], [8, 36800, 300], [9, 44120, 370], [10, 5830, 46]],
    ports: [['22/tcp', 704, 'SSH'], ['443/tcp', 512, 'VLESS'], ['80/tcp', 318, ['сайт-маска', 'mask site']], ['2443/tcp', 160, 'MTProxy'], ['3389/tcp', 141, ['свободен', 'free']], ['853/tcp', 88, 'DoT']],
    disk: '18,4', started: '01.06.2026', days_n: 156
  };
})();
const PERIODS = ['h24', 'd7', 'm30', 'all'];
const perName = p => ({ h24: t('24 часа', '24 hours'), d7: t('7 дней', '7 days'), m30: t('месяц', 'month'), all: t('всё время', 'all time') })[p];
const perShort = p => ({ h24: t('24 ч', '24 h'), d7: t('7 дн', '7 d'), m30: t('месяц', 'month'), all: t('всё', 'all') })[p];
const hh = h => String(h).padStart(2, '0');
const median = v => { const s = [...v].sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const dlab = (d, C) => LANG === 'en' ? WD.en[d.wd] + ' ' + (C >= 80 ? +d.dd + ' ' + MON.en[d.m] : d.dd) : WD.ru[d.wd] + ' ' + (C >= 80 ? d.dd + '.' + d.mm : d.dd);
/* ряды графика по представлению: [подпись оси, вход, выход] */
function series(p, C) {
  if (p === 'h24') { const o = []; for (let i = 0; i < 24; i += 2) o.push([hh((D.hStart + i) % 24) + '–' + hh((D.hStart + i + 2) % 24), D.hours[i] + D.hours[i + 1], D.outHours[i] + D.outHours[i + 1]]); return o; }
  if (p === 'd7') return D.days.slice(23).map(d => [dlab(d, C), d.in, d.out]);
  if (p === 'm30') { const k = C >= 80 ? 2 : 3, o = []; for (let i = 0; i < 30; i += k) { const g = D.days.slice(i, i + k), d = g[0]; o.push([LANG === 'en' ? +d.dd + ' ' + MON.en[d.m] : d.dd + '.' + d.mm, g.reduce((x, y) => x + y.in, 0), g.reduce((x, y) => x + y.out, 0)]); } return o; }
  return D.months.map(m => [t(MON.ru[m[0]], MON.en[m[0]]) + ' 26', m[1], m[2]]);
}
const axisName = (p, C) => ({ h24: t('часы', 'hours'), d7: t('день', 'day'), m30: C >= 80 ? t('2 дня', '2 days') : t('3 дня', '3 days'), all: t('месяц', 'month') })[p];
function peak(p) {
  if (p === 'h24') { const m = Math.max(...D.hours), i = D.hours.indexOf(m); return { lab: hh((D.hStart + i) % 24) + ':00–' + hh((D.hStart + i + 1) % 24) + ':00', at: hh((D.hStart + i) % 24) + ':00', v: m, x: m / median(D.hours) }; }
  if (p === 'd7' || p === 'm30') { const g = p === 'd7' ? D.days.slice(23) : D.days, v = g.map(d => d.in), m = Math.max(...v), d = g[v.indexOf(m)]; return { lab: dlab(d, 80), at: dlab(d, 80), v: m, x: m / median(v) }; }
  const v = D.months.map(m => m[1]), m = Math.max(...v); return { lab: t(MON.ru[D.months[v.indexOf(m)][0]], MON.en[D.months[v.indexOf(m)][0]]) + ' 2026', v: m, x: 0 };
}
const SPIKE_X = 2;
/* топ-30 сетей */
const NAMES = ['EXAMPLE-DC (Example Datacenter)', 'SAMPLE-ISP', 'TEST-CLOUD', 'DEMO-VPS (Demo Servers Inc)', 'EXAMPLE-NET (Example LLC)', 'ANOTHER-AS', '', 'SAMPLE-CLOUD-HOSTING (Sample Hosting Ltd)', 'TEST-NET-EU', 'DEMO-TRANSIT', 'EXAMPLE-BACKBONE', '', 'SAMPLE-COLO', 'TEST-HOSTING-2', 'DEMO-NET-ASIA', 'EXAMPLE-MOBILE', 'SAMPLE-RESEARCH-SCAN', 'TEST-BROADBAND', '', 'DEMO-CDN', 'EXAMPLE-EDGE (Example Edge BV)', 'SAMPLE-UNI-NET', 'TEST-FIBER', 'DEMO-WIRELESS', 'EXAMPLE-SECURITY-LAB', 'SAMPLE-TELECOM', '', 'TEST-DATACENTER-3', 'DEMO-HOST-EU', 'EXAMPLE-CLOUD-2'];
const ASN = [...Array(16)].map((_, i) => 64496 + i).concat([...Array(14)].map((_, i) => 65536 + i));
const PORTS_OF = ['443/tcp', '22/tcp', '22/tcp', '80/tcp', '3389/tcp', '443/tcp', '22/tcp', '2443/tcp', '853/tcp', '22/tcp'];
function top30(p) {
  const P = D.per[p], rnd = lcg(PERIODS.indexOf(p) * 97 + 11), rows = [];
  for (let i = 0; i < 30; i++) { const j = (i * 7 + PERIODS.indexOf(p) * 3) % 30; const w = 1 / Math.pow(i + 1.7, 1.15) * (0.85 + rnd() * 0.3); rows.push({ k: j, w }); }
  const sw = rows.reduce((x, y) => x + y.w, 0);
  let list = rows.map(x => ({ asn: ASN[x.k], name: NAMES[x.k], a: Math.max(3, Math.round(P.in[0] * 0.82 * x.w / sw)), b: Math.max(1, Math.round(P.in[1] * 0.7 * x.w / sw)), port: PORTS_OF[x.k % 10], k: x.k }));
  const fixed = p === 'h24' ? [[64500, 'EXAMPLE-NET (Example LLC)', 820, 24], [64501, 'ANOTHER-AS', 310, 9], [64502, '', 205, 6], [64503, 'SAMPLE-CLOUD-HOSTING (Sample Hosting Ltd)', 160, 5], [64504, 'TEST-NET-EU', 94, 3]]
    : p === 'd7' ? [[64500, 'EXAMPLE-NET (Example LLC)', 4610, 96], [64503, 'SAMPLE-CLOUD-HOSTING (Sample Hosting Ltd)', 1920, 31], [64501, 'ANOTHER-AS', 1405, 22], [64505, 'DEMO-TRANSIT', 870, 15], [64502, '', 760, 11]] : null;
  if (fixed) { const fa = fixed.map(f => f[0]); list = list.filter(x => !fa.includes(x.asn)); list = fixed.map(f => ({ asn: f[0], name: f[1], a: f[2], b: f[3], port: PORTS_OF[(f[0] - 64496 + 1) % 10], k: f[0] - 64496 })).concat(list.map(x => ({ ...x, a: Math.min(x.a, 90), b: Math.min(x.b, 3) }))); }
  list = list.slice(0, 30).sort((x, y) => y.a - x.a);
  return list.map((x, i) => { const mins = i * 9 + 4 + (x.k % 5) * 3; const old = p !== 'h24' && i > 11; const tm = 14 * 60 + 5 - mins; const day = old ? D.days[29 - Math.min(28, i - 10)] : null;
    return { ...x, n: i + 1, last: day ? day.dd + '.' + day.mm + ' ' + hh((x.k * 5) % 24) + ':' + hh((x.k * 13) % 60) : '03.11 ' + hh(Math.floor(tm / 60)) + ':' + hh(tm % 60) }; });
}
const topN = (p, n) => top30(p).slice(0, n).map(x => [x.asn, x.name, x.a, x.b]);

/* ---------- графики ---------- */
const LV = [' ', '▁', '▂', '▃', '▃', '▅', '▅', '▇', '█'];
function vbars(vals, H, bw, gap, tok) {
  const mx = Math.max(1, ...vals), out = [];
  for (let k = 0; k < H; k++) {
    const s = [];
    vals.forEach((v, i) => {
      const e = Math.round(v / mx * H * 8) - (H - 1 - k) * 8;
      let ch = e >= 8 ? '█' : e <= 0 ? ' ' : LV[e];
      if (k === H - 1 && v > 0 && ch === ' ') ch = '▁';
      if (i && gap) s.push([rep(' ', gap), 'text']);
      s.push([rep(ch, bw), ch === ' ' ? 'text' : tok]);
    });
    out.push(merge(s));
  }
  return out;
}
function labelRow(labs, bw, gap) {
  const n = labs.length, W = n * bw + (n - 1) * gap, a = Array(W).fill(' ');
  labs.forEach((l, i) => { if (!l) return; const c = i * (bw + gap); if (c + len(l) <= W && (c === 0 || a[c - 1] === ' ')) [...l].forEach((ch, k) => (a[c + k] = ch)); });
  return [[a.join(''), 'muted']];
}
const SPK = [' ', '▁', '▂', '▃', '▃', '▅', '▅', '▇', '█'];
function spark(kind, bw, gap) {
  const v = D.days.slice(23).map(d => kind === 'out' ? d.out : d.in), mn = Math.min(...v), mx = Math.max(...v);
  return v.map(n => rep(SPK[1 + Math.round((n - mn) / Math.max(1, mx - mn) * 7)], bw || 1)).join(rep(' ', gap || 0));
}
/* «пирамида»: по центру колонка подписей, по бокам две нулевые линии │,
   вход растёт влево (▐ — половинка), выход вправо (▌), сетка ┊ на круглых значениях, у сторон свой масштаб */
function niceMax(mx) {
  mx = Math.max(1, mx);
  for (let k = 0; k < 8; k++) for (const m of [1, 2, 5]) { const st = m * Math.pow(10, k), n = Math.ceil(mx / st); if (n <= 4) return { max: n * st, step: st }; }
  return { max: mx, step: mx };
}
function side(v, W, sc, left) {
  const a = Array(W).fill(' '), tk = Array(W).fill('text');
  for (let g = sc.step; g < sc.max; g += sc.step) { const j = Math.round(g / sc.max * W) - 1; if (j >= 0 && j < W) { a[j] = '┊'; tk[j] = 'shadow'; } }
  const h = Math.round(v / sc.max * W * 2), full = h >> 1;
  for (let j = 0; j < full && j < W; j++) { a[j] = '█'; tk[j] = left ? 'in' : 'out'; }
  if (h % 2 && full < W) { a[full] = left ? '▐' : '▌'; tk[full] = left ? 'in' : 'out'; }
  if (v > 0 && h === 0) { a[0] = left ? '▕' : '▏'; tk[0] = left ? 'in' : 'out'; }
  if (left) { a.reverse(); tk.reverse(); }
  return merge(a.map((c, i) => [c, tk[i]]));
}
function scaleRow(W, sc, left) {
  const a = Array(W).fill(' '), put = (txt, end) => { const st = Math.max(0, Math.min(W - len(txt), left ? end - len(txt) + 1 : end)); if (st < 0 || st + len(txt) > W) return; for (let k = st - 1; k <= st + len(txt); k++) if (k >= 0 && k < W && a[k] !== ' ') return; [...txt].forEach((c, k) => (a[st + k] = c)); };
  const pos = g => { const j = Math.max(0, Math.round(g / sc.max * W) - 1); return left ? W - 1 - j : j; };
  put('0', left ? W - 1 : 0);
  for (let g = sc.step; g <= sc.max; g += sc.step) put(nf(g), pos(g));
  return [[a.join(''), 'muted']];
}
function pyramid(rows, g) {   // g: { L, AX, R, axisName, sel }
  const si = niceMax(Math.max(...rows.map(x => x[1]))), so = niceMax(Math.max(...rows.map(x => x[2])));
  const Z = sel => [['│', 'rule', sel]], out = [];
  const mark = (segs, sel) => segs.map(q => [q[0], q[1], sel]);
  out.push([[padL('← ' + t('ВХОД', 'IN'), g.L), 'in'], ...Z(), [padC(g.axisName, g.AX), 'muted'], ...Z(), [padR(t('ВЫХОД', 'OUT') + ' →', g.R), 'out']]);
  out.push([[padL(t('сканеры', 'scanners'), g.L), 'muted'], ...Z(), [rep(' ', g.AX), 'text'], ...Z(), [padR(t('утечка IP', 'IP leak'), g.R), 'muted']]);
  rows.forEach((x, i) => { const sel = i === g.sel; out.push(mark([...side(x[1], g.L, si, true), ['│', 'rule'], [padC(x[0], g.AX), sel ? 'title' : 'text'], ['│', 'rule'], ...side(x[2], g.R, so, false)], sel)); });
  out.push([...scaleRow(g.L, si, true), ['┴', 'rule'], [padC(t('шкала', 'scale'), g.AX), 'muted'], ['┴', 'rule'], ...scaleRow(g.R, so, false)]);
  const x = rows[g.sel] || rows[rows.length - 1];
  const info = [['▸ ', 'cursor'], [x[0].trim() + ': ', 'text'], [t('вход ', 'in ') + nf(x[1]), 'in'], [' · ', 'muted'], [t('выход ', 'out ') + nf(x[2]), 'out']];
  return { lines: out.map(l => merge(l)), info, row: x };
}

/* ---------- рамки и общие строки ---------- */
function frame2(W, H, title, right, lines) {
  const out = [];
  const top = [['╔═ ', 'grad'], ...title, [' ', 'grad']];
  let tr = right ? [[' ', 'grad'], ...right, [' ═╗', 'grad']] : [['═╗', 'grad']];
  let fill = W - slen(top) - slen(tr);
  if (fill < 1) { tr = [['═╗', 'grad']]; fill = W - slen(top) - 2; }
  out.push(fit([...top, [rep('═', Math.max(0, fill)), 'grad'], ...tr], W).segs);
  for (let i = 0; i < H; i++) {
    const l = lines[i] || { s: [] };
    const f = fit(l.sel ? l.s.map(q => [q[0], q[1], true]) : l.s, W - 2);
    out.push([['║', 'grad'], ...f.segs, [rep(' ', W - 2 - f.used), 'text', l.sel], ['║', 'grad']]);
  }
  out.push([['╚' + rep('═', W - 2) + '╝', 'grad']]);
  return out;
}
function twoWin(C, LW, H, L, R) {
  const RW = C - LW - 2, lf = frame2(LW, H, L.title, L.right, L.lines), rf = frame2(RW, H, R.title, R.right, R.lines), out = [];
  lf.forEach((row, i) => out.push(r(i === 0 ? [...row, [' ', 'text'], ...rf[i], [' ', 'text']] : [...row, ['░', 'shadow'], ...rf[i], ['░', 'shadow']])));
  out.push(r([[' ', 'text'], [rep('░', LW), 'shadow'], [' ', 'text'], [rep('░', RW), 'shadow']]));
  return out;
}
function oneWin(C, W, H, title, right, lines) {
  const out = frame2(W, H, title, right, lines).map((row, i) => r(i === 0 ? [...row, [rep(' ', C - W), 'text']] : [...row, ['░', 'shadow']]));
  out.push(r([[' ', 'text'], [rep('░', W), 'shadow']]));
  return out;
}
function sbox(C, title, right, inner, bottom) {
  const Wb = C - 1, iw = Wb - 4, R = [];
  const top = [['╔═ ', 'grad'], ...title, [' ', 'grad']];
  let tr = right ? [[' ', 'grad'], ...right, [' ═╗', 'grad']] : [['═╗', 'grad']];
  if (Wb - slen(top) - slen(tr) < 1) tr = [['═╗', 'grad']];
  R.push(r([...top, [rep('═', Wb - slen(top) - slen(tr)), 'grad'], ...tr, [' ', 'text']]));
  inner.forEach(l => {
    if (l === 'SEP') { R.push(r([['║' + rep(' ', Wb - 2) + '║', 'grad'], ['░', 'shadow']])); return; }
    const f = fit(l, iw);
    R.push(r([['║ ', 'grad'], ...f.segs, [rep(' ', iw - f.used), 'text'], [' ║', 'grad'], ['░', 'shadow']]));
  });
  const bl = [['╚═ ', 'grad'], ...bottom, [' ', 'grad']];
  R.push(r([...bl, [rep('═', Wb - slen(bl) - 1), 'grad'], ['╝', 'grad'], ['░', 'shadow']]));
  R.push(r([[' ', 'text'], [rep('░', Wb), 'shadow']]));
  return R;
}
function hbar(frac, w, tok) {
  const cells = Math.max(0, Math.min(1, frac)) * w, full = Math.floor(cells), part = Math.floor((cells - full) * 8);
  const P = ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉'];
  const s = [[rep('█', full), tok]];
  if (full < w) { s.push([part ? P[part] : '░', part ? tok : 'rule']); s.push([rep('░', w - full - 1), 'rule']); }
  return s;
}
function hud(C, ver) {
  const n = C < 60;
  const left = [[' goInstaller', 'title'], [' ' + ver, 'muted'], ...(n ? [] : [['  ·  vpn-fin-1', 'text']])];
  const m = (lab, fr, pct, w) => [[lab + ' ', 'muted'], ['▕', 'rule'], ...hbar(fr, w, fr < 0.7 ? 'ok' : fr < 0.9 ? 'warn' : 'err'), ['▏', 'rule'], [pct, 'text']];
  const right = n ? [...m(t('диск', 'disk'), 0.58, '58 %', 4), ['  ' + t('озу', 'mem') + ' ', 'muted'], ['41 % ', 'text']]
    : [...m(t('диск', 'disk'), 0.58, '58 %', 6), ['  ', 'text'], ...m(t('озу', 'mem'), 0.41, '41 %', 6), ['  ' + t('нагр', 'load') + ' ', 'muted'], ['0.4 ', 'text']];
  return r(spread(left, right, C));
}
function keysRow(C, keys) {
  const s = [['  ', 'text']];
  keys.forEach(([k, l], i) => { if (i) s.push([' · ', 'muted']); s.push([k, 'key']); if (l) s.push([' ' + l, 'muted']); });
  return r(s);
}
const LINK = 'github.com/C24Be/AS_Network_List';
function footer(C, plain) {
  const P = [t('Списки сетей — открытый проект AS_Network_List · ' + LINK + ' (BSD-2)', 'Network lists: open project AS_Network_List · ' + LINK + ' (BSD-2)'),
    t('Спасибо автору C24Be за данные и идею. Защита в goInstaller — anten-ka.', 'Thanks to C24Be for the data and the idea. goInstaller protection — anten-ka.')];
  return P.flatMap(p => wrap(p, C - 2, [LINK])).map(l => r([[(plain ? '# ' : '  ') + l, plain ? 'text' : 'muted']]));
}
const pad = (rows, n) => { while (rows.length < n) rows.push(r([])); return rows; };
const statusRight = o => { const a = G(o.on), b = G(o.vk); return [[a[0] + ' ', a[1]], [t('вход ', 'in ') + (o.on ? t('вкл', 'on') : t('выкл', 'off')), a[1]], [' · ', 'muted'], [b[0] + ' ', b[1]], [t('выход ', 'out ') + (o.vk ? t('вкл', 'on') : t('выкл', 'off')), b[1]], [' ', 'text']]; };
const titleRow = (C, title, right) => r(spread([['  ' + title, 'title']], right || [], C));
function tabBar(C, labels, cur) {
  const s = [['  ', 'text']];
  labels.forEach((l, i) => { s.push(['═ ', 'grad'], [String(i + 1), 'key'], [' ' + (i === cur ? '● ' : '○ '), i === cur ? 'cursor' : 'muted'], [l, i === cur ? 'title' : 'text'], [' ', 'text']); });
  const w = slen(s); if (w < C - 1) s.push([rep('═', C - 1 - w), 'grad']);
  return r(s);
}

/* ---------- карточка «Защита» (главное меню g2 и меню sh-d) ---------- */
function card(o) {   // o: { lang, on, vk, chart: 'fly'|'bars', RI, row }
  if (o.lang) LANG = o.lang;
  const RI = o.RI || 38, L = [], days = D.days.slice(23), sel = o.row == null ? 6 : Math.max(0, Math.min(6, o.row));
  let info;
  if (o.chart === 'bars') {
    const vi = days.map(d => d.in), vo = days.map(d => d.out), labs = days.map(d => WD[LANG][d.wd]);
    L.push(spread([['← ' + t('ВХОД · сканеры', 'IN · scanners'), 'in']], [[t('макс ', 'max ') + nf(Math.max(...vi)), 'muted']], RI));
    vbars(vi, 3, 3, 2, 'in').forEach(x => L.push(x)); L.push(labelRow(labs, 3, 2));
    L.push(spread([[t('ВЫХОД · утечка IP', 'OUT · IP leak') + ' →', 'out']], [[t('макс ', 'max ') + nf(Math.max(...vo)), 'muted']], RI));
    vbars(vo, 3, 3, 2, 'out').forEach(x => L.push(x)); L.push(labelRow(labs, 3, 2));
    const d = days[sel]; info = [['▸ ', 'cursor'], [dlab(d, 80) + ': ', 'text'], [t('вход ', 'in ') + nf(d.in), 'in'], [' · ', 'muted'], [t('выход ', 'out ') + nf(d.out), 'out']];
  } else {
    const pm = pyramid(days.map(d => [dlab(d, 46), d.in, d.out]), { L: 15, AX: 6, R: 15, axisName: t('день', 'day'), sel });
    pm.lines.forEach(x => L.push(x));
    const d = days[sel]; info = [['▸ ', 'cursor'], [dlab(d, 80) + ': ', 'text'], [t('вход ', 'in ') + nf(d.in), 'in'], [' · ', 'muted'], [t('выход ', 'out ') + nf(d.out), 'out']];
  }
  const P = D.per, cw = 16, g1 = G(o.on), g2 = G(o.vk);
  L.push([[padR('', cw) + padL(t('СУТКИ', '24 H'), 9) + padL(t('7 ДНЕЙ', '7 DAYS'), 10), 'muted']]);
  L.push([[g1[0] + ' ', g1[1]], [padR(o.on ? t('вход, попыток', 'in, attempts') : t('вход выкл, счёт', 'in off, counted'), cw - 2), 'text'], [padL(nf(P.h24.in[0]), 9) + padL(nf(P.d7.in[0]), 10), 'text']]);
  L.push([[padR('  ' + t('адресов', 'addresses'), cw), 'muted'], [padL(nf(P.h24.in[1]), 9) + padL(nf(P.d7.in[1]), 10), 'text']]);
  L.push(o.vk ? [[g2[0] + ' ', g2[1]], [padR(t('выход, к ВК', 'out, to VK'), cw - 2), 'text'], [padL(nf(P.h24.out[0]), 9) + padL(nf(P.d7.out[0]), 10), 'text']]
    : [[g2[0] + ' ', g2[1]], [t('выход выкл: утечка IP не защищена', 'out off: IP leak not protected'), 'warn']]);
  L.push(info);
  return { title: [[t('Защита от сканеров', 'Scanner protection'), 'title']], right: [[(o.on && o.vk ? '✓' : '!') + ' ', o.on && o.vk ? 'ok' : 'warn'], [o.on && o.vk ? t('вкл', 'on') : !o.on ? t('вход выкл', 'in off') : t('выход выкл', 'out off'), o.on && o.vk ? 'ok' : 'warn']], lines: L };
}

/* ---------- sh-a / sh-b / sh-c: уведомление при входе ---------- */
const LASTLOGIN = () => r([['Last login: Mon Nov  2 18:40:12 2026 from 203.0.113.24', 'text']]);
function newsInner(C, probs, ver) {
  const n = C < 60, inner = [], nx = ver === '0.9.5' ? '0.9.6' : '1.2.4';
  const ups = [['↑', 'update', 'goTelegram pro', '2.10.46 → 2.10.49', t('обновление в main', 'update in main')], ['✚', 'new', 'goAmnezia pro', '1.0.2', t('новый продукт серии, main', 'new in the series, main')], ['↑', 'update', 'goInstaller', ver + ' → ' + nx, t('новая версия установщика', 'new installer version')]];
  ups.forEach(u => inner.push(n ? [[u[0], u[1]], [' ' + padR(u[2], 15), 'name'], [u[3], u[1]]] : [[' ' + u[0], u[1]], [' ' + padR(u[2], 17), 'name'], [padR(u[3], 20), u[1]], [u[4], 'muted']]));
  if (probs) {
    inner.push('SEP');
    [{ name: 'vpn.example.com', msg: t('сертификат истекает через 9 дней', 'certificate expires in 9 days'), short: t('сертификат vpn.example.com: 9 дней', 'vpn.example.com cert: 9 days left'), step: 'certbot renew' },
      { name: 'goDNS pro', msg: t('dnsdist: 3 перезапуска за час', 'dnsdist: 3 restarts in an hour'), short: t('goDNS pro: dnsdist 3 перезапуска за час', 'goDNS pro: dnsdist restarted 3 times/h'), step: 'journalctl -u dnsdist' }].forEach(p => {
      if (n) { inner.push([['!', 'warn'], [' ' + p.short, 'text']]); inner.push([['  → ', 'muted'], [p.step, 'key']]); }
      else inner.push([[' !', 'warn'], [' ' + padR(p.name, 17), 'name'], [p.msg, 'text'], [' → ', 'muted'], [p.step, 'key']]);
    });
    inner.push([[n ? '' : ' ', 'text'], [t('диск 58 % · память 41 % · нагрузка 0.4', 'disk 58 % · memory 41 % · load 0.4'), 'muted']]);
  }
  return inner;
}
function awayLines(o, C, ind) {
  const n = C < 60, A = D.away, gi = G(o.on), go = G(o.vk), L = [];
  const inNum = [att(A.in[0]) + ' · ' + adr(A.in[1]), o.on ? 'title' : 'warn'], outNum = [conn(A.out[0]), 'title'];
  if (!n) {
    L.push([[ind + gi[0], gi[1]], [' ' + IN_L(o.on) + ': ', 'text'], inNum]);
    L.push(o.vk ? [[ind + go[0], go[1]], [' ' + OUT_L(true) + ': ', 'text'], outNum] : [[ind + go[0], go[1]], [' ' + OUT_L(false), 'warn']]);
  } else {
    L.push([[ind + gi[0], gi[1]], [' ' + IN_L(o.on) + ':', 'text']], [[ind + '  ' + inNum[0], inNum[1]]]);
    if (o.vk) L.push([[ind + go[0], go[1]], [' ' + OUT_L(true) + ':', 'text']], [[ind + '  ' + outNum[0], outNum[1]]]);
    else L.push([[ind + go[0], go[1]], [' ' + t('Выход · выкл ·', 'Out · off ·'), 'warn']], [[ind + '  ' + t('защита от утечки IP не работает', 'IP leak protection is not working'), 'warn']]);
  }
  return L;
}
function spikeLine(C, ind) {
  const p = peak('h24');
  return C >= 60 ? [[ind + '▲', 'warn'], [' ' + t('Всплеск в ', 'Spike at ') + p.at + ': ' + t('попыток в ' + dec(p.x) + ' раза больше обычного', dec(p.x) + '× the usual attempts') + ' (' + nf(p.v) + t(' за час', ' in an hour') + ')', 'text']]
    : [[ind + '▲', 'warn'], [' ' + t('всплеск в ', 'spike at ') + p.at + ': ×' + dec(p.x) + t(' к обычному', ' the usual'), 'text']];
}
function topLine80(x) { return [['     ' + padR('AS' + x[0], 9), 'text'], [padR(x[1] || noLabel(), 40), x[1] ? 'name' : 'muted'], [padL(nf(x[2]), 6) + ' · ' + nf(x[3]), 'text']]; }
function blockA(o, C) {
  const n = C < 60, top = topN('h24', o.spike ? 2 : 3);
  if (!n) return [
    [[' ✓', 'ok'], [' ' + t('Защита от сканеров', 'Scanner protection'), 'name'], [' · ' + t('пока вас не было (с ', 'while you were away (since ') + D.since() + '):', 'muted']],
    ...awayLines(o, C, '   '), ...(o.spike ? [spikeLine(C, '   ')] : []),
    [['   ' + t('Чаще всего за сутки', 'Most active over 24 h'), 'text'], [' (' + PRESUMED() + '):', 'muted']], ...top.map(topLine80)];
  const L = [[['✓', 'ok'], [' ' + t('Защита', 'Protection'), 'name'], [' · ' + t('с 02.11 18:40', 'since 2 Nov 18:40') + ':', 'muted']], ...awayLines(o, C, '  ')];
  if (o.spike) L.push(spikeLine(C, '  '));
  else { const x = topN('h24', 1)[0]; L.push([['  ' + t('чаще всего: ', 'most active: '), 'muted'], ['AS' + x[0] + ' ', 'text'], [x[1] || noLabel(), 'name']], [['  (' + PRESUMED() + ')', 'muted']]); }
  return L;
}
function blockB(o, C) {
  const n = C < 60, oo = { ...o, on: false };
  if (!n) return [
    [[' !', 'warn'], [' ' + t('Защита от сканеров: ', 'Scanner protection: '), 'name'], [t('выкл', 'off'), 'warn'], [t(' · сервер не блокирует, только считает', ' · the server does not block, only counts'), 'muted']],
    [['   ' + t('Пока вас не было (с ', 'While you were away (since ') + D.since() + '):', 'text']], ...awayLines(oo, C, '     '),
    [['   ' + t('Рекомендуем включить: ', 'Recommended: '), 'text'], ['goinstall', 'key'], [' → ', 'muted'], ['s', 'key'], [' ' + t('Защита', 'Scanner protection'), 'text'], [' → ', 'muted'], ['1', 'key'], [' ' + t('Включить защиту', 'Turn protection on'), 'text']]];
  return [[['!', 'warn'], [' ' + t('Защита: ', 'Shield: '), 'name'], [t('выкл', 'off'), 'warn'], [' · ' + t('с 02.11 18:40', 'since 2 Nov') + ':', 'muted']], ...awayLines(oo, C, '  '),
    [['  ' + t('включить: ', 'turn on: '), 'text'], ['goinstall', 'key'], [' → ', 'muted'], ['s', 'key'], [t(' Защита', ' → 1'), 'text']]];
}
function summary(C, probs, block, ver) {
  const n = C < 60, sved = t('сведения от ', 'data as of ') + '14:05';
  return sbox(C, [['goInstaller', 'title'], [' · vpn-fin-1', 'muted']], [[n ? '14:05' : sved, 'muted']], [...newsInner(C, probs, ver), 'SEP', ...block],
    [['goinstall', 'key'], [n ? t(' — меню', ' — menu') : t(' — открыть меню', ' — open the menu'), 'muted']]);
}
const prompt = badge => r([['root@vpn-fin-1', 'text'], ...badge, [':~# ', 'text'], ['█', 'cursor']]);
const badge = pr => [[' [go', 'muted'], [' ↑2', 'update'], [' ✚1', 'new'], [' !' + pr, 'warn'], [']', 'muted']];

/* ---------- sh-d: меню «Защита» ---------- */
function menuItems(o) {
  const on = o.on, vk = o.vk;
  return [
    { key: '1', act: 'toggle', label: on ? t('Выключить защиту', 'Turn protection off') : t('Включить защиту', 'Turn protection on'), tag: on ? ['✓ ' + t('вкл', 'on'), 'ok'] : ['! ' + t('выкл', 'off'), 'warn'], hint: on ? t('Сервер перестанет блокировать вход.', 'The server stops blocking inbound.') : t('Сервер начнёт блокировать вход.', 'The server starts blocking inbound.') },
    { key: '2', act: 'vk', label: t('ВК: не выпускать', 'VK: block outbound'), tag: vk ? ['✓ ' + t('вкл', 'on'), 'ok'] : ['! ' + t('выкл', 'off'), 'warn'], hint: t('Защита от утечки IP к сетям ВК.', 'IP leak protection towards VK.') },
    { key: '3', act: 'none', label: t('Обновить списки', 'Update lists'), tag: [t('от ', '') + D.list(), 'muted'], hint: t('Скачать свежие AS_Network_List.', 'Fetch fresh AS_Network_List.') },
    { key: '4', act: 'none', label: t('Исключения', 'Exclusions'), tag: [nf(D.excl), 'muted'], hint: t('Сети, которые защита пропускает.', 'Networks the protection lets through.') },
    { key: '5', act: 'none', label: t('Свои добавки', 'Own additions'), hint: t('Свои сети в дополнение к спискам.', 'Your own networks on top of the lists.') },
    { key: '6', act: 'stats', label: t('Статистика', 'Statistics'), hint: t('Графики входа и выхода за 4 периода.', 'In and out charts for 4 periods.') },
    { key: '7', act: 'top', label: t('Топ-30 сканеров', 'Top 30 scanners'), hint: t('Сети, которые стучались чаще всего.', 'Networks that knocked most often.') },
    { key: '8', act: 'settings', label: t('Настройки статистики', 'Statistics settings'), hint: t('Размер на диске, обнуление.', 'Size on disk, reset.') },
    { key: '9', act: 'none', label: t('Удалить защиту', 'Remove protection'), hint: t('Спросит 1 Да / 2 Нет.', 'Asks 1 Yes / 2 No.') },
    { key: '0', act: 'back', label: t('Назад', 'Back'), hint: t('В главное меню goInstaller.', 'Back to the goInstaller main menu.') }
  ];
}
function shD(o) {
  const C = o.C, items = menuItems(o), cur = o.cur || 0, body = [hud(C, o.ver)];
  if (C >= 80) {
    const LW = 37, lw = 21, L = [];
    items.forEach((it, i) => {
      const sel = i === cur;
      if (it.key === '0') L.push({ s: [[' ' + rep('─', LW - 4), 'rule']] });
      L.push({ s: [[' ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + ' ', sel ? 'cursor' : 'muted'], [padR(it.label, lw), sel ? 'title' : 'name'], ...(it.tag ? [it.tag] : [])], sel });
    });
    while (L.length < 15) L.push({ s: [] });
    L.push({ s: [[' ', 'text'], ['goinstall --shield stats', 'key']] });
    const cd = card({ ...o, RI: 38 }), R = cd.lines.map(s => ({ s: [[' ', 'text'], ...s] }));
    while (R.length < 15) R.push({ s: [] });
    R.length = 15; R.push({ s: [[' ', 'text'], [items[cur].hint, 'muted']] });
    body.push(...twoWin(C, LW, 16, { title: [[t('ДЕЙСТВИЯ', 'ACTIONS'), 'title']], lines: L }, { title: cd.title, right: cd.right, lines: R }));
    body.push(...footer(C)); pad(body, 23);
    body.push(keysRow(C, [['↑↓', ''], ['Enter', ''], ['1–9', t('сразу', 'jump')], ['0', t('назад', 'back')], ['q', t('выход', 'quit')]]));
  } else {
    const L = [], P = segs => L.push({ s: [[' ', 'text'], ...segs] }), gi = G(o.on), go = G(o.vk);
    P([[gi[0] + ' ', gi[1]], [t('Вход · сканеры остановлены: ', 'In · scanners stopped: '), 'text'], [nf(D.per.h24.in[0]) + ' · ' + nf(D.per.h24.in[1]), 'title']]);
    P(o.vk ? [[go[0] + ' ', go[1]], [t('Выход · утечка IP предотвращена: ', 'Out · IP leak prevented: '), 'text'], [nf(D.per.h24.out[0]), 'title']] : [[go[0] + ' ', go[1]], [t('Выход: защита от утечки IP не работает', 'Out: IP leak protection is not working'), 'warn']]);
    P([[t('  за сутки · графики — 6 Статистика', '  over 24 h · charts — 6 Statistics'), 'muted']]);
    P([[rep('─', 41), 'rule']]);
    items.forEach((it, i) => { const sel = i === cur; L.push({ s: [[' ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + ' ', sel ? 'cursor' : 'muted'], [padR(it.label, 29), sel ? 'title' : 'name'], ...(it.tag ? [it.tag] : [])], sel }); });
    const cd = card({ ...o });
    body.push(...oneWin(C, 45, 14, cd.title, cd.right, L));
    body.push(...footer(C)); pad(body, 23);
    body.push(keysRow(C, [['↑↓', ''], ['Enter', ''], ['1–9', ''], ['0', t('назад', 'back')]]));
  }
  return { rows: body, items, keymap: [['↑↓ Enter', t('выбрать пункт', 'pick an item')], ['1–9', t('сразу, без Enter', 'at once, no Enter')], ['1 · 2', t('вход / выход вкл и выкл', 'in / out on and off')], ['6 · 7 · 8', t('статистика · топ-30 · настройки', 'statistics · top 30 · settings')], ['0 · Esc', t('назад', 'back')], ['q', t('выход', 'quit')]] };
}

/* ---------- sh-e: статистика ---------- */
function extras(p, W) {
  const P = D.per[p], k = P.in[0] / D.per.h24.in[0], E = [], pk = peak(p);
  E.push([[t('ПИК', 'PEAK'), 'muted']]);
  E.push([[pk.lab + ' · ' + nf(pk.v), 'text']]);
  if (p !== 'all') E.push(pk.x >= SPIKE_X ? [['▲ ', 'warn'], [t('всплеск ×', 'spike ×') + dec(pk.x) + t(' к обычному', ' the usual'), 'text']] : [['· ', 'muted'], [t('всплеска нет · пик ×', 'no spike · peak ×') + dec(pk.x), 'muted']]);
  E.push([]);
  E.push([[t('АДРЕСА', 'ADDRESSES'), 'muted']]);
  if (P.nw != null) { E.push([[padR(t('новые', 'new'), 11), 'text'], [padL(nf(P.nw), 5), 'text']]); E.push([[padR(t('повторные', 'repeat'), 11), 'text'], [padL(nf(P.rp), 5), 'text']]); }
  else E.push([[padR(t('всего', 'total'), 11), 'text'], [padL(nf(P.in[1]), 5), 'text']]);
  E.push([]);
  E.push([[t('ПОРТЫ · чаще всего', 'PORTS · most hit'), 'muted']]);
  D.ports.slice(0, 4).forEach(x => E.push([[padR(x[0], 8), 'text'], [padL(nf(Math.round(x[1] * k)), 6), 'text'], [' ' + (Array.isArray(x[2]) ? t(x[2][0], x[2][1]) : x[2]), 'muted']]));
  return E.map(q => fit(q, W).segs);
}
function barsBlock(p, C, W) {
  const n = C < 80, S = series(p, 80), O = [];
  let vi, vo, labs, bw, gap;
  if (p === 'h24') { vi = D.hours; vo = D.outHours; labs = D.hours.map((_, i) => { const h = (D.hStart + i) % 24; return h % (n ? 6 : 3) === 0 ? hh(h) : ''; }); bw = 1; gap = n ? 0 : 1; }
  else if (p === 'd7') { const g = D.days.slice(23); vi = g.map(d => d.in); vo = g.map(d => d.out); labs = g.map(d => WD[LANG][d.wd]); bw = n ? 4 : 5; gap = 2; }
  else if (p === 'm30') { vi = D.days.map(d => d.in); vo = D.days.map(d => d.out); labs = D.days.map((d, i) => i % 5 === 0 ? d.dd : ''); bw = 1; gap = 0; }
  else { vi = D.months.map(m => m[1]); vo = D.months.map(m => m[2]); labs = D.months.map(m => t(MON.ru[m[0]], MON.en[m[0]])); bw = n ? 5 : 6; gap = 2; }
  const HI = n ? 4 : 7, HO = n ? 2 : 4;
  O.push(spread([['← ' + t('ВХОД · сканеры остановлены', 'IN · scanners stopped'), 'in']], [[t('макс ', 'max ') + nf(Math.max(...vi)), 'muted']], W));
  vbars(vi, HI, bw, gap, 'in').forEach(x => O.push(x)); O.push(labelRow(labs, bw, gap));
  O.push(spread([[t('ВЫХОД · утечка IP предотвращена', 'OUT · IP leak prevented') + ' →', 'out']], [[t('макс ', 'max ') + nf(Math.max(...vo)), 'muted']], W));
  vbars(vo, HO, bw, gap, 'out').forEach(x => O.push(x)); O.push(labelRow(labs, bw, gap));
  O.push([[t('всего: вход ', 'total: in ') + nf(vi.reduce((a, b) => a + b, 0)) + t(' · выход ', ' · out ') + nf(vo.reduce((a, b) => a + b, 0)), 'muted']]);
  return O;
}
function shE(o) {
  const C = o.C, p = PERIODS[o.view || 0], body = [], S = series(p, C), sel = o.row == null ? S.length - 1 : Math.max(0, Math.min(S.length - 1, o.row));
  body.push(titleRow(C, t('Статистика защиты', 'Protection statistics'), statusRight(o)));
  body.push(tabBar(C, PERIODS.map(C >= 80 ? perName : perShort), o.view || 0));
  const x = S[sel];
  if (C >= 80) {
    const CW = 50;
    let chart;
    if (o.chart === 'bars') chart = barsBlock(p, C, CW);
    else chart = pyramid(S, { L: 20, AX: 8, R: 20, axisName: axisName(p, 80), sel }).lines;
    const ex = [[[t('СТРОКА', 'ROW') + ' · ↑↓', 'muted']], [[x[0], 'title']], [[padR(t('вход', 'in'), 7), 'in'], [padL(nf(x[1]), 8), 'text'], [' ' + t('попыток', 'attempts'), 'muted']], [[padR(t('выход', 'out'), 7), 'out'], [padL(nf(x[2]), 8), 'text'], [' ' + t('к ВК', 'to VK'), 'muted']], [], ...extras(p, 25)];
    const n = Math.max(chart.length, ex.length);
    for (let i = 0; i < n; i++) body.push(r([['  ', 'text'], ...padSegs(chart[i] || [], CW), ['   ', 'text'], ...(ex[i] || [])]));
    pad(body, 20); body.length = 20;
    body.push(...footer(C));
    body.push(keysRow(C, [['1–4', t('период', 'period')], ['↑↓', t('строка', 'row')], ['5', t('топ-30', 'top 30')], ['6', t('настройки', 'settings')], ['0', t('назад', 'back')], ['q', '']]));
  } else {
    let chart;
    if (o.chart === 'bars') chart = barsBlock(p, C, 44);
    else chart = [...pyramid(S, { L: 17, AX: 7, R: 17, axisName: axisName(p, 46), sel }).lines, [['▸ ', 'cursor'], [x[0] + ': ', 'text'], [t('вход ', 'in ') + nf(x[1]), 'in'], [' · ', 'muted'], [t('выход ', 'out ') + nf(x[2]), 'out']]];
    chart.forEach(q => body.push(r([[' ', 'text'], ...q])));
    const spare = 18 - body.length, pk = peak(p), P = D.per[p], ex = [];
    ex.push([[' ' + t('пик ', 'peak ') + pk.lab + ' · ' + nf(pk.v), 'muted'], ...(p !== 'all' && pk.x >= SPIKE_X ? [[' · ', 'muted'], ['▲ ×' + dec(pk.x), 'warn']] : [])]);
    if (P.nw != null) ex.push([[' ' + t('адреса: новые ', 'addresses: new ') + nf(P.nw) + t(' · повторные ', ' · repeat ') + nf(P.rp), 'muted']]);
    ex.push([[' ' + t('ПОРТЫ', 'PORTS'), 'muted']]);
    D.ports.slice(0, 4).forEach(q => ex.push([[' ' + padR(q[0], 9), 'text'], [padL(nf(Math.round(q[1] * P.in[0] / D.per.h24.in[0])), 7), 'text'], [' ' + (Array.isArray(q[2]) ? t(q[2][0], q[2][1]) : q[2]), 'muted']]));
    if (spare > 0) { if (spare > 1) body.push(r([])); ex.slice(0, spare - (spare > 1 ? 1 : 0)).forEach(q => body.push(r(q))); }
    pad(body, 18); body.length = 18;
    body.push(...footer(C));
    body.push(keysRow(C, [['1–4', ''], ['↑↓', ''], ['5', t('топ', 'top')], ['6', ''], ['0', t('назад', 'back')]]));
  }
  return { rows: body, nrows: S.length, keymap: [['1–4', t('24 часа · 7 дней · месяц · всё время', '24 h · 7 days · month · all time')], ['↑↓', t('строка графика, числа — рядом', 'chart row, numbers shown')], ['←→', t('соседний период', 'next period')], ['5 · 6', t('топ-30 · настройки', 'top 30 · settings')], ['0 · Esc', t('назад в меню «Защита»', 'back to the protection menu')], ['q', t('выход', 'quit')]] };
}

/* ---------- sh-g: топ-30 сканеров ---------- */
function shG(o) {
  const C = o.C, p = PERIODS[o.view || 0], list = top30(p), n = C < 80, body = [];
  const page = n ? 6 : 15, cur = Math.max(0, Math.min(29, o.cur || 0)), start = Math.max(0, Math.min(30 - page, cur - Math.floor(page / 2)));
  body.push(titleRow(C, t('Топ-30 сканеров', 'Top 30 scanners'), [[(n ? '' : PRESUMED() + ' '), 'muted']]));
  body.push(tabBar(C, PERIODS.map(C >= 80 ? perName : perShort), o.view || 0));
  if (!n) {
    body.push(r([['  ' + padL('№', 2) + ' ' + padR('AS', 8) + padR(t('СЕТЬ', 'NETWORK'), 24) + padL(t('ПОПЫТОК', 'ATTEMPTS'), 9) + padL(t('АДРЕСОВ', 'ADDRESSES'), 10) + '  ' + padR(t('ПОСЛЕДНИЙ', 'LAST SEEN'), 13) + t('ПОРТ', 'PORT'), 'muted']]));
    list.slice(start, start + page).forEach(x => { const sel = x.n - 1 === cur;
      body.push(r([[sel ? '▸ ' : '  ', 'cursor'], [padL(String(x.n), 2) + ' ', sel ? 'cursor' : 'muted'], [padR('AS' + x.asn, 8), 'text'], [padR(x.name || noLabel(), 24), x.name ? (sel ? 'title' : 'name') : 'muted'], [padL(nf(x.a), 9) + padL(nf(x.b), 10), 'text'], ['  ' + padR(x.last, 13), 'muted'], [x.port, 'text']], sel)); });
    body.push(r([['  ' + (start + 1) + '–' + (start + page) + t(' из 30', ' of 30') + (start + page < 30 ? ' · ▼ ' + t('ниже ещё ', 'more below: ') + (30 - start - page) : '') + (start > 0 ? ' · ▲ ' + t('выше ', 'above: ') + start : ''), 'muted']]));
    pad(body, 20); body.length = 20; body.push(...footer(C));
    body.push(keysRow(C, [['1–4', t('период', 'period')], ['↑↓', ''], ['PgUp PgDn', t('страница', 'page')], ['0', t('назад', 'back')], ['q', t('выход', 'quit')]]));
  } else {
    body.push(r([[' ' + PRESUMED(), 'muted']]));
    list.slice(start, start + page).forEach(x => { const sel = x.n - 1 === cur;
      body.push(r([[sel ? '▸' : ' ', 'cursor'], [padL(String(x.n), 2) + ' ', sel ? 'cursor' : 'muted'], [padR('AS' + x.asn, 8), 'text'], [x.name || noLabel(), x.name ? (sel ? 'title' : 'name') : 'muted']], sel));
      body.push(r([['    ' + nf(x.a) + ' · ' + nf(x.b) + ' · ' + x.last.slice(p === 'h24' ? 6 : 0, p === 'h24' ? 11 : 5) + ' · ' + x.port, 'muted']], sel)); });
    body.push(r([[' ' + (start + 1) + '–' + (start + page) + t(' из 30', ' of 30') + (start + page < 30 ? ' · ▼ ' + t('ещё ', 'more: ') + (30 - start - page) : ''), 'muted']]));
    body.push(r([[' ' + t('попыток · адресов · последний раз · порт', 'attempts · addresses · last seen · port'), 'muted']]));
    pad(body, 18); body.length = 18; body.push(...footer(C));
    body.push(keysRow(C, [['1–4', ''], ['↑↓', ''], ['PgUp PgDn', ''], ['0', t('назад', 'back')]]));
  }
  return { rows: body, keymap: [['1–4', t('период', 'period')], ['↑↓', t('по одной сети', 'one network')], ['PgUp PgDn', t('по странице', 'by page')], ['Home End', t('в начало · в конец', 'top · bottom')], ['0 · Esc', t('назад', 'back')]] };
}

/* ---------- sh-h: настройки статистики ---------- */
function shH(o) {
  const C = o.C, n = C < 80, body = [], st = o.reset ? 'done' : o.confirm ? 'confirm' : 'main';
  body.push(titleRow(C, t('Настройки статистики', 'Statistics settings'), n ? [] : [[t('защита от сканеров ', 'scanner protection '), 'muted']]));
  body.push(r([['  ' + rep('═', C - 4), 'grad']]));
  body.push(r([]));
  const kv = (k, v) => body.push(r([['  ' + padR(k, n ? 18 : 22), 'muted'], [v, 'text']]));
  kv(t('собирается с', 'collected since'), st === 'done' ? '03.11.2026 14:05' : D.started + ' · ' + D.days_n + t(' дней', ' days'));
  kv(t('на диске', 'on disk'), st === 'done' ? t('0,1 МБ', '0.1 MB') : t(D.disk + ' МБ', D.disk.replace(',', '.') + ' MB'));
  kv(t('адресов в памяти', 'addresses in memory'), st === 'done' ? '0' : nf(D.per.all.in[1]));
  body.push(r([]));
  const items = st === 'confirm' ? [{ key: '1', label: t('Да, обнулить', 'Yes, reset'), act: 'yes' }, { key: '2', label: t('Нет', 'No'), act: 'no' }]
    : [{ key: '1', label: t('Обнулить статистику', 'Reset statistics'), act: 'ask' }, { key: '0', label: t('Назад', 'Back'), act: 'back' }];
  const cur = st === 'confirm' ? (o.cur == null ? 1 : o.cur) : (o.cur || 0);
  if (st === 'confirm') {
    wrap(t('Обнулить статистику? Счётчики входа и выхода, графики и топ начнутся заново.', 'Reset statistics? In and out counters, charts and the top start over.'), C - 4).forEach(l => body.push(r([['  ' + l, 'title']])));
    body.push(r([['  ' + t('Списки сетей и правила защиты не изменятся. Enter — 2, Нет', 'Network lists and protection rules stay. Enter — 2, No'), 'muted']]));
    body.push(r([]));
  }
  if (st === 'done') { body.push(r([['  ✓ ', 'ok'], [t('Статистика обнулена. Собирается заново с 03.11.2026 14:05.', 'Statistics reset. Collecting again since 2026-11-03 14:05.'), 'text']])); body.push(r([])); }
  items.forEach((it, i) => { const sel = i === cur; body.push(r([['  ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + '  ', sel ? 'cursor' : 'key'], [it.label, sel ? 'title' : 'name']], sel)); });
  if (st === 'main') { body.push(r([])); wrap(t('Обнуление стирает счётчики, графики и топ. Списки сетей и правила защиты остаются.', 'Reset clears counters, charts and the top. Network lists and protection rules stay.'), C - 4).forEach(l => body.push(r([['  ' + l, 'muted']]))); }
  pad(body, 23); body.length = 23;
  body.push(keysRow(C, st === 'confirm' ? [['1', t('да', 'yes')], ['2', t('нет', 'no')], ['Enter', t('нет', 'no')]] : [['↑↓', ''], ['Enter', ''], ['1', ''], ['0', t('назад', 'back')]]));
  return { rows: body, items, defCur: st === 'confirm' ? 1 : 0, keymap: st === 'confirm' ? [['1', t('обнулить', 'reset')], ['2 · Enter · Esc', t('не обнулять', 'keep')]] : [['1', t('обнулить, спросит подтверждение', 'reset, asks to confirm')], ['0 · Esc', t('назад', 'back')]] };
}

/* ---------- sh-f: вывод без tty ---------- */
function shF(o) {
  const C = o.C, n = C < 60, R = [], T = x => R.push(r([[x.replace(/\s+$/, ''), 'text']]));
  const kv = (k, v) => T(padR(k, 11) + v);
  const line = (k, l, Lw, cols, name) => T(padR(k, 7) + padR(l, Lw) + cols.map((c, i) => padL(c == null ? '' : String(c), i ? 9 : 9)).join('') + (name != null ? '  ' + name : ''));
  const head = [t('защита от сканеров', 'scanner protection'), 'vpn-fin-1 · 03.11.2026 14:05'];
  if (n) { T('# goInstaller · ' + head[0]); T('# ' + head[1]); } else T('# goInstaller · ' + head[0] + ' · ' + head[1]);
  kv(t('вход', 'in'), o.on ? t('вкл · сканеры останавливаются', 'on · scanners are stopped') : t('выкл · только считает', 'off · counting only'));
  kv(t('выход', 'out'), o.vk ? t('вкл · утечка IP к ВК не выпускается', 'on · IP leak to VK is blocked') : t('выкл · защита от утечки IP не работает', 'off · IP leak protection is not working'));
  kv(t('список', 'list'), 'AS_Network_List ' + t('от ', 'of ') + '03.11.2026 · ' + D.nets + t(' сетей · исключено ', ' networks · excluded ') + D.excl);
  kv('ipv6', t('считается по /64', 'counted per /64'));
  T('');
  line('#', t('период', 'period'), 18, [t('попыток', 'attempts'), t('адресов', 'address')], null);
  [[t('с 02.11 18:40', 'since 02.11 18:40'), D.away.in], [t('сутки', '24h'), D.per.h24.in], [t('7 дней', '7d'), D.per.d7.in], [t('месяц', '30d'), D.per.m30.in], [t('всего', 'all'), D.per.all.in]].forEach(([l, v]) => line(t('вход', 'in'), l, 18, v));
  T('');
  line('#', t('период', 'period'), 18, [t('всего', 'total'), t('клиенты', 'clients'), t('сервер', 'server')], null);
  [[t('с 02.11 18:40', 'since 02.11 18:40'), D.away.out], [t('сутки', '24h'), D.per.h24.out], [t('7 дней', '7d'), D.per.d7.out], [t('месяц', '30d'), D.per.m30.out], [t('всего', 'all'), D.per.all.out]].forEach(([l, v]) => line(t('выход', 'out'), l, 18, v));
  T('');
  line('#', t('дата', 'date'), 14, [t('вход', 'in'), t('выход', 'out')], null);
  D.days.slice(23).forEach(d => line(t('день', 'day'), d.dd + '.' + d.mm + ' ' + WD[LANG][d.wd], 14, [d.in, d.out]));
  T('');
  line('#', t('время', 'time'), 14, [t('вход', 'in'), t('выход', 'out')], null);
  D.hours.forEach((v, i) => line(t('час', 'hour'), hh((D.hStart + i) % 24) + ':00', 14, [v, D.outHours[i]]));
  T('');
  const pk = peak('h24');
  kv(t('пик', 'peak'), pk.lab + ' · ' + pk.v);
  kv(t('всплеск', 'spike'), pk.x >= SPIKE_X ? '×' + dec(pk.x) + t(' к медиане часа', ' vs hourly median') : t('нет', 'none'));
  kv(t('адреса', 'addresses'), t('новые ', 'new ') + D.per.h24.nw + t(' · повторные ', ' · repeat ') + D.per.h24.rp);
  T('');
  line('#', t('порт', 'port'), 14, [t('сутки', '24h')], t('чей', 'whose'));
  D.ports.forEach(x => line(t('порт', 'port'), x[0], 14, [x[1]], Array.isArray(x[2]) ? t(x[2][0], x[2][1]) : x[2]));
  T('');
  const net = t('сеть — ', 'network — ') + PRESUMED();
  if (n) { line('#', 'AS', 10, [t('попыток', 'attempts'), t('адресов', 'address')]); T('#   ' + net); } else line('#', 'AS', 10, [t('попыток', 'attempts'), t('адресов', 'address')], net);
  [[t('топ24ч', 'top24h'), topN('h24', 5)], [t('топ7д', 'top7d'), topN('d7', 5)]].forEach(([k, list]) => list.forEach(x => {
    const nm = x[1] || noLabel();
    if (n) { line(k, 'AS' + x[0], 10, [x[2], x[3]]); T('   ' + nm); } else line(k, 'AS' + x[0], 10, [x[2], x[3]], nm);
  }));
  T('');
  R.push(...footer(C, true));
  return { rows: R, keymap: [['—', t('без tty: печатается целиком, без рамок и цвета', 'no tty: printed in full, no frames or colour')]] };
}

/* ---------- сборка ---------- */
const META = {
  'sh-a': [t('Уведомление при входе, защита вкл', 'Login notice, protection on')], 'sh-b': [t('Уведомление, защита выкл', 'Login notice, protection off')],
  'sh-c': [t('Уведомление, всё тихо', 'Login notice, all quiet')], 'sh-d': [t('Меню «Защита» (s)', 'Protection menu (s)')],
  'sh-e': [t('Статистика', 'Statistics')], 'sh-g': [t('Топ-30 сканеров', 'Top 30 scanners')], 'sh-h': [t('Настройки статистики', 'Statistics settings')], 'sh-f': [t('Статистика без tty', 'Statistics without a tty')]
};
function build(id, o) {
  LANG = o.lang || 'ru';
  o = { on: true, vk: true, ver: '1.2.3', chart: 'fly', ...o };
  const C = o.C;
  let res;
  if (id === 'sh-a') res = { rows: [LASTLOGIN(), r([]), ...summary(C, true, blockA(o, C), o.ver), r([]), prompt(badge(2))] };
  else if (id === 'sh-b') res = { rows: [LASTLOGIN(), r([]), ...summary(C, false, blockB(o, C), o.ver), r([]), prompt(badge(1))] };
  else if (id === 'sh-c') res = { rows: [LASTLOGIN(), r([]),
    r([['✓ ', 'ok'], [t('goInstaller: всё актуально', 'goInstaller: all up to date'), 'text'], ...(C < 60 ? [] : [[t(', 3 продукта, проблем нет', ', 3 products, no problems'), 'muted']])]),
    r(C < 60 ? [['✓ ', 'ok'], [t('Защита: вкл', 'Protection: on'), 'text'], [t(' · сутки: вход 0 · выход 0', ' · 24 h: in 0 · out 0'), 'muted']]
      : [['✓ ', 'ok'], [t('Защита: вкл', 'Protection: on'), 'text'], [t(' · за сутки: вход 0 попыток · выход 0 соединений к ВК', ' · over 24 h: in 0 attempts · out 0 connections to VK'), 'muted']]),
    r([['  ' + t('сведения от ', 'data as of ') + '14:05 · ', 'muted'], ['goinstall', 'key'], [C < 60 ? t(' — меню', ' — menu') : t(' — открыть меню', ' — open the menu'), 'muted']]),
    r([]), r([['root@vpn-fin-1', 'text'], [':~# ', 'text'], ['█', 'cursor']])] };
  else if (id === 'sh-d') res = shD(o);
  else if (id === 'sh-e') res = shE(o);
  else if (id === 'sh-g') res = shG(o);
  else if (id === 'sh-h') res = shH(o);
  else res = shF(o);
  if (id !== 'sh-f') { pad(res.rows, 24); res.rows.length = 24; }
  res.rows = res.rows.map(row => { const f = fit(row.segs, C); return { segs: (row.sel ? [...f.segs, [rep(' ', C - f.used), 'text']] : f.segs).filter(s => s[0].length), sel: row.sel }; });
  res.C = C; res.R = res.rows.length; res.label = META[id][0];
  res.keymap = res.keymap || [['—', t('печатается при входе, ничего не спрашивает', 'printed at login, asks nothing')]];
  return res;
}
function toJSON(id, o, state) {
  const b = build(id, o);
  return { id, label: b.label, state, screen: 'shield', dir: 'arcade', lang: o.lang, cols: o.C, rows_max: id === 'sh-f' ? null : 24, tty: id !== 'sh-f', ...(o.chart && ['sh-d', 'sh-e'].includes(id) ? { chart: o.chart } : {}),
    rows: b.rows.map(rw => rw.segs.map(s => [s[0], s[1] + (rw.sel || s[2] ? '+sel' : '')])) };
}
function all(lang) {
  const out = [], base = { lang, on: true, vk: true, cur: 0, view: 0, ver: '1.2.3', chart: 'fly' };
  [80, 46].forEach(C => {
    out.push(toJSON('sh-a', { ...base, C, spike: true }, 'on_spike'), toJSON('sh-a', { ...base, C }, 'on'), toJSON('sh-a', { ...base, C, vk: false }, 'on_vk_off'), toJSON('sh-b', { ...base, C }, 'off'), toJSON('sh-c', { ...base, C }, 'quiet'));
    ['fly', 'bars'].forEach(ch => { out.push(toJSON('sh-d', { ...base, C, chart: ch }, 'on')); PERIODS.forEach((p, v) => out.push(toJSON('sh-e', { ...base, C, view: v, chart: ch }, p))); });
    out.push(toJSON('sh-d', { ...base, C, on: false, vk: false }, 'off'));
    PERIODS.forEach((p, v) => out.push(toJSON('sh-g', { ...base, C, view: v }, p)));
    out.push(toJSON('sh-h', { ...base, C }, 'main'), toJSON('sh-h', { ...base, C, confirm: true }, 'confirm'), toJSON('sh-h', { ...base, C, reset: true }, 'done'));
    out.push(toJSON('sh-f', { ...base, C }, 'on'));
  });
  return out;
}
const ASCII_NEW = { '▁': '_', '▂': '_', '▃': '-', '▅': '=', '▇': '#', '┊': ':' };
root.GoShield = { build, all, toJSON, card, spark, ASCII_NEW, PERIODS, setLang: l => { LANG = l; }, perName: (p, l) => { LANG = l; return perName(p); },
  menuItems: o => { LANG = o.lang; return menuItems(o); }, IN_L: (on, l) => { LANG = l; return IN_L(on); }, OUT_L: (vk, l) => { LANG = l; return OUT_L(vk); }, conn: (n, l) => { LANG = l; return conn(n); }, att: (n, l) => { LANG = l; return att(n); }, adr: (n, l) => { LANG = l; return adr(n); }, nf: (n, l) => { LANG = l; return nf(n); }, D };
})(typeof window !== 'undefined' ? window : globalThis);

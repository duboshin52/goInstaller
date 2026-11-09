// genfix.js <shield-screens.js> <ru|en> — модель «ui» из данных макета
const fs = require('fs');
let src = fs.readFileSync(process.argv[2], 'utf8');
src = src.replace('root.GoShield = {', 'root.GoShield = { top30, peak, median, series, setL: l => { LANG = l; },');
new Function(src)();
const G = globalThis.GoShield, D = G.D, L = process.argv[3];
G.setL(L);
const out = [], P = (...a) => out.push(a.join('|'));
const pn = { h24: '24h', d7: '7d', m30: '30d', all: 'all' };
P('g', 3, D.started, '00:00', D.days_n, 19293798, D.per.all.in[1]);
for (const p of G.PERIODS) { const x = D.per[p]; P('per', pn[p], x.in[0], x.in[1], x.out[0], x.nw == null ? '-' : x.nw, x.rp == null ? '-' : x.rp); }
D.hours.forEach((v, i) => P('h', String((D.hStart + i) % 24).padStart(2, '0'), v, D.outHours[i]));
{ const m = Math.max(...D.hours), i = D.hours.indexOf(m), x = m / G.median(D.hours); P('pk', '24h', m, Math.round(x * 10), x >= 2 ? 1 : 0, String((D.hStart + i) % 24).padStart(2, '0')); }
D.days.forEach(d => P('d', d.dd, d.mm, d.wd, d.in, d.out));
for (const p of ['d7', 'm30']) { const g = p === 'd7' ? D.days.slice(23) : D.days, v = g.map(d => d.in), m = Math.max(...v), d = g[v.indexOf(m)], x = m / G.median(v); P('pk', pn[p], m, Math.round(x * 10), x >= 2 ? 1 : 0, d.dd, d.mm, d.wd); }
D.months.forEach(m => P('m', m[0] + 1, 2026, m[1], m[2]));
{ const v = D.months.map(m => m[1]), m = Math.max(...v); P('pk', 'all', m, 0, 0, D.months[v.indexOf(m)][0] + 1, 2026); }
for (const p of G.PERIODS) {
  const k = D.per[p].in[0] / D.per.h24.in[0];
  D.ports.slice(0, 4).forEach(x => P('pt', pn[p], x[0], Math.round(x[1] * k), Array.isArray(x[2]) ? x[2][L === 'en' ? 1 : 0] : x[2]));
  G.top30(p).forEach(x => P('t', pn[p], x.n, x.a, x.b, x.asn, x.last.slice(0, 5), x.last.slice(6), x.port, x.name));
}
process.stdout.write(out.join('\n') + '\n');

/* goInstaller · главное меню (g1 / g2) с графиком «Защиты от сканеров».
   Основа — функции прототипа v2 (как есть), поверх — пункты c, s, x и защита. */
(function (root) {
'use strict';
let LANG = 'ru';
const t = (ru, en) => (LANG === 'en' && en != null ? en : ru);
const len = s => [...s].length;
const padR = (s, n) => { const a = [...s]; return a.length > n ? a.slice(0, n - 1).join('') + '…' : s + ' '.repeat(n - a.length); };
const padL = (q, n) => { const a = [...q]; return a.length >= n ? q : ' '.repeat(n - a.length) + q; };
const rep = (c, n) => c.repeat(Math.max(0, n));
const slen = segs => segs.reduce((a, s) => a + len(s[0]), 0);
const r = (segs, sel) => ({ segs: segs || [], sel: !!sel });
function wrap(text, w) {
  const out = []; let line = '';
  for (const word of text.split(' ')) {
    if (!line) line = word;
    else if (len(line) + 1 + len(word) <= w) line += ' ' + word;
    else { out.push(line); line = word; }
  }
  if (line) out.push(line);
  return out;
}
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
const spread = (left, right, C) => { const g = C - slen(left) - slen(right); return g >= 1 ? [...left, [rep(' ', g), 'text'], ...right] : left; };

/* ---------- palettes ---------- */
const PAL = {
  calm: {
    dark: { bg:'#1e1e1e', title:{c:'#e8e6e1',b:1}, text:{c:'#c8c6c0'}, muted:{c:'#8a8880'}, rule:{c:'#55534e'}, name:{c:'#e0ded8'}, cursor:{c:'#86b3d1',b:1}, key:{c:'#86b3d1'}, ok:{c:'#8db88a'}, update:{c:'#d8b26a',b:1}, new:{c:'#a7b6e6',b:1}, warn:{c:'#dc9a62'}, err:{c:'#e27b6f',b:1}, sel:{bg:'#303236'}, grad:['#86b3d1','#86b3d1'] },
    light:{ bg:'#ffffff', title:{c:'#1a1a18',b:1}, text:{c:'#2e2d2a'}, muted:{c:'#6b6962'}, rule:{c:'#bdbab3'}, name:{c:'#1a1a18'}, cursor:{c:'#2a668f',b:1}, key:{c:'#2a668f'}, ok:{c:'#2f7433'}, update:{c:'#865d00',b:1}, new:{c:'#3a4fa0',b:1}, warn:{c:'#9a4f0e'}, err:{c:'#b02a1f',b:1}, sel:{bg:'#ecebe6'}, grad:['#2a668f','#2a668f'] }
  },
  night: {
    dark: { bg:'#1e1e1e', title:{c:'#ffffff',b:1}, text:{c:'#d4d6f2'}, muted:{c:'#8d90bd'}, rule:{c:'#4b4a7a'}, name:{c:'#eef0ff'}, cursor:{c:'#34d6ff',b:1}, key:{c:'#34d6ff'}, ok:{c:'#3ee8a0'}, update:{c:'#ffd24a',b:1}, new:{c:'#ff6fd8',b:1}, warn:{c:'#ffa24a'}, err:{c:'#ff5c7c',b:1}, sel:{bg:'#2b2366'}, grad:['#8a6bff','#34d6ff','#3ee8a0'] },
    light:{ bg:'#ffffff', title:{c:'#14163a',b:1}, text:{c:'#23264a'}, muted:{c:'#585c8a'}, rule:{c:'#c6c6e6'}, name:{c:'#14163a'}, cursor:{c:'#006d9e',b:1}, key:{c:'#006d9e'}, ok:{c:'#0a7a4c'}, update:{c:'#8f6400',b:1}, new:{c:'#b01b86',b:1}, warn:{c:'#a34c00'}, err:{c:'#c1123a',b:1}, sel:{bg:'#ece8ff'}, grad:['#5b3de0','#006d9e','#0a7a4c'] }
  },
  phos: (() => {
    const mk = (bg, B, N, D, sel) => ({ bg, title:{c:B,b:1}, text:{c:N}, muted:{c:D}, rule:{c:D}, name:{c:N}, cursor:{c:B,b:1}, key:{c:B}, ok:{c:N}, update:{c:B,b:1}, new:{c:B,b:1}, warn:{c:B}, err:{c:B,b:1}, sel, grad:[B,B] });
    return { dark: mk('#1e1e1e','#8dffa6','#3fd46b','#23914a',{bg:'#3fd46b',fg:'#07170c'}), light: mk('#ffffff','#0b4a1f','#136b2f','#3d7a4f',{bg:'#136b2f',fg:'#ffffff'}) };
  })()
};
PAL.arcade = {
  dark: { bg:'#1e1e1e', title:{c:'#ffd23f',b:1}, text:{c:'#e6e9f5'}, muted:{c:'#8e96b8'}, rule:{c:'#3d6bff'}, name:{c:'#ffffff'}, cursor:{c:'#34d2ff',b:1}, key:{c:'#34d2ff'}, ok:{c:'#3ee07a'}, update:{c:'#ffb02e',b:1}, new:{c:'#ff5fd2',b:1}, warn:{c:'#ff9a3c'}, err:{c:'#ff4d5e',b:1}, sel:{bg:'#1d3aa8',fg:'#ffffff'}, grad:['#2f6bff','#34d2ff'],
    logo0:{c:'#fff4b0',b:1}, logo1:{c:'#ffd23f',b:1}, logo2:{c:'#ff9a1f',b:1}, logo3:{c:'#ff5a1f',b:1}, shade:{c:'#9c2433'}, shadow:{c:'#343a66'} },
  light:{ bg:'#ffffff', title:{c:'#0038b8',b:1}, text:{c:'#1a1f3a'}, muted:{c:'#565e80'}, rule:{c:'#2f5bdc'}, name:{c:'#0d1230'}, cursor:{c:'#0068a8',b:1}, key:{c:'#0068a8'}, ok:{c:'#16803e'}, update:{c:'#9a5a00',b:1}, new:{c:'#b0158a',b:1}, warn:{c:'#a44a00'}, err:{c:'#c0182e',b:1}, sel:{bg:'#dfe7ff'}, grad:['#1d4ed8','#0086b8'],
    logo0:{c:'#f0a000',b:1}, logo1:{c:'#e07800',b:1}, logo2:{c:'#d04800',b:1}, logo3:{c:'#b02400',b:1}, shade:{c:'#5a1020'}, shadow:{c:'#c3c9e6'} }
};
Object.values(PAL).forEach(d => Object.values(d).forEach(p => { ['logo0','logo1','logo2','logo3'].forEach(k => { if (!p[k]) p[k] = p.title; }); if (!p.shade) p.shade = p.rule; if (!p.shadow) p.shadow = p.rule; }));
const TOKENS = ['title','text','muted','rule','name','cursor','key','ok','update','new','warn','err','grad','sel','logo0','logo1','logo2','logo3','shade','shadow'];
const TOKDESC = { title:'заголовки', text:'основной текст', muted:'пояснения', rule:'рамки и линии', name:'названия продуктов', cursor:'курсор ▸, шкалы', key:'клавиши и команды', ok:'● установлен, ✓', update:'↑ обновления', new:'✚ новое', warn:'! замечания', err:'✗ препятствия', grad:'рамки окон (градиент)', sel:'выделенная строка', logo0:'логотип, 1-я строка', logo1:'логотип, 2-я строка', logo2:'логотип, 3-я строка', logo3:'логотип, 4-я строка', shade:'объём логотипа', shadow:'тень окон' };
const A16 = {
  calm: { title:{c:'39',b:1}, text:{c:'39'}, muted:{c:'90'}, rule:{c:'90'}, name:{c:'39'}, cursor:{c:'36',b:1}, key:{c:'36'}, ok:{c:'32'}, update:{c:'33',b:1}, new:{c:'34',b:1}, warn:{c:'33'}, err:{c:'31',b:1}, grad:{c:'36',b:1}, sel:{inv:1} },
  night:{ title:{c:'39',b:1}, text:{c:'39'}, muted:{c:'90'}, rule:{c:'35'}, name:{c:'39'}, cursor:{c:'36',b:1}, key:{c:'36'}, ok:{c:'32'}, update:{c:'33',b:1}, new:{c:'35',b:1}, warn:{c:'33'}, err:{c:'31',b:1}, grad:{c:'35',b:1}, sel:{inv:1} },
  phos: { title:{c:'32',b:1}, text:{c:'32'}, muted:{c:'32',dim:1}, rule:{c:'32',dim:1}, name:{c:'32'}, cursor:{c:'32',b:1}, key:{c:'32',b:1}, ok:{c:'32'}, update:{c:'32',b:1}, new:{c:'32',b:1}, warn:{c:'32',b:1}, err:{c:'32',b:1}, grad:{c:'32',b:1}, sel:{inv:1} },
  arcade:{ title:{c:'33',b:1}, text:{c:'39'}, muted:{c:'90'}, rule:{c:'34'}, name:{c:'39',b:1}, cursor:{c:'36',b:1}, key:{c:'36'}, ok:{c:'32'}, update:{c:'33',b:1}, new:{c:'35',b:1}, warn:{c:'33'}, err:{c:'31',b:1}, grad:{c:'34',b:1}, sel:{inv:1},
    logo0:{c:'33',b:1}, logo1:{c:'33',b:1}, logo2:{c:'31',b:1}, logo3:{c:'31',b:1}, shade:{c:'31',dim:1}, shadow:{c:'34',dim:1} }
};
Object.values(A16).forEach(a => { ['logo0','logo1','logo2','logo3'].forEach(k => { if (!a[k]) a[k] = a.title; }); if (!a.shade) a.shade = a.rule; if (!a.shadow) a.shadow = a.rule; });
const NONE = { title:'bold', text:'обычный', muted:'dim', rule:'dim', name:'обычный', cursor:'bold', key:'bold', ok:'обычный', update:'bold', new:'bold', warn:'bold', err:'bold', grad:'bold', sel:'inverse', logo0:'bold', logo1:'bold', logo2:'bold', logo3:'bold', shade:'dim', shadow:'dim' };
const ANSI = {
  dark: { '30':'#000000','31':'#f14c4c','32':'#23d18b','33':'#e5e510','34':'#3b8eea','35':'#d670d6','36':'#29b8db','37':'#e5e5e5','90':'#8a8a8a' },
  light:{ '30':'#000000','31':'#b40000','32':'#00a600','33':'#999900','34':'#0000b2','35':'#b200b2','36':'#00a6b2','37':'#bfbfbf','90':'#666666' }
};
const FG = { dark:'#cccccc', light:'#1a1a1a' };

const hex = h => [1,3,5].map(i => parseInt(h.slice(i, i + 2), 16));
const toHex = a => '#' + a.map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
function interp(stops, tt) {
  const n = stops.length - 1, x = Math.min(n, Math.max(0, tt * n)), i = Math.min(n - 1, Math.floor(x)), f = x - i;
  const a = hex(stops[i]), b = hex(stops[i + 1]);
  return toHex(a.map((v, k) => v + (b[k] - v) * f));
}
const blend = (a, b, f) => { const A = hex(a), B = hex(b); return toHex(A.map((v, i) => v + (B[i] - v) * f)); };
const CUBE = [0, 95, 135, 175, 215, 255];
const Q = {};
function q256(h) {
  if (Q[h]) return Q[h];
  const [R, G, B] = hex(h); let best = null;
  const test = (i, rgb) => { const d = (rgb[0]-R)**2 + (rgb[1]-G)**2 + (rgb[2]-B)**2; if (!best || d < best.d) best = { d, i, hex: toHex(rgb) }; };
  for (let ri = 0; ri < 6; ri++) for (let gi = 0; gi < 6; gi++) for (let bi = 0; bi < 6; bi++) test(16 + 36*ri + 6*gi + bi, [CUBE[ri], CUBE[gi], CUBE[bi]]);
  for (let g = 0; g < 24; g++) { const v = 8 + 10*g; test(232 + g, [v, v, v]); }
  return (Q[h] = best);
}

const ASC = { '─':'-','━':'-','│':'|','┌':'+','┐':'+','└':'+','┘':'+','├':'+','┤':'+','┬':'+','┴':'+','┼':'+','╭':'+','╮':'+','╰':'+','╯':'+','═':'=','║':'|','╔':'+','╗':'+','╚':'+','╝':'+',
  '█':'#','▓':'#','▒':'=','░':'.','▀':'"','▄':'_','▌':'[','▐':']','▏':'=','▎':'=','▍':'=','▋':'=','▊':'=','▉':'=','▕':']',
  '●':'*','○':'o','▲':'^','▼':'v','▸':'>','◆':'+','✓':'+','✗':'x','✚':'+','·':'.','→':'>','←':'<','↑':'^','↓':'v','…':'.','—':'-','«':'"','»':'"','–':'-',
  '⠋':'|','⠙':'/','⠹':'-','⠸':'\\','⠼':'|','⠴':'/','⠦':'-','⠧':'\\','⠇':'|','⠏':'/' };
const SYMBOLS = ['─','│','╭','╮','╰','╯','├','┤','┌','┐','└','┘','═','█','▌','▀','▄','░','▏','▎','▍','▋','▊','▉','⠋','⠙','⠹','⠸','●','○','◆','▸','✓','✗','✚','·','→','↑','…','—'];
const SPIN = ['⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏'];

/* ---------- data ---------- */
const PRODS = [
  { id:'govless', name:'goVLESS pro', cmd:'govless', desc:['VLESS Reality/TLS на 3X-UI, бот, mini-app','VLESS Reality/TLS on 3X-UI, bot, mini-app'], inst:true, srv:'1.3.7', main:'1.3.7', dev:'1.3.7', modes:['pro','lite'], curMode:'pro', svc:['x-ui','nginx'],
    held:[['443/tcp','xray',['VLESS inbound','VLESS inbound']],['80/tcp','nginx',['сайт-маска, ACME certbot','mask site, certbot ACME']]] },
  { id:'gotelegram', name:'goTelegram pro', cmd:'gotelegram', desc:['MTProxy (telemt), сайт-маска, бот, панель','MTProxy (telemt), mask site, bot, panel'], inst:true, srv:'2.10.46', main:'2.10.49', dev:'2.10.49', modes:['pro','lite'], curMode:'lite', svc:['telemt'],
    held:[['2443/tcp','telemt',['MTProxy, режим Lite','MTProxy, Lite mode']],['9090/tcp','telemt',['loopback: метрики','loopback: metrics']],['9091/tcp','telemt',['loopback: локальный API','loopback: local API']]] },
  { id:'godns', name:'goDNS pro', cmd:'godns', desc:['DoH/DoT-резолвер на сертификате соседа',"DoH/DoT resolver on a neighbour's certificate"], inst:true, srv:'1.0.1', main:'1.0.1', dev:'1.0.1', modes:[], svc:['dnsdist'],
    held:[['4443/tcp','dnsdist',['DoH, 443 занят','DoH, 443 is taken']],['853/tcp','dnsdist',['DoT','DoT']],['5199/tcp','dnsdist',['loopback: консоль','loopback: console']],['53/tcp','dnsdist',['loopback: DNS 127.0.0.1','loopback: DNS 127.0.0.1']]] },
  { id:'gokaskad', name:'goKaskad pro', cmd:'gokaskad', desc:['каскад портов (iptables), бот, прокси для API Telegram','port cascade (iptables), bot, Telegram API egress'], inst:false, main:'2.8', dev:null, modes:[], status:'ready', svc:['iptables'], held:[] },
  { id:'gowarp', name:'goWARP pro', cmd:'gowarp', desc:['Cloudflare WARP как SOCKS5 для 3X-UI','Cloudflare WARP as SOCKS5 for 3X-UI'], inst:false, main:'2.5.0', dev:null, modes:[], status:'notes', svc:['warp-svc','warp-bot'], held:[['40000/tcp','warp-svc',['loopback: SOCKS5 WARP','loopback: WARP SOCKS5']]] },
  { id:'goamnezia', name:'goAmnezia pro', cmd:'goamnezia', desc:['AmneziaWG в Docker, сайт-маска, бот, панель','AmneziaWG in Docker, mask site, bot, panel'], inst:false, main:'1.0.2', dev:'1.0.2', modes:['lazy','pro','lite_site','lite'], status:'lite', isNew:true, svc:['docker: amnezia-awg'], held:[['1985/tcp','docker',['loopback: веб-панель','loopback: web panel']]] }
];
const PROD = id => PRODS.find(p => p.id === id);
const STATUS = {
  installed:{ g:'●', tok:'ok', w:['установлен','installed'] },
  ready:{ g:'○', tok:'muted', w:['готов','ready'] },
  notes:{ g:'!', tok:'warn', w:['готов, есть замечания','ready, with notes'] },
  lite:{ g:'◆', tok:'warn', w:['только Lite','Lite only'] }
};
const sw = s => t(s.w[0], s.w[1]);
const modeName = m => ({ lazy: t('Ленивый pro','Lazy pro'), pro:'pro', lite_site:'Semi-pro', lite:'Lite' })[m];
function modeDesc(id, m) {
  if (id === 'goamnezia') return ({
    lazy: t('только домен, остальное сделает продукт; UDP 443 занят — встанет Semi-pro','just a domain, the product does the rest; UDP 443 taken — it becomes Semi-pro'),
    pro: t('сайт на TCP 443, AmneziaWG на UDP 443','site on TCP 443, AmneziaWG on UDP 443'),
    lite_site: t('сайт на TCP 443 и 80, AmneziaWG на своих портах','site on TCP 443 and 80, AmneziaWG on its own ports'),
    lite: t('только VPN, TCP-порты не нужны','VPN only, no TCP ports needed') })[m];
  return m === 'pro' ? t('домен, сертификат, сайт-маска: 443 и 80','domain, certificate, mask site: 443 and 80') : t('без домена: только 443','no domain: 443 only');
}
function info(p, x) {
  const o = x.st.over[p.id];
  const inst = o ? true : p.inst;
  let srv = o ? o.srv : p.srv;
  if (!o && p.id === 'gotelegram' && !x.news) srv = p.main;
  return { inst, srv: inst ? srv : '—', upd: inst && srv !== p.main, isNew: !!p.isNew && x.news && !inst, status: inst ? 'installed' : p.status, branch: o ? o.branch : 'main', mode: o ? o.mode : p.curMode };
}
const defMode = (p, x) => p.id === 'goamnezia' ? 'lite' : (info(p, x).inst ? info(p, x).mode : p.modes[0]);

/* ---------- preflight ---------- */
function pf(id, mode) {
  const R = (port, st, ru, en, holder) => ({ port, st, d: t(ru, en), h: holder || '' });
  const own = p => t('свой: ', 'own: ') + p;
  let rows = [], rules = [];
  const busyV = p => p + ' → goVLESS pro';
  if (id === 'govless') {
    rows = [R('443/tcp','ok','VLESS inbound xray — жёстко 443','VLESS inbound xray — hardcoded 443',own('xray')), R('80/tcp','ok','nginx: сайт-маска и ACME-проверка certbot','nginx: mask site and certbot ACME',own('nginx')),
      R('8443/tcp','ok','loopback: mini-app бота (режим Lite)','loopback: bot mini-app (Lite mode)'), R('10808/tcp','ok','loopback: SOCKS5 прокси для API Telegram','loopback: SOCKS5 Telegram API egress'),
      R('10851/tcp','ok','loopback: API xray для балансировщика','loopback: xray API for the balancer'), R('18181/tcp','ok','loopback: метрики cloudflared (Lite)','loopback: cloudflared metrics (Lite)')];
  } else if (id === 'gotelegram' && mode === 'pro') {
    rows = [R('443/tcp','bad','telemt MTProxy — жёстко 443 в режиме pro','telemt MTProxy — hardcoded 443 in pro',busyV('xray')), R('80/tcp','bad','nginx: ACME certbot и редирект на https','nginx: certbot ACME and https redirect',busyV('nginx')),
      R('8443/tcp','ok','loopback: nginx с сайтом-маской','loopback: nginx mask site'), R('9090/tcp','ok','loopback: метрики telemt','loopback: telemt metrics',own('telemt')), R('9091/tcp','ok','loopback: локальный API telemt','loopback: telemt local API',own('telemt')),
      R('1984/tcp','ok','loopback: веб-панель','loopback: web panel'), R('18080/tcp','ok','loopback: WEB-транспорт telemt','loopback: telemt WEB transport'), R('8444/tcp','ok','loopback: decoy-хост nginx','loopback: nginx decoy vhost')];
    rules = [['✗','err', t('TCP 443 и 80 держит goVLESS pro. В режиме Lite telemt встанет на свой порт, сейчас это 2443.','TCP 443 and 80 are held by goVLESS pro. In Lite mode telemt uses its own port, now 2443.')]];
  } else if (id === 'gotelegram') {
    rows = [R('443/tcp','note','telemt — порт по умолчанию, можно другой','telemt — default port, another is fine',busyV('xray')), R('9090/tcp','ok','loopback: метрики telemt','loopback: telemt metrics',own('telemt')), R('9091/tcp','ok','loopback: локальный API telemt','loopback: telemt local API',own('telemt')),
      R('1984/tcp','ok','loopback: веб-панель','loopback: web panel'), R('18080/tcp','ok','loopback: WEB-транспорт telemt','loopback: telemt WEB transport'), R('8444/tcp','ok','loopback: decoy-хост nginx','loopback: nginx decoy vhost')];
    rules = [['!','warn', t('TCP 443 занят: установщик оставит telemt на своём порту, сейчас это 2443.','TCP 443 is taken: the installer keeps telemt on its own port, now 2443.')]];
  } else if (id === 'godns') {
    rows = [R('443/tcp','info','DoH: возьмёт 443, только если свободен','DoH: takes 443 only if free',busyV('xray')), R('4443/tcp','ok','DoH: первый запасной порт','DoH: first fallback port',own('dnsdist')), R('853/tcp','ok','DoT','DoT',own('dnsdist')),
      R('5199/tcp','ok','loopback: консоль dnsdist','loopback: dnsdist console',own('dnsdist')), R('53/tcp','ok','loopback: обычный DNS 127.0.0.1:53','loopback: plain DNS 127.0.0.1:53',own('dnsdist')), R('80/tcp','info','нужен, только если выпускать свой сертификат','only for issuing an own certificate',busyV('nginx'))];
    rules = [['·','muted', t('Сертификат берётся у соседа goVLESS pro, свой выпускать не нужно.',"The certificate comes from the goVLESS pro neighbour; no need to issue one.")]];
  } else if (id === 'gokaskad') {
    rows = [R('10808/tcp','ok','loopback: SOCKS5 прокси для API Telegram','loopback: SOCKS5 Telegram API egress'), R('10851/tcp','ok','loopback: API xray прокси','loopback: xray API of the egress')];
  } else if (id === 'gowarp') {
    rows = [R('40000/tcp','ok','loopback: SOCKS5 WARP','loopback: WARP SOCKS5')];
    rules = [['!','warn', t('goWARP pro сам не проверяет, свободен ли 40000: не отдавайте этот порт другим службам.','goWARP pro never checks port 40000 itself: keep it free for WARP.')]];
  } else if (id === 'goamnezia') {
    const site = mode !== 'lite';
    if (site) rows.push(R('443/tcp','bad',"nginx: сайт на домене с сертификатом Let's Encrypt","nginx: site on the domain with a Let's Encrypt cert",busyV('xray')), R('80/tcp','bad',"nginx: проверка Let's Encrypt и редирект на https","nginx: Let's Encrypt challenge and https redirect",busyV('nginx')));
    if (mode === 'pro') rows.push(R('443/udp','ok','AmneziaWG на UDP 443','AmneziaWG on UDP 443'));
    if (mode === 'lazy') rows.push(R('443/udp','ok','AmneziaWG 2.0 на UDP 443','AmneziaWG 2.0 on UDP 443'));
    rows.push(R('1985/tcp','ok','loopback: веб-панель','loopback: web panel'), R('1986/tcp','ok','loopback: MCP по HTTP, по умолчанию выключен','loopback: MCP over HTTP, off by default'));
    if (site) rows.push(R('1987/tcp','ok','loopback: страницы подключения','loopback: connection pages'));
    rules = site ? [['·','muted', t('TCP 443 держит xray. Это мешает только сайту: в режиме Lite goAmnezia pro ставится рядом.','TCP 443 is held by xray. That blocks only the site: in Lite mode goAmnezia pro installs alongside.')]]
      : [['✓','ok', t('TCP-порты не нужны: AmneziaWG работает по UDP на своих портах.','No TCP ports needed: AmneziaWG works over UDP on its own ports.')]];
  }
  const bad = rows.filter(x => x.st === 'bad').length;
  const notes = rows.filter(x => x.st === 'note').length + rules.filter(x => x[0] === '!').length;
  let verdict;
  if (bad) verdict = ['✗', 'err', t('Ставить нельзя: препятствий — ' + bad + '.', 'Cannot install: ' + bad + ' obstacles.')];
  else if (notes) verdict = ['✓', 'ok', t('Можно ставить: препятствий нет, замечаний — ' + notes + '.', 'Ready to install: no obstacles, ' + notes + ' note(s).')];
  else verdict = ['✓', 'ok', t('Можно ставить: препятствий нет.', 'Ready to install: no obstacles.')];
  return { rows, rules, bad, notes, verdict };
}
const PFG = { ok:['✓','ok'], bad:['✗','err'], note:['!','warn'], info:['·','muted'] };
const verdictTag = v => v.bad ? ['✗ ' + t('препятствий: ', 'obstacles: ') + v.bad, 'err'] : v.notes ? ['! ' + t('замечаний: ', 'notes: ') + v.notes, 'warn'] : ['✓ ' + t('готов', 'ready'), 'ok'];

/* ---------- poll ---------- */
const DUR = [340, 520, 610, 380, 720, 450, 530, 690];
function schedule() { const w = [0, 0, 0]; return DUR.map(d => { let i = w.indexOf(Math.min(...w)); const s = w[i]; w[i] = s + d; return [s, s + d]; }); }
const SCHED = schedule();
const POLL_TOTAL = Math.max(...SCHED.map(s => s[1]));
function pollItems(x) {
  return [
    ['goInstaller', x.instUpd ? '0.9.6' : x.st.instVer, x.instUpd ? 'update' : 'text'],
    [t('ключ доступа', 'access key'), x.probs ? t('открывает 5 из 6', 'opens 5 of 6') : t('открывает 6 из 6', 'opens 6 of 6'), x.probs ? 'warn' : 'text'],
    ['goVLESS pro', 'main 1.3.7 · dev 1.3.7', 'text'],
    ['goTelegram pro', 'main 2.10.49 · dev 2.10.49', x.tgUpd ? 'update' : 'text'],
    ['goDNS pro', 'main 1.0.1 · dev 1.0.1', 'text'],
    ['goKaskad pro', 'main 2.8', 'text'],
    ['goWARP pro', 'main 2.5.0', 'text'],
    ['goAmnezia pro', 'main 1.0.2 · dev 1.0.2', x.amNew ? 'new' : 'text']
  ];
}
function pollState(x) {
  const p = x.st.poll;
  if (!p) return { el: 1e9, done: 8, finished: true, items: SCHED.map(() => 'done'), err: null };
  const el = x.now - p.t0, err = p.err;
  const items = SCHED.map(([s, e], i) => {
    const end = err === 'github' ? e * 1.4 : e;
    if (el < s) return 'wait';
    if (el < end) return 'run';
    if (err === 'github' || (err === 'rate' && i >= 5)) return 'fail';
    return 'done';
  });
  const done = items.filter(s => s === 'done' || s === 'fail').length;
  return { el, done, finished: done === 8, items, err };
}

/* ---------- drawing helpers ---------- */
const TT = x => (x.dir === 'night' ? 'grad' : 'title');
function hdr(x, left, right) {
  const { C, dir } = x;
  const lead = dir === 'phos' ? [['▌', 'title']] : [['  ', 'text']];
  const row1 = spread([...lead, ...left], right ? [[right, 'muted']] : [], C);
  const ch = dir === 'calm' ? '─' : '═';
  return [r(fit(row1, C).segs), r([['  ' + rep(ch, C - 4), dir === 'night' || dir === 'arcade' ? 'grad' : 'rule']])];
}
const merge = segs => segs.reduce((a, s) => { const l = a[a.length - 1]; if (l && l[1] === s[1] && l[2] === s[2]) l[0] += s[0]; else a.push([s[0], s[1], s[2]]); return a; }, []);
const GO = ['▄██████▄  ▄██████▄', '██        ██    ██', '██  ████  ██    ██', '▀██████▀  ▀██████▀'];
const SPEED = ['      ', '  ════', '══════', ' ═════', '      '];
function logoRows(x) {
  const g = GO.map(l => [...l]), H = g.length, W = g[0].length, out = [];
  const face = rr => x.dir === 'night' ? 'grad' : 'logo' + rr;
  for (let rr = 0; rr <= H; rr++) {
    const s = [];
    for (let c = 0; c <= W; c++) {
      const ch = rr < H ? g[rr][c] : undefined;
      if (ch && ch !== ' ') { s.push([ch, face(rr)]); continue; }
      const up = rr > 0 && c > 0 ? g[rr - 1][c - 1] : ' ';
      s.push(up && up !== ' ' ? [rr === H ? '▀' : '▓', 'shade'] : [' ', 'text']);
    }
    out.push(merge(s));
  }
  return out;
}
function hud(x) {
  const n = x.C < 60;
  const left = [[' goInstaller', 'title'], [' ' + x.st.instVer, 'muted'], ...(n ? [] : [['  ·  vpn-fin-1', 'text']])];
  const m = (lab, fr, pct, w) => [[lab + ' ', 'muted'], ['▕', 'rule'], ...bar(fr, w, fr < 0.7 ? 'ok' : fr < 0.9 ? 'warn' : 'err'), ['▏', 'rule'], [pct, 'text']];
  const right = n ? [...m(t('диск', 'disk'), 0.58, '58 %', 4), ['  ' + t('озу', 'mem') + ' ', 'muted'], ['41 % ', 'text']]
    : [...m(t('диск', 'disk'), 0.58, '58 %', 6), ['  ', 'text'], ...m(t('озу', 'mem'), 0.41, '41 %', 6), ['  ' + t('нагр', 'load') + ' ', 'muted'], ['0.4 ', 'text']];
  return r(spread(left, right, x.C));
}
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
function arcadeList(x, items, cur, W) {
  const L = [];
  items.forEach((it, i) => {
    const sel = i === cur;
    let s;
    if (it.kind === 'p') {
      const f = info(it.p, x);
      const g = f.upd ? ['↑ ' + it.p.main, 'update'] : f.isNew ? ['✚ ' + t('новое', 'new'), 'new'] : f.inst ? ['● ' + f.srv, 'ok']
        : f.status === 'notes' ? ['! ' + t('замечания', 'notes'), 'warn'] : f.status === 'lite' ? ['◆ ' + t('только Lite', 'Lite only'), 'warn'] : ['○ ' + t('готов', 'ready'), 'muted'];
      s = [[' ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + ' ', sel ? 'cursor' : 'muted'], [padR(it.p.name, 16), sel ? 'title' : 'name'], g];
    } else s = [[' ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + ' ', sel ? 'cursor' : 'muted'], [padR(it.label, W - 11), sel ? 'title' : (it.tok || 'name')], [it.hot, it.key === 'c' ? 'update' : 'key']];
    L.push({ s: s.map(q => [q[0], q[1], sel]), sel });
    if (i === 5) L.push({ s: [[' ' + rep('─', W - 4), 'rule']] });
  });
  if (x.SH.variant === 'A') { while (L.length < 15) L.push({ s: [] }); L.push({ s: [[' ', 'text'], ...lineA(x)] }); }
  return L;
}
function arcadeCard(x, it, IW, H, inProduct) {
  const L = [], P = segs => L.push({ s: [[' ', 'text'], ...segs] });
  let title, right = null, foot;
  if (it.kind === 'p') {
    const p = it.p, f = info(p, x), s = STATUS[f.status];
    title = [[p.name, 'title']]; right = [[s.g + ' ', s.tok], [sw(s), s.tok === 'muted' ? 'text' : s.tok]];
    wrap(t(p.desc[0], p.desc[1]), IW - 2).slice(0, 2).forEach(l => P([[l, 'muted']]));
    P([]);
    P([[padR(t('ВЕТКА', 'BRANCH'), 8) + padR(t('СЕРВЕР', 'SERVER'), 10) + 'GITHUB', 'muted']]);
    P([[padR('main', 8), f.inst && f.branch === 'main' ? 'title' : 'text'], [padR(f.inst && f.branch === 'main' ? f.srv : '—', 10), f.upd ? 'update' : 'text'], [padR(p.main, 9), f.upd ? 'update' : f.isNew ? 'new' : 'text'], ...(f.upd ? [['↑ ' + t('новее', 'newer'), 'update']] : f.isNew ? [['✚ ' + t('новое', 'new'), 'new']] : [])]);
    P([[padR('dev', 8), f.inst && f.branch === 'dev' ? 'title' : 'text'], [padR(f.inst && f.branch === 'dev' ? f.srv : '—', 10), 'text'], [p.dev || t('нет ветки', 'no branch'), 'muted']]);
    P([]);
    if (f.inst) {
      wrap((p.held || []).map(h => h[0]).join(' ') || '—', IW - 10).forEach((l, i) => P([[padR(i ? '' : t('ПОРТЫ', 'PORTS'), 8), 'muted'], [l, 'text']]));
      P([[padR(t('СЛУЖБЫ', 'UNITS'), 8), 'muted'], ...p.svc.flatMap((u, i) => [[(i ? '  ' : '') + '● ', 'ok'], [u, 'text']])]);
      if (p.id === 'godns' && x.probs) P([[rep(' ', 8), 'text'], ['! ', 'warn'], [t('3 перезапуска за час', '3 restarts in an hour'), 'warn']]);
    } else {
      const v = pf(p.id, p.modes.length ? defMode(p, x) : null);
      wrap(v.rows.map(rw => rw.port).join(' '), IW - 10).slice(0, 2).forEach((l, i) => P([[padR(i ? '' : t('НУЖНЫ', 'NEEDS'), 8), 'muted'], [l, 'text']]));
      P([[padR(t('ИТОГ', 'RESULT'), 8), 'muted'], verdictTag(v), ...(p.modes.length ? [[' · ' + modeName(defMode(p, x)), 'muted']] : [])]);
    }
    P([]);
    P([[t('ЧТО НОВОГО', "WHAT'S NEW"), 'muted']]);
    if (f.upd) P([['↑ ', 'update'], [f.srv + ' → ' + p.main + t(' в main', ' in main'), 'text']]);
    else if (f.isNew) P([['✚ ', 'new'], [t('вышел в main, версия ', 'released in main, version ') + p.main, 'text']]);
    else if (f.inst) P([['✓ ', 'ok'], [t('актуален', 'up to date'), 'text']]);
    else P([['○ ', 'muted'], ['main ' + p.main, 'text']]);
    foot = inProduct ? [[t('команда ', 'command '), 'muted'], [p.cmd, 'key']] : [['Enter', 'key'], [' — ' + (f.inst ? t('меню продукта', 'product menu') : t('установка', 'install')), 'muted'], ['  ·  ', 'rule'], [p.cmd, 'key']];
  } else if (it.shield && x.SH.variant !== 'none') {
    const cd = SG().card({ lang: LANG, on: x.SH.on, vk: x.SH.vk, chart: x.SH.chart, RI: IW - 2, row: x.SH.row });
    title = cd.title; right = cd.right;
    cd.lines.forEach(l => P(l));
    foot = [['Enter', 'key'], [' — ' + t('меню «Защита»', 'protection menu'), 'muted'], ['  ·  ', 'rule'], ['←→', 'key'], [' ' + t('день', 'day'), 'muted']];
  } else {
    title = [[it.label, it.tok || 'title']];
    if (it.note) wrap(it.note, IW - 2).forEach(l => P([[l, it.noteTok || 'muted']]));
    P([]);
    if (it.key === '7') PRODS.filter(p => info(p, x).inst).forEach(p => (p.held || []).slice(0, 2).forEach(h => P([[padR(h[0], 10), 'text'], [padR(h[1], 9), 'muted'], [p.name, 'muted']])));
    if (it.key === '8') { P([['/opt/go-installer/token', 'muted']]); P([[t('режим 0600, только root', 'mode 0600, root only'), 'muted']]); }
    if (it.key === '9') { P([['1', 'key'], [' Русский   ', 'text'], ['2', 'key'], [' English', 'text']]); }
    if (it.key === 'u') { P([[t('ветка main · ', 'branch main · '), 'muted'], ['go-installer.sh', 'text']]); }
    if (it.key === '0') { P([[t('вернуться в консоль', 'back to the shell'), 'muted']]); }
    foot = it.hot ? [['Enter', 'key'], [t(' или ', ' or '), 'muted'], [it.hot, 'key'], [t(' с любого экрана', ' from any screen'), 'muted']] : [['Enter', 'key'], [' — ' + t('открыть', 'open'), 'muted']];
  }
  while (L.length < H - 1) L.push({ s: [] });
  L.length = H - 1;
  L.push({ s: [[' ', 'text'], ...foot] });
  return { title, right, lines: L };
}
function optLines(x, items, cur, W, o) {
  o = o || {}; const L = [];
  items.forEach((it, i) => {
    const sel = i === cur;
    const lead = [[' ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + '  ', sel ? 'cursor' : 'key']];
    const lab = [it.label, sel ? 'title' : (it.tok || 'name')];
    if (o.below) {
      const tg = it.tag && len(it.label) + 9 + len(it.tag[0]) <= W ? [['   ', 'text'], it.tag] : [];
      L.push({ s: [...lead, lab, ...tg], sel });
      if (it.note) wrap(it.note, W - 7).forEach(l => L.push({ s: [['      ', 'text'], [l, 'muted']] }));
      if (it.tag && !tg.length) L.push({ s: [['      ', 'text'], it.tag] });
    } else {
      const lw = o.lw || 0;
      const segs = [...lead, [lw && it.note ? padR(it.label, lw) : it.label, lab[1]]];
      if (it.note && lw) segs.push([it.note, it.noteTok || 'muted']);
      L.push({ s: segs, sel });
    }
  });
  return L;
}
function shell2(x, L, R, extra) {
  const C = x.C, body = [hud(x)];
  if (C >= 80 && !R.wide) {
    const H = 17, LW = L.w, RW = C - LW - 2;
    const lf = frame2(LW, H, L.title, L.right || null, L.build(LW - 2));
    const rf = frame2(RW, H, R.title, R.right || null, R.build(RW - 2));
    for (let i = 0; i < H + 2; i++) body.push(r([...lf[i], [i ? '░' : ' ', 'shadow'], ...rf[i], [i ? '░' : ' ', 'shadow']]));
    body.push(r([[' ', 'text'], [rep('░', LW), 'shadow'], [' ', 'text'], [rep('░', RW), 'shadow']]));
  } else {
    const W = C - 1;
    if (L.steps46) body.push(L.steps46);
    const main = (R.build46 || R.build)(W - 2);
    const lines = [...main, ...(L.list && !R.wide ? [...(main.length ? [{ s: [[' ' + rep('─', W - 4), 'rule']] }] : []), ...L.build(W - 2)] : [])];
    const H = Math.max(1, Math.min(lines.length, 24 - 2 - body.length - 3 - (extra ? extra.length : 0)));
    frame2(W, H, R.title, R.right46 || null, lines).forEach((row, i) => body.push(r([...row, [i ? '░' : ' ', 'shadow']])));
    body.push(r([[' ', 'text'], [rep('░', W), 'shadow']]));
  }
  (extra || []).forEach(e => body.push(r(e)));
  return body;
}
function stepsL(x, p, idx) {
  const steps = wizSteps(p), P = x.P, vals = {};
  if (P.mode) vals[t('Режим', 'Mode')] = modeName(P.mode);
  if (P.branch) vals[t('Ветка', 'Branch')] = P.branch;
  return { title: [[t('УСТАНОВКА', 'INSTALL'), 'title']], w: 26, steps46: stepsRow(x, steps, Math.min(idx, steps.length - 1)),
    build: W => {
      const L = [];
      steps.forEach((n, i) => {
        const g = i < idx ? ['✓ ', 'ok'] : i === idx ? ['● ', 'cursor'] : ['○ ', 'muted'];
        L.push({ s: [[' ', 'text'], g, [padR(n, 11), i === idx ? 'title' : i < idx ? 'text' : 'muted'], [vals[n] || '', 'muted']], sel: false });
        if (i < steps.length - 1) L.push({ s: [[' │', i < idx ? 'ok' : 'rule']] });
      });
      const f = info(p, x), s = STATUS[f.status];
      L.push({ s: [] }, { s: [[' ' + rep('─', W - 2), 'rule']] }, { s: [[' ' + p.name, 'name']] }, { s: [[' ' + s.g + ' ', s.tok], [sw(s) + (f.inst ? ' ' + f.srv : ''), 'muted']] });
      return L;
    } };
}
function prodL(x, p, extra) {
  return { title: [[t('ПРОДУКТ', 'PRODUCT'), 'title']], w: 26, build: W => {
    const f = info(p, x), s = STATUS[f.status];
    const L = [{ s: [[' ' + p.name, 'name']] }, { s: [[' ' + s.g + ' ', s.tok], [sw(s) + (f.inst ? ' ' + f.srv : ''), 'muted']] }, { s: [] }];
    wrap(t(p.desc[0], p.desc[1]), W - 2).forEach(l => L.push({ s: [[' ' + l, 'muted']] }));
    (extra || []).forEach(e => L.push({ s: e }));
    return L;
  } };
}
const ARC = {};
ARC.product = (x, b) => {
  const p = PROD(x.P.id);
  const card = arcadeCard(x, { kind: 'p', p }, 38, 17, true);
  const L = { title: [[t('ДЕЙСТВИЯ', 'ACTIONS'), 'title']], w: 40, list: true, build: W => { const o = optLines(x, b.items, x.st.cur, W); const it = b.items[x.st.cur]; if (it && it.note && W > 30) { o.push({ s: [] }, { s: [[' ' + rep('─', W - 2), 'rule']] }); wrap(it.note, W - 3).forEach(l => o.push({ s: [['  ' + l, it.noteTok || 'muted']] })); } return o; } };
  const R = { title: card.title, right: card.right, build: W => arcadeCard(x, { kind: 'p', p }, W, 17, true).lines,
    build46: W => { const f = info(p, x), s = STATUS[f.status]; const o = wrap(t(p.desc[0], p.desc[1]), W - 2).map(l => ({ s: [[' ' + l, 'muted']] }));
      o.push({ s: [[' ' + s.g + ' ', s.tok], [sw(s) + (f.inst ? ' ' + f.srv + ' · ' + f.branch : ' · main ' + p.main), 'text'], ...(f.upd ? [['  ↑ ' + p.main, 'update']] : f.isNew ? [['  ✚ ' + t('новое', 'new'), 'new']] : [])] }); return o; } };
  return { ...b, body: shell2(x, L, R) };
};
ARC.mode = (x, b) => {
  const p = PROD(x.P.id), def = defMode(p, x), di = p.modes.indexOf(def);
  const hint = [['Enter — ' + (di + 1) + ', ' + modeName(def), 'muted']];
  const R = { title: [[t('РЕЖИМ', 'MODE'), 'title']], right: hint, right46: hint, build: W => optLines(x, b.items, x.st.cur, W, { below: true }) };
  return { ...b, body: shell2(x, x.P.only ? prodL(x, p) : stepsL(x, p, 0), R) };
};
ARC.check = (x, b) => {
  const p = PROD(x.P.id), mode = x.P.mode, v = pf(p.id, mode), steps = wizSteps(p);
  const R = { title: [[t('ПРОВЕРКА ПОРТОВ', 'PORT CHECK'), 'title']], right: mode ? [[t('режим ', 'mode ') + modeName(mode), 'muted']] : null,
    build: W => {
      const L = [], n = W < 50, HW = 20, DW = W - 13 - HW;
      if (!n) L.push({ s: [[' ' + padR(t('ПОРТ', 'PORT'), 10) + '  ' + padR(t('ЧТО ЭТО', 'WHAT FOR'), DW) + t('КТО ДЕРЖИТ', 'HELD BY'), 'muted']] });
      v.rows.forEach(rw => {
        const g = PFG[rw.st];
        if (n) L.push({ s: [[' ' + padR(rw.port, 10), 'text'], g, [' ', 'text'], rw.h && rw.st !== 'ok' ? [rw.h, rw.st === 'bad' ? 'err' : 'text'] : [rw.d, 'muted']] });
        else L.push({ s: [[' ' + padR(rw.port, 10), 'text'], g, [' ', 'text'], [padR(rw.d, DW - 1) + ' ', 'text'], [rw.h, rw.st === 'bad' ? 'err' : rw.st === 'ok' ? 'muted' : 'text']] });
      });
      L.push({ s: [] });
      v.rules.forEach(rl => wrap(rl[2], W - 4).forEach((l, i) => L.push({ s: [[' ' + (i ? ' ' : rl[0]) + ' ', rl[1]], [l, 'text']] })));
      L.push({ s: [[' ' + v.verdict[0] + ' ', v.verdict[1]], [v.verdict[2], v.verdict[1] === 'err' ? 'err' : 'title']] });
      L.push({ s: [] });
      return L.concat(optLines(x, b.items, x.st.cur, W));
    } };
  const Lc = x.P.wiz ? stepsL(x, p, steps.indexOf(t('Проверка', 'Check'))) : { steps46: null };
  const title = [[p.name, 'title'], [' · ' + t('проверка портов', 'port check') + (mode ? ' · ' + modeName(mode) : ''), 'muted']];
  return { ...b, body: shell2(x, Lc, { ...R, wide: true, title, right46: null }) };
};
ARC.branch = (x, b) => {
  const p = PROD(x.P.id), steps = wizSteps(p), hint = [['Enter — 1, main', 'muted']];
  return { ...b, body: shell2(x, stepsL(x, p, steps.indexOf(t('Ветка', 'Branch'))), { title: [[t('ВЕТКА', 'BRANCH'), 'title']], right: hint, right46: hint, build: W => optLines(x, b.items, x.st.cur, W, { below: true }) }) };
};
ARC.confirm = (x, b) => {
  const p = PROD(x.P.id), steps = wizSteps(p), br = x.P.branch, ver = br === 'dev' ? p.dev : p.main;
  const q = t('Запустить установщик ', 'Run the installer of ') + p.name + ' — ' + t('ветка ', 'branch ') + br + ', ' + ver + '?';
  const hint = [['Enter — 1, ' + t('Да', 'Yes'), 'muted']];
  return { ...b, body: shell2(x, stepsL(x, p, steps.indexOf(t('Установка', 'Install'))), { title: [[t('ПОДТВЕРЖДЕНИЕ', 'CONFIRM'), 'title']], right: hint, right46: hint,
    build: W => [...wrap(q, W - 2).map(l => ({ s: [[' ' + l, 'title']] })), { s: [] }, ...optLines(x, b.items, x.st.cur, W), { s: [] }, { s: [[' ✓ ', 'ok'], [t('проверка портов пройдена', 'port check passed'), 'muted']] }] }) };
};
ARC.installing = (x, b) => {
  const p = PROD(x.P.id), steps = wizSteps(p), el = x.now - x.st.t0, fr = SPIN[Math.floor(x.now / 100) % 10];
  return { ...b, body: shell2(x, stepsL(x, p, steps.indexOf(t('Установка', 'Install'))), { title: [[t('УСТАНОВКА', 'INSTALLING'), 'title'], [' · ' + p.cmd, 'muted']],
    build: W => [{ s: [[' → ', 'cursor'], [t('Управление передано установщику ', 'Handed over to the installer of ') + p.name, 'text']] },
      ...wrap(t('Его вопросы и вывод идут ниже как есть.', 'Its questions and output follow as is.'), W - 4).map(l => ({ s: [['   ' + l, 'muted']] })), { s: [] },
      { s: [[' ' + fr + ' ', 'cursor'], [t('установщик продукта работает · ', 'product installer running · ') + Math.floor(el / 1000) + t(' с', ' s'), 'muted']] }] }) };
};
ARC.result = (x, b) => {
  const p = PROD(x.P.id), f = info(p, x), steps = wizSteps(p), mism = x.P.mismatch;
  const build = W => {
    const L = [], P = (g, tok, text, tt) => wrap(text, W - 4).forEach((l, i) => L.push({ s: [[' ' + (i ? ' ' : g) + ' ', tok], [l, tt || 'text']] }));
    if (mism) { P('!', 'warn', t('Ветка не сменилась: ', 'Branch did not change: ') + p.name + t(' стоит с ветки ', ' runs from branch ') + f.branch + t(', а выбрана ', ', but ') + x.P.branch + t('', ' was chosen'), 'title'); P(' ', 'muted', t('Повторите установку или смените ветку в меню продукта: ', 'Run the install again or switch the branch in the product menu: ') + p.cmd, 'muted'); }
    else P('✓', 'ok', t('Проверено: ', 'Verified: ') + p.name + t(' стоит с ветки ', ' runs from branch ') + f.branch + t(', версия ', ', version ') + f.srv, 'title');
    if (x.P.lazy) { L.push({ s: [] }); P('!', 'warn', t('Ленивый pro встал в режиме Semi-pro', 'Lazy pro ended up in Semi-pro mode'), 'title'); P(' ', 'muted', t('UDP 443 был занят. Режим меняется в меню продукта: goamnezia', 'UDP 443 was taken. Change the mode in the product menu: goamnezia'), 'muted'); }
    L.push({ s: [] });
    return L.concat(optLines(x, b.items, x.st.cur, W));
  };
  return { ...b, body: shell2(x, stepsL(x, p, steps.length), { title: [[t('СВЕРКА', 'VERIFY'), 'title']], right: [[mism ? '! ' + t('замечание', 'note') : '✓ ' + t('готово', 'done'), mism ? 'warn' : 'ok']], build }) };
};
ARC.ports = (x, b) => {
  const groups = PRODS.filter(p => info(p, x).inst && p.held.length).map(p => ({ name: p.name, held: p.held }));
  groups.push({ name: t('система', 'system'), held: [['22/tcp', 'sshd', ['SSH', 'SSH']], ['53/udp', 'resolved', ['loopback: 127.0.0.53', 'loopback: 127.0.0.53']]] });
  const cur = Math.min(x.st.cur, groups.length);
  const items = groups.map((g, i) => ({ key: String(i + 1), label: g.name, note: String(g.held.length), act: () => x.A.setCur(i) }));
  items.push(BACK(x));
  const g = groups[Math.min(cur, groups.length - 1)];
  const L = { title: [[t('КТО ДЕРЖИТ', 'HOLDERS'), 'title']], w: 28, list: true, build: W => optLines(x, items, cur, W, { lw: W - 9 }) };
  const R = { title: [[g.name, 'title']], right: [['goinstall --ports', 'muted']], build: W => {
    const n = W < 50, L2 = [];
    if (!n) L2.push({ s: [[' ' + padR(t('ПОРТ', 'PORT'), 11) + padR(t('ПРОЦЕСС', 'PROCESS'), 12) + t('ЧТО ЭТО', 'WHAT FOR'), 'muted']] });
    g.held.forEach(h => L2.push({ s: [[' ' + padR(h[0], n ? 10 : 11), 'text'], [padR(h[1], n ? 9 : 12), 'key'], [t(h[2][0], h[2][1]), 'muted']] }));
    return L2;
  } };
  return { ...b, items, body: shell2(x, L, R), keys: K_NAV(), keymap: [['↑↓ · цифра', t('выбрать владельца', 'pick a holder')], ['0 · Esc', t('назад', 'back')]] };
};
ARC.key = (x, b) => {
  const chk = x.st.keyCheck, el = chk ? x.now - chk : 1e9;
  const L = { title: [[t('ДЕЙСТВИЯ', 'ACTIONS'), 'title']], w: 30, list: true, build: W => optLines(x, b.items, x.st.cur, W) };
  const R = { title: [[t('КЛЮЧ ДОСТУПА', 'ACCESS KEY'), 'title']], right: [[x.probs ? '! 5/6' : '✓ 6/6', x.probs ? 'warn' : 'ok']], build: W => {
    const o = [{ s: [[' ● ', 'ok'], [t('сохранён', 'saved'), 'text']] }, { s: [['   /opt/go-installer/token · 0600', 'muted']] }, { s: [] }];
    if (el < 900) o.push({ s: [[' ' + SPIN[Math.floor(x.now / 100) % 10] + ' ', 'cursor'], [t('проверяю 6 репозиториев…', 'checking 6 repositories…'), 'muted']] });
    else if (x.probs) {
      o.push({ s: [[' ! ', 'warn'], [t('открывает 5 из 6', 'opens 5 of 6'), 'text']] }, { s: [['   goAmnezia pro — ' + t('нет доступа', 'no access'), 'warn']] }, { s: [] });
      wrap(t('Возьмите свежий ключ в «anten-ka club», ветка «goinstall», и введите его пунктом 2.', 'Get a fresh key in “anten-ka club”, topic “goinstall”, and enter it via item 2.'), W - 4).forEach(l => o.push({ s: [['   ' + l, 'muted']] }));
    } else o.push({ s: [[' ✓ ', 'ok'], [t('открывает 6 из 6', 'opens 6 of 6'), 'text']] }, { s: [['   ' + t('проверен в ', 'checked at ') + (chk ? '14:07' : x.sved), 'muted']] });
    return o;
  } };
  return { ...b, body: shell2(x, L, R) };
};
ARC.lang = (x, b) => {
  const L = { title: [['ЯЗЫК · LANGUAGE', 'title']], w: 30, list: true, build: W => optLines(x, b.items, x.st.cur, W) };
  const di = x.S.lang === 'en' ? 1 : 0;
  const R = { title: [['goinstall', 'title']], build: W => [{ s: [[' Язык / Language', 'title']] }, { s: [[' Enter — ' + (di + 1) + ', ' + (di ? 'English' : 'Русский'), 'muted']] }, { s: [] },
    ...wrap(t('Выбор запоминается в /opt/go-installer/.language и больше не спрашивается.', 'The choice is saved to /opt/go-installer/.language and not asked again.'), W - 2).map(l => ({ s: [[' ' + l, 'muted']] }))], build46: () => [] };
  return { ...b, body: shell2(x, L, { ...R, title: [['ЯЗЫК · LANGUAGE', 'title']] }) };
};
function arcadeMenu(x, items, cur) {
  const C = x.C, body = [hud(x)];
  const alerts = x.probs ? problems() : [];
  if (C >= 80) {
    const LW = 37, RW = C - LW - 2, H = 16;
    const lf = frame2(LW, H, [[t('ПРОДУКТЫ', 'PRODUCTS'), 'title']], null, arcadeList(x, items, cur, LW));
    const card = arcadeCard(x, items[cur], RW - 2, H);
    const rf = frame2(RW, H, card.title, card.right, card.lines);
    for (let i = 0; i < H + 2; i++) body.push(r([...lf[i], [i ? '░' : ' ', 'shadow'], ...rf[i], [i ? '░' : ' ', 'shadow']]));
    body.push(r([[' ', 'text'], [rep('░', LW), 'shadow'], [' ', 'text'], [rep('░', RW), 'shadow']]));
    alerts.forEach(p => body.push(r([[' ! ', 'warn'], [p.name + ': ' + p.msg, 'text'], [' → ', 'muted'], [p.step, 'key']])));
  } else {
    const W = C - 1, lines = arcadeList(x, items, cur, W);
    const lf = frame2(W, lines.length, [[t('ПРОДУКТЫ', 'PRODUCTS'), 'title']], null, lines);
    lf.forEach((row, i) => body.push(r([...row, [i ? '░' : ' ', 'shadow']])));
    body.push(r([[' ', 'text'], [rep('░', W), 'shadow']]));
    const sp = items[cur];
    body.push(r(sp.kind === 'p' ? [[' ' + t(sp.p.desc[0], sp.p.desc[1]), 'muted']] : [[' ' + (sp.note || ''), sp.noteTok || 'muted']]));
    alerts.forEach(p => body.push(r([[' ! ', 'warn'], [p.short, 'text']])));
  }
  return body;
}
const mainTitle = x => [['goInstaller', TT(x)], [' ' + x.st.instVer, 'muted']];
function crumbs(x, name) { return [['goInstaller', TT(x)], [' › ', 'muted'], [name, 'title']]; }
function box(x, title, right, inner, bottom) {
  const { C, dir } = x, R = [];
  if (dir === 'arcade') {
    const Wb = C - 1, iw = Wb - 4;
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
  if (dir === 'night') {
    const top = [['═══ ', 'grad'], ...title, [' ', 'text']];
    const tr = [...(right || []), ['═══', 'grad']];
    R.push(r([...top, [rep('═', C - slen(top) - slen(tr)), 'grad'], ...tr]));
    inner.forEach(l => R.push(r(l === 'SEP' ? [] : [['  ', 'text'], ...l])));
    const bl = [['═══ ', 'grad'], ...bottom, [' ', 'text']];
    R.push(r([...bl, [rep('═', C - slen(bl) - 3), 'grad'], ['═══', 'grad']]));
    return R;
  }
  const ph = dir === 'phos';
  const K = ph ? ['┌', '┐', '└', '┘'] : ['╭', '╮', '╰', '╯'];
  const l0 = ph ? '─[ ' : '─ ', l1 = ph ? ' ]' : ' ';
  const top = [[K[0] + l0, 'rule'], ...title, [l1, 'rule']];
  const tr = right ? [[ph ? '[ ' : ' ', 'rule'], ...right, [ph ? ' ]─' + K[1] : ' ─' + K[1], 'rule']] : [['─' + K[1], 'rule']];
  const tn = C - slen(top) - slen(tr);
  R.push(r(tn >= 1 ? [...top, [rep('─', tn), 'rule'], ...tr] : [...top, [rep('─', C - slen(top) - 1), 'rule'], [K[1], 'rule']]));
  const iw = C - 4;
  inner.forEach(l => {
    if (l === 'SEP') { R.push(r(ph ? [['│', 'rule'], [rep(' ', C - 2), 'text'], ['│', 'rule']] : [['├' + rep('─', C - 2) + '┤', 'rule']])); return; }
    const f = fit(l, iw);
    R.push(r([['│ ', 'rule'], ...f.segs, [rep(' ', iw - f.used), 'text'], [' │', 'rule']]));
  });
  const bl = [[K[2] + l0, 'rule'], ...bottom, [l1, 'rule']];
  R.push(r([...bl, [rep('─', C - slen(bl) - 1), 'rule'], [K[3], 'rule']]));
  return R;
}
function bar(frac, w, tok) {
  const cells = Math.max(0, Math.min(1, frac)) * w, full = Math.floor(cells), part = Math.floor((cells - full) * 8);
  const P = ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉'];
  const s = [[rep('█', full), tok]];
  if (full < w) { s.push([part ? P[part] : '░', part ? tok : 'rule']); s.push([rep('░', w - full - 1), 'rule']); }
  return s;
}
function keysRow(x, keys) {
  const build = sh => { const s = [['  ', 'text']]; keys.forEach(([k, l, s2], i) => { const lab = sh ? s2 : l; if (i) s.push([' · ', 'muted']); s.push([k, 'key']); if (lab) s.push([' ' + lab, 'muted']); }); return s; };
  let s = build(false); if (slen(s) > x.C) s = build(true); return s;
}
function stepsRow(x, steps, cur) {
  if (x.C < 60) return r([['  ' + t('Шаг ', 'Step ') + (cur + 1) + t(' из ', ' of ') + steps.length + ' · ', 'muted'], [steps[cur], 'title'], ...(steps[cur + 1] ? [[' → ' + steps[cur + 1], 'muted']] : [])]);
  const s = [['  ', 'text']];
  steps.forEach((n, i) => { if (i) s.push([' → ', 'muted']); if (i < cur) s.push(['✓ ', 'ok'], [n, 'text']); else if (i === cur) s.push(['● ', 'cursor'], [n, 'title']); else s.push(['○ ', 'muted'], [n, 'muted']); });
  return r(s);
}
function wizSteps(p) { const s = []; if (p.modes.length) s.push(t('Режим', 'Mode')); s.push(t('Проверка', 'Check')); if (p.dev) s.push(t('Ветка', 'Branch')); s.push(t('Установка', 'Install'), t('Сверка', 'Verify')); return s; }
function choiceRows(x, items, cur, opt) {
  opt = opt || {}; const { C } = x, R = [], lw = opt.lw || (C >= 80 ? 32 : 26);
  items.forEach((it, i) => {
    const sel = i === cur;
    const lead = [['  ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + '  ', sel ? 'cursor' : 'key']];
    if (opt.below) {
      R.push(r([...lead, [it.label, sel ? 'title' : (it.tok || 'name')], ...(it.tag && C >= 60 ? [['   ', 'text'], it.tag] : [])], sel));
      if (it.note) wrap(it.note, C - 9).forEach(l => R.push(r([[rep(' ', 7), 'text'], [l, 'muted']])));
      if (it.tag && C < 60) R.push(r([[rep(' ', 7), 'text'], it.tag]));
    } else {
      const segs = [...lead, [it.note && C >= 60 ? padR(it.label, lw) : it.label, sel ? 'title' : (it.tok || 'name')]];
      if (it.note && C >= 60) segs.push([it.note, it.noteTok || 'muted']);
      R.push(r(segs, sel));
    }
  });
  return R;
}
const BACK = x => ({ key: '0', label: t('Назад', 'Back'), act: x.A.back });
const K_NAV = () => [['↑↓', t('выбрать', 'move'), ''], ['Enter', t('выбрать', 'select'), ''], [t('цифра', 'digit'), t('сразу', 'jumps'), ''], ['0', t('назад', 'back'), t('назад', 'back')]];

/* ---------- login summary ---------- */
function problems() {
  return [
    { name:'vpn.example.com', msg:t('сертификат истекает через 9 дней','certificate expires in 9 days'), short:t('сертификат vpn.example.com: 9 дней','vpn.example.com cert: 9 days left'), step:'certbot renew' },
    { name:'goDNS pro', msg:t('dnsdist: 3 перезапуска за час','dnsdist: 3 restarts in an hour'), short:t('goDNS pro: dnsdist 3 перезапуска за час','goDNS pro: dnsdist restarted 3 times/h'), step:'journalctl -u dnsdist' }
  ];
}
function newsList(x) {
  const u = [];
  if (x.tgUpd) u.push(['↑', 'update', 'goTelegram pro', '2.10.46 → 2.10.49', t('обновление в main', 'update in main')]);
  if (x.amNew) u.push(['✚', 'new', 'goAmnezia pro', '1.0.2', t('новый продукт серии, main', 'new in the series, main')]);
  if (x.instUpd) u.push(['↑', 'update', 'goInstaller', x.st.instVer + ' → 0.9.6', t('новая версия установщика', 'new installer version')]);
  return u;
}
function summaryRows(x) {
  const { C } = x, n = C < 60;
  const ups = newsList(x), pr = x.probs ? problems() : [];
  const sved = t('сведения от ', 'data as of ') + x.sved;
  if (!ups.length && !pr.length) return [
    r([['✓ ', 'ok'], [t('goInstaller: всё актуально', 'goInstaller: all up to date'), 'text'], ...(n ? [] : [[t(', 3 продукта, проблем нет', ', 3 products, no problems'), 'muted']])]),
    r([['  ' + sved + ' · ', 'muted'], ['goinstall', 'key'], [n ? t(' — меню', ' — menu') : t(' — открыть меню', ' — open the menu'), 'muted']])
  ];
  const inner = [];
  ups.forEach(u => inner.push(n ? [[u[0], u[1]], [' ' + padR(u[2], 15), 'name'], [u[3], u[1]]] : [[' ' + u[0], u[1]], [' ' + padR(u[2], 17), 'name'], [padR(u[3], 20), u[1]], [u[4], 'muted']]));
  if (pr.length) {
    if (ups.length) inner.push('SEP');
    pr.forEach(p => {
      if (n) { inner.push([['!', 'warn'], [' ' + p.short, 'text']]); inner.push([['  → ', 'muted'], [p.step, 'key']]); }
      else inner.push([[' !', 'warn'], [' ' + padR(p.name, 17), 'name'], [p.msg, 'text'], [' → ', 'muted'], [p.step, 'key']]);
    });
    inner.push([[n ? '' : ' ', 'text'], [t('диск 58 % · память 41 % · нагрузка 0.4', 'disk 58 % · memory 41 % · load 0.4'), 'muted']]);
  }
  let right;
  if (x.dir === 'night') {
    right = [];
    const nu = ups.filter(u => u[0] === '↑').length, nn = ups.filter(u => u[0] === '✚').length;
    if (nu) right.push(['↑' + nu + ' ', 'update']); if (nn) right.push(['✚' + nn + ' ', 'new']); if (pr.length) right.push(['!' + pr.length + ' ', 'warn']);
  } else right = [[n ? x.sved : sved, 'muted']];
  const title = [['goInstaller', 'title'], [' · vpn-fin-1', 'muted']];
  const bottom = x.dir === 'night' ? [[n ? x.sved : sved, 'muted'], [' · ', 'muted'], ['goinstall', 'key'], [t(' — меню', ' — menu'), 'muted']] : [['goinstall', 'key'], [n ? t(' — меню', ' — menu') : t(' — открыть меню', ' — open the menu'), 'muted']];
  return box(x, title, right, inner, bottom);
}
function promptSegs(x) {
  const ups = newsList(x), pr = x.probs ? 2 : 0;
  const nu = ups.filter(u => u[0] === '↑').length, nn = ups.filter(u => u[0] === '✚').length;
  const b = [];
  if (nu || nn || pr) { b.push([' [go', 'muted']); if (nu) b.push([' ↑' + nu, 'update']); if (nn) b.push([' ✚' + nn, 'new']); if (pr) b.push([' !' + pr, 'warn']); b.push([']', 'muted']); }
  return [['root@vpn-fin-1', 'text'], ...b, [':~# ', 'text'], [x.st.typed || '', 'text'], ['█', 'cursor']];
}
const LASTLOGIN = () => r([['Last login: Tue Sep 29 14:07:31 2026 from 203.0.113.24', 'text']]);

/* ---------- screens ---------- */
const SCR = {};
SCR.login = x => {
  const body = [LASTLOGIN(), r([]), ...summaryRows(x), r([]), r(promptSegs(x))];
  return { body, keymap: [['Enter', t('набрать goinstall и запустить', 'type goinstall and run it')]], onKey: k => { if (k === 'Enter') x.A.launch(); return true; } };
};
SCR.console = x => ({ body: [r([['goinstall: ' + t('выход', 'exit'), 'muted']]), r(promptSegs(x))], keymap: [['Enter', t('снова goinstall', 'goinstall again')]], onKey: k => { if (k === 'Enter') x.A.launch(); return true; } });
SCR.countdown = x => {
  const el = x.now - x.st.t0, rem = Math.max(0, 5000 - el), n = x.C < 60;
  const body = [LASTLOGIN(), r([]), ...summaryRows(x), r([]),
    r([['  ', 'text'], ['Enter', 'key'], [n ? t(' — goinstall · другая клавиша — консоль', ' — goinstall · other key — shell') : t(' — открыть goinstall · любая другая клавиша — в консоль', ' — open goinstall · any other key — shell'), 'muted']]),
    r([['  ', 'text'], ...bar(rem / 5000, n ? 20 : 24, 'cursor'), ['  ' + Math.ceil(rem / 1000) + t(' с', ' s'), 'muted']])];
  return { body, anim: true, tick: () => { if (rem <= 0) x.A.replace('login'); },
    keymap: [['Enter', t('открыть goinstall', 'open goinstall')], [t('другая', 'other'), t('в консоль', 'to the shell')], ['5 с', t('сами уходим в консоль', 'falls through to the shell')]],
    onKey: k => { if (k === 'Enter') x.A.launch(); else x.A.replace('login'); return true; } };
};
const LOGO = ['▄▀▀▀ ▄▀▀▄', '█ ▀█ █  █', '▀▄▄▀ ▀▄▄▀'];
SCR.splash = x => {
  const ps = pollState(x), n = x.C < 60, items = pollItems(x), arc = x.dir === 'arcade';
  const side = [[], [['goInstaller ', 'title'], [x.st.instVer, 'muted']], [[n ? t('установщик серии go', 'go series installer') : t('установщик продуктов серии go', 'installer for the go series'), 'muted']], [[n ? 'vpn-fin-1' : 'vpn-fin-1 · Ubuntu 24.04.3 LTS', 'muted']], []];
  const body = logoRows(x).map((l, i) => r([[' ', 'text'], ...(arc && !n ? [[SPEED[i], 'grad']] : [[' ', 'text']]), ...l, ['   ', 'text'], ...side[i]]));
  body.push(r([]));
  body.push(r([[t('  Опрос GitHub  ', '  GitHub poll   '), 'text'], ...bar(ps.done / 8, n ? 14 : 24, 'cursor'), ['  ' + ps.done + t(' из 8', ' of 8'), 'muted']]));
  body.push(r([]));
  const fr = SPIN[Math.floor(x.now / 100) % 10];
  items.forEach((it, i) => {
    const s = ps.items[i];
    const g = s === 'done' ? ['✓', 'ok'] : s === 'fail' ? ['✗', 'err'] : s === 'run' ? [fr, 'cursor'] : ['·', 'muted'];
    const res = s === 'done' ? [it[1], it[2]] : s === 'fail' ? [ps.err === 'rate' ? t('403: лимит запросов', '403: rate limit') : t('нет ответа', 'no answer'), 'err'] : s === 'run' ? [t('спрашиваю…', 'asking…'), 'muted'] : [t('ждёт', 'queued'), 'muted'];
    body.push(r([['  ', 'text'], g, [' ' + padR(it[0], n ? 15 : 17), 'name'], res]));
  });
  const ups = newsList(x);
  if (ps.finished && ups.length && !ps.err) {
    body.push(r([]));
    body.push(r([['  ' + t('Что нового', "What's new"), 'title']]));
    ups.forEach(u => body.push(r([['  ' + u[0], u[1]], [' ' + padR(u[2], n ? 15 : 17), 'name'], [n ? u[3] : padR(u[3], 20), u[1]], ...(n ? [] : [[u[4], 'muted']])])));
  }
  if (arc && ps.finished && !ps.err) { body.push(r([])); body.push(r(Math.floor(x.now / 500) % 2 ? [] : [['  ▸ ', 'cursor'], [t('НАЖМИТЕ ENTER', 'PRESS ENTER'), 'title']])); }
  const keys = ps.finished ? [['Enter', t('в меню', 'to the menu'), t('меню', 'menu')]] : [[t('любая клавиша', 'any key'), t('пропустить, опрос идёт дальше', 'skip, polling continues'), t('пропустить', 'skip')]];
  return { body, keys, anim: true, keymap: keys.map(k => [k[0], k[1]]),
    onKey: k => { if (!ps.finished) { x.A.root('menu'); return true; } if (k === 'Enter') x.A.root('menu'); return true; } };
};

function menuItems(x) {
  const it = PRODS.map((p, i) => ({ kind: 'p', key: String(i + 1), p, act: () => x.A.go('product', { id: p.id }) }));
  it.push({ kind: 's', key: '7', hot: 'p', label: t('Карта портов', 'Port map'), note: t('кто какие порты держит', 'who holds which ports'), act: () => x.A.go('ports') });
  it.push({ kind: 's', key: '8', hot: 'r', label: t('Ключ доступа', 'Access key'), note: x.probs ? t('не открывает goAmnezia pro', 'does not open goAmnezia pro') : t('сохранён, проверен в ', 'saved, checked at ') + x.sved, noteTok: x.probs ? 'warn' : 'muted', act: () => x.A.go('key') });
  it.push({ kind: 's', key: '9', hot: 'l', label: t('Язык', 'Language'), note: t('русский', 'English'), act: () => x.A.go('lang') });
  it.push({ kind: 's', key: 'c', hot: x.news ? '↑2' : '', label: t('Компоненты', 'Components'), note: '', act: () => x.A.go('components') });
  it.push({ kind: 's', key: 's', hot: '', label: t('Защита от сканеров', 'Scanner protection'), note: '', shield: true, act: () => x.A.go('shield') });
  if (x.instUpd) it.push({ kind: 's', key: 'u', hot: '', label: t('Обновить goInstaller', 'Update goInstaller'), note: x.st.instVer + ' → ' + NEXTVER(x), tok: 'update', noteTok: 'update', act: () => x.A.go('selfupd') });
  it.push({ kind: 's', key: 'x', hot: '', label: t('Удалить goInstaller', 'Uninstall goInstaller'), note: '', act: () => x.A.go('uninstall') });
  it.push({ kind: 's', key: '0', hot: 'q', label: t('Выход', 'Quit'), note: '', act: () => x.A.exit() });
  return it;
}
function menuInfo(x) {
  const base = [['  ' + t('сведения от ', 'data as of ') + x.sved + (x.C < 60 ? '' : t(' · обновляются сами раз в 3 мин', ' · refresh every 3 min by themselves')), 'muted']];
  if (x.SH.variant === 'B') { const p = sparkPair(x, x.C < 60); base.push([' · ', 'muted'], ...p.a, [x.C < 60 ? ' ' : '  ', 'text'], ...p.b); }
  return base;
}
function menuKeys(x) {
  if (x.C < 60) return [['↑↓', '', ''], ['Enter', '', ''], ['1–9', '', ''], ...(x.instUpd ? [['u', '', '']] : []), ['s', '', ''], ['0', t('выход', 'quit'), t('выход', 'quit')]];
  const k = [['↑↓', '', ''], ['Enter', '', ''], ['1–9', t('сразу', 'jump'), '']];
  if (x.instUpd) k.push(['u', t('обновить', 'update'), '']);
  k.push(['s', '', ''], ['p', t('порты', 'ports'), ''], ['r', t('ключ', 'key'), ''], ['l', t('язык', 'language'), ''], ['0', t('выход', 'quit'), t('выход', 'quit')]);
  return k;
}
/* ---------- защита: два счётчика (вход / выход) и спарклайны ---------- */
const NEXTVER = x => x.st.instVer === '0.9.5' ? '0.9.6' : '1.2.4';
const SG = () => root.GoShield;
const shG = x => x.SH.on && x.SH.vk ? ['✓', 'ok'] : ['!', 'warn'];
const nf = n => SG().nf(n, LANG);
function sparkPair(x, short) {
  const S = SG(), gi = x.SH.on ? ['✓', 'ok'] : ['!', 'warn'], go = x.SH.vk ? ['✓', 'ok'] : ['!', 'warn'];
  const a = [[short ? t('вх ', 'in ') : t('вход ', 'in '), 'in'], [S.spark('in'), 'in']];
  const b = x.SH.vk ? [[short ? t('вых ', 'out ') : t('выход ', 'out '), 'out'], [S.spark('out'), 'out']] : [[short ? t('вых ', 'out ') : t('выход ', 'out '), 'out'], ['! ' + t('выкл', 'off'), 'warn']];
  return { a, b, gi, go };
}
const lineA = x => { const p = sparkPair(x); return [...p.a, [' ', 'text'], p.gi, ['  ', 'text'], ...p.b, ...(x.SH.vk ? [[' ', 'text'], p.go] : [])]; };
function counters(x, n) {
  const S = SG(), P = S.D.per.h24, gi = x.SH.on ? ['✓', 'ok'] : ['!', 'warn'], go = x.SH.vk ? ['✓', 'ok'] : ['!', 'warn'];
  if (!n) return [
    [[rep(' ', 8), 'text'], gi, [' ' + S.IN_L(x.SH.on, LANG) + t(' за сутки: ', ' over 24 h: '), 'text'], [S.att(P.in[0], LANG) + ' · ' + S.adr(P.in[1], LANG), x.SH.on ? 'title' : 'warn']],
    x.SH.vk ? [[rep(' ', 8), 'text'], go, [' ' + S.OUT_L(true, LANG) + t(' за сутки: ', ' over 24 h: '), 'text'], [S.conn(P.out[0], LANG), 'title']] : [[rep(' ', 8), 'text'], go, [' ' + S.OUT_L(false, LANG), 'warn']]];
  return [
    [['  ', 'text'], gi, [' ' + S.IN_L(x.SH.on, LANG) + ': ', 'text'], [nf(P.in[0]) + ' · ' + nf(P.in[1]), x.SH.on ? 'title' : 'warn']],
    x.SH.vk ? [['  ', 'text'], go, [' ' + S.OUT_L(true, LANG) + ': ', 'text'], [nf(P.out[0]), 'title']] : [['  ', 'text'], go, [' ' + t('Выход: защита от утечки IP не работает', 'Out: IP leak protection is not working'), 'warn']],
    [['  ' + t('за сутки: попыток · адресов · соединений', '24 h: attempts · addresses · connections'), 'muted']]];
}
function prodRow80(x, p, i, sel) {
  const f = info(p, x), s = STATUS[f.status];
  const tag = f.upd ? ['↑ ' + t('обновление', 'update'), 'update'] : f.isNew ? ['✚ ' + t('новое', 'new'), 'new'] : ['', 'text'];
  return r([['  ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [(i + 1) + '   ', sel ? 'cursor' : 'muted'], [padR(p.name, 16), sel ? 'title' : 'name'], [s.g + ' ', s.tok], [padR(sw(s), 22), f.status === 'notes' || f.status === 'lite' ? 'warn' : 'text'],
    [padR(f.srv, 8), f.upd ? 'update' : 'text'], [f.upd ? '→ ' : '  ', 'update'], [padR(p.main, 8), f.upd ? 'update' : f.isNew ? 'new' : 'muted'], [' ', 'text'], tag], sel);
}
function prodRow46(x, p, i, sel) {
  const f = info(p, x), s = STATUS[f.status];
  let g = [s.g, s.tok], txt;
  if (f.upd) { g = ['↑', 'update']; txt = [f.srv + ' → ' + p.main, 'update']; }
  else if (f.isNew) { g = ['✚', 'new']; txt = [t('новое · ', 'new · ') + sw(s), 'new']; }
  else if (f.inst) txt = [sw(s) + ' ' + f.srv, 'text'];
  else txt = [sw(s), f.status === 'ready' ? 'text' : 'warn'];
  return r([[sel ? '▸ ' : '  ', 'cursor'], [(i + 1) + ' ', sel ? 'cursor' : 'muted'], [padR(p.name, 15), sel ? 'title' : 'name'], g, [' ', 'text'], txt], sel);
}
function cardRows(x, it, W) {
  const R = [];
  const L = (segs) => R.push(fit(segs, W).segs);
  if (it.kind === 'p') {
    const p = it.p, f = info(p, x), s = STATUS[f.status];
    L(spread([[p.name, 'title']], [[s.g + ' ', s.tok], [sw(s), s.tok === 'muted' ? 'text' : s.tok]], W));
    wrap(t(p.desc[0], p.desc[1]), W).slice(0, 2).forEach(l => L([[l, 'muted']]));
    L([]);
    L([[padR(t('ветка', 'branch'), 8) + padR(t('сервер', 'server'), 10) + 'GitHub', 'muted']]);
    L([[padR('main', 8), 'text'], [padR(f.inst && f.branch === 'main' ? f.srv : '—', 10), f.upd ? 'update' : 'text'], [padR(p.main, 9), f.upd ? 'update' : f.isNew ? 'new' : 'text'], ...(f.upd ? [['↑ ' + t('новее', 'newer'), 'update']] : f.isNew ? [['✚ ' + t('новое', 'new'), 'new']] : [])]);
    L([[padR('dev', 8), 'text'], [padR(f.inst && f.branch === 'dev' ? f.srv : '—', 10), 'text'], [p.dev || t('нет ветки', 'no branch'), 'muted']]);
    L([]);
    if (f.inst) {
      const ports = (p.held || []).map(h => h[0]).join(' ');
      wrap(ports || '—', W - 8).forEach((l, i) => L([[padR(i ? '' : t('порты', 'ports'), 8), 'muted'], [l, 'text']]));
      L([[padR(t('службы', 'units'), 8), 'muted'], ...p.svc.flatMap((u, i) => [[(i ? '  ' : '') + '● ', 'ok'], [u, 'text']])]);
      if (p.id === 'godns' && x.probs) L([[rep(' ', 8), 'text'], ['! ', 'warn'], [t('3 перезапуска за час', '3 restarts in an hour'), 'warn']]);
    } else {
      const v = pf(p.id, p.modes.length ? defMode(p, x) : null);
      const need = v.rows.map(rw => rw.port).join(' ');
      wrap(need, W - 8).slice(0, 2).forEach((l, i) => L([[padR(i ? '' : t('нужны', 'needs'), 8), 'muted'], [l, 'text']]));
      L([[padR(t('проверка', 'check'), 8), 'muted'], verdictTag(v), ...(p.modes.length ? [[' · ' + modeName(defMode(p, x)), 'muted']] : [])]);
    }
    L([]);
    L([[t('что нового', "what's new"), 'muted']]);
    if (f.upd) L([['↑ ', 'update'], [f.srv + ' → ' + p.main + t(' в main', ' in main'), 'text']]);
    else if (f.isNew) L([['✚ ', 'new'], [t('вышел в main, версия ', 'released in main, version ') + p.main, 'text']]);
    else if (f.inst) L([['✓ ', 'ok'], [t('актуален', 'up to date'), 'text']]);
    else L([['○ ', 'muted'], ['main ' + p.main, 'text']]);
    L([]);
    L([[padR(t('команда', 'command'), 8), 'muted'], [p.cmd, 'key']]);
  } else {
    L([[it.label, 'title']]);
    if (it.note) wrap(it.note, W).forEach(l => L([[l, it.noteTok || 'muted']]));
    L([]);
    if (it.key === '7') {
      PRODS.filter(p => info(p, x).inst).forEach(p => (p.held || []).slice(0, 2).forEach(h => L([[padR(h[0], 10), 'text'], [padR(h[1], 9), 'muted'], ['→ ' + p.name, 'muted']])));
    }
    if (it.hot) L([[it.hot, 'key'], [t(' — открыть с любого экрана', ' — opens from any screen'), 'muted']]);
    if (it.key === 'u') L([['u', 'key'], [t(' — обновить из любого экрана', ' — update from any screen'), 'muted']]);
  }
  return R;
}
SCR.menu = x => {
  const items = menuItems(x), cur = Math.min(x.st.cur, items.length - 1), C = x.C;
  const body = x.dir === 'arcade' && x.S.layout === 'panels' ? arcadeMenu(x, items, cur) : [...hdr(x, mainTitle(x), C >= 60 ? 'vpn-fin-1 · Ubuntu 24.04.3 LTS' : 'vpn-fin-1')];
  const alerts = x.probs ? problems() : [];
  if (x.dir === 'arcade' && x.S.layout === 'panels') {
  } else if (C >= 80 && x.S.layout === 'panels') {
    const LW = 36, RW = C - LW - 3;
    const left = [], selIt = items[cur];
    items.forEach((it, i) => {
      const sel = i === cur;
      let segs;
      if (it.kind === 'p') {
        const f = info(it.p, x), s = STATUS[f.status];
        const g = f.upd ? ['↑ ' + it.p.main, 'update'] : f.isNew ? ['✚ ' + t('новое', 'new'), 'new'] : f.inst ? [s.g + ' ' + f.srv, s.tok] : [s.g + ' ' + (f.status === 'ready' ? t('готов', 'ready') : f.status === 'lite' ? 'Lite' : t('готов', 'ready')), s.tok];
        segs = [[' ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + ' ', sel ? 'cursor' : 'muted'], [padR(it.p.name, 16), sel ? 'title' : 'name'], g];
      } else segs = [[' ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + ' ', sel ? 'cursor' : 'muted'], [padR(it.label, 22), sel ? 'title' : (it.tok || 'name')], [it.hot, 'key']];
      const f = fit(segs, LW);
      left.push(f.segs.map(s => [s[0], s[1], sel]).concat([[rep(' ', LW - f.used), 'text', sel]]));
      if (i === 5) left.push([]);
    });
    const right = cardRows(x, selIt, RW);
    const h = Math.max(left.length, right.length, 16);
    body.push(r([]));
    for (let i = 0; i < h; i++) {
      const L0 = left[i] || []; const lf = fit(L0, LW);
      body.push(r([...lf.segs, [rep(' ', LW - lf.used), 'text'], [' │ ', 'rule'], ...(right[i] || [])]));
    }
    body.push(r([]));
    alerts.forEach(p => body.push(r([['  ! ', 'warn'], [p.name + ': ' + p.msg, 'text'], [' → ', 'muted'], [p.step, 'key']])));
  } else if (C >= 80) {
    body.push(r([]));
    body.push(r([[rep(' ', 8) + padR(t('продукт', 'product'), 16) + padR(t('состояние', 'status'), 24) + padR(t('сервер', 'server'), 10) + 'main', 'muted']]));
    items.forEach((it, i) => {
      const sel = i === cur;
      if (it.kind === 'p') body.push(prodRow80(x, it.p, i, sel));
      else {
        let note = [[it.note, it.noteTok || 'muted']];
        if (it.shield && x.SH.variant === 'A') note = lineA(x);
        body.push(r([['  ', 'text'], [sel ? '▸ ' : '  ', 'cursor'], [it.key + '   ', sel ? 'cursor' : 'muted'], [padR(it.label, 24), sel ? 'title' : (it.tok || 'name')], [padR(it.hot, 4), it.key === 'c' ? 'update' : 'key'], ...note], sel));
      }
      if (i === 5) {
        const sp = items[cur];
        if (sp.shield && x.SH.variant !== 'none') counters(x, false).forEach(l => body.push(r(l)));
        else {
          body.push(r(sp.kind === 'p' ? [[rep(' ', 8), 'text'], [t(sp.p.desc[0], sp.p.desc[1]), 'muted'], ['  ·  ', 'rule'], [sp.p.cmd, 'key']] : []));
          body.push(r([]));
        }
      }
    });
    alerts.forEach(p => body.push(r([['  ! ', 'warn'], [p.name + ': ' + p.msg, 'text'], [' → ', 'muted'], [p.step, 'key']])));
  } else {
    items.forEach((it, i) => {
      const sel = i === cur;
      if (it.kind === 'p') body.push(prodRow46(x, it.p, i, sel));
      else body.push(r([[sel ? '▸ ' : '  ', 'cursor'], [it.key + ' ', sel ? 'cursor' : 'muted'], [padR(it.key === '9' ? it.label + ' · ' + it.note : it.label, 34), sel ? 'title' : (it.tok || 'name')], [it.hot, it.key === 'c' ? 'update' : 'key']], sel));
      if (i === 5) {
        const sp = items[cur];
        if (sp.shield && x.SH.variant !== 'none') counters(x, true).forEach(l => body.push(r(l)));
        else {
          body.push(r([]));
          body.push(r(sp.kind === 'p' ? [['  ' + t(sp.p.desc[0], sp.p.desc[1]), 'muted']] : [['  ' + (sp.note || ''), sp.noteTok || 'muted']]));
          body.push(r([]));
        }
      }
    });
    body.push(r(x.SH.variant === 'A' ? [['  ', 'text'], ...lineA(x)] : []));
    alerts.forEach(p => body.push(r([['  ! ', 'warn'], [p.short, 'text']])));
  }
  return { body, items, info: menuInfo(x), keys: menuKeys(x), isRoot: true,
    keymap: [['↑↓', t('водить курсор', 'move the cursor')], ['Enter', t('открыть пункт', 'open the item')], ['1–9', t('открыть сразу', 'open at once')], ...(x.instUpd ? [['u', t('обновить goInstaller', 'update goInstaller')]] : []), ['p', t('карта портов', 'port map')], ['r', t('ключ доступа', 'access key')], ['l', t('язык', 'language')], ['0 · q · Esc', t('выход', 'quit')]] };
};
SCR.product = x => {
  const p = PROD(x.P.id), f = info(p, x), s = STATUS[f.status], n = x.C < 60;
  const body = [...hdr(x, crumbs(x, p.name), n ? null : 'vpn-fin-1'), r([])];
  body.push(r([['  ' + p.name, 'title'], ...(n ? [] : [['  ' + t(p.desc[0], p.desc[1]), 'muted']])]));
  if (n) body.push(r([['  ' + t(p.desc[0], p.desc[1]), 'muted']]));
  const st = [['  ' + s.g + ' ', s.tok], [sw(s), f.status === 'installed' ? 'text' : s.tok]];
  if (f.inst) st.push([' ' + f.srv, 'text'], [' · ' + t('ветка ', 'branch ') + f.branch, 'muted']);
  else st.push([' · main ' + p.main, 'muted']);
  if (f.upd) st.push([' · ', 'muted'], ['↑ ' + t('в main ', 'in main ') + p.main, 'update']);
  if (f.isNew) st.push([' · ', 'muted'], ['✚ ' + t('новое', 'new'), 'new']);
  body.push(r(st), r([]));
  const items = f.inst ? [
    { key:'1', label:t('Открыть меню продукта','Open the product menu'), note:p.cmd, noteTok:'key', act:() => x.A.go('openprod', { id:p.id }) },
    { key:'2', label:t('Обновить или переустановить','Update or reinstall'), note:f.upd ? '↑ ' + p.main + t(' в main', ' in main') : t('версия ', 'version ') + f.srv + t(' актуальна', ' is current'), noteTok:f.upd ? 'update' : 'muted', act:() => x.A.wizard(p.id) },
    { key:'3', label:t('Проверить порты','Check ports'), act:() => x.A.check(p.id) }, BACK(x)
  ] : [
    { key:'1', label:t('Установить','Install'), note:sw(s), noteTok:s.tok === 'muted' ? 'text' : s.tok, act:() => x.A.wizard(p.id) },
    { key:'2', label:t('Проверить порты','Check ports'), act:() => x.A.check(p.id) }, BACK(x)
  ];
  body.push(...choiceRows(x, items, x.st.cur));
  return { body, items, keys: K_NAV(), keymap: K_NAV().map(k => [k[0], k[1]]) };
};
SCR.openprod = x => {
  const p = PROD(x.P.id);
  return { body: [r([['root@vpn-fin-1:~# ', 'text'], [p.cmd, 'text']]), r([]), r([['  ' + t('Здесь открывается меню ', 'The menu of ') + p.name + t('.', ' opens here.'), 'muted']]), r([['  ' + t('Выход из него возвращает в goinstall.', 'Leaving it returns to goinstall.'), 'muted']])],
    items: [BACK(x)], keys: [['0', t('вернуться в goinstall', 'back to goinstall'), t('назад', 'back')]], keymap: [['0', t('назад в goinstall', 'back to goinstall')]] };
};
SCR.mode = x => {
  const p = PROD(x.P.id), def = defMode(p, x), di = p.modes.indexOf(def), n = x.C < 60;
  const items = p.modes.map((m, i) => ({ key: String(i + 1), label: modeName(m), note: modeDesc(p.id, m), tag: verdictTag(pf(p.id, m)), act: () => x.A.go('check', { id: p.id, mode: m, wiz: !x.P.only, only: !!x.P.only }) }));
  items.push(BACK(x));
  const body = [...hdr(x, crumbs(x, p.name), null)];
  body.push(x.P.only ? r([]) : stepsRow(x, wizSteps(p), 0), r([]));
  body.push(r([['  ' + t('Режим ', 'Mode for ') + p.name, 'title']]));
  body.push(r([['  Enter — ' + (di + 1) + ', ' + modeName(def), 'muted']]), r([]));
  body.push(...choiceRows(x, items, x.st.cur, { below: true }));
  return { body, items, defCur: di, keys: K_NAV(), keymap: [...K_NAV().map(k => [k[0], k[1]]), ['Enter', t('без движения — ', 'untouched — ') + modeName(def)]] };
};
SCR.check = x => {
  const p = PROD(x.P.id), mode = x.P.mode, v = pf(p.id, mode), C = x.C, n = C < 60;
  const body = [...hdr(x, crumbs(x, p.name), null)];
  const steps = wizSteps(p);
  body.push(x.P.wiz ? stepsRow(x, steps, steps.indexOf(t('Проверка', 'Check'))) : r([]));
  body.push(r([['  ' + t('Проверка портов', 'Port check'), 'title'], ...(mode ? [[' · ' + t('режим ', 'mode ') + modeName(mode), 'muted']] : [])]));
  if (!n) body.push(r([['  ' + padR(t('порт', 'port'), 10) + '   ' + padR(t('что это', 'what for'), 38) + t('кто держит', 'held by'), 'muted']]));
  v.rows.forEach(rw => {
    const g = PFG[rw.st];
    if (n) body.push(r([['  ' + padR(rw.port, 10), 'text'], g, [' ', 'text'], rw.h && rw.st !== 'ok' ? [rw.h, rw.st === 'bad' ? 'err' : 'text'] : [rw.d, 'muted']]));
    else body.push(r([['  ' + padR(rw.port, 10), 'text'], g, ['  ', 'text'], [padR(rw.d, 37) + ' ', 'text'], [rw.h, rw.st === 'bad' ? 'err' : rw.st === 'ok' ? 'muted' : 'text']]));
  });
  body.push(r([]));
  v.rules.forEach(rl => wrap(rl[2], C - 6).forEach((l, i) => body.push(r([['  ' + (i ? ' ' : rl[0]) + ' ', rl[1]], [l, 'text']]))));
  body.push(r([['  ' + v.verdict[0] + ' ', v.verdict[1]], [v.verdict[2], v.verdict[1] === 'err' ? 'err' : 'title']]));
  body.push(r([]));
  let items;
  if (x.P.wiz) {
    items = v.bad ? [...(p.modes.length ? [{ key: '1', label: t('Выбрать другой режим', 'Pick another mode'), act: x.A.back }] : []), BACK(x)]
      : [{ key: '1', label: t('Продолжить', 'Continue'), note: p.dev ? t('дальше — выбор ветки', 'next: branch') : t('дальше — подтверждение', 'next: confirm'), act: () => p.dev ? x.A.go('branch', { id: p.id, mode }) : x.A.go('confirm', { id: p.id, mode, branch: 'main' }) }, BACK(x)];
  } else {
    items = [...(p.modes.length ? [{ key: '1', label: t('Проверить другой режим', 'Check another mode'), act: () => x.A.go('mode', { id: p.id, only: true }) }] : []), BACK(x)];
  }
  body.push(...choiceRows(x, items, x.st.cur));
  return { body, items, info: n ? [['  ✓ ' + t('свой · ✗ препятствие · ! замечание', 'own · ✗ obstacle · ! note'), 'muted']] : [['  ✓ ' + t('свободен или свой · ✗ занят, препятствие · ! занят, замечание · · к сведению', 'free or own · ✗ taken, obstacle · ! taken, note · · for info'), 'muted']],
    keys: K_NAV(), keymap: [...K_NAV().map(k => [k[0], k[1]]), ['p', t('карта портов', 'port map')]] };
};
SCR.branch = x => {
  const p = PROD(x.P.id), f = info(p, x);
  const mainNote = t('стабильная', 'stable') + (f.inst ? t('; сейчас стоит ', '; installed now ') + f.srv : '') + (f.upd ? t('; ↑ новее', '; ↑ newer') : '');
  const items = [
    { key: '1', label: 'main ' + p.main, note: mainNote, act: () => x.A.go('confirm', { id: p.id, mode: x.P.mode, branch: 'main' }) },
    { key: '2', label: 'dev ' + p.dev, note: t('экспериментальная', 'experimental'), act: () => x.A.go('confirm', { id: p.id, mode: x.P.mode, branch: 'dev' }) }, BACK(x)];
  const steps = wizSteps(p);
  const body = [...hdr(x, crumbs(x, p.name), null), stepsRow(x, steps, steps.indexOf(t('Ветка', 'Branch'))), r([]),
    r([['  ' + t('Ветка ', 'Branch for ') + p.name, 'title']]), r([['  Enter — 1, main', 'muted']]), r([]), ...choiceRows(x, items, x.st.cur, { below: true })];
  return { body, items, keys: K_NAV(), keymap: [...K_NAV().map(k => [k[0], k[1]]), ['Enter', t('без движения — main', 'untouched — main')]] };
};
SCR.confirm = x => {
  const p = PROD(x.P.id), br = x.P.branch, ver = br === 'dev' ? p.dev : p.main, C = x.C;
  const items = [{ key: '1', label: t('Да', 'Yes'), act: () => x.A.replace('installing', x.P) }, { key: '2', label: t('Нет', 'No'), act: () => x.A.backTo('product') }];
  const steps = wizSteps(p);
  const q = t('Запустить установщик ', 'Run the installer of ') + p.name + ' — ' + t('ветка ', 'branch ') + br + ', ' + ver + '?';
  const body = [...hdr(x, crumbs(x, p.name), null), stepsRow(x, steps, steps.indexOf(t('Установка', 'Install'))), r([])];
  wrap(q, C - 4).forEach(l => body.push(r([['  ' + l, 'title']])));
  body.push(r([['  Enter — 1, ' + t('Да', 'Yes'), 'muted']]), r([]), ...choiceRows(x, items, x.st.cur));
  body.push(r([]));
  if (x.P.mode) body.push(r([['  ' + t('режим ', 'mode ') + modeName(x.P.mode), 'muted']]));
  body.push(r([['  ✓ ', 'ok'], [t('проверка портов пройдена', 'port check passed'), 'muted']]));
  return { body, items, keys: [['1', t('да', 'yes'), ''], ['2', t('нет', 'no'), ''], ['Enter', '1', '1']], keymap: [['1', t('да', 'yes')], ['2 · 0', t('нет, назад к продукту', 'no, back to the product')], ['Enter', t('да', 'yes')]], back: () => x.A.backTo('product') };
};
SCR.installing = x => {
  const p = PROD(x.P.id), el = x.now - x.st.t0, steps = wizSteps(p), fr = SPIN[Math.floor(x.now / 100) % 10];
  const body = [...hdr(x, crumbs(x, p.name), null), stepsRow(x, steps, steps.indexOf(t('Установка', 'Install'))), r([]),
    r([['  → ', 'cursor'], [t('Управление передано установщику ', 'Handed over to the installer of ') + p.name, 'text']]),
    r([['    ' + p.cmd + ' · ' + t('ветка ', 'branch ') + x.P.branch + (x.P.mode ? ' · ' + modeName(x.P.mode) : ''), 'muted']]),
    r([['    ' + t('Его вопросы и вывод идут ниже как есть.', 'Its questions and output follow as is.'), 'muted']]), r([]),
    r([['  ' + fr + ' ', 'cursor'], [t('установщик продукта работает · ', 'product installer running · ') + Math.floor(el / 1000) + t(' с', ' s'), 'muted']])];
  return { body, anim: true, tick: () => { if (el > 2600) x.A.finishInstall(x.P); }, keymap: [['—', t('ввод принадлежит установщику продукта', 'input belongs to the product installer')]], onKey: () => true };
};
SCR.result = x => {
  const p = PROD(x.P.id), f = info(p, x), steps = wizSteps(p), C = x.C, mism = x.P.mismatch;
  const body = [...hdr(x, crumbs(x, p.name), null), stepsRow(x, steps, steps.length - 1), r([])];
  const L = (g, tok, text, tt) => wrap(text, C - 6).forEach((l, i) => body.push(r([['  ' + (i ? ' ' : g) + ' ', tok], [l, tt || 'text']])));
  if (mism) {
    L('!', 'warn', t('Ветка не сменилась: ', 'Branch did not change: ') + p.name + t(' стоит с ветки ', ' runs from branch ') + f.branch + t(', а выбрана ', ', but ') + x.P.branch + t('', ' was chosen'), 'title');
    L(' ', 'muted', t('Повторите установку или смените ветку в меню продукта: ', 'Run the install again or switch the branch in the product menu: ') + p.cmd, 'muted');
  } else L('✓', 'ok', t('Проверено: ', 'Verified: ') + p.name + t(' стоит с ветки ', ' runs from branch ') + f.branch + t(', версия ', ', version ') + f.srv, 'title');
  if (x.P.lazy) { body.push(r([])); L('!', 'warn', t('Ленивый pro встал в режиме Semi-pro', 'Lazy pro ended up in Semi-pro mode'), 'title'); L(' ', 'muted', t('UDP 443 был занят. Режим меняется в меню продукта: goamnezia', 'UDP 443 was taken. Change the mode in the product menu: goamnezia'), 'muted'); }
  body.push(r([]));
  const items = [{ key: '1', label: t('Открыть меню продукта', 'Open the product menu'), note: p.cmd, noteTok: 'key', act: () => x.A.go('openprod', { id: p.id }) }, { key: '0', label: t('В главное меню', 'Main menu'), act: () => x.A.root('menu') }];
  body.push(...choiceRows(x, items, x.st.cur));
  return { body, items, keys: K_NAV(), keymap: K_NAV().map(k => [k[0], k[1]]), back: () => x.A.root('menu') };
};
SCR.ports = x => {
  const C = x.C, n = C < 60;
  const body = [...hdr(x, [[t('Кто какие порты держит', 'Who holds which ports'), TT(x)]], n ? null : 'goinstall --ports')];
  if (!n) body.push(r([['  ' + padR(t('порт', 'port'), 11) + padR(t('процесс', 'process'), 12) + t('что это', 'what for'), 'muted']]));
  const group = (name, rows) => { body.push(r([['  ' + name, 'title']])); rows.forEach(h => body.push(r([['    ' + padR(h[0], n ? 10 : 11), 'text'], [padR(h[1], n ? 9 : 12), 'key'], [t(h[2][0], h[2][1]), 'muted']]))); };
  PRODS.filter(p => info(p, x).inst && p.held.length).forEach(p => group(p.name, p.held));
  group(t('система', 'system'), [['22/tcp', 'sshd', ['SSH', 'SSH']], ['53/udp', 'resolved', ['loopback: 127.0.0.53', 'loopback: 127.0.0.53']]]);
  return { body, items: [BACK(x)], keys: [['0', t('назад', 'back'), t('назад', 'back')]], keymap: [['0 · Esc', t('назад', 'back')]], noP: true };
};
SCR.key = x => {
  const n = x.C < 60, chk = x.st.keyCheck, el = chk ? x.now - chk : 1e9;
  const body = [...hdr(x, [[t('Ключ доступа', 'Access key'), TT(x)]], null), r([])];
  body.push(r([['  ● ', 'ok'], [t('сохранён', 'saved'), 'text'], [' · /opt/go-installer/token', 'muted']]));
  if (el < 900) body.push(r([['  ' + SPIN[Math.floor(x.now / 100) % 10] + ' ', 'cursor'], [t('проверяю доступ к 6 репозиториям…', 'checking access to 6 repositories…'), 'muted']]));
  else if (x.probs) {
    body.push(r([['  ! ', 'warn'], [t('открывает 5 из 6: goAmnezia pro — нет доступа', 'opens 5 of 6: goAmnezia pro — no access'), 'text']]));
    wrap(t('Возьмите свежий ключ в «anten-ka club», ветка «goinstall», и введите его пунктом 2.', 'Get a fresh key in “anten-ka club”, topic “goinstall”, and enter it via item 2.'), x.C - 6).forEach(l => body.push(r([['    ' + l, 'muted']])));
  } else body.push(r([['  ✓ ', 'ok'], [t('открывает 6 из 6 · проверен в ', 'opens 6 of 6 · checked at ') + (chk ? '14:07' : x.sved), 'text']]));
  body.push(r([]));
  const items = [{ key: '1', label: t('Проверить ключ', 'Check the key'), act: () => x.A.checkKey() }, { key: '2', label: t('Ввести новый ключ', 'Enter a new key'), act: () => x.A.go('keyinput') }, { key: '3', label: t('Удалить ключ', 'Forget the key'), note: 'goinstall --key forget', act: () => x.A.root('nokey') }, BACK(x)];
  body.push(...choiceRows(x, items, x.st.cur));
  return { body, items, anim: el < 1000, keys: K_NAV(), keymap: K_NAV().map(k => [k[0], k[1]]), noR: true };
};
SCR.keyinput = x => {
  const v = x.st.input || '', chk = x.st.keyCheck, el = chk ? x.now - chk : -1;
  const body = [...hdr(x, [[t('Ключ доступа', 'Access key'), TT(x)]], null), r([]),
    r([['  ' + t('Вставьте ключ и нажмите Enter.', 'Paste the key and press Enter.'), 'text']]),
    r([['  ' + t('Он сохранится в /opt/go-installer/token, режим 0600.', 'It is saved to /opt/go-installer/token, mode 0600.'), 'muted']]), r([]),
    r([['  ' + t('ключ: ', 'key: '), 'muted'], [rep('*', Math.min(v.length, x.C - 12)), 'text'], ['█', 'cursor']]), r([])];
  if (el >= 0 && el < 900) body.push(r([['  ' + SPIN[Math.floor(x.now / 100) % 10] + ' ', 'cursor'], [t('проверяю…', 'checking…'), 'muted']]));
  if (el >= 900) body.push(r([['  ✓ ', 'ok'], [t('ключ подошёл: открывает 6 из 6', 'the key works: opens 6 of 6'), 'text']]));
  return { body, anim: el >= 0 && el < 1400, tick: () => { if (el >= 1400) x.A.keyDone(); },
    keys: [['Enter', t('сохранить', 'save'), ''], ['Esc', t('назад', 'back'), t('назад', 'back')]], keymap: [[t('символы', 'chars'), t('ввод ключа, на экране звёздочки', 'key input, shown as asterisks')], ['Enter', t('проверить и сохранить', 'check and save')], ['Esc', t('назад', 'back')]],
    input: true };
};
SCR.nokey = x => {
  const C = x.C;
  const txt = t('Ключ на чтение выдаётся подписчикам в закрытой группе «anten-ka club», в ветке «goinstall». Подписка: boosty.to/anten-ka',
    'A read key is given to subscribers in the private “anten-ka club” group, topic “goinstall”. Subscription: boosty.to/anten-ka');
  const inner = [[[t('Репозитории продуктов закрытые: без ключа не скачивается ни один.', 'Product repositories are private: nothing downloads without a key.'), 'text']], []];
  wrap(txt, C - 6).forEach(l => inner.push([[l, 'muted']]));
  const inW = inner.map(l => l.length ? [[' ', 'text'], ...l] : l);
  const body = [...hdr(x, mainTitle(x), null), r([]), ...box(x, [[t('Нужен ключ доступа', 'An access key is needed'), 'warn']], null, inW, [['goinstall --key set', 'key']]), r([])];
  const items = [{ key: '1', label: t('Ввести ключ', 'Enter the key'), act: () => x.A.go('keyinput') }, { key: '0', label: t('Выход', 'Quit'), act: () => x.A.exit() }];
  body.push(...choiceRows(x, items, x.st.cur));
  return { body, items, keys: K_NAV(), keymap: [['1', t('ввести ключ', 'enter the key')], ['0 · q', t('выход', 'quit')]], back: () => x.A.exit() };
};
SCR.lang = x => {
  const items = [{ key: '1', label: 'Русский', act: () => x.A.setLang('ru') }, { key: '2', label: 'English', act: () => x.A.setLang('en') }, BACK(x)];
  const di = x.S.lang === 'en' ? 1 : 0;
  const body = [...hdr(x, mainTitle(x), null), r([]), r([['  Язык / Language', 'title']]), r([['  Enter — ' + (di + 1) + ', ' + (di ? 'English' : 'Русский'), 'muted']]), r([]), ...choiceRows(x, items, x.st.cur)];
  return { body, items, defCur: di, keys: [['1', 'Русский', ''], ['2', 'English', ''], ['0', t('назад', 'back'), '']], keymap: [['1', 'Русский'], ['2', 'English'], ['Enter', t('текущий язык', 'current language')], ['0', t('назад', 'back')]], noL: true };
};
SCR.selfupd = x => {
  const ph = x.P.phase, el = x.now - x.st.t0, C = x.C;
  const body = [...hdr(x, [[t('Обновить goInstaller', 'Update goInstaller'), TT(x)]], null), r([])];
  if (!ph) {
    body.push(r([['  goInstaller ', 'title'], [x.st.instVer, 'text'], [' → ', 'muted'], ['0.9.6', 'update'], [t(' · ветка main', ' · branch main'), 'muted']]), r([]));
    body.push(r([['  ' + t('Запустить обновление?', 'Run the update?'), 'title']]), r([['  Enter — 1, ' + t('Да', 'Yes'), 'muted']]), r([]));
    const items = [{ key: '1', label: t('Да', 'Yes'), act: () => x.A.replace('selfupd', { phase: 1 }) }, { key: '2', label: t('Нет', 'No'), act: x.A.back }];
    body.push(...choiceRows(x, items, x.st.cur));
    return { body, items, keys: [['1', t('да', 'yes'), ''], ['2', t('нет', 'no'), ''], ['0', t('назад', 'back'), '']], keymap: [['1 · Enter', t('да', 'yes')], ['2 · 0', t('нет', 'no')]] };
  }
  const fr = Math.min(1, el / 1200);
  body.push(r([['  go-installer.sh  ', 'text'], ...bar(fr, C < 60 ? 16 : 30, 'cursor'), ['  ' + Math.round(fr * 100) + ' %', 'muted']]));
  if (fr >= 1) { body.push(r([])); body.push(r([['  ✓ ', 'ok'], [t('goInstaller обновлён: 0.9.6. Перезапускаю меню.', 'goInstaller updated to 0.9.6. Restarting the menu.'), 'text']])); }
  return { body, anim: true, tick: () => { if (el > 1700) x.A.selfDone(); }, keymap: [['—', t('ждём конца загрузки', 'waiting for the download')]], onKey: () => true };
};
function errScreen(x, kind) {
  const C = x.C, gh = kind === 'github';
  const body = [...hdr(x, mainTitle(x), null), r([])];
  const W = C - 6;
  body.push(r([['  ' + (gh ? '✗ ' : '! '), gh ? 'err' : 'warn'], [gh ? t('GitHub недоступен', 'GitHub is unreachable') : t('Лимит запросов к GitHub исчерпан, повтор в 15:00', 'GitHub rate limit reached, retry at 15:00'), 'title']]), r([]));
  const lines = gh ? [t('Новые версии узнать не удалось. Меню откроется со сведениями от 14:05.', 'Could not fetch new versions. The menu opens with data as of 14:05.'), t('Проверьте сеть сервера: curl -I https://api.github.com', 'Check the server network: curl -I https://api.github.com')]
    : [t('Ответили 5 из 8. Остальное меню покажет по сведениям от 14:05.', '5 of 8 answered. The rest shows data as of 14:05.'), t('В 15:00 goinstall спросит GitHub сам.', 'At 15:00 goinstall asks GitHub again by itself.')];
  lines.forEach(tx => wrap(tx, W).forEach(l => body.push(r([['    ' + l, 'text']]))));
  body.push(r([]));
  const items = [{ key: '1', label: t('Открыть меню со сведениями от 14:05', 'Open the menu with data as of 14:05'), act: () => x.A.root('menu') }, { key: '2', label: t('Повторить опрос', 'Retry the poll'), act: () => x.A.retryPoll() }, { key: '0', label: t('Выход', 'Quit'), act: () => x.A.exit() }];
  body.push(...choiceRows(x, items, x.st.cur));
  return { body, items, keys: K_NAV(), keymap: [['1 · Enter', t('меню со старыми сведениями', 'menu with old data')], ['2', t('повторить', 'retry')], ['0 · q', t('выход', 'quit')]], back: () => x.A.exit() };
}
SCR.err_github = x => errScreen(x, 'github');
SCR.err_rate = x => errScreen(x, 'rate');
SCR.small = x => {
  const body = [r([['goinstall: ' + t('окно 40 × 16', 'window 40 × 16'), 'title']]), r([]),
    r([[t('Нужно не меньше 46 × 24.', 'Needs at least 46 × 24.'), 'text']]), r([[t('Растяните окно или уменьшите шрифт.', 'Enlarge the window or shrink the font.'), 'muted']]), r([]),
    r([[t('Без меню: ', 'Without the menu: '), 'muted'], ['goinstall --list', 'key']]), r([]), r([['q', 'key'], [t(' — выход', ' — quit'), 'muted']])];
  return { body, cols: 40, rows: 16, keymap: [['q', t('выход', 'quit')], [t('ресайз', 'resize'), t('меню нарисуется само', 'the menu redraws itself')]], onKey: k => { if (k === 'q' || k === 'Escape') x.A.exit(); else x.A.root('menu'); return true; } };
};

/* ---------- jump list ---------- */
const JUMPS = [
  ['А · Вход', [['a1', 'Сводка при входе', { scr: 'login' }], ['a2', 'Сводка: всё актуально', { scr: 'login', S: { scen: 'ok' } }], ['b', 'Вход с отсчётом', { scr: 'countdown' }]]],
  ['В · Заставка', [['v1', 'Опрос GitHub', { scr: 'splash', poll: true }], ['v2', 'Что нового', { scr: 'splash' }]]],
  ['Г · Меню', [['g1', 'Список', { scr: 'menu', S: { layout: 'list' } }], ['g2', 'Две панели', { scr: 'menu', S: { layout: 'panels', cols: 80 } }]]],
  ['Д · Продукт', [['d1', 'Установлен: goTelegram pro', { scr: 'product', P: { id: 'gotelegram' }, stack: ['menu'] }], ['d2', 'Не установлен: goAmnezia pro', { scr: 'product', P: { id: 'goamnezia' }, stack: ['menu'] }]]],
  ['Е · Проверка', [['e1', 'goAmnezia pro, режим pro', { scr: 'check', P: { id: 'goamnezia', mode: 'pro', wiz: true }, stack: ['menu', 'product:goamnezia', 'mode:goamnezia'] }], ['e2', 'goAmnezia pro, режим Lite', { scr: 'check', P: { id: 'goamnezia', mode: 'lite', wiz: true }, stack: ['menu', 'product:goamnezia', 'mode:goamnezia'] }]]],
  ['Ж · Вопросы', [['z1', 'Язык', { scr: 'lang', stack: ['menu'] }], ['z2', 'Режим goAmnezia pro', { scr: 'mode', P: { id: 'goamnezia' }, stack: ['menu', 'product:goamnezia'] }], ['z3', 'Ветка goTelegram pro', { scr: 'branch', P: { id: 'gotelegram', mode: 'lite' }, stack: ['menu', 'product:gotelegram'] }], ['z4', 'Подтверждение', { scr: 'confirm', P: { id: 'gotelegram', mode: 'lite', branch: 'main' }, stack: ['menu', 'product:gotelegram'] }]]],
  ['З · Итог', [['i1', 'Успех', { scr: 'result', P: { id: 'gotelegram', branch: 'main' }, over: { gotelegram: { srv: '2.10.49', branch: 'main', mode: 'lite' } } }], ['i2', 'Ветка не сменилась', { scr: 'result', P: { id: 'gotelegram', branch: 'main', mismatch: true }, over: { gotelegram: { srv: '2.10.49', branch: 'dev', mode: 'lite' } } }], ['i3', 'Ленивый pro → Semi-pro', { scr: 'result', P: { id: 'goamnezia', branch: 'main', lazy: true }, over: { goamnezia: { srv: '1.0.2', branch: 'main', mode: 'lite_site' } } }]]],
  ['И · Порты', [['p', 'Карта портов', { scr: 'ports', stack: ['menu'] }]]],
  ['К · Ошибки', [['k1', 'Нет ключа', { scr: 'nokey' }], ['k2', 'GitHub недоступен', { scr: 'err_github' }], ['k3', 'Лимит запросов', { scr: 'err_rate' }], ['k4', 'Окно слишком мало', { scr: 'small' }], ['k5', 'Терминал без UTF-8', { scr: 'menu', S: { cs: 'ascii' } }], ['k6', 'Ключ не открывает продукт', { scr: 'key', S: { scen: 'problems' }, stack: ['menu'] }]]],
  ['Идеи', [['x1', 'Значок в приглашении', { scr: 'login', S: { scen: 'problems' } }], ['x2', 'Мастер со ступенями', { scr: 'mode', P: { id: 'goamnezia' }, stack: ['menu', 'product:goamnezia'] }]]]
];

const DEF_S = { dir: 'arcade', cols: 80, color: 'true', bg: 'dark', cs: 'utf8', lang: 'ru', layout: 'panels', scen: 'problems', fresh: false, err: 'none', entry: 'summary', result: 'ok' };
const STORE = 'goinstaller-proto-v2';
const RUKEYS = { 'з':'p', 'к':'r', 'д':'l', 'г':'u', 'й':'q', 'З':'p', 'К':'r', 'Д':'l', 'Г':'u', 'Й':'q' };


/* ---------- сборка главного меню ---------- */
const NOOPA = new Proxy({}, { get: () => () => {} });
function buildMenu(o) {
  LANG = o.lang || 'ru';
  const C = o.C, S = { lang: LANG, cols: C, dir: 'arcade', layout: C >= 80 ? (o.layout || 'panels') : 'list', scen: o.scen || 'problems' };
  const st = { scr: 'menu', P: {}, stack: [], cur: o.cur || 0, over: {}, sved: '14:05', instVer: o.ver || '1.2.3', poll: null, pollErr: null };
  const x = { S, st, C, dir: 'arcade', now: 0, P: {}, A: o.A || NOOPA, SH: { on: o.on !== false, vk: o.vk !== false, variant: o.variant || 'A', chart: o.chart || 'fly', row: o.row } };
  x.news = S.scen !== 'ok'; x.probs = S.scen === 'problems';
  x.tgUpd = info(PROD('gotelegram'), x).upd; x.amNew = info(PROD('goamnezia'), x).isNew;
  x.instUpd = x.news; x.sved = st.sved;
  const scr = SCR.menu(x), R = 24;
  const foot = [r(scr.info), r(keysRow(x, scr.keys))];
  let body = scr.body.slice(0, R - 2); while (body.length < R - 2) body.push(r([]));
  body = body.concat(foot);
  const rows = body.map(row => { const f = fit(row.segs, C); return { segs: (row.sel ? [...f.segs, [rep(' ', C - f.used), 'text']] : f.segs).filter(q => q[0].length), sel: row.sel }; });
  return { rows, items: scr.items, C, R, layout: S.layout,
    keymap: [['↑↓', t('водить курсор', 'move the cursor')], ['Enter', t('открыть пункт', 'open the item')], ['1–9 · c s u x', t('открыть сразу', 'open at once')], ['s', t('меню «Защита»', 'protection menu')], ['p · r · l', t('порты · ключ · язык', 'ports · key · language')], ['0 · q · Esc', t('выход', 'quit')]] };
}
const txt = rows => rows.map(rw => rw.segs.map(q => q[0]).join(''));
function diff(o) {
  const a = txt(buildMenu(o).rows), b = txt(buildMenu({ ...o, variant: 'none', ver: o.ver }).rows);
  return a.map((l, i) => l !== b[i] ? i + 1 : 0).filter(Boolean);
}
function toJSON(o, id) {
  const m = buildMenu(o);
  return { id, label: (o.C >= 80 && m.layout === 'panels') ? 'Две панели' : 'Меню-список', variant: o.variant, chart: o.chart || 'fly', cursor: m.items[o.cur || 0].key, state: o.scen || 'problems',
    screen: 'menu', dir: 'arcade', lang: o.lang, cols: o.C, rows_max: 24, ver: o.ver || '1.2.3', shield_rows: diff(o),
    rows: m.rows.map(rw => rw.segs.map(q => [q[0], q[1] + (rw.sel || q[2] ? '+sel' : '')])) };
}
function allMenu(lang) {
  const out = [];
  ['A', 'B'].forEach(v => [['g2', 80, 'panels'], ['g1', 80, 'list'], ['g1', 46, 'list']].forEach(([id, C, layout]) => [0, 10].forEach(cur => {
    out.push(toJSON({ lang, C, layout, cur, variant: v, chart: 'fly' }, id));
    if (id === 'g2' && cur === 10) out.push({ ...toJSON({ lang, C, layout, cur, variant: v, chart: 'bars' }, id), chart: 'bars' });
  })));
  return out;
}
root.GoMenu = { build: buildMenu, diff, toJSON, all: allMenu, sIndex: 10 };
})(typeof window !== 'undefined' ? window : globalThis);

# Данные для замера статистики защиты (REVIEW-6 №1): bench.sh и тест набора.
# gen.py <каталог> <адресов в базе> <now>
# Пишет: <каталог>/st (stats/ с базой addrs на N строк), <каталог>/live
# (листинг nft -a: seen4 65536 + seen6 16384 со счётчиками, pair4 32768,
# pair6 16384, ports 8192, scan4 30000), <каталог>/own (lists/owners, 30 тыс. сетей).
import os, random, sys
d, N, now = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
random.seed(7)
st = os.path.join(d, 'st')
os.makedirs(st, exist_ok=True)
def v4(i):
    return '45.%d.%d.%d' % ((i >> 16) & 63, (i >> 8) & 255, i & 255)
def v6(i):
    return '2a00:%x:%x:%x::' % ((i >> 32) & 0xffff, (i >> 16) & 0xffff, i & 0xffff)
# lists/owners: 30 тыс. сетей /24 из 45.0.0.0/10 по 3000 AS.
with open(os.path.join(d, 'own'), 'w') as f:
    for i in range(30000):
        f.write('45.%d.%d.0/24\t%d\tNET-%d EXAMPLE (Org %d)\n' % ((i >> 8) & 63, i & 255, 64500 + i % 3000, i % 3000, i % 3000))
# База адресов: N строк, адрес first last att oid cnt gen lasth lastd lastport.
pp = ['22/tcp', '443/tcp', '80/tcp', '3389/tcp', '8080/tcp', '53/udp']
rows = []
for i in range(N):
    ad = v4(i * 7 + 3) if i % 5 else v6(i)
    last = now - 3600 - random.randint(0, 35 * 86400)
    first = last - random.randint(0, 5 * 86400)
    rows.append('%s %d %d %d %d %d %d %d %d %s' % (ad, first, last, random.randint(1, 500), 1 + i % 3000, random.randint(0, 50), 1,
                                                    last - last % 3600, 20261101, random.choice(pp)))
with open(os.path.join(st, 'addrs'), 'w') as f:
    f.write('\n'.join(rows) + '\n')
with open(os.path.join(st, 'owners'), 'w') as f:
    for k in range(1, 3001):
        f.write('%d %d NET-%d EXAMPLE (Org %d)\n' % (k, 64500 + k - 1, k - 1, k - 1))
prev = now - 3600
with open(os.path.join(st, 'meta'), 'w') as f:
    f.write('started=%d\nsnap=%d\nkey=b1:23\ngen=1\nlvl=3\nc_in4=1000\nc_in6=10\nc_out_fwd=0\nc_out_srv=0\ntin=5000000\ntfw=0\ntsr=0\nnaddr=%d\n'
            % (now - 40 * 86400, prev, N))
with open(os.path.join(st, 'hours'), 'w') as f:
    for h in range(40 * 24):
        f.write('%d %d 50 10 40 0 1\n' % (now - now % 3600 - h * 3600, random.randint(100, 9000)))
def dur(s):
    o = ''
    for u, k in (('d', 86400), ('h', 3600), ('m', 60), ('s', 1)):
        if s >= k:
            o += '%d%s' % (s // k, u); s %= k
    return o or '0s'
out = ['table inet goinstall_shield { # handle 23']
for c, v in (('in4', 9000000), ('in6', 20000), ('out_fwd', 30), ('out_srv', 10)):
    out.append('\tcounter %s { # handle 5\n\t\tpackets %d bytes 0\n\t}\n' % (c, v))
sc = ', '.join('45.%d.%d.0/24' % ((i >> 8) & 63, i & 255) for i in range(30000))
out.append('\tset scan4 { # handle 7\n\t\ttype ipv4_addr\n\t\tflags interval\n\t\tauto-merge\n\t\telements = { ' + sc + ' }\n\t}\n')
def sset(name, typ, size, tmo, els):
    out.append('\tset %s { # handle 9\n\t\ttype %s\n\t\tsize %d\n\t\tflags dynamic%s' % (name, typ, size, ',timeout' if tmo else ''))
    if tmo:
        out.append('\t\ttimeout %s' % dur(tmo))
    out.append('\t\telements = { ' + ',\n\t\t\t     '.join(els) + ' }\n\t}\n')
T = 35 * 86400
# Половина seen — уже в базе, половина — новые; все обновлены после прошлого снимка.
sset('seen4', 'ipv4_addr', 65536, T, ['%s timeout 35d expires %s counter packets %d bytes 0'
     % (v4((i * 7 + 3) if i % 2 else (10 ** 6 + i)), dur(T - random.randint(1, 3000)), random.randint(1, 900)) for i in range(65536)])
sset('seen6', 'ipv6_addr', 16384, T, ['%s timeout 35d expires %s counter packets %d bytes 0'
     % (v6(5 * i if i % 2 else 10 ** 7 + i), dur(T - random.randint(1, 3000)), random.randint(1, 900)) for i in range(16384)])
sset('ports', 'inet_proto . inet_service', 8192, 7200, ['%s . %d timeout 2h expires 1h%dm counter packets %d bytes 0'
     % ('tcp' if i % 3 else 'udp', 1 + i, 10 + i % 50, random.randint(1, 5000)) for i in range(8192)])
sset('pair4', 'ipv4_addr . inet_proto . inet_service', 32768, 7200, ['%s . tcp . %d timeout 2h expires 1h%dm'
     % (v4(10 ** 6 + i), 1 + i % 2000, random.randint(10, 59)) for i in range(32768)])
sset('pair6', 'ipv6_addr . inet_proto . inet_service', 16384, 7200, ['%s . tcp . %d timeout 2h expires 1h%dm'
     % (v6(10 ** 7 + i), 1 + i % 2000, random.randint(10, 59)) for i in range(16384)])
out.append('\tchain incoming { # handle 30\n\t\ttype filter hook prerouting priority -150; policy accept;\n\t}\n}')
with open(os.path.join(d, 'live'), 'w') as f:
    f.write('\n'.join(out) + '\n')

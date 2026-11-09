#!/bin/bash
# Замер снимка и отчёта статистики защиты на большой базе (REVIEW-6 №1).
#   bench.sh <go-installer.sh> [адресов в базе, 200000] [python, python3]
# Данные — gen.py: база addrs на N строк, листинг nft со всеми наборами
# полными (seen4 65536 + seen6 16384, все обновлены за час; pair4 32768,
# pair6 16384; ports 8192), список владельцев на 30 тыс. сетей. Худший
# случай для снимка. Печатает пик памяти (maxRSS) и ЦП (user+sys) каждой
# команды. Работает на Linux и macOS; ничего вне временного каталога не трогает.
set -u
src="$1"; N="${2:-200000}"; PY="${3:-python3}"
B=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/shield-bench.XXXXXX")
trap 'rm -rf "$W"' EXIT
awk '/^_shield_spy\(\) \{/ {f=1; next} f && /<<.SPY.$/ {g=1; next} g && /^SPY$/ {exit} g' "$src" > "$W/spy.py"
cat > "$W/rss.py" <<'PY'
import resource, subprocess, sys
r = subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
u = resource.getrusage(resource.RUSAGE_CHILDREN)
m = u.ru_maxrss if sys.platform == 'darwin' else u.ru_maxrss * 1024
print('rc=%d rss=%.1f МБ cpu=%.2f с' % (r, m / 1048576.0, u.ru_utime + u.ru_stime))
PY
NOW=1793714400
"$PY" -I "$B/gen.py" "$W" "$N" "$NOW"
printf 'scan=1\nvk=1\nhost=bench\n' > "$W/info"
m() { printf '%-22s ' "$1"; shift; "$PY" -I "$W/rss.py" "$PY" -I "$W/spy.py" "$@"; }
m "snap (новый ключ)" snap "$W/st" "$W/live" "$W/own" b2 $((NOW + 600))
m "snap (тот же ключ)" snap "$W/st" "$W/live" "$W/own" b2 $((NOW + 4200))
m "report full" report "$W/st" full 80 ru "$W/info" $((NOW + 4300))
m "top 30d" top "$W/st" 30d 80 ru "$W/info" $((NOW + 4300))
m "size" size "$W/st" ru
echo "строк в базе: $(grep -c '' "$W/st/addrs"), всего адресов: $(sed -n 's/^naddr=//p' "$W/st/meta"); $("$PY" --version 2>&1)"

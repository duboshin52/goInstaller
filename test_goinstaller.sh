#!/bin/bash
# Тесты goInstaller. Нужен bash 4.0+ (на macOS штатный 3.2 — запускать на
# Ubuntu или через /opt/homebrew/bin/bash). Ничего в системе не трогает:
# порты берутся из фикстур (GOINST_SS_FIXTURE), юниты — из таблицы
# pid=unit (GOINST_UNIT_FIXTURE), ОС — из подложенного os-release.
set -uo pipefail

# Базовый набор проверяет прежний режим закрытых репозиториев.
# Публичный режим проверяется отдельно.
export GOINST_PUBLIC=0

if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "SKIP: нужен bash 4.0+ (найден ${BASH_VERSION:-?})"; exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/go-installer.sh"
# Версия скрипта — в тестах переменной: зашитый номер пришлось бы менять с
# каждым выпуском, и подъём версии прятался бы за правкой тестов.
GIV=$(sed -n -E 's/^GOINST_VERSION="([^"]+)"$/\1/p' "$SCRIPT" | head -1)
# Рабочие файлы набор только читает: однажды тест удаления стёр
# go-installer.sh. Суммы — до всего, сверка — в самом конце.
SELF_SUM="$(cksum < "$SCRIPT") $(cksum < "$HERE/test_goinstaller.sh")"
T=$(mktemp -d "${TMPDIR:-/tmp}/goinst-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
# Защита от сканеров читает состояние с диска: на сервере с защитой её
# каталог попал бы в меню и экраны набора. Здесь — заведомо пустой.
export GOINST_SHIELD_DIR="$T/no-shield"
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); }
# В сообщении — вид проверки и её последний аргумент (ожидание), но не
# многострочное содержимое: оно уводит глаз от сути.
fail() { FAIL=$((FAIL+1)); echo "  ✗ $1 … '${*: -1}'  [$(caller 1 | awk '{print "line " $1}')]"; }
# Код без комментариев: страж обязан смотреть на код, а не на пояснения к нему.
code() { grep -v -E '^[[:space:]]*#' "$SCRIPT"; }
check() { if "$@" >/dev/null 2>&1; then pass; else fail "${*}"; fi; }
# neg — отрицание для check: «check ! cmd» не работает, в "$@" знак ! — это
# имя команды, а не отрицание, и такая проверка краснела бы всегда.
neg() { ! "$@"; }

# ── фикстуры ────────────────────────────────────────────────────────────
osrel() {  # osrel <файл> <ID> <VERSION_ID> [ID_LIKE]
    printf 'PRETTY_NAME="%s %s"\nNAME="%s"\nVERSION_ID="%s"\nID=%s\n%s' \
        "$2" "$3" "$2" "$3" "$2" "${4:+ID_LIKE=$4}" > "$1"
}
osrel "$T/os-ubuntu2404" ubuntu 24.04
osrel "$T/os-ubuntu2604" ubuntu 26.04
osrel "$T/os-ubuntu2204" ubuntu 22.04
osrel "$T/os-debian12"   debian 12
osrel "$T/os-mint"       linuxmint 22 ubuntu

# Стенд с goDNS: DoH на 443, DoT 853, консоль, панель; resolved на 53.
cat > "$T/ss-godns" <<'SS'
tcp   LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=887858,fd=3),("systemd",pid=1,fd=266))
tcp   LISTEN 0      4096         0.0.0.0:443       0.0.0.0:*    users:(("dnsdist",pid=941622,fd=7))
tcp   LISTEN 0      4096         0.0.0.0:853       0.0.0.0:*    users:(("dnsdist",pid=941622,fd=8))
tcp   LISTEN 0      4096         0.0.0.0:9445      0.0.0.0:*    users:(("python3",pid=887820,fd=4))
tcp   LISTEN 0      4096       127.0.0.1:5199      0.0.0.0:*    users:(("dnsdist",pid=941622,fd=11))
tcp   LISTEN 0      4096       127.0.0.1:8642      0.0.0.0:*    users:(("python3",pid=887820,fd=3))
tcp   LISTEN 0      4096       127.0.0.2:53        0.0.0.0:*    users:(("dnsdist",pid=941622,fd=10))
tcp   LISTEN 0      4096    127.0.0.53%lo:53       0.0.0.0:*    users:(("systemd-resolve",pid=887845,fd=18))
udp   UNCONN 0      0          127.0.0.2:53        0.0.0.0:*    users:(("dnsdist",pid=941622,fd=9))
udp   UNCONN 0      0          127.0.0.1:323       0.0.0.0:*    users:(("chronyd",pid=12800,fd=4))
tcp   LISTEN 0      4096            [::]:22           [::]:*    users:(("sshd",pid=887858,fd=4),("systemd",pid=1,fd=267))
SS
cat > "$T/units-godns" <<'U'
941622=dnsdist.service
887820=godns-web.service
887845=systemd-resolved.service
887858=ssh.service
12800=chrony.service
U

# Сервер с goVLESS pro: xray на 443, nginx на 80, панель и sub на случайных.
cat > "$T/ss-govless" <<'SS'
tcp   LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=500,fd=3))
tcp   LISTEN 0      4096               *:443             *:*    users:(("xray",pid=1001,fd=9))
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=1002,fd=6),("nginx",pid=1000,fd=6))
tcp   LISTEN 0      4096               *:38850           *:*    users:(("x-ui",pid=1003,fd=7))
tcp   LISTEN 0      4096               *:39002           *:*    users:(("x-ui",pid=1003,fd=8))
SS
cat > "$T/units-govless" <<'U'
500=ssh.service
1001=x-ui.service
1002=nginx.service
1000=nginx.service
1003=x-ui.service
U
mkdir -p "$T/nginx-govless/sites-enabled"; : > "$T/nginx-govless/sites-enabled/govless"

# Сервер с goTelegram pro: telemt на 443, nginx на 80 и 127.0.0.1:8443, панель 1984.
cat > "$T/ss-gotelegram" <<'SS'
tcp   LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=500,fd=3))
tcp   LISTEN 0      4096         0.0.0.0:443       0.0.0.0:*    users:(("telemt",pid=2001,fd=9))
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=2002,fd=6))
tcp   LISTEN 0      511        127.0.0.1:8443      0.0.0.0:*    users:(("nginx",pid=2002,fd=7))
tcp   LISTEN 0      4096       127.0.0.1:9090      0.0.0.0:*    users:(("telemt",pid=2001,fd=10))
tcp   LISTEN 0      4096       127.0.0.1:9091      0.0.0.0:*    users:(("telemt",pid=2001,fd=11))
tcp   LISTEN 0      4096       127.0.0.1:1984      0.0.0.0:*    users:(("python3",pid=2003,fd=4))
SS
cat > "$T/units-gotelegram" <<'U'
500=ssh.service
2001=telemt.service
2002=nginx.service
2003=gotelegram-admin.service
U
mkdir -p "$T/nginx-gotelegram/sites-enabled"; : > "$T/nginx-gotelegram/sites-enabled/gotelegram"

: > "$T/ss-empty"; : > "$T/units-empty"
mkdir -p "$T/nginx-empty" "$T/le-empty"

# ── обвязка ─────────────────────────────────────────────────────────────
# pf <ss> <units> <nginx-root> <os> <installed> <id> <mode> → stdout: "rc" и PF_LINES
pf() {
    local ss="$1" units="$2" ngx="$3" os="$4" inst="$5" id="$6" mode="$7"
    (
        export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
        export GOINST_SS_FIXTURE="$T/$ss" GOINST_UNIT_FIXTURE="$T/$units"
        export GOINST_NGINX_ROOT="$T/$ngx" GOINST_OS_RELEASE="$T/$os"
        export GOINST_FAKE_INSTALLED="$inst" GOINST_LE_ROOT="$T/le-empty"
        export GOINST_FAKE_CMDS="${FAKE_CMDS:-}"
        # Настоящий docker на стенде протёк бы в проверку: только фикстура.
        export GOINST_DOCKER_FIXTURE="${DOCKER_FX:-$T/docker-empty}"
        # shellcheck source=/dev/null
        . "$SCRIPT"
        os_detect
        preflight "$id" "$mode" >/dev/null 2>&1
        echo "rc=$?"
        printf '%s' "$PF_LINES"
    )
}
has()  { grep -qF -- "$2" <<<"$1"; }
hasnt() { ! grep -qF -- "$2" <<<"$1"; }

# Помощники объявляем ЗДЕСЬ, до первого использования: bash находит функцию
# только если её определение уже исполнено, а разделы набора переставляются.
# ml  — вызвать функцию скрипта;            vt  — то же с поддельным деревом /opt;
# vc  — то же с отдельным кешем версий;     vcc — с ЧИСТЫМ кешем;
# pf_env — проверка на фикстурах;           rd  — готовность продукта.
ml() { GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; $*"; }
pf_env() {
    local ss="$1" units="$2" ngx="$3" os="$4" inst="$5" expr="$6"
    (
        export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
        export GOINST_SS_FIXTURE="$T/$ss" GOINST_UNIT_FIXTURE="$T/$units"
        export GOINST_NGINX_ROOT="$T/$ngx" GOINST_OS_RELEASE="$T/$os"
        export GOINST_FAKE_INSTALLED="$inst" GOINST_LE_ROOT="$T/le-empty"
        export GOINST_DOCKER_FIXTURE="${DOCKER_FX:-$T/docker-empty}"
        # Архитектуру задаём явно: набор гоняется и на arm-ноутбуке, а
        # goAmnezia ставится только на amd64 — иначе «не та система»
        # вылезала бы там, где проверяют совсем другое.
        export GOINST_ARCH="${ARCH:-x86_64}"
        . "$SCRIPT"; os_detect; eval "$expr"
    )
}
rd() { pf_env "$1" "$2" "$3" "$4" "$5" "prod_readiness $6"; }
vt() { T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="${FS_ROOT:-$T/fs}" bash -c ". '$SCRIPT'; $*"; }
vc() { T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_VER_CACHE="$T/vc" bash -c "mkdir -p '$T/vc'; . '$SCRIPT'; $*"; }
vcc() { rm -rf "$T/vc"; vc "$@"; }   # с чистым кешем

echo "── структура"
check bash -n "$SCRIPT"
# Ключ никогда не в argv curl: только конфиг-файл. Смотрим ВЫЗОВЫ curl, а не
# любое упоминание слова: `command -v curl` рядом с переменной TOKEN_STATUS
# — не утечка, и страж, спотыкавшийся об это, скрывал бы настоящие.
_curl_calls=$(code | grep -E '(^|[^-a-z])curl ' | grep -v 'command -v curl')
check [ -n "$_curl_calls" ]
check hasnt "$_curl_calls" '$TOKEN'
# Заголовок с ключом собирается только в конфиг-файле, и он 0600.
check [ "$(code | grep -c 'header = "Authorization')" -ge 2 ]
check [ "$(code | grep -c 'chmod 600 "\$cfg"')" -ge 2 ]
# Kaskad и goWARP запускаются ИЗ ФАЙЛА: они копируют $0 в /usr/local/bin.
check has "$(code | grep 'gokaskad)')" './install.sh'
check has "$(code | grep 'gowarp)')" 'bash ./warp.sh'
check hasnt "$(code)" 'bash <('
# Страж осмотрел непустой код.
check [ "$(code | wc -l)" -gt 500 ]
# У каждого продукта заполнены все таблицы.
n=0
for id in govless gotelegram godns gokaskad gowarp goamnezia; do
    out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; prod_ports $id pro | wc -l; prod_desc $id; echo; prod_entry $id; echo; prod_repo $id; echo; prod_cmd $id; echo; prod_name $id")
    lines=$(printf '%s\n' "$out" | wc -l)
    check [ "$lines" -ge 6 ]
    check [ "$(printf '%s\n' "$out" | head -1)" -ge 1 ]
    n=$((n+1))
done
check [ "$n" -eq 6 ]
# У goVLESS и goTelegram наборы pro и Lite различаются — иначе вопрос о режиме пустой.
for id in govless gotelegram; do
    a=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; prod_ports $id pro")
    b=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; prod_ports $id lite")
    check [ "$a" != "$b" ]
done

echo "── ОС: общие ворота"
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-mint" GOINST_SS_FIXTURE="$T/ss-empty" bash "$SCRIPT" --check govless pro 2>&1); rc=$?
check [ "$rc" -eq 1 ]
check has "$out" 'производная'

echo "── стенд с goDNS (DoH на 443)"
r=$(pf ss-godns units-godns nginx-empty os-ubuntu2604 "godns" govless pro)
check has "$r" 'rc=1'
check has "$r" '443/tcp|busy|must|godns|dnsdist'
check has "$r" 'rule|must|govless-kills-443|godns'
check has "$r" '80/tcp|free|must'
r=$(pf ss-godns units-godns nginx-empty os-ubuntu2604 "godns" govless lite)
check has "$r" 'rc=1'
check hasnt "$r" 'govless-kills-443'
r=$(pf ss-godns units-godns nginx-empty os-ubuntu2604 "godns" gotelegram pro)
check has "$r" 'rc=1'
check has "$r" '443/tcp|busy|must|godns|dnsdist'
check has "$r" 'rule|info|godns-doh-443|godns'
r=$(pf ss-godns units-godns nginx-empty os-ubuntu2604 "godns" gotelegram lite)
check has "$r" 'rc=2'
check has "$r" '443/tcp|busy|soft|godns|dnsdist'
# goDNS поверх себя: всё своё, панель (python3 под godns-web.service) тоже.
r=$(pf ss-godns units-godns nginx-empty os-ubuntu2604 "godns" godns pro)
check has "$r" 'rc=0'
check has "$r" '443/tcp|own|info|godns'
check has "$r" '853/tcp|own|soft|godns'
check has "$r" '5199/tcp|own|must|godns'
check has "$r" '9445/tcp|own|soft|godns'
# На :53 первым в снимке стоит свой dnsdist (127.0.0.2), resolved — вторым.
check has "$r" '53/tcp|own|info|godns'
check hasnt "$r" 'no-cert'
# А если бы goDNS по маркерам не стоял, а dnsdist держал бы порты — это
# остатки прежней установки, и они препятствие, а не «свой».
r=$(pf ss-godns units-godns nginx-empty os-ubuntu2604 "" godns pro)
check has "$r" 'rc=1'
check has "$r" '5199/tcp|busy|must|godns|dnsdist'
check has "$r" 'rule|soft|no-cert|'
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2604" GOINST_SS_FIXTURE="$T/ss-godns" GOINST_UNIT_FIXTURE="$T/units-godns" GOINST_FAKE_INSTALLED="" GOINST_LE_ROOT="$T/le-empty" bash "$SCRIPT" --check godns 2>&1)
check has "$out" 'остатки прежней установки'
r=$(pf ss-godns units-godns nginx-empty os-ubuntu2604 "godns" gokaskad pro)
check has "$r" 'rc=0'
r=$(pf ss-godns units-godns nginx-empty os-ubuntu2404 "godns" gowarp pro)
check has "$r" 'rc=0'
check has "$r" '40000/tcp|free|must'
# На Ubuntu новее 24.04 замечания нет: у Cloudflare есть и её пакет.
r=$(pf ss-godns units-godns nginx-empty os-ubuntu2604 "godns" gowarp pro)
check has "$r" 'rc=0'
check hasnt "$r" 'os|'

echo "── сервер с goVLESS pro"
r=$(pf ss-govless units-govless nginx-govless os-ubuntu2404 "govless" gotelegram pro)
check has "$r" 'rc=1'
check has "$r" '443/tcp|busy|must|govless|xray'
check has "$r" '80/tcp|busy|must|govless|nginx'
check has "$r" 'rule|info|shared443-hint|govless'
r=$(pf ss-govless units-govless nginx-govless os-ubuntu2404 "govless" gotelegram lite)
check has "$r" 'rc=2'
# goDNS рядом с goVLESS ставится, но не на стандартный 443 — это замечание,
# а не «готов»: DoH уйдёт на 4443, и сказано это прямо.
r=$(pf ss-govless units-govless nginx-govless os-ubuntu2404 "govless" godns pro)
check has "$r" 'rc=2'
check has "$r" '443/tcp|busy|info|govless|xray'
check has "$r" 'rule|soft|godns-beside-443|govless'
check has "$r" '4443/tcp|free|soft'
check hasnt "$r" 'no-cert'
r=$(pf ss-govless units-govless nginx-govless os-ubuntu2404 "govless" govless pro)
check has "$r" 'rc=0'
check has "$r" '443/tcp|own|must|govless'
check has "$r" '80/tcp|own|must|govless'
r=$(pf ss-govless units-govless nginx-govless os-ubuntu2404 "govless" gokaskad pro)
check has "$r" 'rc=0'

echo "── сервер с goTelegram pro"
r=$(pf ss-gotelegram units-gotelegram nginx-gotelegram os-ubuntu2404 "gotelegram" govless pro)
check has "$r" 'rc=1'
check has "$r" '443/tcp|busy|must|gotelegram|telemt'
check has "$r" 'rule|must|govless-kills-443|gotelegram'
r=$(pf ss-gotelegram units-gotelegram nginx-gotelegram os-ubuntu2404 "gotelegram" gotelegram pro)
check has "$r" 'rc=0'
check has "$r" '443/tcp|own|must|gotelegram'
check has "$r" '80/tcp|own|must|gotelegram'
check has "$r" '8443/tcp|own|must|gotelegram'
check has "$r" '1984/tcp|own|soft|gotelegram'
r=$(pf ss-gotelegram units-gotelegram nginx-gotelegram os-ubuntu2404 "gotelegram" godns pro)
check has "$r" 'rc=2'
check has "$r" '443/tcp|busy|info|gotelegram|telemt'
check has "$r" 'rule|soft|godns-beside-443|gotelegram'

echo "── goWARP: чужой warp-cli"
r=$(FAKE_CMDS="warp-cli" pf ss-empty units-empty nginx-empty os-ubuntu2404 "" gowarp pro)
check has "$r" 'rc=1'
check has "$r" 'rule|must|warp-cli-foreign|'
r=$(FAKE_CMDS="warp-cli" pf ss-empty units-empty nginx-empty os-ubuntu2404 "gowarp" gowarp pro)
check has "$r" 'rc=0'

echo "── ОС: частные требования"
r=$(pf ss-empty units-empty nginx-empty os-ubuntu2204 "" gotelegram pro)
check has "$r" 'rc=1'
check has "$r" 'os|must|'
# goTelegram pro проверяет ОС только при первой установке: стоящий
# обновляется на любой.
r=$(pf ss-empty units-empty nginx-empty os-ubuntu2204 "gotelegram" gotelegram pro)
check hasnt "$r" 'os|'
# goVLESS pro при новой установке отказывает ниже Ubuntu 24.04 и Debian 12
# (require_fresh_os); обновление стоящего — и pro поверх бесплатного Lite,
# который кладёт те же x-ui и config.json, — не блокируется.
r=$(pf ss-empty units-empty nginx-empty os-ubuntu2204 "" govless pro)
check has "$r" 'rc=1'
check has "$r" 'os|must|goVLESS pro при новой установке требует Ubuntu 24.04+ или Debian 12+'
r=$(pf ss-empty units-empty nginx-empty os-ubuntu2204 "govless" govless pro)
check hasnt "$r" 'os|'
osrel "$T/os-debian11" debian 11
osrel "$T/os-ubuntu2004" ubuntu 20.04
osrel "$T/os-ubuntu2310" ubuntu 23.10
check has "$(pf ss-empty units-empty nginx-empty os-debian11 "" govless pro)" 'os|must|'
check has "$(pf ss-empty units-empty nginx-empty os-ubuntu2310 "" govless pro)" 'os|must|'
check hasnt "$(pf ss-empty units-empty nginx-empty os-debian12 "" govless pro)" 'os|'
check hasnt "$(pf ss-empty units-empty nginx-empty os-ubuntu2404 "" govless pro)" 'os|'
# goWARP pro на Ubuntu новее 24.04 — без замечания: у Cloudflare есть resolute.
check hasnt "$(pf ss-empty units-empty nginx-empty os-ubuntu2604 "" gowarp pro)" 'os|'
# goAmnezia pro на 20.04: бот и сайт не встанут, AmneziaWG встанет — замечание.
r=$(pf_env ss-empty units-empty nginx-empty os-ubuntu2004 "" 'prod_os_check goamnezia')
check has "$r" 'soft|на ubuntu 20.04 бот (python 3.8) и сайт (certbot 0.40) goAmnezia pro не встанут, AmneziaWG — встанет.'
check [ -z "$(pf_env ss-empty units-empty nginx-empty os-ubuntu2204 "" 'prod_os_check goamnezia')" ]
r=$(pf ss-empty units-empty nginx-empty os-debian12 "" godns pro)
check has "$r" 'rc=1'
check has "$r" 'os|must|'
r=$(pf ss-empty units-empty nginx-empty os-debian12 "" gotelegram pro)
check has "$r" 'rc=2'
check has "$r" 'os|soft|'
r=$(pf ss-empty units-empty nginx-empty os-debian12 "" gokaskad pro)
check has "$r" 'rc=0'

echo "── --ports и --list"
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2604" GOINST_SS_FIXTURE="$T/ss-godns" GOINST_UNIT_FIXTURE="$T/units-godns" bash "$SCRIPT" --ports 2>&1)
check has "$out" 'dnsdist (941622)'
check has "$out" 'goDNS'
check has "$out" 'система'
out=$(GOINST_TEST=1 GOINST_LANG=en GOINST_OS_RELEASE="$T/os-ubuntu2604" GOINST_FAKE_INSTALLED="godns gowarp" bash "$SCRIPT" --list 2>&1)
check has "$out" 'goDNS'
check [ "$(grep -c 'installed' <<<"$out")" -eq 2 ]
out=$(GOINST_TEST=1 GOINST_OS_RELEASE="$T/os-ubuntu2604" bash "$SCRIPT" --check nosuch 2>&1); rc=$?
check [ "$rc" -eq 64 ]
out=$(bash "$SCRIPT" --version 2>&1)
check has "$out" 'goInstaller'

echo "── goAmnezia pro: режимы, Docker, amd64"
# Сервер с goAmnezia pro: nginx на 80/443, AmneziaWG в контейнере на UDP 443.
cat > "$T/ss-goamnezia" <<'SS'
tcp   LISTEN 0      511          0.0.0.0:443       0.0.0.0:*    users:(("nginx",pid=3002,fd=6))
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=3002,fd=7))
tcp   LISTEN 0      4096       127.0.0.1:1985      0.0.0.0:*    users:(("python3",pid=3003,fd=4))
SS
printf '3002=nginx.service\n3003=goamnezia-admin.service\n' > "$T/units-goamnezia"
mkdir -p "$T/nginx-goamnezia/sites-enabled"; : > "$T/nginx-goamnezia/sites-enabled/goamnezia"
# Контейнер держит UDP 443, слушателя на хосте НЕТ: userland-proxy выключен.
printf 'amnezia-awg2 0.0.0.0:443->443/udp, [::]:443->443/udp\namnezia-awg3 0.0.0.0:39221->39221/udp\n' > "$T/docker-goamnezia"
: > "$T/docker-empty"

ga() {  # ga <ss> <units> <nginx> <os> <installed> <docker> <режим>
    (
        export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
        export GOINST_SS_FIXTURE="$T/$1" GOINST_UNIT_FIXTURE="$T/$2"
        export GOINST_NGINX_ROOT="$T/$3" GOINST_OS_RELEASE="$T/$4"
        export GOINST_FAKE_INSTALLED="$5" GOINST_LE_ROOT="$T/le-empty"
        export GOINST_DOCKER_FIXTURE="$T/$6" GOINST_ARCH="${ARCH:-x86_64}"
        . "$SCRIPT"; os_detect
        preflight goamnezia "$7" >/dev/null 2>&1
        echo "rc=$?"; printf '%s' "$PF_LINES"
    )
}
# Режимов три, и они перечислены от требовательного к скромному.
check [ "$(vt 'prod_modes goamnezia')" = "pro lite_site lite" ]
check [ "$(vt 'prod_modes govless')" = "pro lite" ]
check vt 'prod_has_modes goamnezia'
check vt '! prod_has_modes godns'
# На чистой машине pro проходит, панель и MCP свободны.
r=$(ga ss-empty units-empty nginx-empty os-ubuntu2404 "" docker-empty pro)
check has "$r" 'rc=0'
check has "$r" '443/tcp|free|must'
check has "$r" '1985/tcp|free|soft'
check has "$r" '1986/tcp|free|info'
# Lite не требует TCP вовсе: ни 443, ни 80 в наборе нет.
r=$(ga ss-govless units-govless nginx-govless os-ubuntu2404 "" docker-empty lite)
check has "$r" 'rc=0'
check hasnt "$r" '443/tcp'
check hasnt "$r" '80/tcp'
# Сайт рядом с goVLESS не поставить, и причина названа портом соседа.
r=$(ga ss-govless units-govless nginx-govless os-ubuntu2404 "govless" docker-empty lite_site)
check has "$r" 'rc=1'
check has "$r" '443/tcp|busy|must|govless|xray'
# И сказано прямо, что Lite (только VPN) встанет рядом.
check has "$r" 'rule|info|goamnezia-lite-alongside|govless'
# Готовность в меню: «только Lite», а не «ставить нельзя».
check [ "$(pf_env ss-govless units-govless nginx-govless os-ubuntu2404 "govless" 'GOINST_DOCKER_FIXTURE="$T/docker-empty" prod_readiness goamnezia')" = "y:только Lite" ]
# Тот же xray без goVLESS pro — просто панель 3X-UI, и сосед назван ею.
r=$(ga ss-govless units-govless nginx-empty os-ubuntu2404 "" docker-empty lite_site)
check has "$r" '443/tcp|busy|must|xui|xray'
# Порт, занятый контейнером, найден, хотя слушателя на хосте нет.
r=$(ga ss-goamnezia units-goamnezia nginx-goamnezia os-ubuntu2404 "" docker-goamnezia pro)
check has "$r" '443/udp|busy|soft|goamnezia|docker:amnezia-awg2'
# А при переустановке тот же контейнер — свой, и препятствием не считается.
r=$(ga ss-goamnezia units-goamnezia nginx-goamnezia os-ubuntu2404 "goamnezia" docker-goamnezia pro)
check has "$r" 'rc=0'
check has "$r" '443/udp|own|must|goamnezia'
check has "$r" '443/tcp|own|must|goamnezia'
check has "$r" '1985/tcp|own|soft|goamnezia'
# Не amd64 — препятствие, названное архитектурой, а не портом.
r=$(ARCH=aarch64 ga ss-empty units-empty nginx-empty os-ubuntu2404 "" docker-empty pro)
check has "$r" 'rc=1'
check has "$r" 'os|must|'
check [ "$(ARCH=aarch64 pf_env ss-empty units-empty nginx-empty os-ubuntu2404 "" 'GOINST_ARCH=aarch64 GOINST_DOCKER_FIXTURE="$T/docker-empty" prod_readiness goamnezia')" = "r:система не подходит" ]
# Признак установки — ключ installed, а не наличие файла.
printf '{"version":"0.3.0","installed":false}\n' > "$T/ga-config-no.json"
printf '{"version":"0.3.0","installed":true}\n'  > "$T/ga-config-yes.json"
check vt 'GOINST_GOAMNEZIA_CONFIG="$T/ga-config-yes.json" GOINST_FAKE_INSTALLED= ; unset GOINST_FAKE_INSTALLED; GOINST_GOAMNEZIA_CONFIG="$T/ga-config-yes.json" prod_installed goamnezia'
check vt 'unset GOINST_FAKE_INSTALLED; ! GOINST_GOAMNEZIA_CONFIG="$T/ga-config-no.json" prod_installed goamnezia'
check vt 'unset GOINST_FAKE_INSTALLED; ! GOINST_GOAMNEZIA_CONFIG="$T/нет.json" prod_installed goamnezia'
# Версия читается оттуда же, откуда и в ветке на GitHub.
mkdir -p "$T/fs/opt/goamnezia/lib"; printf 'GOAMNEZIA_VERSION="0.3.0"\n' > "$T/fs/opt/goamnezia/lib/common.sh"
check [ "$(vt 'prod_version goamnezia')" = "0.3.0" ]
check [ "$(vt 'prod_ver_spec goamnezia')" = "lib/common.sh|GOAMNEZIA_VERSION" ]
check [ "$(vt 'prod_repo goamnezia')" = "duboshin52/goamnezia_pro" ]
check [ "$(vt 'prod_entry goamnezia')" = "bootstrap.sh" ]
# Ключ goAmnezia лежит в своей переменной, а не в GH_TOKEN.
check has "$(code | grep 'goamnezia)')" 'GOAMNEZIA_PAT'

echo "── goAmnezia pro: пункты как в его мастере, Ленивый pro — флагом"
# Вопрос о режиме повторяет первый экран мастера goAmnezia pro 1.0: Ленивый
# pro, pro, Semi-pro, Lite. Ленивый — сценарий, а не режим: config.json его
# не хранит, готовность по нему не считается.
check [ "$(vt 'prod_mode_choices goamnezia')" = "lazy pro lite_site lite" ]
check [ "$(vt 'prod_mode_choices govless')" = "pro lite" ]
check [ "$(vt 'prod_modes goamnezia')" = "pro lite_site lite" ]
check [ "$(vt 'prod_mode_default goamnezia')" = "lite" ]
check [ "$(vt 'prod_mode_default govless')" = "pro" ]
check [ -z "$(vt 'prod_mode_default godns')" ]
check [ "$(vt 'mode_name lite_site')" = "Semi-pro" ]
check [ "$(vt 'mode_name lazy')" = "Ленивый pro" ]
check [ "$(GOINST_SOURCE_ONLY=1 GOINST_LANG=en bash -c ". '$SCRIPT'; mode_name lazy")" = "Lazy pro" ]
am() {  # am <установлено> <ввод> [id] → выбранный режим или rc=N
    ( export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FAKE_INSTALLED="$1"
      . "$SCRIPT"; MODE=""
      if ask_mode "${3:-goamnezia}" <<<"$2" >/dev/null 2>&1; then printf '%s' "$MODE"; else printf 'rc=%s' "$?"; fi )
}
# Enter — Lite, как «Enter — 4, Lite» у мастера продукта; номера — его же.
check [ "$(am '' '')" = "lite" ]
check [ "$(am '' '1')" = "lazy" ]
check [ "$(am '' '2')" = "pro" ]
check [ "$(am '' '3')" = "lite_site" ]
check [ "$(am '' '5')" = "rc=1" ]
check [ "$(am '' '0')" = "rc=1" ]
check [ "$(am '' '1a')" = "rc=1" ]
# Ленивый pro — только первая установка: на стоящем продукте первым идёт pro.
check [ "$(am goamnezia '1')" = "pro" ]
check [ "$(am goamnezia '')" = "lite" ]
# У остальных Enter — по-прежнему первый пункт.
check [ "$(am '' '' govless)" = "pro" ]
out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FAKE_INSTALLED= bash -c ". '$SCRIPT'; ask_mode goamnezia <<<'1a'" 2>&1)
check hasnt "$out" 'integer'
out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FAKE_INSTALLED= bash -c ". '$SCRIPT'; ask_mode goamnezia <<<''" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
check has "$out" '1) Ленивый pro'
check has "$out" '3) Semi-pro'
check has "$out" '4) Lite'
check has "$out" 'кроме Ленивого pro'
# Pro — это AmneziaWG на UDP 443: без порта мастер ставит Semi-pro. Для pro
# порт обязателен, Ленивому — замечание, у Semi-pro и Lite его нет вовсе.
r=$(ga ss-empty units-empty nginx-empty os-ubuntu2404 "" docker-empty pro)
check has "$r" '443/udp|free|must'
check has "$r" '1987/tcp|free|info'
r=$(ga ss-empty units-empty nginx-empty os-ubuntu2404 "" docker-empty lazy)
check has "$r" 'rc=0'
check has "$r" '443/udp|free|soft'
check has "$r" '443/tcp|free|must'
check has "$r" '80/tcp|free|must'
r=$(ga ss-empty units-empty nginx-empty os-ubuntu2404 "" docker-empty lite_site)
check hasnt "$r" '443/udp'
check has "$r" '443/tcp|free|must'
r=$(ga ss-empty units-empty nginx-empty os-ubuntu2404 "" docker-empty lite)
check hasnt "$r" '1987/tcp'
# UDP 443 у чужого процесса: pro не встанет, Ленивый встанет Semi-pro, а
# в меню — «только Semi-pro», а не «готов».
cat > "$T/ss-udp443" <<'SS'
udp   UNCONN 0      0            0.0.0.0:443       0.0.0.0:*    users:(("caddy",pid=4100,fd=7))
SS
printf '4100=caddy.service\n' > "$T/units-udp443"
r=$(ga ss-udp443 units-udp443 nginx-empty os-ubuntu2404 "" docker-empty pro)
check has "$r" 'rc=1'
check has "$r" '443/udp|busy|must|'
r=$(ga ss-udp443 units-udp443 nginx-empty os-ubuntu2404 "" docker-empty lazy)
check has "$r" 'rc=2'
check has "$r" '443/udp|busy|soft|'
check [ "$(pf_env ss-udp443 units-udp443 nginx-empty os-ubuntu2404 "" 'GOINST_DOCKER_FIXTURE="$T/docker-empty" prod_readiness goamnezia')" = "y:только Semi-pro" ]
# UDP 443 держит docker-proxy (userland-proxy включён, как на 89.125.74.168).
# Обновление стоящего goAmnezia pro упиралось в его же контейнер: docker не
# назвал его, и порт считался чужим.
cat > "$T/ss-awg-proxy" <<'SS'
udp   UNCONN 0      0            0.0.0.0:443       0.0.0.0:*    users:(("docker-proxy",pid=5001,fd=4))
udp   UNCONN 0      0               [::]:443          [::]:*    users:(("docker-proxy",pid=5002,fd=4))
SS
printf '5001=docker.service\n5002=docker.service\n' > "$T/units-awg-proxy"
# Контейнер опознан — свой, обновлению не мешает.
r=$(ga ss-awg-proxy units-awg-proxy nginx-empty os-ubuntu2404 "goamnezia" docker-goamnezia pro)
check has "$r" '443/udp|own|must|goamnezia'
# Порт наружу 443, внутри контейнера другой: искать надо по порту сервера.
printf 'amnezia-awg 0.0.0.0:443->51820/udp, [::]:443->51820/udp\n' > "$T/docker-awg-remap"
r=$(ga ss-awg-proxy units-awg-proxy nginx-empty os-ubuntu2404 "goamnezia" docker-awg-remap pro)
check has "$r" '443/udp|own|must|goamnezia'
check [ "$(GOINST_DOCKER_FIXTURE="$T/docker-awg-remap" ml 'scan_docker; printf %s "$DOCKER_PORTS"')" = "udp|443|amnezia-awg"$'\n'"udp|443|amnezia-awg" ]
# Docker не назвал контейнер: у стоящего продукта это замечание, не запрет…
r=$(ga ss-awg-proxy units-awg-proxy nginx-empty os-ubuntu2404 "goamnezia" docker-empty pro)
check has "$r" 'rc=2'
check has "$r" '443/udp|busy|soft|'
# …а при первой установке — по-прежнему препятствие: чей порт, неизвестно.
r=$(ga ss-awg-proxy units-awg-proxy nginx-empty os-ubuntu2404 "" docker-empty pro)
check has "$r" 'rc=1'
check has "$r" '443/udp|busy|must|'
# docker сам сворачивает соседние порты в диапазон — каждый порт свой.
printf 'awg 0.0.0.0:1000-1002->1000-1002/udp\n' > "$T/docker-range"
check [ "$(GOINST_DOCKER_FIXTURE="$T/docker-range" ml 'scan_docker; printf %s "$DOCKER_PORTS" | tr "\n" " "')" = "udp|1000|awg udp|1001|awg udp|1002|awg " ]
# Клиент docker новее демона: повторить с версией API, которую назвал демон.
DK="$T/dk-bin"; mkdir -p "$DK"
cat > "$DK/docker" <<'D'
#!/bin/sh
if [ "${DOCKER_API_VERSION:-}" = "1.47" ]; then echo "amnezia-awg 0.0.0.0:443->443/udp, [::]:443->443/udp"; exit 0; fi
echo "Error response from daemon: client version 1.52 is too new. Maximum supported API version is 1.47" >&2
exit 1
D
chmod +x "$DK/docker"
dk() { PATH="$DK:$PATH" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c "unset GOINST_DOCKER_FIXTURE; . '$SCRIPT'; $*"; }
out=$(dk 'scan_docker; printf "%s[%s]" "$DOCKER_PORTS" "$DOCKER_ERR"')
check has "$out" 'udp|443|amnezia-awg'
check has "$out" '[]'
# Не ответил вовсе — причина названа в проверке, а не «docker-proxy» загадкой.
printf '#!/bin/sh\necho "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" >&2\nexit 1\n' > "$DK/docker"
check has "$(dk 'scan_docker; printf %s "$DOCKER_ERR"')" 'Cannot connect to the Docker daemon'
# Демон завис — меню не висит: тайм-аут, и это названо.
if command -v timeout >/dev/null 2>&1; then
    printf '#!/bin/sh\nsleep 5\n' > "$DK/docker"
    check has "$(dk 'GOINST_DOCKER_TIMEOUT=1 scan_docker; printf %s "$DOCKER_ERR"')" 'не ответил за 1 с'
fi
printf '#!/bin/sh\necho "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" >&2\nexit 1\n' > "$DK/docker"
out=$(PATH="$DK:$PATH" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_SS_FIXTURE="$T/ss-awg-proxy" GOINST_UNIT_FIXTURE="$T/units-awg-proxy" \
      GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_FAKE_INSTALLED=goamnezia GOINST_LE_ROOT="$T/le-empty" GOINST_ARCH=x86_64 \
      bash -c "unset GOINST_DOCKER_FIXTURE; . '$SCRIPT'; os_detect; preflight goamnezia pro >/dev/null 2>&1; printf '%s\n' \"\${PF_ROWS[@]}\"")
check has "$out" 'контейнер не опознан'
check has "$out" 'docker: Cannot connect to the Docker daemon'
# Тот же UDP 443 у контейнера AmneziaWG: продукт предлагает подхватить его
# вместе с людьми, порт остаётся за ним — замечание, а не препятствие.
r=$(ga ss-empty units-empty nginx-empty os-ubuntu2404 "" docker-goamnezia pro)
check has "$r" 'rc=2'
check has "$r" '443/udp|busy|soft|goamnezia|docker:amnezia-awg2'
out=$(pf_env ss-empty units-empty nginx-empty os-ubuntu2404 "" 'GOINST_DOCKER_FIXTURE="$T/docker-goamnezia" preflight goamnezia pro 2>&1')
check has "$out" 'подхватить'
# Ленивый pro уходит в установщик флагом: install.sh --lazy [--domain=…]
# [--keys=N], bootstrap передаёт аргументы как есть. Поддельный установщик
# пишет, с чем его запустили; «run» первой строкой — что он вообще
# запускался, иначе пустой список аргументов доказал бы что угодно.
mkdir -p "$T/amz-src"
# Без аргументов `printf "%s\n"` печатает пустую строку — отсюда проверка $#.
printf '#!/bin/bash\n{ echo run; [ $# -eq 0 ] || printf "%%s\\n" "$@"; } > "%s"\n' "$T/amz-args" > "$T/amz-src/install.sh"
# Локальное дерево идёт через загрузчик продукта с GOAMNEZIA_LOCAL_TREE, как настоящая установка.
printf '#!/bin/bash\necho "$GOAMNEZIA_LOCAL_TREE" > "%s"\nexec bash "$GOAMNEZIA_LOCAL_TREE/install.sh" "$@"\n' "$T/amz-tree" > "$T/amz-src/bootstrap.sh"
amz_run() {  # amz_run <режим> [ПЕРЕМЕННАЯ=значение…] → «run» и аргументы
    rm -f "$T/amz-args"
    ( export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_DIR="$T/amz-dir"
      export GOINST_SRC_goamnezia="$T/amz-src"
      for kv in "${@:2}"; do export "$kv"; done
      . "$SCRIPT"; MODE="$1"; TOKEN=x
      run_product_installer goamnezia </dev/null >/dev/null 2>&1 )
    paste -sd' ' - < "$T/amz-args" 2>/dev/null
}
amz_remote() {  # то же, но загрузчик «скачан» с GitHub
    rm -f "$T/amz-args"
    ( export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_DIR="$T/amz-dir"
      unset GOINST_SRC_goamnezia
      . "$SCRIPT"; MODE="$1"; TOKEN=x; REF=main
      ensure_token() { return 0; }
      fetch_raw() { cp "$T/amz-src/install.sh" "$4"; }
      run_product_installer goamnezia </dev/null >/dev/null 2>&1 )
    paste -sd' ' - < "$T/amz-args" 2>/dev/null
}
check [ "$(amz_run lazy)" = "run --lazy" ]
check [ "$(cat "$T/amz-tree")" = "$T/amz-src" ]
check [ "$(amz_run pro)" = "run" ]
check [ "$(amz_run lazy GOINST_LAZY_DOMAIN=vpn.example.com GOINST_LAZY_KEYS=3)" = "run --lazy --domain=vpn.example.com --keys=3" ]
# Домен и число ключей без Ленивого pro не передаются: мастер их не ждёт.
check [ "$(amz_run lite GOINST_LAZY_DOMAIN=vpn.example.com)" = "run" ]
check [ "$(amz_remote lazy)" = "run --lazy" ]
check [ "$(amz_remote lite)" = "run" ]
# После Ленивого pro сказано, каким режимом он встал: pro или Semi-pro.
mkdir -p "$T/fs-lazy/opt/goamnezia"
printf '{"installed":true,"mode":"lite_site"}\n' > "$T/fs-lazy/opt/goamnezia/config.json"
printf 'branch=main\n' > "$T/fs-lazy/opt/goamnezia/.install-source"
out=$(FS_ROOT="$T/fs-lazy" vt 'unset GOINST_FAKE_INSTALLED GOINST_GOAMNEZIA_CONFIG; MODE=lazy; installer_postcheck goamnezia main 2>&1' | sed 's/\x1b\[[0-9;]*m//g')
check has "$out" 'Ленивый pro встал в режиме Semi-pro'
out=$(FS_ROOT="$T/fs-lazy" vt 'unset GOINST_FAKE_INSTALLED GOINST_GOAMNEZIA_CONFIG; MODE=pro; installer_postcheck goamnezia main 2>&1')
check has "$out" 'main'
check hasnt "$out" 'Ленивый'
# «lazy» в config.json режимом не считается: такого режима продукт не пишет.
printf '{"installed":true,"mode":"lazy"}\n' > "$T/fs-lazy/opt/goamnezia/config.json"
check vt "unset GOINST_FAKE_INSTALLED GOINST_GOAMNEZIA_CONFIG; GOINST_FS_ROOT='$T/fs-lazy'; ! prod_installed_mode goamnezia"
# Опечатка в режиме — отказ с перечнем, а не проверка пустого набора портов.
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2604" GOINST_SS_FIXTURE="$T/ss-empty" bash "$SCRIPT" --check goamnezia Pro 2>&1); rc=$?
check [ "$rc" -eq 64 ]
check has "$out" 'lazy pro lite_site lite'
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2604" GOINST_SS_FIXTURE="$T/ss-empty" bash "$SCRIPT" --install goamnezia lite_sit main 2>&1); rc=$?
check [ "$rc" -eq 64 ]
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_ARCH=x86_64 GOINST_OS_RELEASE="$T/os-ubuntu2604" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_DOCKER_FIXTURE="$T/docker-empty" GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_FAKE_INSTALLED= bash "$SCRIPT" --check goamnezia lazy 2>&1); rc=$?
check [ "$rc" -eq 0 ]
check has "$out" 'Ленивый pro'
# У продукта без режимов слово режима по-прежнему ничего не ломает.
GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2604" GOINST_SS_FIXTURE="$T/ss-empty" bash "$SCRIPT" --check gokaskad pro >/dev/null 2>&1; rc=$?
check [ "$rc" -ne 64 ]

echo "── меню: раскладка строк"
# Кириллица в колонке: ширина считается в СИМВОЛАХ, иначе строка разъезжается
# ровно на длину подписи.
check [ "$(ml 'str_len "goDNS"')" = 5 ]
check [ "$(ml 'str_len "установлен"')" = 10 ]
check [ "$(LC_ALL=C ml 'str_len "установлен"')" = 10 ]
check [ "$(ml 'pad_to "goDNS" 10 | wc -c')" -eq 10 ]
check [ "$(ml 'str_len "$(pad_to "установлен" 16)"')" = 16 ]
# Слишком длинное обрезается, иначе одно имя сдвигает всю таблицу.
check [ "$(ml 'str_len "$(pad_to "оченьдлинноеимяпродукта" 10)"')" = 10 ]
# Разделитель не получает строки и не ловит курсор.
r=$(ml 'MENU_ITEMS=("1|A|g:ок|подпись" "-|||" "0|Выход|d:|"); menu_build_rows; printf "%s\n" "${MENU_KEY[@]}"')
check [ "$(printf '%s\n' "$r" | tr -d '\n')" = "1-0" ]
check [ "$(ml 'MENU_ITEMS=("1|A|g:ок|x" "-|||" "0|B|d:|"); menu_build_rows; _menu_next 0 1')" = 2 ]
check [ "$(ml 'MENU_ITEMS=("1|A|g:ок|x" "-|||" "0|B|d:|"); menu_build_rows; _menu_next 2 1')" = 0 ]
check [ "$(ml 'MENU_ITEMS=("1|A|g:ок|x" "-|||" "0|B|d:|"); menu_build_rows; _menu_next 0 -1')" = 2 ]
# Без терминала стрелочный экран не предлагается: под `curl | bash` и в
# тестах посимвольный ввод невозможен.
check ml 'MENU_ITEMS=("1|A|d:|"); ! menu_is_interactive'
check ml 'GOINST_PLAIN_MENU=1; MENU_ITEMS=("1|A|d:|"); ! menu_is_interactive'

echo "── меню: готовность продукта"
# Приговор в строке меню обязан совпадать с приговором проверки: он ею и
# считается. Стенд с goDNS на 443.
check [ "$(rd ss-godns units-godns nginx-empty os-ubuntu2604 godns govless)" = "r:443 занят: goDNS pro" ]
check [ "$(rd ss-godns units-godns nginx-empty os-ubuntu2604 godns gokaskad)" = "g:готов" ]
# pro занят, а Lite проходит — это «только Lite», а не «нельзя».
check [ "$(rd ss-godns units-godns nginx-empty os-ubuntu2604 godns gotelegram)" = "y:только Lite" ]
check [ "$(rd ss-godns units-godns nginx-empty os-ubuntu2604 godns gowarp)" = "g:готов" ]
check [ "$(rd ss-empty units-empty nginx-empty os-debian12 "" gotelegram)" = "y:готов, есть замечания" ]
# Препятствие по системе называется системой, а не портом.
check [ "$(rd ss-empty units-empty nginx-empty os-ubuntu2204 "" gotelegram)" = "r:система не подходит" ]
check [ "$(rd ss-empty units-empty nginx-empty os-debian12 "" godns)" = "r:система не подходит" ]
# Конфликт соседа — тоже не порт.
check [ "$(FAKE_CMDS=warp-cli pf_env ss-empty units-empty nginx-empty os-ubuntu2404 "" 'GOINST_FAKE_CMDS=warp-cli prod_readiness gowarp')" = "r:конфликт с соседом" ]

echo "── меню исполняется: что нажали, то и вызвалось"
# Греп по коду перестановку пунктов не заметит, поэтому меню запускается
# по-настоящему, а вызовы пишутся в журнал.
drive() {  # drive <клавиши построчно> [установлено] → журнал вызовов
    local keys="$1" inst="${2:-godns}"
    (
        export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_PLAIN_MENU=1
        export GOINST_SS_FIXTURE="$T/ss-godns" GOINST_UNIT_FIXTURE="$T/units-godns"
        export GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_OS_RELEASE="$T/os-ubuntu2604"
        export GOINST_FAKE_INSTALLED="$inst" GOINST_LE_ROOT="$T/le-empty"
        . "$SCRIPT"; os_detect
        LOG="$T/calls.log"; : > "$LOG"
        sleep() { :; }
        # Готовность считается при сборке экрана и зовёт preflight — в журнале
        # действий ей делать нечего, иначе она прячет то, ради чего журнал.
        prod_readiness() { printf 'g:готов'; }
        install_flow() { echo "install_flow $1" >> "$LOG"; }
        show_ports()   { echo "show_ports" >> "$LOG"; }
        preflight()    { echo "preflight $1 $2" >> "$LOG"; PF_MUST=0; PF_SOFT=0; PF_LINES=""; return 0; }
        ask_mode()     { MODE=pro; return 0; }
        printf '%s\n' $keys | main_menu >/dev/null 2>&1
        cat "$LOG"
    )
}
# Пятый пункт — пятый продукт, а не четвёртый.
check [ "$(drive '5 1' | head -1)" = "install_flow gowarp" ]
check [ "$(drive '1 1' | head -1)" = "install_flow govless" ]
check [ "$(drive '3 2' | head -1)" = "install_flow godns" ]
check has "$(drive 'p')" 'show_ports'
# Проверка портов из подменю зовёт именно проверку и именно того продукта.
check has "$(drive '2 3')" 'preflight gotelegram pro'
# Выход из подменю возвращает в главное, а не наружу.
check has "$(drive '1 0 p')" 'show_ports'
# У установленного продукта первый пункт — его меню, а не установка.
check [ -z "$(drive '3 1' godns | grep install_flow)" ]
# Мёртвых пунктов нет: у каждого ключа есть ветка обработчика.
keys_main=$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'menu_items_main; printf "%s " "${MENU_ITEMS[@]%%|*}"')
check [ "$(tr -d ' -' <<<"$keys_main")" = "123456plcsx0" ]
for id in govless gotelegram godns gokaskad gowarp; do
    k=$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 "" "menu_items_product $id; printf '%s ' \"\${MENU_ITEMS[@]%%|*}\"")
    check [ "$(tr -d ' -' <<<"$k")" = "130" ]
    k=$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 "$id" "menu_items_product $id; printf '%s ' \"\${MENU_ITEMS[@]%%|*}\"")
    check [ "$(tr -d ' -' <<<"$k")" = "1230" ]
done
# Ctrl-D из меню — выход, а не проход по умолчанию.
check [ -z "$(drive '' godns)" ]

echo "── версии: чтение номера из файла"
# Дерево «установленного» продукта: версия обязана читаться тем же способом,
# каким она потом читается из ветки на GitHub.
mkdir -p "$T/fs/opt/godns-installer/lib" "$T/fs/opt/gotelegram/lib" \
         "$T/fs/opt/govless-installer/lib" "$T/fs/usr/local/bin"
printf 'GODNS_VERSION="0.32.1"\n'        > "$T/fs/opt/godns-installer/lib/common.sh"
printf 'GOTELEGRAM_VERSION="2.10.46"\n'  > "$T/fs/opt/gotelegram/lib/common.sh"
printf 'GOVLESS_VERSION="1.3.1"\n'       > "$T/fs/opt/govless-installer/lib/common.sh"
printf '#!/bin/bash\nKASKAD_VERSION="2.8"\n' > "$T/fs/usr/local/bin/gokaskad"
printf '#!/bin/bash\nWARP_VERSION="2.4.1"\n' > "$T/fs/usr/local/bin/gowarp"
# Упоминание переменной в комментарии или в сообщении версией не является.
printf '# GODNS_VERSION="9.9.9" — так было\necho "GODNS_VERSION=8.8.8"\nGODNS_VERSION="0.33.0"\n' > "$T/ver-tricky.sh"
check [ "$(vt 'prod_version godns')"      = "0.32.1" ]
check [ "$(vt 'prod_version gotelegram')" = "2.10.46" ]
check [ "$(vt 'prod_version govless')"    = "1.3.1" ]
check [ "$(vt 'prod_version gokaskad')"   = "2.8" ]
check [ "$(vt 'prod_version gowarp')"     = "2.4.1" ]
check [ "$(vt "ver_extract '$T/ver-tricky.sh' GODNS_VERSION")" = "0.33.0" ]
check vt "! ver_extract '$T/fs/opt/godns-installer/lib/common.sh' НЕТ_ТАКОЙ"
check vt "! ver_extract '$T/нет-файла' GODNS_VERSION"
# Пустое дерево — пустая версия, а не мусор и не падение.
check [ -z "$(FS_ROOT="$T/пусто" vt 'prod_version govless')" ]

echo "── версии: сравнение и выбор ветки"
check vt 'ver_newer 0.9.0 0.10.0'      # десятый минорный новее девятого
check vt '! ver_newer 0.10.0 0.9.0'
check vt '! ver_newer 2.8 2.8'         # равные — не новее
check vt 'ver_newer 2.10.45 2.10.46'
check vt '! ver_newer 1.3.1 ""'        # нечего предложить — не новее
check vt 'ver_newer "" 1.3.1'          # ничего не стоит — годится любое
# Кеш: свежая запись читается, протухшая нет.
check [ "$(vc 'ver_cache_write govless main 1.4.0; ver_cache_read govless main')" = "1.4.0" ]
check vc 'printf "1 1.0.0\n" > "$T/vc/govless.main"; ! ver_cache_read govless main'
check vc 'printf "мусор 1.0.0\n" > "$T/vc/govless.main"; ! ver_cache_read govless main'
# Из двух веток выбирается новейшая, и названа именно она.
check [ "$(vc 'ver_cache_write govless main 1.3.1; ver_cache_write govless dev 1.4.0; prod_best_remote govless')" = "dev 1.4.0" ]
check [ "$(vc 'ver_cache_write govless main 1.5.0; ver_cache_write govless dev 1.4.0; prod_best_remote govless')" = "main 1.5.0" ]
# Пустой ответ ветки в выбор не попадает.
check [ "$(vc 'ver_cache_write govless main 1.3.1; ver_cache_write govless dev ""; prod_best_remote govless')" = "main 1.3.1" ]
check vc 'ver_cache_write govless main ""; ver_cache_write govless dev ""; ! prod_best_remote govless'
# Ячейка «доступно»: стрелка только когда в ветке ДЕЙСТВИТЕЛЬНО новее.
check [ "$(vc 'ver_cache_write govless main 1.4.0; prod_avail_cell govless 1.3.1')" = "g:main 1.4.0 ↑" ]
check [ "$(vc 'ver_cache_write govless main 1.4.0; prod_avail_cell govless 1.4.0')" = "d:main 1.4.0" ]
check [ "$(vc 'ver_cache_write govless main 1.4.0; prod_avail_cell govless ""')"    = "d:main 1.4.0" ]
check [ "$(vcc 'prod_avail_cell govless 1.3.1')" = "d:—" ]
# У goDNS ветки main на GitHub нет: спрашивать её незачем.
# Ветки узнаются у GitHub. Пока не спросили — запасной список, одинаковый
# для всех: гадать за конкретный продукт не на чем.
check [ "$(vt 'prod_refs godns')" = "main dev" ]
check [ "$(vt 'prod_refs gokaskad')" = "main dev" ]
# Узнанное вытесняет запасное и переживает перезапуск через кеш.
cat > "$T/branches" <<'BR'
duboshin52/kaskad-pro=main test backup/pre-v2.5
duboshin52/go_warp_pro=alfa-v2 alpha main test v2.4-menu
duboshin52/goDNS=dev main
BR
brf() { GOINST_SOURCE_ONLY=1 GOINST_LANG=ru T="$T" GOINST_VER_CACHE="$T/vcb" GOINST_BRANCHES_FIXTURE="$T/branches" bash -c "mkdir -p '$T/vcb'; . '$SCRIPT'; $*"; }
rm -rf "$T/vcb"
# Рабочие ветки авторов в выбор не попадают: оператор выбирает зрелость
# кода, а не место разработки.
check [ "$(brf 'refs_fetch_one gokaskad ""; prod_refs gokaskad')" = "main" ]
check [ "$(brf 'refs_fetch_one gowarp ""; prod_refs gowarp')" = "main" ]
check [ "$(brf 'refs_fetch_one godns ""; prod_refs godns')" = "main dev" ]
# Ветка со слэшем не должна ломать имя файла кеша.
check brf 'ver_cache_write x "backup/pre-v2.5" 1.0; [ "$(ver_cache_read x "backup/pre-v2.5")" = "1.0" ]'
check [ "$(brf 'GOINST_REFS_MAX=1; REFS_MAX=1; refs_fetch_one godns ""; prod_refs_probe godns | tr "\n" " "')" = "main " ]
# Заданное человеком сильнее узнанного.
check [ "$(brf 'refs_fetch_one gokaskad ""; GOINST_REFS_gokaskad="rc1"; prod_refs gokaskad')" = "rc1" ]
# Версия ищется по нескольким файлам: подсказка первая, потом общие места.
check [ "$(vt 'prod_ver_paths gokaskad | head -1')" = "install.sh" ]
check [ "$(vt 'prod_ver_paths govless | head -1')" = "lib/common.sh" ]
check [ "$(vt 'prod_ver_paths govless | wc -l')" -ge 4 ]
# Имя переменной знать необязательно: годится любая «…VERSION=».
printf 'FOO_VERSION="7.8.9"\n' > "$T/anyver.sh"
check [ "$(vt "ver_extract_any '$T/anyver.sh'")" = "7.8.9" ]
printf '# CHANGED_VERSION="9.9.9"\necho CHANGED_VERSION=8\nCHANGED_VERSION="1.2.3"\n' > "$T/anyver2.sh"
check [ "$(vt "ver_extract_any '$T/anyver2.sh'")" = "1.2.3" ]
check vt "! ver_extract_any '$T/нет-такого'" 
check [ "$(vt 'prod_refs govless')" = "main dev" ]
check [ "$(vt 'GOINST_REFS_govless="rc1"; prod_refs govless')" = "rc1" ]

echo "── версии: опрос сети не обязателен"
# Без ключа и без сети опрос молча пропускается: меню не должно ждать.
check vc 'TOKEN=""; versions_fetch govless; [ "$VER_NET_TRIED" = no ]'
check vc 'TOKEN="x"; GOINST_NO_NET=1; versions_fetch govless; [ "$VER_NET_TRIED" = no ]'
# Пустой кеш — колонка «доступно» не показывается вовсе.
check vcc 'TOKEN="x"; GOINST_NO_NET=1; versions_fetch govless; [ "$VER_NET_OK" = no ]'
# А вот известное раньше показывается и без сети: ответ уже на руках.
check vcc 'ver_cache_write govless main 1.4.0; TOKEN=""; GOINST_NO_NET=1; versions_fetch govless; [ "$VER_NET_OK" = yes ]'
check vcc 'ver_cache_write govless main 1.4.0; TOKEN=""; versions_fetch govless; [ "$VER_NET_OK" = yes ]'
check vc 'ver_cache_write govless main 1.4.0; ver_cache_write govless dev 1.4.0; TOKEN=x; versions_fetch govless; [ "$VER_NET_OK" = yes ]'
# Забывание кеша заставляет спросить заново.
check vcc 'ver_cache_write govless main 1.4.0; versions_forget; ! prod_best_remote govless'
# Ключ не уезжает в argv curl: /proc/<pid>/cmdline читает любой локальный.
check hasnt "$(code | sed -n '/_ver_fetch_one/,/^}/p')" 'TOKEN'
# Колонка появляется только после удачного опроса.
r=$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'VER_NET_OK=no; menu_items_main; printf "%s" "$MENU_W_EXTRA"')
check [ "$r" = 0 ]
r=$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'VER_NET_OK=yes; menu_items_main; printf "%s" "$MENU_W_EXTRA"')
check [ "$r" -gt 0 ]
# Пункт «обновить сведения» есть только когда его есть чем исполнить.
r=$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'TOKEN=""; VER_NET_TRIED=no; menu_items_main; printf "%s " "${MENU_ITEMS[@]%%|*}"')
check [ "$(tr -d ' -' <<<"$r")" = "123456plcsx0" ]
r=$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'TOKEN="x"; menu_items_main; printf "%s " "${MENU_ITEMS[@]%%|*}"')
check [ "$(tr -d ' -' <<<"$r")" = "123456prlcsx0" ]
check has "$(drive 'r')" ''   # ключ r не роняет меню

echo "── ответы только цифрами"
cf() { GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; printf '%s\n' '$1' | { confirm вопрос '$2' >/dev/null 2>&1; echo \$?; }"; }
check [ "$(cf 1 y)" = 0 ]
check [ "$(cf 2 y)" = 1 ]
check [ "$(cf 1 n)" = 0 ]
check [ "$(cf 2 n)" = 1 ]
# Enter берёт умолчание, и оно разное у разных вопросов.
check [ "$(cf '' y)" = 0 ]
check [ "$(cf '' n)" = 1 ]
# Буквы больше не ответ: ни «y», ни «да».
check [ "$(cf y y)" = 1 ]
check [ "$(cf да y)" = 1 ]
# В тексте вопроса нет ни [Y/n], ни [y/N].
check hasnt "$(code)" '[Y/n]'
check hasnt "$(code)" '[y/N]'
# Цвета печатаются между «1)» и «Да», поэтому сверяем по тексту без них.
_cf_out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; confirm вопрос y </dev/null 2>&1" | sed $'s/\x1b\[[0-9;]*m//g')
check has "$_cf_out" '1) Да'
check has "$_cf_out" '2) Нет'
check has "$_cf_out" 'по умолчанию'

echo "── режим установленного не спрашивается"
# Три продукта с режимами пишут его одним ключом в свой config.json.
mkdir -p "$T/fs/opt/govless" "$T/fs/opt/gotelegram" "$T/fs/opt/goamnezia"
printf '{"mode":"pro","port":443}\n'      > "$T/fs/opt/govless/config.json"
printf '{"mode":"lite","engine":"telemt"}\n' > "$T/fs/opt/gotelegram/config.json"
printf '{"installed":true,"mode":"lite_site"}\n' > "$T/fs/opt/goamnezia/config.json"
check [ "$(vt 'prod_installed_mode govless')" = "pro" ]
check [ "$(vt 'prod_installed_mode gotelegram')" = "lite" ]
check [ "$(vt 'prod_installed_mode goamnezia')" = "lite_site" ]
# Чужое слово режимом не считается: иначе проверка пойдёт по пустому
# набору портов и скажет «всё свободно».
printf '{"mode":"турбо"}\n' > "$T/fs/opt/govless/config.json"
check vt '! prod_installed_mode govless'
printf '{"mode":"lite_site"}\n' > "$T/fs/opt/govless/config.json"
check vt '! prod_installed_mode govless'   # у goVLESS такого режима нет
printf '{"mode":"pro"}\n' > "$T/fs/opt/govless/config.json"
check vt '! prod_installed_mode godns'     # у goDNS режимов нет вовсе
# Установлен — режим берётся, не спрашивается.
check [ "$(vt 'GOINST_FAKE_INSTALLED=govless mode_resolve govless >/dev/null 2>&1; printf %s "$MODE"')" = "pro" ]
# Не установлен — спрашивать надо.
check vt 'unset GOINST_FAKE_INSTALLED; GOINST_FAKE_INSTALLED=""; ! mode_resolve govless'
# Принудительный вопрос остаётся возможен.
check vt 'GOINST_FAKE_INSTALLED=govless GOINST_ASK_MODE=1; ! mode_resolve govless'
# У продукта без режимов вопроса нет никогда.
check vt 'mode_resolve godns'

echo "── выбор ветки при установке и обновлении"
# Ветку выбирает человек: на main и dev лежат разные версии.
mkdir -p "$T/fs/opt/gotelegram" "$T/fs/opt/goamnezia"
printf 'branch=dev\nrepo=duboshin52/gotelegram_pro\n' > "$T/fs/opt/gotelegram/.install-source"
printf 'branch=main\n' > "$T/fs/opt/goamnezia/.install-source"
rm -rf "$T/vc"; mkdir -p "$T/vc"
_now=$(date +%s)
for e in "govless.main 1.3.1" "govless.dev 1.4.0" "gotelegram.main 2.10.46" "gotelegram.dev 2.11.0" "godns.dev 0.32.1"; do
    set -- $e; printf '%s %s\n' "$_now" "$2" > "$T/vc/$1"
done
ar() {  # ar <id> <что ввели> [установлено] → "rc=<код>:<ветка>"
    (
        export T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
        export GOINST_VER_CACHE="$T/vc" GOINST_FS_ROOT="$T/fs"
        export GOINST_FAKE_INSTALLED="${3:-}" GOINST_OS_RELEASE="$T/os-ubuntu2404"
        . "$SCRIPT"
        printf '%s\n' "$2" | { ask_ref "$1" >/dev/null 2>&1; echo "rc=$?:$REF"; }
    )
}
# Номером выбирается именно та ветка, что напечатана под ним.
check [ "$(ar govless 1)" = "rc=0:main" ]
check [ "$(ar govless 2)" = "rc=0:dev" ]
# Enter без установленного продукта — стабильная ветка, она первая в списке.
check [ "$(ar govless '')" = "rc=0:main" ]
# А у установленного Enter оставляет ту ветку, с которой он стоит: переезд
# со стабильной на отладочную не должен случаться от промаха по клавише.
check [ "$(ar gotelegram '' gotelegram)" = "rc=0:dev" ]
check [ "$(ar goamnezia '' goamnezia)" = "rc=0:main" ]
# Ветка одна — вопроса нет, но она названа. Это про goKaskad и goWARP:
# ветки dev у них на GitHub нет.
check [ "$(ar gokaskad 1)" = "rc=0:main" ]
check [ "$(ar gokaskad '')" = "rc=0:main" ]
check [ "$(ar gowarp '')" = "rc=0:main" ]
# А у goDNS их теперь две, и выбор работает как у всех.
check [ "$(ar godns 1)" = "rc=0:main" ]
check [ "$(ar godns 2)" = "rc=0:dev" ]
# Неверный ввод не выбирает молча.
check [ "$(ar govless 9)" = "rc=1:" ]
check [ "$(ar govless нет)" = "rc=1:" ]
# Ctrl-D — отмена, а не согласие с умолчанием.
check [ "$(ar govless "" | head -1)" != "rc=1:" ]
r=$( export T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_VER_CACHE="$T/vc" \
        GOINST_FS_ROOT="$T/fs" GOINST_OS_RELEASE="$T/os-ubuntu2404"; . "$SCRIPT"
     ask_ref govless </dev/null >/dev/null 2>&1; echo "rc=$?:$REF" )
check [ "$r" = "rc=1:" ]
# Ветка установленного читается из .install-source, а где её нет — не врём.
check [ "$(vt 'prod_installed_ref gotelegram')" = "dev" ]
check [ "$(vt 'prod_installed_ref goamnezia')" = "main" ]
check vt '! prod_installed_ref govless'
check vt '! prod_installed_ref godns'
# Ветки подписаны словами, а не только именами.
check [ "$(vt 'ref_kind main')" = "стабильная" ]
check [ "$(vt 'ref_kind dev')" = "экспериментальная" ]
check [ -z "$(vt 'ref_kind feature-x')" ]
# Выбранная ветка доходит до установщика продукта.
check has "$(code | grep 'ref=')" 'REF:-'
# В вопросе о запуске названы и продукт, и ветка.
check has "$(code | sed -n '/confirm "\$(bi "Запустить установщик"/p')" 'REF'
# `read -p` не разворачивает escape-последовательности: цвета в приглашении
# печатались бы буквально, как «\033[1mmain\033[0m».
check hasnt "$(code | grep -E 'confirm "|read_line [a-z]+ "')" '${BOLD}'
check hasnt "$(code | grep -E 'confirm "|read_line [a-z]+ "')" '${CYAN}'
check hasnt "$(code | grep -E 'confirm "|read_line [a-z]+ "')" '${GREEN}'

echo "── запуск установщика продукта доходит до дела"
# Эту функцию не трогал ни один тест, и в ней жила ошибка, обрывавшая ЛЮБУЮ
# установку на первой же строке. Теперь она исполняется: с локальным
# источником, где нужного файла нет, — значит до проверки файла дошли.
ri() {  # ri <id> → "rc=<код>" + сообщение
    local id="$1" d="$T/src-$1"
    mkdir -p "$d"
    (
        export T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
        export GOINST_DIR="$T/goinst-work" GOINST_VER_CACHE="$T/vc"
        export "GOINST_SRC_${id}=$d"
        # Ключ goWARP спрашивается ДО разбора источника, а ключ доступа —
        # при скачивании. В наборе ввода нет: подаём заранее, иначе функция
        # ждёт человека и набор висит.
        export GOWARP_KEY="TEST-KEY" TOKEN="test"
        . "$SCRIPT"
        TOKEN="test"
        out=$(run_product_installer "$id" </dev/null 2>&1); echo "rc=$?"; printf '%s' "$out"
    )
}
for id in govless gotelegram godns gokaskad gowarp goamnezia; do
    r=$(ri "$id")
    # Код возврата любой, кроме обрыва на раскрытии переменной: важно, что
    # функция ДОШЛА до разбора локального источника и сказала про файл.
    check hasnt "$r" 'indirect expansion'
    check hasnt "$r" 'непрямое раскрытие'
    check has "$r" 'Локальный источник'
done
# Запуск из файла для тех, кто копирует сам себя в /usr/local/bin.
check has "$(code | sed -n '/^run_product_installer/,/^}/p')" 'REF:-'

echo "── ключ доступа: хранение и проверка"
# Ответы GitHub подменяем фикстурой: без неё ветки «отвергнут», «нет
# доступа» и «нет сети» не проверить, а в них весь смысл проверки.
all200() { for r in duboshin52/goVLESS duboshin52/gotelegram_pro duboshin52/goDNS duboshin52/kaskad-pro duboshin52/go_warp_pro duboshin52/goamnezia_pro; do echo "$r=$1"; done; }
all200 200 > "$T/http-ok"
all200 401 > "$T/http-401"
all200 404 > "$T/http-404"
all200 000 > "$T/http-nonet"
{ all200 200 | head -4; echo "duboshin52/go_warp_pro=404"; echo "duboshin52/goamnezia_pro=404"; } > "$T/http-partial"

tk() {  # tk <фикстура-ответов> <выражение> ; ключ и файл — во временном дереве
    (
        export T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
        export GOINST_TOKEN_FILE="$T/token" GOINST_HTTP_FIXTURE="$T/$1"
        export GOINST_OS_RELEASE="$T/os-ubuntu2404"
        unset GH_TOKEN GOTELEGRAM_PAT GITHUB_PAT GOINST_TOKEN
        . "$SCRIPT"
        eval "$2"
    )
}
# Все репозитории читаются — ключ годен.
check [ "$(tk http-ok 'TOKEN=x; token_check; printf "%s" "$TOKEN_STATUS"')" = "ok" ]
# GitHub отверг ключ — это «негоден», а не «нет доступа».
check [ "$(tk http-401 'TOKEN=x; token_check; printf "%s" "$TOKEN_STATUS"')" = "bad" ]
# Ключ принят, но не видит ни одного нашего репозитория — тоже негоден.
check [ "$(tk http-404 'TOKEN=x; token_check; printf "%s" "$TOKEN_STATUS"')" = "bad" ]
# Часть репозиториев закрыта — ключ рабочий, но неполный, и названы именно они.
check [ "$(tk http-partial 'TOKEN=x; token_check; printf "%s" "$TOKEN_STATUS"')" = "denied" ]
check has "$(tk http-partial 'TOKEN=x; token_check; printf "%s" "$TOKEN_DENIED"')" 'goWARP pro'
check has "$(tk http-partial 'TOKEN=x; token_check; printf "%s" "$TOKEN_DENIED"')" 'goAmnezia pro'
# Сети нет — ключ не виноват, и трогать его нельзя.
check [ "$(tk http-nonet 'TOKEN=x; token_check; printf "%s" "$TOKEN_STATUS"')" = "nonet" ]
check [ "$(tk http-ok 'TOKEN=""; token_check; printf "%s" "$TOKEN_STATUS"')" = "none" ]

# Хранение: файл 0600, каталог 0700, ключ читается обратно.
check tk http-ok 'token_save "секрет-123"'
check [ "$(tk http-ok 'token_save "секрет-123" >/dev/null; cat "$TOKEN_FILE"')" = "секрет-123" ]
mode=$(tk http-ok 'token_save "с" >/dev/null; if stat -c "%a" "$TOKEN_FILE" 2>/dev/null; then :; else stat -f "%OLp" "$TOKEN_FILE"; fi')
check [ "$mode" = "600" ]
# Окружение выигрывает у файла: разовый запуск чужим ключом не подменяет свой.
check [ "$(tk http-ok 'token_save "изфайла" >/dev/null; token_load; printf "%s:%s" "$TOKEN" "$TOKEN_FROM"')" = "изфайла:file" ]
check [ "$(tk http-ok 'token_save "изфайла" >/dev/null; GH_TOKEN=изсреды; token_load; printf "%s:%s" "$TOKEN" "$TOKEN_FROM"')" = "изсреды:env" ]
# Забыть — значит забыть.
check tk http-ok 'token_save "с" >/dev/null; token_forget; ! token_load'
# Пробелы и перевод строки в ключе не должны попадать в заголовок.
check [ "$(tk http-ok 'printf "  ключ \n" > "$TOKEN_FILE"; token_load; printf "%s" "$TOKEN"')" = "ключ" ]

# Ключ из переменной сохраняется: установка одной командой не должна
# работать ровно один раз.
r=$(tk http-ok 'token_forget; GH_TOKEN=изсреды; token_startup </dev/null >/dev/null 2>&1; head -1 "$TOKEN_FILE" 2>/dev/null')
check [ "$r" = "изсреды" ]
# Повторное сохранение того же значения не делается: `grep -qv` тут не
# годится — он говорит «есть строка без слова», а нужно «слова нет вовсе».
check hasnt "$(tk http-ok 'token_save тот-же >/dev/null; GH_TOKEN=тот-же; token_startup </dev/null 2>&1')" 'Ключ сохранён'
check has   "$(tk http-ok 'token_forget; GH_TOKEN=новый; token_startup </dev/null 2>&1')" 'Ключ сохранён'
# При запуске негодный ключ удаляется, а не остаётся «как бы рабочим».
r=$(tk http-401 'token_save "старый" >/dev/null; token_startup </dev/null >/dev/null 2>&1; [ -f "$TOKEN_FILE" ] && printf "остался" || printf "удалён"')
check [ "$r" = "удалён" ]
# А при недоступном GitHub — остаётся: ключ не виноват.
r=$(tk http-nonet 'token_save "старый" >/dev/null; token_startup </dev/null >/dev/null 2>&1; [ -f "$TOKEN_FILE" ] && printf "остался" || printf "удалён"')
check [ "$r" = "остался" ]
# Ключ не уходит в argv: ни в проверке, ни в скачивании.
check hasnt "$(code | sed -n '/^_token_probe/,/^}/p')" '$TOKEN"'
check has "$(code | sed -n '/^token_check/,/^}/p')" 'header = "Authorization'
# Ключ читается во ВСЕХ путях, а не только в меню: иначе `--versions` на
# машине с сохранённым ключом отвечает «нет ключа».
check has "$(code | sed -n '/^main()/,/^}/p')" 'token_load'
# Проверка «это скрипт» не должна зависеть от гонки: конвейер
# `head | grep -q` под pipefail роняет загрузку через раз.
check hasnt "$(code)" 'head -c 200'
printf '#!/bin/bash\necho привет\n' > "$T/looks-yes.sh"
printf '<html>404</html>\n' > "$T/looks-no.html"
printf '' > "$T/looks-empty"
head -c 200000 /dev/urandom > "$T/looks-big"; printf '#!/bin/bash\n' | cat - "$T/looks-big" > "$T/looks-bigsh"
check vt "looks_like_script '$T/looks-yes.sh'"
check vt "! looks_like_script '$T/looks-no.html'"
check vt "! looks_like_script '$T/looks-empty'"
check vt "! looks_like_script '$T/нет-файла'"
# Большой файл с shebang — тот случай, где конвейер и падал.
check vt "looks_like_script '$T/looks-bigsh'"
# Сто повторов подряд: гонка проявлялась не каждый раз.
r=$(vt "n=0; for i in \$(seq 1 100); do looks_like_script '$T/looks-bigsh' && n=\$((n+1)); done; printf %s \$n")
check [ "$r" = "100" ]
# Качаем по хешу коммита, а не по имени ветки: у raw есть кэш на пять
# минут, и сразу после пуша он отдаёт прежний файл.
check has "$(code | sed -n '/^fetch_raw/,/^}/p')" 'ref_sha'
check has "$(code | sed -n '/^_ver_fetch_one/,/^}/p')" 'ref_sha'
check has "$(code | sed -n '/^ref_sha/,/^}/p')" 'commits/'
# Хеш берётся только из ответа API и только в нужном виде: GitHub отдаёт
# одни 40 знаков, остальное отбрасывается и длина сверяется.
check has "$(code | sed -n '/^ref_sha/,/^}/p')" 'application/vnd.github.sha'
check has "$(code | sed -n '/^ref_sha/,/^}/p')" '[^0-9a-f]'
check has "$(code | sed -n '/^ref_sha/,/^}/p')" '"${#sha}" -eq 40'
# Не удалось узнать хеш — качаем по ветке, а не падаем.
check has "$(code | sed -n '/^fetch_raw/,/^}/p')" '${ref}/${path}'
# Где взять ключ — говорится вместе со ссылкой на подписку.
check has "$(tk http-ok 'token_where 2>&1')" 'boosty.to'
check has "$(tk http-ok 'token_where 2>&1')" 'goinstall'
# Команда называется goinstall, прежнее имя остаётся ссылкой.
check has "$(code | grep GOINST_BIN=)" 'goinstall'
check has "$(code | grep GOINST_BIN_ALIAS=)" 'go-installer'
# Ссылку ставит _self_put — им пишет self_install и из файла, и из канала.
check has "$(code | sed -n '/^_self_put/,/^}/p')" 'ln -sf'
check has "$(code | sed -n '/^self_install/,/^}/p')" '_self_put "$0"'
# REVIEW-8 №4: временный файл свой у каждого запуска, общего goinstall.new нет.
check neg grep -q '\.new"' <<<"$(code | sed -n '/^_self_put/,/^}/p;/^self_update()/,/^}/p')"
check has "$(code | sed -n '/^self_update()/,/^}/p')" '_self_put "$tmp"'

echo "── кеш на минуту и автообновление меню"
# Срок кеша — минута: свежий пуш виден почти сразу.
check [ "$(vt 'printf %s "$VER_TTL"')" = "60" ]
# Протухшая запись — повод спросить заново, но не повод прятать ответ.
check vc 'printf "1 1.2.3\n" > "$T/vc/govless.main"; ! ver_cache_read govless main'
check [ "$(vc 'printf "1 1.2.3\n" > "$T/vc/govless.main"; ver_cache_get govless main')" = "1.2.3" ]
# Колонка версий не пустеет через минуту после опроса.
check [ "$(vcc 'printf "1 1.4.0\n" > "$T/vc/govless.main"; prod_best_remote govless')" = "main 1.4.0" ]
# Показ везде без срока, решение «спросить ли» — со сроком.
check hasnt "$(code)" '$(ver_cache_read '
check has "$(code | sed -n '/^versions_fetch/,/^}/p')" 'ver_cache_read'
# Вышло время ожидания — это такт обновления, а не выход из меню.
r=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; sleep 2 | { _menu_read_key 1; printf %s \"\$KEY\"; }")
check [ "$r" = "tick" ]
r=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; printf '' | { _menu_read_key 1; printf %s \"\$KEY\"; }")
check [ "$r" = "quit" ]
r=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; printf 'x' | { _menu_read_key 1; printf %s \"\$KEY\"; }")
check [ "$r" = "x" ]
# Без тайм-аута поведение прежнее: конец ввода — выход.
r=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; { _menu_read_key; printf %s \"\$KEY\"; } </dev/null")
check [ "$r" = "quit" ]
# Автообновление — только в главном меню.
check [ "$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'menu_items_main; printf %s "$MENU_REFRESH_SEC:$MENU_REFRESH_HOOK"')" = "180:menu_refresh_main" ]
check [ "$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'menu_items_main; menu_items_product godns; printf %s "$MENU_REFRESH_SEC:$MENU_REFRESH_HOOK:${MENU_FOOTER_INFO:-нет}"')" = "0::нет" ]
check has "$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'menu_items_main; printf %s "$MENU_FOOTER_INFO"')" 'раз в 3 мин'
check [ "$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'GOINST_MENU_REFRESH=0; menu_items_main; printf %s "$MENU_REFRESH_SEC:${MENU_FOOTER_INFO:-нет}"')" = "0:нет" ]
check [ "$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'GOINST_MENU_REFRESH=abc; menu_items_main; printf %s "$MENU_REFRESH_SEC"')" = "0" ]
# Такт опрашивает GitHub заново и пересобирает пункты.
check has "$(code | sed -n '/^menu_refresh_main/,/^}/p')" 'versions_fetch'
check has "$(code | sed -n '/^menu_refresh_main/,/^}/p')" 'menu_items_main'
# Обновление на месте: в ветке такта нет clear, отсчёт от SECONDS.
check has "$(code | sed -n '/^pick_menu/,/^}/p')" 'tick)'
check hasnt "$(code | sed -n '/^pick_menu/,/^}/p' | sed -n '/tick)/,/;;/p')" 'clear'
check has "$(code | sed -n '/^pick_menu/,/^}/p')" 'SECONDS'

echo "── goVLESS: ветка и версия читаются с клона, итог сверяется"
if command -v git >/dev/null 2>&1; then
GV="$T/gvrepo"; FSG="$T/fsgv"; rm -rf "$GV" "$FSG"; mkdir -p "$GV" "$FSG/opt"
(
  cd "$GV" || exit 1
  g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
  g init -q src && cd src && mkdir -p lib
  echo 'GOVLESS_VERSION="1.3.6"' > lib/common.sh && g add lib && g commit -qm "main"
  g checkout -qb dev && echo 'GOVLESS_VERSION="1.4.0"' > lib/common.sh && g commit -qam "dev"
  g checkout -q main && cd .. && g clone -q --bare src origin.git
) >/dev/null 2>&1
git -c init.defaultBranch=main clone -q -b main --depth 1 "file://$GV/origin.git" "$FSG/opt/govless-installer" >/dev/null 2>&1
gv() { T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSG" GOINST_VER_CACHE="$T/vc-gv" bash -c ". '$SCRIPT'; $*"; }
# Переключение так, как его делает загрузчик goVLESS с 1.3.7: все ветки,
# явная ссылка, checkout -B. goInstaller сам клон не трогает.
boot() {
  ( cd "$FSG/opt/govless-installer" || exit 1; B="$1"
    git config --replace-all remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    git fetch origin "+refs/heads/$B:refs/remotes/origin/$B" --quiet
    git checkout -q -f -B "$B" "origin/$B" ) >/dev/null 2>&1
}
check [ "$(gv 'prod_installed_ref govless')" = "main" ]
check [ "$(gv 'prod_version govless')" = "1.3.6" ]
boot dev
check [ "$(gv 'prod_installed_ref govless')" = "dev" ]
check [ "$(gv 'prod_version govless')" = "1.4.0" ]
boot main
check [ "$(gv 'prod_installed_ref govless')" = "main" ]
# Проверка после установки называет несменившуюся ветку, а не молчит.
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSG" GOINST_FAKE_INSTALLED=govless GOINST_VER_CACHE="$T/vc-gv" bash -c ". '$SCRIPT'; installer_postcheck govless dev" 2>&1); rc=$?
check [ "$rc" = "1" ]
check has "$out" 'Ветка не сменилась'
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSG" GOINST_FAKE_INSTALLED=govless GOINST_VER_CACHE="$T/vc-gv" bash -c ". '$SCRIPT'; installer_postcheck govless main" 2>&1); rc=$?
check [ "$rc" = "0" ]
check has "$out" 'Проверено'
mkdir -p "$T/vc-gv2"; printf '%s 1.3.9\n' "$(date +%s)" > "$T/vc-gv2/govless.main"
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSG" GOINST_FAKE_INSTALLED=govless GOINST_VER_CACHE="$T/vc-gv2" bash -c ". '$SCRIPT'; installer_postcheck govless main" 2>&1); rc=$?
check [ "$rc" = "1" ]
check has "$out" 'установка могла не дойти'
# Продукт не встал — это не «молчим», а итог словами (1.1.0, второй круг).
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSG" GOINST_FAKE_INSTALLED="" bash -c ". '$SCRIPT'; installer_postcheck govless dev 2>&1; echo \$?")
check [ "$(tail -1 <<<"$out")" = "1" ]
check has "$out" 'goVLESS pro не встал'
check has "$(code | sed -n '/^install_flow/,/^}/p')" 'installer_postcheck'
check has "$(code | sed -n '/^main()/,/^}/p')" 'installer_postcheck'
fi
# Клоны соседей goInstaller не правит: исправление смены ветки живёт в goVLESS.
check hasnt "$(code)" 'govless_prepare_ref_switch'
check hasnt "$(code)" 'remote.origin.fetch'

echo "── goVLESS: бесплатный Lite из инструкции — не goVLESS pro"
# Lite ставится туда же, куда pro: клон в /opt/govless-installer, настройки
# в /opt/govless/config.json, команда govless. goInstaller принимал его за pro:
# «установлен 1.3.6», а «Открыть меню продукта» запускал меню Lite.
FSL="$T/fslite"; rm -rf "$FSL" "$T/vc-lite"; mkdir -p "$T/vc-lite"
mkdir -p "$FSL/opt/govless-installer/.git" "$FSL/opt/govless-installer/lib" "$FSL/opt/govless"
lite_origin() {  # .git/config клона — так его пишет git clone
    printf '[core]\n\trepositoryformatversion = 0\n[remote "origin"]\n\turl = %s\n\tfetch = +refs/heads/main:refs/remotes/origin/main\n[branch "main"]\n\tremote = origin\n\tmerge = refs/heads/main\n' "$1" \
        > "$FSL/opt/govless-installer/.git/config"
}
LITE_URL=https://github.com/anten-ka/govless-lite-version.git
lite_origin "$LITE_URL"
printf 'GOVLESS_VERSION="1.3.6"\n' > "$FSL/opt/govless-installer/lib/common.sh"
printf '{"mode":"lite","version":"1.3.6"}\n' > "$FSL/opt/govless/config.json"
lv() { T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSL" GOINST_VER_CACHE="$T/vc-lite" bash -c ". '$SCRIPT'; $*"; }

# Узнаётся по origin клона, в любом написании адреса.
check lv 'prod_free_lite govless'
for u in https://github.com/anten-ka/govless-lite-version https://github.com/Anten-Ka/GoVLESS-Lite-Version.git/ \
         git@github.com:anten-ka/govless-lite-version.git https://x-access-token:t0k@github.com/anten-ka/govless-lite-version.git \
         https://github.com/someone/govless-lite-version.git; do
    lite_origin "$u"; check lv 'prod_free_lite govless'
done
# Клон pro — не Lite. Нет клона — не Lite. У других продуктов Lite не бывает.
lite_origin https://github.com/duboshin52/goVLESS.git
check lv '! prod_free_lite govless'
lite_origin "$LITE_URL"
check lv '! prod_free_lite gotelegram'
check [ "$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_FS_ROOT="$T/fs" bash -c ". '$SCRIPT'; prod_free_lite govless; echo \$?")" = "1" ]
# Запись без пробелов вокруг «=» и без перевода строки в конце — тоже origin.
printf '[remote "origin"]\nurl=%s' "$LITE_URL" > "$FSL/opt/govless-installer/.git/config"
check lv 'prod_free_lite govless'
check [ "$(lv 'git_origin "$GOINST_FS_ROOT/opt/govless-installer"')" = "$LITE_URL" ]
# origin ищется в своей секции: url соседнего remote — не origin.
printf '[remote "fork"]\n\turl = %s\n[remote "origin"]\n\turl = https://github.com/duboshin52/goVLESS.git\n' "$LITE_URL" > "$FSL/opt/govless-installer/.git/config"
check lv '! prod_free_lite govless'
lite_origin "$LITE_URL"

# Ветка клона Lite — не ветка pro: у Lite своя dev, умолчанием ей не быть.
check lv '! prod_installed_ref govless'

# Главное меню: жёлтое «бесплатный Lite», а не зелёное «установлен».
row=$(GOINST_FS_ROOT="$FSL" pf_env ss-govless units-govless nginx-govless os-ubuntu2404 govless 'menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}" | grep "^1|"')
check has "$row" '|y:бесплатный Lite 1.3.6|'
check hasnt "$row" 'установлен'
# Подменю: первым пунктом — pro поверх Lite, пункта «Открыть меню продукта» нет.
items=$(GOINST_FS_ROOT="$FSL" pf_env ss-govless units-govless nginx-govless os-ubuntu2404 govless 'menu_items_product govless; printf "%s\n" "${MENU_ITEMS[@]}"')
check has "$items" '1|Поставить goVLESS pro поверх Lite|y:бесплатный Lite 1.3.6|'
check hasnt "$items" 'Открыть меню продукта'
check [ "$(sed -n 's/|.*//p' <<<"$items" | tr -d '\n-')" = "130" ]
# А у настоящего goVLESS pro подменю прежнее.
lite_origin https://github.com/duboshin52/goVLESS.git
items=$(GOINST_FS_ROOT="$FSL" pf_env ss-govless units-govless nginx-govless os-ubuntu2404 govless 'menu_items_product govless; printf "%s\n" "${MENU_ITEMS[@]}"')
check has "$items" 'Открыть меню продукта'
check [ "$(sed -n 's/|.*//p' <<<"$items" | tr -d '\n-')" = "1230" ]
lite_origin "$LITE_URL"

# Меню исполняется: Enter на первом пункте ставит pro, а команду Lite НЕ
# запускает. Команда govless подложена и пишет в тот же журнал.
mkdir -p "$T/fakebin"
printf '#!/bin/bash\necho "cmd govless" >> "%s/calls.log"\n' "$T" > "$T/fakebin/govless"; chmod +x "$T/fakebin/govless"
calls=$(PATH="$T/fakebin:$PATH" GOINST_FS_ROOT="$FSL" drive '1 1' govless)
check has "$calls" 'install_flow govless'
check hasnt "$calls" 'cmd govless'
lite_origin https://github.com/duboshin52/goVLESS.git
calls=$(PATH="$T/fakebin:$PATH" GOINST_FS_ROOT="$FSL" drive '1 1' govless)
check has "$calls" 'cmd govless'
check hasnt "$calls" 'install_flow'
lite_origin "$LITE_URL"

# --list и --versions говорят «Lite», а не «установлен».
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_NO_NET=1 GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_FAKE_INSTALLED=govless GOINST_FS_ROOT="$FSL" bash "$SCRIPT" --list 2>&1)
check has "$(grep 'goVLESS pro' <<<"$out")" '[бесплатный Lite 1.3.6]'
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_NO_NET=1 GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_FAKE_INSTALLED=govless GOINST_FS_ROOT="$FSL" GOINST_VER_CACHE="$T/vc-lite" bash "$SCRIPT" --versions 2>&1)
check has "$(grep 'goVLESS pro' <<<"$out")" 'Lite 1.3.6'

# Установка: сначала пояснение, режим Lite берётся из настроек, вопрос
# называет установку поверх Lite. «2) Нет» — ничего не запускается.
fl() {  # fl <ответ на вопрос> → вывод install_flow с заглушками вокруг
    (
        export T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_FS_ROOT="$FSL"
        export GOINST_FAKE_INSTALLED="${GOINST_FAKE_INSTALLED-govless}" GOINST_VER_CACHE="$T/vc-lite"
        . "$SCRIPT"
        preflight() { echo "preflight $1 $2"; PF_LINES=""; return 0; }
        ask_ref() { REF=main; return 0; }
        run_product_installer() { echo "RUN $1"; return 0; }
        installer_postcheck() { echo "POSTCHECK $1 $2"; return 0; }
        printf '%s\n\n' "$1" | install_flow govless 2>&1
    )
}
out=$(fl 2)
check has "$out" 'На сервере бесплатный Lite из инструкции'
check has "$out" 'ключи и пользователи останутся'
check has "$out" 'preflight govless lite'
check has "$out" 'Поставить goVLESS pro поверх Lite — ветка main'
check hasnt "$out" 'RUN govless'
out=$(fl 1)
check has "$out" 'RUN govless'
check has "$out" 'POSTCHECK govless main'
# Пояснение — ДО первого вопроса и до проверки портов.
check [ "$(grep -n -m1 'бесплатный Lite из инструкции' <<<"$out" | cut -d: -f1)" -lt "$(grep -n -m1 'preflight govless' <<<"$out" | cut -d: -f1)" ]
# У настоящего pro пояснения нет, вопрос прежний.
lite_origin https://github.com/duboshin52/goVLESS.git
out=$(fl 2)
check hasnt "$out" 'бесплатный Lite'
check has "$out" 'Запустить установщик goVLESS pro — ветка main'
lite_origin "$LITE_URL"
# Недоустановленный Lite (клон есть, панели нет) — обычная установка: ни
# панели, ни ключей, которые «останутся», там нет.
out=$(GOINST_FAKE_INSTALLED="" fl 2)
check hasnt "$out" 'бесплатный Lite'
check has "$out" 'Запустить установщик goVLESS pro — ветка main'
# Путь --install зовёт то же пояснение.
check has "$(code | sed -n '/^main()/,/^}/p' | sed -n '/--install)/,/;;/p')" 'free_takeover_note'

# Проверка после установки: остался клон Lite — pro не встал, как бы ни
# рапортовал загрузчик. С локальным источником клон не трогается — молчим.
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSL" GOINST_FAKE_INSTALLED=govless GOINST_VER_CACHE="$T/vc-lite" bash -c ". '$SCRIPT'; installer_postcheck govless main" 2>&1); rc=$?
check [ "$rc" = "1" ]
check has "$out" 'по-прежнему от бесплатного Lite'
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSL" GOINST_FAKE_INSTALLED=govless GOINST_VER_CACHE="$T/vc-lite" GOINST_SRC_govless="$T/src-govless" bash -c ". '$SCRIPT'; installer_postcheck govless main" 2>&1)
check hasnt "$out" 'бесплатного Lite'
# Клон заменён загрузчиком pro — проверка проходит.
lite_origin https://github.com/duboshin52/goVLESS.git
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSL" GOINST_FAKE_INSTALLED=govless GOINST_VER_CACHE="$T/vc-lite" bash -c ". '$SCRIPT'; installer_postcheck govless main" 2>&1); rc=$?
check [ "$rc" = "0" ]
check hasnt "$out" 'Lite'
lite_origin "$LITE_URL"
# Сам goInstaller клон Lite не удаляет и не двигает: замена живёт в загрузчике pro.
check [ -z "$(code | grep -E '(rm|mv) [^|;]*govless-installer')" ]

echo "── goKaskad: бесплатный Kaskad из инструкции — не goKaskad pro"
# Бесплатный Kaskad копирует себя в ту же /usr/local/bin/gokaskad, и
# goInstaller принимал его за pro: «установлен», а «Открыть меню продукта»
# запускал бесплатное меню. Строки KASKAD_VERSION= в нём нет ни в одной версии.
FSK="$T/fskaskad"; rm -rf "$FSK" "$T/vc-kaskad"; mkdir -p "$FSK/usr/local/bin" "$T/vc-kaskad"
kfree() { printf '#!/bin/bash\n# Автоматическое создание глобальной команды gokaskad\necho "anten-ka канал представляет"\n' > "$FSK/usr/local/bin/gokaskad"; chmod +x "$FSK/usr/local/bin/gokaskad"; }
kpro()  { printf '#!/bin/bash\nKASKAD_VERSION="2.12"\n# gokaskad\n' > "$FSK/usr/local/bin/gokaskad"; chmod +x "$FSK/usr/local/bin/gokaskad"; }
kv() { T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSK" GOINST_VER_CACHE="$T/vc-kaskad" bash -c ". '$SCRIPT'; $*"; }
kfree
check [ "$(kv 'prod_free_edition gokaskad')" = "Kaskad" ]
check [ "$(kv 'prod_free_edition govless; echo $?')" = "1" ]
kpro
check kv '! prod_free_edition gokaskad'
rm -f "$FSK/usr/local/bin/gokaskad"
check kv '! prod_free_edition gokaskad'
kfree
# Меню: жёлтое «бесплатный Kaskad», первым пунктом — pro поверх, без «Открыть».
row=$(GOINST_FS_ROOT="$FSK" pf_env ss-empty units-empty nginx-empty os-ubuntu2404 gokaskad 'menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}" | grep "^4|"')
check has "$row" '|y:бесплатный Kaskad|'
items=$(GOINST_FS_ROOT="$FSK" pf_env ss-empty units-empty nginx-empty os-ubuntu2404 gokaskad 'menu_items_product gokaskad; printf "%s\n" "${MENU_ITEMS[@]}"; echo "W=$MENU_W_NAME"')
check has "$items" '1|Поставить goKaskad pro поверх Kaskad|y:бесплатный Kaskad|'
check hasnt "$items" 'Открыть меню продукта'
check [ "$(sed -n 's/|.*//p' <<<"$items" | tr -d '\n-')" = "130" ]
# Длинное имя пункта раздвигает колонку, а не наезжает на соседнюю.
check has "$items" 'W=36'
# Прогон клавишами: Enter на первом пункте ставит pro, бесплатную команду не зовёт.
printf '#!/bin/bash\necho "cmd gokaskad" >> "%s/calls.log"\n' "$T" > "$T/fakebin/gokaskad"; chmod +x "$T/fakebin/gokaskad"
calls=$(PATH="$T/fakebin:$PATH" GOINST_FS_ROOT="$FSK" drive '4 1' gokaskad)
check has "$calls" 'install_flow gokaskad'
check hasnt "$calls" 'cmd gokaskad'
kpro
calls=$(PATH="$T/fakebin:$PATH" GOINST_FS_ROOT="$FSK" drive '4 1' gokaskad)
check has "$calls" 'cmd gokaskad'
check hasnt "$calls" 'install_flow'
kfree
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_NO_NET=1 GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_FAKE_INSTALLED=gokaskad GOINST_FS_ROOT="$FSK" GOINST_VER_CACHE="$T/vc-kaskad" bash "$SCRIPT" --list 2>&1)
check has "$(grep 'goKaskad pro' <<<"$out")" '[бесплатный Kaskad]'
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_NO_NET=1 GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_FAKE_INSTALLED=gokaskad GOINST_FS_ROOT="$FSK" GOINST_VER_CACHE="$T/vc-kaskad" bash "$SCRIPT" --versions 2>&1)
check has "$(grep 'goKaskad pro' <<<"$out")" 'Kaskad'
# Установка: пояснение про команду и правила, вопрос — «поверх Kaskad».
fk() {
    (
        export T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_FS_ROOT="$FSK"
        export GOINST_FAKE_INSTALLED="${GOINST_FAKE_INSTALLED-gokaskad}" GOINST_VER_CACHE="$T/vc-kaskad"
        . "$SCRIPT"
        preflight() { echo "preflight $1 $2"; PF_LINES=""; return 0; }
        ask_ref() { REF=main; return 0; }
        run_product_installer() { echo "RUN $1"; return 0; }
        installer_postcheck() { echo "POSTCHECK $1 $2"; return 0; }
        printf '%s\n\n' "$1" | install_flow gokaskad 2>&1
    )
}
out=$(fk 2)
check has "$out" 'На сервере бесплатный Kaskad из инструкции'
check has "$out" 'правила каскада бесплатной версии возьмёт себе'
check has "$out" 'Поставить goKaskad pro поверх Kaskad — ветка main'
check hasnt "$out" 'RUN gokaskad'
check has "$(fk 1)" 'RUN gokaskad'
kpro
out=$(fk 2)
check hasnt "$out" 'бесплатный Kaskad'
check has "$out" 'Запустить установщик goKaskad pro — ветка main'
kfree
# После установки: бесплатная команда на месте — pro не встал, и это сказано.
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSK" GOINST_FAKE_INSTALLED=gokaskad GOINST_VER_CACHE="$T/vc-kaskad" bash -c ". '$SCRIPT'; installer_postcheck gokaskad main" 2>&1); rc=$?
check [ "$rc" = "1" ]
check has "$out" 'по-прежнему бесплатный Kaskad'
check hasnt "$out" 'Проверено'
kpro
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSK" GOINST_FAKE_INSTALLED=gokaskad GOINST_VER_CACHE="$T/vc-kaskad" bash -c ". '$SCRIPT'; installer_postcheck gokaskad main" 2>&1); rc=$?
check [ "$rc" = "0" ]

echo "── goTelegram: прежний MTProxy и бесплатный скрипт поверх pro"
# Бесплатный MTProxy держит прокси в контейнере mtproto-proxy (mtg) на 443.
# Проверка звала его чужим и запрещала режим pro, хотя установщик goTelegram
# pro сам находит этот контейнер и останавливает его.
cat > "$T/ss-mtproxy" <<'SS'
tcp   LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=500,fd=3))
tcp   LISTEN 0      4096         0.0.0.0:443       0.0.0.0:*    users:(("docker-proxy",pid=4001,fd=7))
SS
printf '500=ssh.service\n4001=docker.service\n' > "$T/units-mtproxy"
printf 'mtproto-proxy 0.0.0.0:443->443/tcp, [::]:443->443/tcp\n' > "$T/docker-mtproxy"
gt() {  # gt <установлено> <продукт> <режим> → rc и PF_LINES
    (
        export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
        export GOINST_SS_FIXTURE="$T/ss-mtproxy" GOINST_UNIT_FIXTURE="$T/units-mtproxy"
        export GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_OS_RELEASE="$T/os-ubuntu2404"
        export GOINST_FAKE_INSTALLED="$1" GOINST_LE_ROOT="$T/le-empty"
        export GOINST_DOCKER_FIXTURE="$T/docker-mtproxy" GOINST_ARCH=x86_64
        . "$SCRIPT"; os_detect
        preflight "$2" "$3" >/dev/null 2>&1
        echo "rc=$?"; printf '%s' "$PF_LINES"
    )
}
check [ "$(ml 'container_product mtproto-proxy')" = "mtproxy" ]
check [ "$(ml 'prod_name mtproxy')" = "MTProxy (mtg)" ]
for m in pro lite; do
    r=$(gt "" gotelegram "$m")
    check has "$r" 'rc=2'
    check has "$r" '443/tcp|own|'
    check has "$r" 'rule|soft|gotelegram-old-mtproxy|mtproxy'
done
# Режим pro больше не закрыт: в меню не «только Lite», а «готов, есть замечания».
rdy=$( export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_SS_FIXTURE="$T/ss-mtproxy" \
         GOINST_UNIT_FIXTURE="$T/units-mtproxy" GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_OS_RELEASE="$T/os-ubuntu2404" \
         GOINST_FAKE_INSTALLED="" GOINST_LE_ROOT="$T/le-empty" GOINST_DOCKER_FIXTURE="$T/docker-mtproxy"
       . "$SCRIPT"; os_detect; prod_readiness gotelegram )
check [ "$rdy" = "y:готов, есть замечания" ]
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-mtproxy" GOINST_UNIT_FIXTURE="$T/units-mtproxy" GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_FAKE_INSTALLED="" GOINST_LE_ROOT="$T/le-empty" GOINST_DOCKER_FIXTURE="$T/docker-mtproxy" bash "$SCRIPT" --check gotelegram pro 2>&1)
check has "$out" 'прежний MTProxy, его остановит goTelegram pro'
check has "$out" 'Секрет не переносится'
check hasnt "$out" 'Ставить нельзя'
# Соседу 443 по-прежнему занят — и назван прежним MTProxy.
r=$(gt "" govless lite)
check has "$r" 'rc=1'
check has "$r" '443/tcp|busy|must|mtproxy|docker:mtproto-proxy'
# Бесплатный скрипт, запущенный после pro, подменяет команду (с 2.10.50) или
# сам установщик (раньше, через симлинк). goInstaller видел «установлен» и
# пунктом меню запускал бесплатный скрипт.
FSG2="$T/fsgt"; rm -rf "$FSG2" "$T/vc-gt"; mkdir -p "$FSG2/opt/gotelegram/lib" "$FSG2/usr/local/bin" "$T/vc-gt"
printf 'GOTELEGRAM_VERSION="2.10.50"\n' > "$FSG2/opt/gotelegram/lib/common.sh"
gtpro()  { printf '#!/bin/bash\nexec bash /opt/gotelegram/install.sh "$@"\n' > "$FSG2/usr/local/bin/gotelegram"; printf '#!/bin/bash\n# goTelegram pro\ndocker inspect "$V1_CONTAINER_NAME"\n' > "$FSG2/opt/gotelegram/install.sh"; chmod +x "$FSG2/usr/local/bin/gotelegram"; }
gtfree() { printf '#!/bin/bash\ncp "$0" /usr/local/bin/gotelegram\nsecret=$(docker inspect mtproto-proxy --format x)\n' > "$FSG2/usr/local/bin/gotelegram"; chmod +x "$FSG2/usr/local/bin/gotelegram"; }
gv2() { T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSG2" GOINST_VER_CACHE="$T/vc-gt" bash -c ". '$SCRIPT'; $*"; }
gtpro
check gv2 '! prod_free_edition gotelegram'
gtfree
check [ "$(gv2 'prod_free_edition gotelegram')" = "MTProxy" ]
# Старый случай: бесплатный скрипт записан через симлинк прямо в установщик pro.
gtpro; cp "$FSG2/usr/local/bin/gotelegram" "$FSG2/usr/local/bin/gotelegram.bak"; printf '#!/bin/bash\nsecret=$(docker inspect mtproto-proxy --format x)\n' > "$FSG2/opt/gotelegram/install.sh"
check [ "$(gv2 'prod_free_edition gotelegram')" = "MTProxy" ]
gtpro; gtfree
row=$(GOINST_FS_ROOT="$FSG2" pf_env ss-empty units-empty nginx-empty os-ubuntu2404 gotelegram 'menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}" | grep "^2|"')
check has "$row" '|y:бесплатный MTProxy|'
check hasnt "$row" '2.10.50'
items=$(GOINST_FS_ROOT="$FSG2" pf_env ss-empty units-empty nginx-empty os-ubuntu2404 gotelegram 'menu_items_product gotelegram; printf "%s\n" "${MENU_ITEMS[@]}"')
check has "$items" '1|Поставить goTelegram pro поверх MTProxy|y:бесплатный MTProxy|'
check hasnt "$items" 'Открыть меню продукта'
printf '#!/bin/bash\necho "cmd gotelegram" >> "%s/calls.log"\n' "$T" > "$T/fakebin/gotelegram"; chmod +x "$T/fakebin/gotelegram"
calls=$(PATH="$T/fakebin:$PATH" GOINST_FS_ROOT="$FSG2" drive '2 1' gotelegram)
check has "$calls" 'install_flow gotelegram'
check hasnt "$calls" 'cmd gotelegram'
gtpro
calls=$(PATH="$T/fakebin:$PATH" GOINST_FS_ROOT="$FSG2" drive '2 1' gotelegram)
check has "$calls" 'cmd gotelegram'
gtfree
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_NO_NET=1 GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_FAKE_INSTALLED=gotelegram GOINST_FS_ROOT="$FSG2" GOINST_VER_CACHE="$T/vc-gt" bash "$SCRIPT" --list 2>&1)
check has "$(grep 'goTelegram pro' <<<"$out")" '[бесплатный MTProxy]'
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSG2" GOINST_FAKE_INSTALLED=gotelegram GOINST_VER_CACHE="$T/vc-gt" bash -c ". '$SCRIPT'; free_takeover_note gotelegram" 2>&1)
check has "$out" 'Команда gotelegram сейчас открывает бесплатный MTProxy'
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FS_ROOT="$FSG2" GOINST_FAKE_INSTALLED=gotelegram GOINST_VER_CACHE="$T/vc-gt" bash -c ". '$SCRIPT'; installer_postcheck gotelegram main" 2>&1); rc=$?
check [ "$rc" = "1" ]
check has "$out" 'по-прежнему бесплатный MTProxy'

echo "── goVLESS: панель 3X-UI из другой инструкции — не остатки goVLESS pro"
# x-ui — штатный юнит любой 3X-UI. Панель, поставленную по старой инструкции
# или руками, проверка звала «остатками прежней установки goVLESS pro» и
# запрещала ставить, хотя установщик goVLESS pro такую панель берёт себе.
cat > "$T/ss-xui" <<'SS'
tcp   LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=500,fd=3))
tcp   LISTEN 0      4096               *:443             *:*    users:(("xray-linux-amd6",pid=3001,fd=9))
tcp   LISTEN 0      4096               *:2053            *:*    users:(("x-ui",pid=3003,fd=7))
SS
printf '500=ssh.service\n3001=x-ui.service\n3003=x-ui.service\n' > "$T/units-xui"
FSX="$T/fsxui"; rm -rf "$FSX"; mkdir -p "$FSX/usr/local/x-ui"; : > "$FSX/usr/local/x-ui/x-ui"
# Владелец: 3X-UI, пока goVLESS pro не стоит; goVLESS pro — когда стоит.
check [ "$(GOINST_FS_ROOT="$FSX" pf_env ss-xui units-xui nginx-empty os-ubuntu2404 "" 'holder_product xray-linux-amd6 3001')" = "xui" ]
check [ "$(GOINST_FS_ROOT="$FSX" pf_env ss-xui units-xui nginx-empty os-ubuntu2404 "govless" 'holder_product xray-linux-amd6 3001')" = "govless" ]
check [ "$(GOINST_FS_ROOT="$FSX" pf_env ss-xui units-xui nginx-empty os-ubuntu2404 "" 'holder_product xray 999999')" = "xui" ]
check [ "$(ml 'prod_name xui')" = "3X-UI" ]
for m in lite pro; do
    r=$(GOINST_FS_ROOT="$FSX" pf ss-xui units-xui nginx-empty os-ubuntu2404 "" govless "$m")
    # Не препятствие: порт остаётся за тем же xray, панель забирает goVLESS pro.
    check has "$r" 'rc=2'
    check has "$r" '443/tcp|own|must|xui'
    check has "$r" 'rule|soft|govless-foreign-panel|xui'
    # И в режиме pro его «убийство чужого на 443» xray не касается.
    check hasnt "$r" 'govless-kills-443'
done
check [ "$(GOINST_FS_ROOT="$FSX" rd ss-xui units-xui nginx-empty os-ubuntu2404 "" govless)" = "y:готов, есть замечания" ]
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-xui" GOINST_UNIT_FIXTURE="$T/units-xui" GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_FAKE_INSTALLED="" GOINST_LE_ROOT="$T/le-empty" GOINST_FS_ROOT="$FSX" bash "$SCRIPT" --check govless lite 2>&1)
check has "$out" 'Панель 3X-UI поставлена не goVLESS pro'
check has "$out" 'её возьмёт goVLESS pro'
check has "$out" 'Готовое подключение Reality на 443'
check hasnt "$out" 'остатки прежней установки'
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-xui" GOINST_UNIT_FIXTURE="$T/units-xui" GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_FAKE_INSTALLED="" GOINST_LE_ROOT="$T/le-empty" GOINST_FS_ROOT="$FSX" bash "$SCRIPT" --check govless pro 2>&1)
check has "$out" 'Готовое подключение TLS на 443'
# Замечание только про чужую панель: без неё его нет.
r=$(pf ss-empty units-empty nginx-empty os-ubuntu2404 "" govless lite)
check hasnt "$r" 'govless-foreign-panel'
# Соседу панель мешает как 3X-UI, а не как goVLESS pro.
r=$(GOINST_FS_ROOT="$FSX" pf ss-xui units-xui nginx-empty os-ubuntu2404 "" gotelegram pro)
check has "$r" 'rc=1'
check has "$r" '443/tcp|busy|must|xui|xray'
check has "$r" 'rule|info|shared443-hint|xui'
check [ "$(GOINST_FS_ROOT="$FSX" pf_env ss-xui units-xui nginx-empty os-ubuntu2404 "" 'preflight gotelegram pro >/dev/null 2>&1; _pf_first_blocker')" = "443 занят: 3X-UI" ]
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-xui" GOINST_UNIT_FIXTURE="$T/units-xui" GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_FAKE_INSTALLED="" GOINST_FS_ROOT="$FSX" bash "$SCRIPT" --ports 2>&1)
check has "$out" '3X-UI (без goVLESS pro)'

echo "── язык: спрашивается первым и запоминается"
rm -rf "$T/fslang"; mkdir -p "$T/fslang/opt"
lg() { T="$T" GOINST_SOURCE_ONLY=1 GOINST_FS_ROOT="$T/fslang" GOINST_LANG_FILE="$T/fslang/goinst.language" bash -c ". '$SCRIPT'; $*"; }
# Экран выбора: 1 — русский, 2 — английский, Enter — умолчание.
check [ "$(printf '1\n' | lg 'lang_pick >/dev/null 2>&1; printf %s "$LANG_CODE:$LANG_ASKED"')" = "ru:yes" ]
check [ "$(printf '2\n' | lg 'lang_pick >/dev/null 2>&1; printf %s "$LANG_CODE:$LANG_ASKED"')" = "en:yes" ]
check [ "$(printf '\n'  | lg 'lang_pick >/dev/null 2>&1; printf %s "$LANG_CODE"')" = "ru" ]
check [ "$(printf '\n'  | lg 'lang_pick en >/dev/null 2>&1; printf %s "$LANG_CODE"')" = "en" ]
# Enter берёт язык, уже выбранный в соседнем продукте.
mkdir -p "$T/fslang/opt/godns"; printf 'en\n' > "$T/fslang/opt/godns/.language"
check [ "$(printf '\n' | lg 'lang_pick >/dev/null 2>&1; printf %s "$LANG_CODE"')" = "en" ]
rm -rf "$T/fslang/opt/godns"
# Буквы и чужие цифры ответом не считаются; три промаха — отказ.
check [ "$(printf '9\nда\n3\n' | lg 'lang_pick >/dev/null 2>&1; echo $?')" = "1" ]
# Ctrl-D — отмена, а не согласие с умолчанием.
check [ "$(lg 'lang_pick </dev/null >/dev/null 2>&1; echo $?')" = "1" ]
# Экран выбора сам на двух языках: язык человека ещё неизвестен.
check has "$(printf '1\n' | lg 'lang_pick 2>&1 >/dev/null' | sed $'s/\x1b\\[[0-9;]*m//g')" 'Выберите язык / Choose language'
# Без терминала, с GOINST_LANG или с запомненным выбором вопроса нет.
check [ "$(lg 'lang_startup </dev/null >/dev/null 2>&1; printf %s "rc=$?:${LANG_ASKED:-нет}"')" = "rc=0:нет" ]
check [ "$(GOINST_LANG=en lg 'lang_startup </dev/null >/dev/null 2>&1; printf %s "rc=$?:${LANG_ASKED:-нет}"')" = "rc=0:нет" ]
printf 'en\n' > "$T/fslang/goinst.language"
check [ "$(lg 'lang_startup </dev/null >/dev/null 2>&1; printf %s "rc=$?:${LANG_ASKED:-нет}:$LANG_CODE"')" = "rc=0:нет:en" ]
rm -f "$T/fslang/goinst.language"
# Записывается только спрошенное.
check [ "$(lg 'LANG_CODE=en; LANG_ASKED=yes; lang_persist; cat "$GOINST_LANG_FILE"')" = "en" ]
check [ "$(lg 'rm -f "$GOINST_LANG_FILE"; LANG_CODE=ru; LANG_ASKED=""; lang_persist; [ -f "$GOINST_LANG_FILE" ] && echo есть || echo нет')" = "нет" ]
# Запомненный выбор сильнее соседа и локали.
printf 'en\n' > "$T/fslang/goinst.language"; mkdir -p "$T/fslang/opt/govless"; printf 'ru\n' > "$T/fslang/opt/govless/.language"
check [ "$(LANG=ru_RU.UTF-8 lg 'printf %s "$(_pick_lang)"')" = "en" ]
rm -f "$T/fslang/goinst.language"
# Маркер goAmnezia теперь читается наравне с остальными.
rm -rf "$T/fslang/opt/govless"; mkdir -p "$T/fslang/opt/goamnezia"; printf 'ru\n' > "$T/fslang/opt/goamnezia/.language"
check [ "$(LC_ALL= LANG=en_US.UTF-8 lg 'printf %s "$(_pick_lang)"')" = "ru" ]
rm -rf "$T/fslang/opt/goamnezia"
# Порядок в main: сначала язык, потом проверки; запись — после root.
mb=$(code | sed -n '/^main()/,/^}/p')
lno() { grep -n -m1 -F -- "$1" <<<"$mb" | cut -d: -f1; }
check [ -n "$(lno 'lang_startup')" ]
check [ "$(lno 'lang_startup')" -lt "$(lno 'BASH_VERSINFO')" ]
check [ "$(lno 'lang_startup')" -lt "$(lno 'os_gate_common')" ]
check [ "$(lno 'lang_startup')" -lt "$(lno 'token_startup')" ]
check [ "$(lno 'id -u')" -lt "$(lno 'lang_persist')" ]
# Язык меняется из главного меню.
check has "$(code | sed -n '/^main_menu/,/^}/p')" 'lang_pick'

echo "── названия: «pro» у всех шести"
# Требование заказчика — «pro» везде и строчными. goVLESS до 0.9.1 стоял в
# меню без него: таблица имён писалась руками, а проверки на неё не было.
for id in govless gotelegram godns gokaskad gowarp goamnezia; do
    nm=$(ml "prod_name $id")
    check [ "${nm% pro}" != "$nm" ]
done
# В строках кода название без «pro» не встречается. Хвостовой комментарий
# отсекается: в нём речь о кодовой базе. Репозиторий и путь — не название.
bare_names() { perl -ne 's/\s#\s.*$//; print if /(?<![\/\w-])go(?:VLESS|Telegram|DNS|Kaskad|WARP|Amnezia)(?! pro)(?![\w\/-])(?!\.\w)/'; }
check [ -z "$(code | bare_names)" ]
check [ "$(code | grep -c 'bi "')" -gt 100 ]
# Страж ловит то, ради чего написан, и не ловит репозиторий, путь, имя с pro.
check [ -n "$(printf '%s\n' 'warn "$(bi "443 держит goDNS" "443 is held by goDNS")"' | bare_names)" ]
# В конце предложения тоже: первая версия стража исключала точку целиком
# ради «goVLESS.git» и пропускала «…поставленный не goWARP.».
check [ -n "$(printf '%s\n' 'err "$(bi "поставленный не goWARP." "not installed by goWARP.")"' | bare_names)" ]
check [ -z "$(printf '%s\n' 'r=duboshin52/goVLESS' 'd="$HOME/goVLESS"' 'u=goVLESS.git' 'say "goDNS pro."' 'x=1   # у goDNS так' | bare_names)" ]
# Скобки в русской и английской половинах сходятся одинаково. Подсказка
# ключа goWARP печатала «(из группы)):»: закрывающая скобка английской
# половины стояла за кавычкой и доставалась обоим языкам.
paren_pairs() { perl -ne 'while (/\bbi "([^"\$]*)" "([^"\$]*)"/g) { my ($a,$b)=($1,$2); $t++; print "diff\n" if ($a=~tr/(//)-($a=~tr/)//) != ($b=~tr/(//)-($b=~tr/)//) } END { print "pairs=", $t+0, "\n" }'; }
out=$(code | paren_pairs)
check hasnt "$out" 'diff'
check [ "$(sed -n 's/^pairs=//p' <<<"$out")" -gt 100 ]
check has "$(printf '%s\n' 'read_line k "  $(bi "Ключ (из группы)" "Key (from the group")): "' | paren_pairs)" 'diff'

echo "── GitHub: условные запросы и общий лимит"
# Ключ клуба один на всех, а лимит GitHub — 5000 запросов в час на всех.
# Поддельный curl отвечает как GitHub: код, ETag, тело и заголовки берёт из
# файлов, на совпавший If-None-Match отвечает 304 и пишет журнал запросов.
FG="$T/fakegh-data"; mkdir -p "$T/fakegh" "$FG"
cat > "$T/fakegh/curl" <<'FAKE'
#!/bin/bash
out="" hdr="" wfmt="" url="" inm="" fail=no
while [ $# -gt 0 ]; do
    case "$1" in
        # Как настоящий curl: выход с ошибкой на 4xx — только с опцией fail.
        # Без этого подделка прятала ошибку 0.9.5: там проверка ключа шла без
        # fail, получала 403 как есть и стирала ключ.
        --config|-K) grep -qx 'fail' "$2" 2>/dev/null && fail=yes; shift ;;
        -f|--fail) fail=yes ;;
        --max-time|-m|--connect-timeout) shift ;;
        -o) out="$2"; shift ;;
        -D) hdr="$2"; shift ;;
        -w) wfmt="$2"; shift ;;
        -H) case "$2" in If-None-Match:*) inm="${2#If-None-Match: }" ;; esac; shift ;;
        http*) url="$1" ;;
    esac
    shift
done
key="${url#https://}"; key="${key//[^A-Za-z0-9._-]/_}"
code=$(cat "$FAKEGH/$key.code" 2>/dev/null || echo 404)
etag=$(cat "$FAKEGH/$key.etag" 2>/dev/null)
if [ "$code" = 200 ] && [ -n "$inm" ] && [ "$inm" = "$etag" ]; then code=304; fi
c=no; [ -n "$inm" ] && c=yes
echo "$key cond=$c $code" >> "$FAKEGH/log"
if [ -n "$hdr" ]; then
    { printf 'HTTP/2 %s\r\n' "$code"; [ -n "$etag" ] && printf 'etag: %s\r\n' "$etag"; cat "$FAKEGH/$key.hdr" 2>/dev/null; } > "$hdr"
fi
if [ "$code" = 200 ] && [ -n "$out" ]; then cat "$FAKEGH/$key.body" > "$out" 2>/dev/null; fi
[ -n "$wfmt" ] && printf '%s' "$code"
if [ "$fail" = yes ]; then case "$code" in 4*|5*) exit 22 ;; esac; fi
exit 0
FAKE
chmod +x "$T/fakegh/curl"
fg_set() {  # fg_set <url> <код> [тело] [etag] [доп. заголовки]
    local k="${1#https://}"; k="${k//[^A-Za-z0-9._-]/_}"
    printf '%s' "$2" > "$FG/$k.code"; printf '%s' "${3:-}" > "$FG/$k.body"
    if [ -n "${4:-}" ]; then printf '%s' "$4" > "$FG/$k.etag"; else rm -f "$FG/$k.etag"; fi
    if [ -n "${5:-}" ]; then printf '%b' "$5" > "$FG/$k.hdr"; else rm -f "$FG/$k.hdr"; fi
}
ghx() {  # функции скрипта с поддельным GitHub и своим кешем
    PATH="$T/fakegh:$PATH" FAKEGH="$FG" T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru \
    GOINST_VER_CACHE="$T/vc-gh" bash -c "mkdir -p '$T/vc-gh'; . '$SCRIPT'; printf 'silent\n' > '$T/gh.cfg'; $*"
}
lg_count() { grep -c -F -- "$1" "$FG/log" 2>/dev/null || true; }
SHA1=1111111111111111111111111111111111111111
API=https://api.github.com/repos/duboshin52/goDNS
fg_set "$API/commits/main" 200 "$SHA1" "\"$SHA1\""
# JSON — по строкам, как его отдаёт GitHub: разбор идёт построчно.
fg_set "$API/branches?per_page=100" 200 $'[\n  {\n    "name": "dev"\n  },\n  {\n    "name": "main"\n  }\n]' '"br1"'
fg_set "https://raw.githubusercontent.com/duboshin52/goDNS/$SHA1/lib/common.sh" 200 'GODNS_VERSION="1.0.1"'
: > "$FG/log"
# Первый вопрос обычный, второй — условный: ответ 304 «не изменилось» в
# лимит не засчитывается, а хеш тот же.
check [ "$(ghx "ref_sha duboshin52/goDNS main '$T/gh.cfg'")" = "$SHA1" ]
check [ "$(ghx "ref_sha duboshin52/goDNS main '$T/gh.cfg'")" = "$SHA1" ]
check [ "$(lg_count 'commits_main cond=no 200')" -eq 1 ]
check [ "$(lg_count 'commits_main cond=yes 304')" -eq 1 ]
# Мусор вместо хеша не принимается: качать по нему было бы нечего.
fg_set "$API/commits/junk" 200 '<html>not a sha</html>' '"j1"'
check [ -z "$(ghx "ref_sha duboshin52/goDNS junk '$T/gh.cfg'")" ]
# Список веток — тоже условный.
ghx "refs_fetch_one godns '$T/gh.cfg'; refs_fetch_one godns '$T/gh.cfg'"
check [ "$(ghx 'ver_cache_get godns @refs')" = "main dev" ]
check [ "$(lg_count 'branches_per_page_100 cond=yes 304')" -eq 1 ]
# Версия на том же коммите берётся из кеша: файл из ветки второй раз не качается.
ghx "_ver_fetch_one godns main '$T/gh.cfg'; _ver_fetch_one godns main '$T/gh.cfg'"
check [ "$(ghx 'ver_cache_get godns main')" = "1.0.1" ]
check [ "$(lg_count 'raw.githubusercontent.com')" -eq 1 ]
# Проверка ключа — условная: 304 значит «доступ есть».
fg_set "https://api.github.com/repos/duboshin52/goVLESS" 200 '{}' '"t1"'
check [ "$(ghx "_token_probe duboshin52/goVLESS '$T/gh.cfg'")" = "200" ]
check [ "$(ghx "_token_probe duboshin52/goVLESS '$T/gh.cfg'")" = "200" ]
check [ "$(lg_count 'repos_anten-ka_goVLESS cond=yes 304')" -eq 1 ]
# 403 без признаков лимита — закрытый репозиторий, а не лимит: отметки нет.
fg_set "https://api.github.com/repos/anten-ka/secret" 403 '{}'
check [ "$(ghx "_token_probe anten-ka/secret '$T/gh.cfg'")" = "403" ]
check [ ! -f "$T/vc-gh/@ratelimit" ]
# 403 с x-ratelimit-remaining: 0 — исчерпанный лимит: отметка с часом сброса.
RESET=$(( $(date +%s) + 900 ))
fg_set "$API/commits/dev" 403 '{"message":"API rate limit exceeded"}' '' "x-ratelimit-remaining: 0\r\nx-ratelimit-reset: $RESET\r\n"
check [ -z "$(ghx "ref_sha duboshin52/goDNS dev '$T/gh.cfg'")" ]
check [ -f "$T/vc-gh/@ratelimit" ]
check [ -n "$(ghx 'gh_limited')" ]
# Опрос версий идёт с опцией fail, и код ответа всё равно не теряется.
rm -f "$T/vc-gh/@ratelimit"; printf 'silent\nfail\n' > "$T/gh-fail.cfg"
check [ "$(ghx "gh_get '$API/commits/dev' '$T/gh-fail.cfg' '$T/gh.out'; echo \$?")" = "2" ]
check [ -f "$T/vc-gh/@ratelimit" ]
# Пока лимит действует, GitHub не спрашиваем вовсе: ни хеш, ни ветки, ни ключ.
n0=$(wc -l < "$FG/log")
check [ "$(ghx "gh_get '$API/commits/main' '$T/gh.cfg' '$T/gh.out'; echo \$?")" = "2" ]
ghx "TOKEN=x; versions_fetch godns" >/dev/null 2>&1
check [ "$(ghx "_token_probe duboshin52/goVLESS '$T/gh.cfg'")" = "RL" ]
check [ "$(wc -l < "$FG/log")" -eq "$n0" ]
# Прежние сведения остаются на экране, а под меню сказано, до какого часа.
check [ "$(ghx 'ver_cache_get godns main')" = "1.0.1" ]
check has "$(ghx 'MENU_REFRESH_SEC=180; menu_footer_info; printf %s "$MENU_FOOTER_INFO"')" 'лимит GitHub исчерпан до'
# Лимит на исходе у проверки ключа по сети — тоже «лимит».
rm -f "$T/vc-gh/@ratelimit"
fg_set "https://api.github.com/repos/duboshin52/goVLESS" 403 '{}' '' "retry-after: 60\r\n"
check [ "$(ghx "_token_probe duboshin52/goVLESS '$T/gh.cfg'")" = "RL" ]
# Прошедшая отметка снимается сама.
printf '%s\n' "$(( $(date +%s) - 5 ))" > "$T/vc-gh/@ratelimit"
check ghx '! gh_limited'
check [ ! -f "$T/vc-gh/@ratelimit" ]
# Состояние ключа при лимите — «limited», и ключ НЕ стирается. До 0.9.6
# этот 403 читался как «ключ не принят»: ключ удалялся на каждом сервере
# клуба, запущенном в этот час.
all200 RL > "$T/http-rl"
check [ "$(tk http-rl 'TOKEN=x; token_check; printf "%s" "$TOKEN_STATUS"')" = "limited" ]
out=$(tk http-rl 'token_save "клубный" >/dev/null; TOKEN=""; token_startup </dev/null 2>&1; printf "[%s]" "$(cat "$TOKEN_FILE" 2>/dev/null)"')
check has "$out" '[клубный]'
check has "$out" 'лимит'
check hasnt "$out" 'больше не работает'
# То же на настоящем пути, через «сеть»: все шесть репозиториев отвечают
# 403 с x-ratelimit-remaining: 0. На 0.9.5 ключ здесь стирался.
rm -f "$T/vc-gh/@ratelimit"
for r in duboshin52/goVLESS duboshin52/gotelegram_pro duboshin52/goDNS duboshin52/kaskad-pro duboshin52/go_warp_pro duboshin52/goamnezia_pro; do
    fg_set "https://api.github.com/repos/$r" 403 '{"message":"API rate limit exceeded"}' '' "x-ratelimit-remaining: 0\r\nx-ratelimit-reset: $RESET\r\n"
done
out=$(PATH="$T/fakegh:$PATH" FAKEGH="$FG" T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 \
      GOINST_VER_CACHE="$T/vc-gh" GOINST_TOKEN_FILE="$T/token-net" \
      bash -c "unset GH_TOKEN GOTELEGRAM_PAT GITHUB_PAT GOINST_TOKEN GOINST_HTTP_FIXTURE; . '$SCRIPT'; token_save 'клубный' >/dev/null; TOKEN=''; token_startup </dev/null 2>&1; printf '[%s]' \"\$(cat '$T/token-net' 2>/dev/null)\"")
check has "$out" '[клубный]'
check hasnt "$out" 'больше не работает'

echo "── «Аркада»: экраны клетка в клетку с макетом"
# Эталон — экраны пакета Claude Design (design/handoff/spec/screens): у
# каждой клетки символ и роль цвета. Рисуем тем же кодом, что в жизни, без
# цвета, и сверяем по клеткам. Пробел сверяется только по выделению,
# хвостовые пробелы не в счёт; блок «ЧТО НОВОГО» заказчик убрал — в эталоне
# он гасится. Данные — из прототипа (ui_example*), а не с этой машины: иначе
# сверять было бы не с чем.
GOLD="$T/gold"; mkdir -p "$GOLD"; : > "$GOLD/list"
cat > "$T/golden.py" <<'PY'
import json, os, sys
spec_dir, listfile = sys.argv[1], sys.argv[2]
cache = {}
def spec(lang, sid, cols):
    if lang not in cache:
        with open(os.path.join(spec_dir, f"arcade_{lang}.json"), encoding="utf-8") as f:
            cache[lang] = {(x["id"], x["cols"]): x for x in json.load(f)}
    return cache[lang].get((sid, cols))
def spec_cells(row):
    return [[ch, tok] for txt, tok in row for ch in txt]
def dump_cells(line):
    if "\t" not in line: return [[c, "?"] for c in line]
    text, runs = line.split("\t", 1)
    toks = []
    for r in runs.split(","):
        if r:
            tok, n = r.rsplit(":", 1); toks += [tok] * int(n)
    return [[c, t] for c, t in zip(text, toks)]
def mask_news(exp):
    for i, row in enumerate(exp):
        line = "".join(c for c, _ in row)
        for word in ("ЧТО НОВОГО", "WHAT'S NEW"):
            c = line.find(word)
            if c < 0: continue
            e = line.find("║", c); e = len(line) if e < 0 else e
            for rr in (i, i + 1):
                if rr < len(exp):
                    for k in range(c, min(e, len(exp[rr]))): exp[rr][k] = [" ", "text"]
# en — одно имя защиты (1.2.4): «Scanner shield» эталона у нас «Scanner protection»;
# длиннее на 4 — съедает 4 пробела после себя (или удлиняет строку в конце).
def rename(exp):
    a, b = "Scanner shield", "Scanner protection"; d = len(b) - len(a)
    for row in exp:
        line = "".join(c for c, _ in row); c = line.find(a)
        if c < 0: continue
        e = c + len(a); k = line.find(" " * d, e)
        if k >= 0: del row[k:k + d]
        row[e:e] = [[ch, row[c][1]] for ch in b[len(a):]]
        for i, ch in enumerate(b[:len(a)]): row[c + i][0] = ch
def norm(cells):
    out = [[c, ("SEL" if t.endswith("+sel") else "SP") if c == " " else t] for c, t in cells]
    while out and out[-1][0] == " " and out[-1][1] != "SEL": out.pop()
    return out
for line in open(listfile, encoding="utf-8"):
    lang, sid, cols, dump = line.rstrip("\n").split("\t")
    s = spec(lang, sid, int(cols))
    if s is None:
        print(f"BAD {lang} {sid} {cols}: такого экрана в эталоне нет"); continue
    exp = [spec_cells(r) for r in s["rows"]]; mask_news(exp); rename(exp)
    got = [dump_cells(l) for l in open(dump, encoding="utf-8").read().split("\n")]
    while got and not got[-1]: got.pop()
    bad = []
    for i in range(max(len(exp), len(got))):
        a = norm(exp[i]) if i < len(exp) else []
        b = norm(got[i]) if i < len(got) else []
        if a != b: bad.append((i, a, b))
    if not bad:
        print(f"OK {lang} {sid} {cols}"); continue
    i, a, b = bad[0]
    k = next((j for j in range(min(len(a), len(b))) if a[j] != b[j]), min(len(a), len(b)))
    ta = "".join(c for c, _ in a); tb = "".join(c for c, _ in b)
    print(f"BAD {lang} {sid} {cols}: строк {len(bad)}, первая {i + 1}, клетка {k + 1}: "
          f"ждали {a[k] if k < len(a) else '∅'}, есть {b[k] if k < len(b) else '∅'}\n"
          f"      эталон |{ta}|\n      у нас  |{tb}|")
PY
# Данные экранов — как в прототипе. «certbot renew» в замечаниях — текст
# прототипа; сам goInstaller такого шага не советует (см. сертификаты ниже).
cat > "$T/ui_example.sh" <<'EX'
ui_example() {
    UD_HOST=vpn-fin-1; UD_OS="Ubuntu 24.04.3 LTS"; UD_VER=0.9.5; UD_VERNEW=0.9.6; UD_SVED=14:05; UD_DISK=58; UD_MEM=41; UD_LOAD=0.4
    UD_NAME=("goVLESS pro" "goTelegram pro" "goDNS pro" "goKaskad pro" "goWARP pro" "goAmnezia pro")
    UD_CMD=(govless gotelegram godns gokaskad gowarp goamnezia)
    if [ "${LANG_CODE:-ru}" = en ]; then
        UD_DESC=("VLESS Reality/TLS on 3X-UI, bot, mini-app" "MTProxy (telemt), mask site, bot, panel" "DoH/DoT resolver on a neighbour's certificate" "port cascade (iptables), bot, Telegram API egress" "Cloudflare WARP as SOCKS5 for 3X-UI" "AmneziaWG in Docker, mask site, bot, panel")
        UD_STTXT=("" "" "" "" "" "Lite only"); UD_LANGNOTE="English"; UD_KEYNOTE="does not open goAmnezia pro"
        UD_PROB=("vpn.example.com|certificate expires in 9 days|vpn.example.com cert: 9 days left|certbot renew" "goDNS pro|dnsdist: 3 restarts in an hour|goDNS pro: dnsdist restarted 3 times/h|journalctl -u dnsdist")
    else
        UD_DESC=("VLESS Reality/TLS на 3X-UI, бот, mini-app" "MTProxy (telemt), сайт-маска, бот, панель" "DoH/DoT-резолвер на сертификате соседа" "каскад портов (iptables), бот, прокси для API Telegram" "Cloudflare WARP как SOCKS5 для 3X-UI" "AmneziaWG в Docker, сайт-маска, бот, панель")
        UD_STTXT=("" "" "" "" "" "только Lite"); UD_LANGNOTE="русский"; UD_KEYNOTE="не открывает goAmnezia pro"
        UD_PROB=("vpn.example.com|сертификат истекает через 9 дней|сертификат vpn.example.com: 9 дней|certbot renew" "goDNS pro|dnsdist: 3 перезапуска за час|goDNS pro: dnsdist 3 перезапуска за час|journalctl -u dnsdist")
    fi
    UD_KEYTOK=warn
    token_saved() { return 0; }   # в примере ключ сохранён (файла на стенде нет)
    # Компоненты: два с обновлениями — в меню «c Компоненты ↑2».
    UD_COMPUP=2; COMP_NUP=2; COMP_APT=1; COMP_LISTS_TXT=14:05; COMP_BOTP=()
    CA_ID=(nginx docker certbot); CA_NAME=(nginx Docker certbot); CA_MAIN=(nginx docker.io certbot)
    CA_VER=(1.24.0-2ubuntu7.1 26.1.3-0ubuntu1~24.04.1 2.9.0-1); CA_CAND=(1.24.0-2ubuntu7.4 27.5.1-0ubuntu3~24.04.2 "")
    CA_UP=("nginx=1.24.0-2ubuntu7.4 nginx-common=1.24.0-2ubuntu7.4" "docker.io=27.5.1-0ubuntu3~24.04.2" ""); CA_HOLD=("" "" ""); CA_N=(2 1 1)
    CA_PROD=("goVLESS pro, goTelegram pro" "goAmnezia pro" "goVLESS pro, goTelegram pro, goDNS pro"); CA_PRODM=(0 1 0)
    CA_WHAT=("" "" ""); CA_NOTE=("" "" "")
    UD_INST=(1 1 1 0 0 0); UD_SRV=(1.3.7 2.10.46 1.0.1 — — —); UD_MAIN=(1.3.7 2.10.49 1.0.1 2.8 2.5.0 1.0.2); UD_DEV=(1.3.7 2.10.49 1.0.1 "" "" 1.0.2)
    UD_BRANCH=(main main main main main main); UD_UPD=(0 1 0 0 0 0); UD_NEW=(0 0 0 0 0 1)
    UD_ST=(installed installed installed ready notes lite)
    UD_MODES=("pro lite" "pro lite" "" "" "" "lazy pro lite_site lite"); UD_DEFMODE=(pro lite "" "" "" lite)
    UD_SVC=("x-ui nginx" "telemt" "dnsdist" "iptables" "warp-svc warp-bot" "amnezia-awg"); UD_SVCOK=("" "" "" "" "" "")
    UD_HELD=("443/tcp 80/tcp" "2443/tcp 9090/tcp 9091/tcp" "4443/tcp 853/tcp 5199/tcp 53/tcp" "" "" "")
    UD_HELDP=("443/tcp=xray 80/tcp=nginx" "2443/tcp=telemt 9090/tcp=telemt 9091/tcp=telemt" "4443/tcp=dnsdist 853/tcp=dnsdist 5199/tcp=dnsdist 53/tcp=dnsdist" "" "" "")
    UD_NEED=("" "" "" "10808/tcp 10851/tcp" "40000/tcp" "1985/tcp 1986/tcp"); UD_VBAD=(0 0 0 0 0 0); UD_VNOTES=(0 0 0 0 1 0)
}
ui_example_more() {
    declare -gA UI_MVBAD=([lazy]=2 [pro]=2 [lite_site]=2 [lite]=0) UI_MVNOTES=([lazy]=0 [pro]=0 [lite_site]=0 [lite]=0)
    UI_RESET=15:00; UI_POLLOK=5; UI_SPIN='⠧'
    if [ "${LANG_CODE:-ru}" = en ]; then
        UI_PG_NAME=("goVLESS pro" "goTelegram pro" "goDNS pro" "system")
        UI_PG_ROWS=("443/tcp|xray|VLESS inbound;80/tcp|nginx|mask site, certbot ACME" "2443/tcp|telemt|MTProxy, Lite mode;9090/tcp|telemt|loopback: metrics;9091/tcp|telemt|loopback: local API" "4443/tcp|dnsdist|DoH, 443 is taken;853/tcp|dnsdist|DoT;5199/tcp|dnsdist|loopback: console;53/tcp|dnsdist|loopback: DNS 127.0.0.1" "22/tcp|sshd|SSH;53/udp|resolved|loopback: 127.0.0.53")
        UI_PI_NAME=("goInstaller" "access key" "goVLESS pro" "goTelegram pro" "goDNS pro" "goKaskad pro" "goWARP pro" "goAmnezia pro")
        UI_PI_RES=("0.9.6" "opens 5 of 6" "main 1.3.7 · dev 1.3.7" "main 2.10.49 · dev 2.10.49" "main 1.0.1 · dev 1.0.1" "main 2.8" "main 2.5.0" "main 1.0.2 · dev 1.0.2")
    else
        UI_PG_NAME=("goVLESS pro" "goTelegram pro" "goDNS pro" "система")
        UI_PG_ROWS=("443/tcp|xray|VLESS inbound;80/tcp|nginx|сайт-маска, ACME certbot" "2443/tcp|telemt|MTProxy, режим Lite;9090/tcp|telemt|loopback: метрики;9091/tcp|telemt|loopback: локальный API" "4443/tcp|dnsdist|DoH, 443 занят;853/tcp|dnsdist|DoT;5199/tcp|dnsdist|loopback: консоль;53/tcp|dnsdist|loopback: DNS 127.0.0.1" "22/tcp|sshd|SSH;53/udp|resolved|loopback: 127.0.0.53")
        UI_PI_NAME=("goInstaller" "ключ доступа" "goVLESS pro" "goTelegram pro" "goDNS pro" "goKaskad pro" "goWARP pro" "goAmnezia pro")
        UI_PI_RES=("0.9.6" "открывает 5 из 6" "main 1.3.7 · dev 1.3.7" "main 2.10.49 · dev 2.10.49" "main 1.0.1 · dev 1.0.1" "main 2.8" "main 2.5.0" "main 1.0.2 · dev 1.0.2")
    fi
    UI_PI_TOK=(update warn text update text text text new); UI_PI_ST=(done done done done run run run wait)
    UD_KEYDENIED="goAmnezia pro"; UD_KEYOK=5
}
ui_example_pf() {
    local en=0; [ "${LANG_CODE:-ru}" = en ] && en=1
    UI_PFR_PORT=(); UI_PFR_ST=(); UI_PFR_D=(); UI_PFR_H=(); UI_PFU_G=(); UI_PFU_T=(); UI_PFU_TXT=()
    _r() { UI_PFR_PORT+=("$1"); UI_PFR_ST+=("$2"); if [ "$en" = 1 ]; then UI_PFR_D+=("$4"); else UI_PFR_D+=("$3"); fi; UI_PFR_H+=("${5:-}"); }
    if [ "$1" != lite ]; then
        _r 443/tcp bad "nginx: сайт на домене с сертификатом Let's Encrypt" "nginx: site on the domain with a Let's Encrypt cert" "xray → goVLESS pro"
        _r 80/tcp bad "nginx: проверка Let's Encrypt и редирект на https" "nginx: Let's Encrypt challenge and https redirect" "nginx → goVLESS pro"
    fi
    [ "$1" = pro ] && _r 443/udp ok "AmneziaWG на UDP 443" "AmneziaWG on UDP 443"
    [ "$1" = lazy ] && _r 443/udp ok "AmneziaWG 2.0 на UDP 443" "AmneziaWG 2.0 on UDP 443"
    _r 1985/tcp ok "loopback: веб-панель" "loopback: web panel"
    _r 1986/tcp ok "loopback: MCP по HTTP, по умолчанию выключен" "loopback: MCP over HTTP, off by default"
    if [ "$1" != lite ]; then
        _r 1987/tcp ok "loopback: страницы подключения" "loopback: connection pages"
        UI_PFU_G=('·'); UI_PFU_T=(muted)
        if [ "$en" = 1 ]; then UI_PFU_TXT=("TCP 443 is held by xray. That blocks only the site: in Lite mode goAmnezia pro installs alongside."); else UI_PFU_TXT=("TCP 443 держит xray. Это мешает только сайту: в режиме Lite goAmnezia pro ставится рядом."); fi
        UI_PF_BAD=2; UI_PF_NOTES=0
    else
        UI_PFU_G=('✓'); UI_PFU_T=(ok)
        if [ "$en" = 1 ]; then UI_PFU_TXT=("No TCP ports needed: AmneziaWG works over UDP on its own ports."); else UI_PFU_TXT=("TCP-порты не нужны: AmneziaWG работает по UDP на своих портах."); fi
        UI_PF_BAD=0; UI_PF_NOTES=0
    fi
}
ui_example_news() {
    UI_LASTLOGIN="Last login: Tue Sep 29 14:07:31 2026 from 203.0.113.24"; UD_NINST=3
    if [ "${LANG_CODE:-ru}" = en ]; then
        UD_NEWS=("↑|update|goTelegram pro|2.10.46 → 2.10.49|update in main" "✚|new|goAmnezia pro|1.0.2|new in the series, main" "↑|update|goInstaller|0.9.5 → 0.9.6|new installer version")
    else
        UD_NEWS=("↑|update|goTelegram pro|2.10.46 → 2.10.49|обновление в main" "✚|new|goAmnezia pro|1.0.2|новый продукт серии, main" "↑|update|goInstaller|0.9.5 → 0.9.6|новая версия установщика")
    fi
}
# Худший случай главного меню: и o, и u, защита ✗ и три тревоги.
ui_example_worst() {
    UD_OSUP=can; OSUP_TARGET=24.04; UD_OSUPLBL="Ubuntu 22.04 → 24.04"; SHS_ST=bad
    if [ "${LANG_CODE:-ru}" = en ]; then
        SHS_TEXT="not working"; SHS_WHY="no rules"
        UD_PROB+=("goWARP pro|warp-svc is not running|goWARP pro: warp-svc is down|systemctl status warp-svc|err")
    else
        SHS_TEXT="не работает"; SHS_WHY="правил нет"
        UD_PROB+=("goWARP pro|warp-svc не работает|goWARP pro: warp-svc не работает|systemctl status warp-svc|err")
    fi
}
# Защита стоит и считает: модель статистики — фикстура макета (1.2.4),
# в меню — счётчики под пунктом s и спарклайн «вход / выход».
ui_example_shield() {
    SHS_ST=ok; SHS_SCAN=1; SHS_VK=1; SHS_DATE=03.11; SHS_NEX=3; SHS_REJ=""; SHS_UPDERR=""; SHS_VKREJ=""
    GOINST_TEST=1 GOINST_SHIELD_UIMODEL="${SHFIX:-$T/shfix-${LANG_CODE:-ru}.txt}" ui_sh_model
}
EX
# экран|ширины|чем нарисовать. v2 («Что нового») заказчик отложил, k5
# (без UTF-8) — это g2 в ASCII, x2 — z2: их текст совпадает с соседями.
cat > "$T/gold_cases" <<'GC'
g2|80|ui_example_shield; ui_scr_menu 0
g1|46|ui_example_shield; ui_scr_menu 0
g1w|46|ui_example_worst; ui_scr_menu 0
k4|40|ui_scr_small
d1|80 46|ui_scr_product 1 0
d2|80 46|ui_scr_product 5 0
z2|80 46|ui_scr_mode 5 3
e1|80 46|UI_PMODE=pro; ui_example_pf pro; ui_scr_check 5 0 1
e2|80 46|UI_PMODE=lite; ui_example_pf lite; ui_scr_check 5 0 1
z3|80 46|UI_PMODE=lite; ui_scr_branch 1 0
z4|80 46|UI_PMODE=lite; UI_PBRANCH=main; ui_scr_confirm 1 0
i1|80 46|UD_SRV[1]=2.10.49; UD_UPD[1]=0; UI_PMODE=; UI_PBRANCH=main; ui_scr_result 1 0
i2|80 46|UD_SRV[1]=2.10.49; UD_UPD[1]=0; UD_BRANCH[1]=dev; UI_MISM=1; UI_PMODE=; UI_PBRANCH=main; ui_scr_result 1 0
i3|80 46|UD_INST[5]=1; UD_SRV[5]=1.0.2; UD_ST[5]=installed; UD_NEW[5]=0; UI_PMODE=; UI_PBRANCH=main; UI_LAZYMODE=lite_site; ui_scr_result 5 0
p|80 46|ui_scr_ports 0
k6|80 46|ui_scr_key 0
k1|80 46|ui_scr_nokey 0
k2|80 46|ui_scr_err github 0
k3|80 46|ui_scr_err rate 0
z1|80 46|ui_scr_lang $([ "$LANG_CODE" = en ] && echo 1 || echo 0)
v1|80 46|ui_scr_splash
a1|80 46|ui_scr_login
x1|80 46|ui_scr_login
a2|80 46|UD_NEWS=(); UD_PROB=(); ui_scr_login
b|80 46|ui_scr_login 4200
GC
gold_draw() {  # gold_draw <язык> — один bash на язык, каждый экран в подоболочке
    T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG="$1" GOINST_COLOR=none GOINST_DIR=/opt/go-installer \
    bash -c 'unset GOINST_TOKEN_FILE GOINST_ASCII; . "$1"; . "$T/ui_example.sh"
        while IFS="|" read -r id widths cmd; do
            for w in $widths; do
                f="$T/gold/$LANG_CODE-$id-$w"
                (
                    GOINST_UI_COLS=$w; GOINST_UI_LINES=24; [ "$w" = 40 ] && GOINST_UI_LINES=16
                    ui_detect; ui_example; ui_example_more; ui_example_news; TOKEN=gold
                    [ "$LANG_CODE" = en ] && UI_SPIN=⠇
                    eval "$cmd"; ui_compose; ui_dump
                ) > "$f" 2>&1
                printf "%s\t%s\t%s\t%s\n" "$LANG_CODE" "$id" "$w" "$f"
            done
        done < "$T/gold_cases"' _ "$SCRIPT" >> "$GOLD/list"
}
# Модель статистики защиты для g1/g2 — та же фикстура, что у макета.
cp "$HERE/design/shield/handoff-stats/ui-model/ru.txt" "$T/shfix-ru.txt"
cp "$HERE/design/shield/handoff-stats/ui-model/en.txt" "$T/shfix-en.txt"
if command -v python3 >/dev/null 2>&1; then
    gold_draw ru; gold_draw en
    python3 "$T/golden.py" "$HERE/design/handoff/spec/screens" "$GOLD/list" > "$GOLD/report" 2>&1
    while IFS= read -r l; do
        case "$l" in
            OK\ *) pass ;;
            BAD\ *) FAIL=$((FAIL+1)); echo "  ✗ эталон: ${l#BAD }" ;;
            *) echo "$l" ;;
        esac
    done < "$GOLD/report"
    # Счётчик осмотренного: 25 экранов, 46 сверок на язык. Пустой список
    # (рисование упало целиком) иначе был бы зелёным.
    check [ "$(grep -c '^OK ' "$GOLD/report")" -eq 92 ]
else
    echo "  (нет python3 — сверка с макетом пропущена)"
fi
# Тревог больше, чем строк: последняя строка «… ещё N», а не молча пропавшие;
# строка клавиш целиком, с s. Эталон g1w — три тревоги, здесь пять.
gold_more() {  # gold_more <ширина> → экран без разметки
    T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_DIR=/opt/go-installer \
    bash -c 'unset GOINST_TOKEN_FILE GOINST_ASCII; . "$1"; . "$T/ui_example.sh"
        GOINST_UI_COLS=$2; GOINST_UI_LINES=24; ui_detect; ui_example; ui_example_more; ui_example_news; TOKEN=gold
        ui_example_worst; UD_PROB+=("a|b|четвёртая тревога|c|err" "a|b|пятая тревога|c|err")
        ui_scr_menu 0; ui_compose; ui_dump | cut -f1' _ "$SCRIPT" "$1" 2>&1
}
out=$(gold_more 46)
check has "$out" '! сертификат vpn.example.com: 9 дней'; check has "$out" '✗ goWARP pro: warp-svc не работает'
check has "$out" '  … ещё 2'; check hasnt "$out" 'четвёртая тревога'
check [ "$(wc -l <<<"$out")" -eq 24 ]; check [ "$(tail -1 <<<"$out")" = '  ↑↓ · Enter · 1–9 · u · o · s · 0 выход' ]
out=$(gold_more 80)
check has "$out" ' ! vpn.example.com: сертификат истекает через 9 дней'; check has "$out" ' … ещё 4'
check [ "$(tail -1 <<<"$out")" = '  ↑↓ · Enter · 1–9 · u · o · s · p · r · l · 0 выход' ]

echo "── goDNS pro: 443 занят — встанет рядом, и это сказано"
# Как на 89.125.74.168: TCP 443 держит nginx goAmnezia pro. Меню писало
# «○ готов», и было непонятно, что на стандартный порт goDNS pro не встанет.
out=$(pf_env ss-goamnezia units-goamnezia nginx-goamnezia os-ubuntu2404 "goamnezia" 'preflight godns pro 2>&1; echo "rc=$?"')
check has "$out" 'rc=2'
check has "$out" '443 занят (goAmnezia pro): на стандартном порту goDNS pro не встанет — встанет рядом: DoH на 4443'
check has "$out" 'iPhone и Mac получат профиль DoT'
check [ "$(rd ss-goamnezia units-goamnezia nginx-goamnezia os-ubuntu2404 "goamnezia" godns)" = "y:не на 443" ]
# 443 свободен — этого замечания нет.
check hasnt "$(pf ss-empty units-empty nginx-empty os-ubuntu2404 "" godns pro)" 'godns-beside-443'
# 443 держит сам goDNS pro (переустановка) — порт свой, замечания нет.
check hasnt "$(pf ss-godns units-godns nginx-empty os-ubuntu2404 "godns" godns pro)" 'godns-beside-443'
# Карточка: под строкой ИТОГ — само замечание словами, в меню — «◆ не на 443».
card() {  # card <замечаний> — карточка goDNS pro в меню на 80 колонках
    T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example
        UD_INST[2]=0; UD_SRV[2]='—'; UD_ST[2]=lite; UD_STTXT[2]='не на 443'; UD_NEED[2]='443/tcp 4443/tcp 853/tcp'
        UD_VBAD[2]=0; UD_VNOTES[2]=$1; UD_VWHY[2]='443 занят (goAmnezia pro): на стандартном порту goDNS pro не встанет — встанет рядом: DoH на 4443'
        ui_scr_menu 2; ui_compose; ui_dump" | cut -f1 | tr -s ' '
}
out=$(card 1)
check has "$out" '◆ не на 443'
check has "$out" '! замечаний: 1'
check has "$out" 'стандартном порту goDNS pro'      # пояснение переносится по строкам
check has "$out" 'не встанет — встанет рядом'
# Без замечаний пояснение не выводится: под зелёным «готов» оно сбивало бы.
check hasnt "$(card 0)" 'стандартном порту'

echo "── «Аркада»: ширина окна → раскладка"
plain() { sed $'s/\033\\[[0-9;?]*[A-Za-z]//g'; }   # текст без управляющих последовательностей
lay() { GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_UI_COLS="$1" GOINST_UI_LINES="$2" GOINST_UI_SIZE_FILE="$T/ui-size" bash -c ". '$SCRIPT'; ui_size; echo \"\$UI_C \$UI_R\""; }
check [ "$(lay 80 24)" = "80 24" ]
# Большое окно: по умолчанию холст во всю ширину (не шире 160), высота 24 —
# высокие окна выходили пустыми коробками.
check [ "$(lay 120 36)" = "120 24" ]
check [ "$(lay 200 60)" = "160 24" ]
# Прежние 80×24 — по выбору: по центру или в углу.
check [ "$(GOINST_UI_SIZE=center lay 200 60)" = "80 24" ]
check [ "$(GOINST_UI_SIZE=compact lay 200 60)" = "80 24" ]
pad() { GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_UI_COLS="$1" GOINST_UI_LINES="$2" GOINST_UI_SIZE="$3" bash -c ". '$SCRIPT'; ui_size; echo \"\$UI_PADL \$UI_PADT\""; }
check [ "$(pad 200 60 full)" = "20 18" ]
check [ "$(pad 200 60 center)" = "60 18" ]
check [ "$(pad 200 60 compact)" = "0 0" ]
check [ "$(pad 80 24 full)" = "0 0" ]
# Узкое окно режимы не трогают.
check [ "$(GOINST_UI_SIZE=full lay 79 24)" = "46 24" ]
# F2 — по кругу и запоминается.
rm -f "$T/ui-size"
check [ "$(GOINST_SOURCE_ONLY=1 GOINST_UI_SIZE_FILE="$T/ui-size" bash -c ". '$SCRIPT'; for i in 1 2 3; do ui_size_next; GOINST_UI_SIZE=; printf '%s ' \"\$(ui_size_mode)\"; done")" = "center compact full " ]
check [ "$(cat "$T/ui-size")" = full ]
# Окна растут вместе с холстом: ни одна строка не шире окна, рамка закрыта.
wide=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS=130 GOINST_UI_LINES=40 GOINST_UI_SIZE=full bash -c ". '$SCRIPT'; ui_detect; ui_scr_menu 0; ui_compose; ui_dump" | cut -f1)
check [ "$(wc -l <<<"$wide" | tr -d ' ')" = 24 ]
check [ "$(python3 -c 'import sys; print(max(len(l.rstrip("\n")) for l in sys.stdin))' <<<"$wide")" -le 130 ]
check [ "$(grep -c '╚' <<<"$wide")" -ge 1 ]
check has "$(tail -1 <<<"$wide")" 'F2 размер'
# На 80×24 подсказки про размер нет: эталоны клетка в клетку не меняются.
check hasnt "$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 bash -c ". '$SCRIPT'; ui_detect; ui_scr_menu 0; ui_compose; ui_dump" | cut -f1)" 'F2'
check [ "$(lay 160 50)" = "160 24" ]
check [ "$(lay 79 24)" = "46 24" ]      # уже 80 — один столбец
check [ "$(lay 46 24)" = "46 24" ]
check [ "$(lay 45 40)" = "40 16" ]      # меньше 46 × 24 — «окно мало»
check [ "$(lay 120 23)" = "40 16" ]
check [ "$(lay '' '')" = "80 24" ]      # tput не ответил — не падаем
# Длинное имя машины (у облаков обычное) сокращается, а диск, память и
# нагрузка остаются: раньше верхняя строка теряла их целиком.
hud() { GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 bash -c ". '$SCRIPT'; ui_detect; UD_VER=1.0.1; UD_HOST='$1'; UD_DISK=58; UD_MEM=41; UD_LOAD=0.4; UI_BODY=(); ui_hud; UI_ROWS=(\"\${UI_BODY[0]}\"); ui_dump" | cut -f1; }
out=$(hud ubuntu-s-1vcpu-1gb-fra1-01)
check has "$out" 'диск'
check has "$out" 'нагр 0.4'
check has "$out" '…  диск'
check [ "$(printf '%s' "$out" | LC_ALL=C.UTF-8 wc -m | tr -d ' ')" -le 80 ]
check has "$(hud vpn-fin-1)" '·  vpn-fin-1  диск'
# Меню без UTF-8-рамок: всё рисованное — ASCII, в английском — весь экран.
asc=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=en GOINST_ASCII=1 GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 \
      bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example; ui_scr_menu 0; ui_compose; ui_emit")
asc_t=$(printf '%s' "$asc" | plain)
check has "$asc_t" '+='
check has "$asc_t" '> 1 goVLESS pro'
check [ -z "$(printf '%s' "$asc" | LC_ALL=C tr -d '\000-\177')" ]
# Меню во всех четырёх цветовых режимах рисуется без ошибок.
for cm in true 256 16 none; do
    out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=$cm GOINST_UI_COLS=80 GOINST_UI_LINES=24 \
          bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example; ui_scr_menu 0; ui_compose; ui_emit" 2>&1)
    check has "$out" 'goVLESS pro'
    check hasnt "$out" 'ошибка'
    check hasnt "$out" 'error'
done
# truecolor — 24-битные цвета (…;38;2;R;G;B), 256 — палитра (…;38;5;N).
check has "$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=true GOINST_UI_COLS=80 GOINST_UI_LINES=24 \
      bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example; ui_scr_menu 0; ui_compose; ui_emit")" ';38;2;'
check has "$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=256 GOINST_UI_COLS=80 GOINST_UI_LINES=24 \
      bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example; ui_scr_menu 0; ui_compose; ui_emit")" ';38;5;'

echo "── «Аркада»: локаль без UTF-8 чинится, а не рвёт рамки"
# SSH принёс ru_RU.UTF-8, а на сервере её нет: bash считает байты. Выход —
# C.UTF-8, если она есть в `locale -a`. Список читается в переменную: в
# конвейере `| grep -q` под pipefail locale -a ловит SIGPIPE, и «её нет»
# выходило там, где она есть. Поддельный locale печатает длинный список с
# C.UTF-8 в начале — ровно тот случай, где конвейер ломается.
LOC="$T/locale-bin"; mkdir -p "$LOC"
cat > "$LOC/locale" <<'LF'
#!/bin/bash
case "$1" in
    charmap) echo ANSI_X3.4-1968 ;;
    -a) echo C; echo C.utf8; echo POSIX; for i in $(seq 1 20000); do echo "xx_XX$i.utf8"; done ;;
esac
LF
chmod +x "$LOC/locale"
lf() { PATH="$LOC:$PATH" LC_ALL=C GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; ui_locale_fix; echo \"\$UI_ASCII \${LC_ALL:-}\""; }
check [ "$(lf)" = "0 C.UTF-8" ]
check [ "$(lf)" = "0 C.UTF-8" ]
# C.UTF-8 нет вовсе — ASCII-рамки, а не кривые.
printf '#!/bin/bash\ncase "$1" in charmap) echo ANSI_X3.4-1968 ;; -a) echo C; echo POSIX ;; esac\n' > "$LOC/locale"
check [ "$(lf)" = "1 C" ]
# Ни одного тихого grep на конвейере: страж смотрит смысл, а не одну строку.
check [ -z "$(code | grep -nE '[|][[:space:]]*grep[[:space:]]+(-[A-Za-z]*q|--quiet)')" ]

echo "── «Аркада»: переменная вплотную к не-ASCII — только в скобках"
# bash в C-локали (и на macOS) считает ведущий байт UTF-8 частью имени:
# "$UI_US╔" — переменная «UI_US╔», и рамка рвётся. Пишем "${UI_US}╔".
nb_scan() {  # nb_scan <файл> → найденные места и последней строкой «lines=N»
    python3 - "$1" <<'PY'
import re, sys
n = 0
for i, l in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    n += 1
    if l.lstrip().startswith("#"): continue
    for m in re.finditer(r'(?<!\\)\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7f])', l):
        print(f"{i}: {m.group(0)}")
print(f"lines={n}")
PY
}
if command -v python3 >/dev/null 2>&1; then
    out=$(nb_scan "$SCRIPT")
    check [ "$(grep -vc '^lines=' <<<"$out")" -eq 0 ]
    check [ "${out##*lines=}" -gt 5000 ]      # осмотрен весь файл
    printf 'x="$UI_US╔"\ny="${UI_US}╔"\n' > "$T/nb-neg.sh"
    check [ "$(nb_scan "$T/nb-neg.sh" | grep -vc '^lines=')" -eq 1 ]   # страж видит ошибку
fi

echo "── «Аркада»: клавиши"
rk() {  # rk <байты> [UI_INPUT] — что прочитает ui_read_key
    printf '%b' "$1" | GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; ui_locale_fix; UI_INPUT=${2:-0}; ui_read_key; printf '%s' \"\$UI_KEY\""
}
check [ "$(rk 1)" = 1 ]
check [ "$(rk '\n')" = enter ]
check [ "$(rk '\033[A')" = up ]
check [ "$(rk '\033[B')" = down ]
check [ "$(rk '\033[C')" = enter ]       # вправо — выбрать
check [ "$(rk '\033[D')" = esc ]         # влево — назад
# Стрелки в режиме курсора приложения (\033O…): терминал остаётся в нём,
# если прошлая программа его не вернула.
check [ "$(rk '\033OA')" = up ]
check [ "$(rk '\033OB')" = down ]
check [ "$(rk '\033')" = esc ]
check [ "$(rk '\177')" = back ]
check [ "$(rk '\033[15~')" = f5 ]        # F5 — не Esc и не выход
# F-клавиши во всех распространённых видах.
check [ "$(rk '\033OQ')" = f2 ]           # xterm, iTerm, Termius
check [ "$(rk '\033[12~')" = f2 ]         # rxvt, PuTTY
check [ "$(rk '\033[[B')" = f2 ]          # консоль Linux
check [ "$(rk '\033OR')" = f3 ]
check [ "$(rk '\033[13~')" = f3 ]
check [ "$(rk '\033OS')" = f4 ]
check [ "$(rk '\033[14~')" = f4 ]
check [ "$(rk '\033[1;5A')" = other ]     # Ctrl+стрелка — не F-клавиша
check [ "$(rk '')" = eof ]
# Русская раскладка: з к д г й — это p r l u q.
check [ "$(rk 'з')" = p ]
check [ "$(rk 'к')" = r ]
check [ "$(rk 'Д')" = l ]
check [ "$(rk 'г')" = u ]
check [ "$(rk 'й')" = q ]
# Пачка символов — вставка из буфера, а не нажатия: иначе вставленная
# команда жала бы пункты меню буква за буквой.
check [ "$(rk 'goinstall --list')" = paste ]
check [ "$(rk '17')" = paste ]
# А «цифра и сразу Enter» (привычка прежнего меню) и одна клавиша, нажатая
# несколько раз, — это одно нажатие. До 1.0.2 такое пропадало как вставка, и
# меню выглядело зависшим: «Выход» не выходил.
check [ "$(rk '0\n')" = 0 ]
check [ "$(rk 'q\r')" = q ]
check [ "$(rk '000')" = 0 ]
check [ "$(rk '7\n7\n')" = 7 ]
# \r — тоже Enter: терминал, оставленный продуктом без icrnl. Несколько Enter
# пачкой — одно нажатие; Enter с чем-то ещё — вставка.
check [ "$(rk '\r')" = enter ]
check [ "$(rk '\n\n\n')" = enter ]
check [ "$(rk '\r\r')" = enter ]
check [ "$(rk '\n0')" = paste ]
# При вводе ключа всё наоборот: русская буква — буква, пачка — ключ.
check [ "$(rk 'й' 1)" = 'й' ]
check [ "$(rk 'ab' 1)" = a ]
# Тишина — такт для спиннера, а не конец ввода.
check [ "$(sleep 1 | GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; ui_read_key 0.1; printf '%s' \"\$UI_KEY\"")" = tick ]

echo "── «Аркада»: что нажали, то и открылось"
# nav <клавиши…> — «Аркада» настоящим циклом ui_main. Клавиши идут через FIFO
# по одной: следующая — только когда цикл записал предыдущую в журнал
# (GOINST_UI_TRACE: «клавиша экран продукт»); пачкой они читались бы как
# вставка. «~x» — отдать x без ожидания (ответ на read после установщика),
# «@N» — подождать N секунд, «%экран» — дождаться, пока он нарисуется (после
# установщика ввод сбрасывается, и клавиша раньше экрана пропала бы). Всё,
# что меняет систему, заглушено и пишет в act, что именно вызвали;
# systemctl — тоже.
NAV="$T/nav"; mkdir -p "$NAV/bin"; : > "$NAV/err-all"
printf '#!/bin/sh\necho "systemctl $*" >> "%s/act"\nexit 0\n' "$NAV" > "$NAV/bin/systemctl"; chmod +x "$NAV/bin/systemctl"
nav() {
    local k n=0 i pid wd
    rm -f "$NAV/fifo"; : > "$NAV/trace"; : > "$NAV/trace.draw"; : > "$NAV/act"; mkfifo "$NAV/fifo"
    (
        export PATH="$NAV/bin:$PATH"
        export GOINST_SOURCE_ONLY=1 GOINST_LANG="${NAVLANG:-ru}" GOINST_TEST=1
        export GOINST_SS_FIXTURE="$T/ss-govless" GOINST_UNIT_FIXTURE="$T/units-govless"
        export GOINST_NGINX_ROOT="$T/nginx-govless" GOINST_OS_RELEASE="${NAVOS:-$T/os-ubuntu2404}"
        export GOINST_FAKE_INSTALLED="govless" GOINST_LE_ROOT="$T/le-empty" GOINST_ARCH=x86_64
        export GOINST_DOCKER_FIXTURE="$T/docker-empty"
        export GOINST_VER_CACHE="$NAV/vc" GOINST_DIR="$NAV/gi" GOINST_FS_ROOT="$NAV/fs" GOINST_UI_SYS="10 20 0.1"
        export GOINST_COLOR=none GOINST_UI_COLS="${NAVCOLS:-80}" GOINST_UI_LINES=24 GOINST_BIN="$NAV/no-bin"
        export GOINST_UI_TRACE="$NAV/trace" GOINST_NO_NET=1 GOINST_MENU_REFRESH="${NAVREFRESH:-0}"
        export GOINST_SUM_CHOICE="${NAVSUM:-$NAV/sum-choice}" NAV NAVTOKEN="${NAVTOKEN-test}" NAVSTUB="${NAVSTUB:-}"
        unset GH_TOKEN GOTELEGRAM_PAT GITHUB_PAT GOINST_TOKEN GOINST_ASCII
        mkdir -p "$NAV/vc" "$NAV/gi"
        [ -n "${NAVNET:-}" ] && unset GOINST_NO_NET
        exec bash -c '. "$1"; os_detect
            ui_enter_screen() { UI_ALT=1; }; ui_leave_screen() { UI_ALT=0; }; sleep() { :; }; clear() { :; }
            act() { printf "%s\n" "$*" >> "$NAV/act"; }
            run_product_installer() { act "RUN $1 mode=$MODE ref=$REF"; GOINST_FAKE_INSTALLED="$GOINST_FAKE_INSTALLED $1"; return 0; }
            ui_open_product() { act "OPEN ${UD_CMD[$UI_WP]}"; }
            self_update() { act "SELFUPDATE${1:+ $1}"; }
            ui_poll_start() { act POLL; return 1; }
            summary_enable() { act SUMON; }
            summary_disable() { act SUMOFF; }
            token_check() { TOKEN_STATUS=ok; act "KEYCHECK $TOKEN"; }
            token_save() { act "KEYSAVE $1"; }
            token_forget() { act KEYFORGET; }
            eval "$NAVSTUB"
            TOKEN="$NAVTOKEN"; ui_main; act "EXIT $?"; [ -n "${UI_UNINSTALL:-}" ] && act "UNINSTALL $UI_UNINSTALL"' _ "$SCRIPT" < "$NAV/fifo" > "$NAV/out" 2> "$NAV/err"
    ) &
    pid=$!
    # Сторож: зависший цикл не должен вешать весь набор.
    ( trap 'kill "$s" 2>/dev/null; exit 0' TERM; sleep 60 & s=$!; wait "$s"; kill "$pid" 2>/dev/null ) &
    wd=$!
    # Подача — в подоболочке с выключенным SIGPIPE: упавший цикл закрывает
    # канал, и запись в него иначе убила бы весь набор молча.
    (
        trap '' PIPE
        exec 7> "$NAV/fifo"
        for k in "$@"; do
            kill -0 "$pid" 2>/dev/null || break
            case "$k" in
                '~'*) printf '%b' "${k#\~}" >&7 2>/dev/null; continue ;;
                @*) sleep "${k#@}"; continue ;;
                # ?шаблон — дождаться процесса (pgrep -f), до 10 с.
                '?'*) for ((i = 0; i < 200; i++)); do
                        pgrep -f "${k#\?}" >/dev/null 2>&1 && break
                        kill -0 "$pid" 2>/dev/null || break
                        sleep 0.05
                    done; continue ;;
                # %экран — дождаться, пока цикл его нарисует.
                %*) for ((i = 0; i < 200; i++)); do
                        [ "$(tail -1 "$NAV/trace.draw" 2>/dev/null)" = "${k#%}" ] && break
                        kill -0 "$pid" 2>/dev/null || break
                        sleep 0.05
                    done; continue ;;
            esac
            printf '%b' "$k" >&7 2>/dev/null || break
            n=$(( n + 1 ))
            for ((i = 0; i < 200; i++)); do
                [ "$(wc -l < "$NAV/trace")" -ge "$n" ] && break
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.05
            done
        done
    )
    wait "$pid" 2>/dev/null
    kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
    cat "$NAV/err" >> "$NAV/err-all"
    return 0
}
# Журнал одной строкой: «клавиша экран[продукт]|…».
navtr() { awk '{printf "%s%s %s%s", (NR>1?"|":""), $1, $2, ($3!=""?"["$3"]":"")}' "$NAV/trace"; }
navtr0() { navtr | sed 's/\[[0-9]*\]//g'; }   # без номера продукта
# Сводку при входе спрашиваем один раз, до первого экрана; ответ — цифрой.
NAVSUM="$NAV/sum-new1" nav 1
check [ "$(navtr0)" = "1 sumask|eof menu" ]
check grep -qx SUMON "$NAV/act"
check grep -qx 'EXIT 0' "$NAV/act"
NAVSUM="$NAV/sum-new2" nav 2
check grep -qx SUMOFF "$NAV/act"
: > "$NAV/sum-choice"      # дальше вопрос уже задан
# Стрелки и Enter: вниз, вниз, Enter — третий продукт (goDNS pro); Esc — назад.
nav '\033[B' '\033[B' '\n' '\033' q
check [ "$(navtr)" = "down menu|down menu|enter menu|esc product[2]|q menu[2]" ]
# Цифры: 3 — goDNS pro, 1 — установить, проверка, 1 — ветка main, 1 — «да»:
# установщик с этой веткой; после — сверка итога и 0 — в главное меню.
nav 3 1 1 1 1 '~\n' %result 0
check [ "$(navtr)" = "3 menu|1 product[2]|1 check[2]|1 branch[2]|1 confirm[2]|0 result[2]|eof menu[2]" ]
check grep -qx 'RUN godns mode=pro ref=main' "$NAV/act"
check grep -q 'Проверено: goDNS pro стоит с ветки main' "$NAV/out"
# Выбрана dev — запускается dev.
nav 3 1 1 2 1 '~\n' %result 0
check grep -qx 'RUN godns mode=pro ref=dev' "$NAV/act"
# Установщик отработал, а ветка осталась прежней — экран так и говорит.
NAVSTUB='prod_installed_ref() { printf dev; }' nav 3 1 1 1 1 '~\n' %result 0
check grep -q 'Ветка не сменилась' "$NAV/out"
# «Нет» на подтверждении — к карточке продукта, установщик не запускается.
nav 3 1 1 1 2 q
check [ "$(navtr)" = "3 menu|1 product[2]|1 check[2]|1 branch[2]|2 confirm[2]|q product[2]" ]
check neg grep -q '^RUN' "$NAV/act"
# goAmnezia pro: курсор режима стоит на умолчании (Lite), Enter берёт его.
# Пауза перед Enter — как у человека: Enter сразу за цифрой проглатывается.
# Ждём сам экран, а не время: на сервере с Docker проверка четырёх режимов
# идёт дольше паузы, и Enter, пришедший до экрана, честно проглатывался.
nav 6 1 %mode @0.6 '\n' 1 1 1 '~\n' %result 0
check grep -qx 'RUN goamnezia mode=lite ref=main' "$NAV/act"
# Режим pro упирается в xray на 443: «продолжить» нет, только другой режим.
nav 6 1 2 1 q
check [ "$(navtr)" = "6 menu|1 product[5]|2 mode[5]|1 check[5]|q mode[5]" ]
check neg grep -q '^RUN' "$NAV/act"
# Стоящий продукт: 1 — его собственное меню.
nav 1 1 q
check grep -qx 'OPEN govless' "$NAV/act"
# Служебные пункты цифрами и буквами: 7 порты, 8 ключ, 9 язык; p r l.
nav 7 0 8 0 9 0 p '\033' r '\033' l '\033' q
check [ "$(navtr0)" = "7 menu|0 ports|8 menu|0 key|9 menu|0 lang|p menu|esc ports|r menu|esc key|l menu|esc lang|q menu" ]
# Русская раскладка: з — это p, й — это q; вставка из буфера пунктов не жмёт.
nav 'з' 0 123 'й'
check [ "$(navtr0)" = "p menu|0 ports|paste menu|q menu" ]
# Язык: 9, 2 — English, выбор запоминается, меню — на английском.
nav 9 2 q
check [ "$(cat "$NAV/gi/.language" 2>/dev/null)" = en ]
check grep -q 'PRODUCTS' "$NAV/out"
rm -f "$NAV/gi/.language"
# Удаление: x — экран удаления; 0 — назад, ничего не удалено.
nav x 0 q
check [ "$(navtr0)" = "x menu|0 uninstall|q menu" ]
check neg grep -q '^UNINSTALL' "$NAV/act"
# 1 — удалить вместе с ключом: меню закрывается, удаление — после выхода.
nav x 1
check grep -qx 'UNINSTALL drop' "$NAV/act"
# Есть ключ — есть и выбор «ключ оставить».
: > "$NAV/gi/token"; nav x 2
check grep -qx 'UNINSTALL keep' "$NAV/act"
rm -f "$NAV/gi/token"
# Ключ: 8, 2 — ввод. Буквы ключа — это ключ, а не команды (q и з не
# выходят и не открывают порты), Backspace стирает, на экране ключа нет.
nav 8 2 z q x 'з' j '\177' '\n' j
# Опрос в наборе не стартует (заглушка) — и это путь «некуда писать»: сразу
# меню, а не вечная заставка.
check [ "$(navtr0)" = "8 menu|2 key|z keyinput|q keyinput|x keyinput|з keyinput|j keyinput|back keyinput|enter keyinput|j menu|eof menu" ]
check grep -qx 'KEYCHECK zqxз' "$NAV/act"
check grep -qx 'KEYSAVE zqxз' "$NAV/act"
check neg grep -q 'zqx' "$NAV/out"
# Esc при вводе — назад, ключ не проверяется и не сохраняется.
nav 8 2 z z '\033' q
check neg grep -q 'KEYCHECK\|KEYSAVE' "$NAV/act"
# Ключа нет — первый экран «ввести ключ»; 0 — выход.
NAVTOKEN= nav 1 z '\033' 0
check [ "$(navtr0)" = "1 nokey|z keyinput|esc keyinput|0 nokey" ]
# Удалить ключ: 8, 3 — и сразу экран «ввести ключ».
nav 8 3 0
check grep -qx KEYFORGET "$NAV/act"
check [ "$(navtr0)" = "8 menu|3 key|0 nokey" ]
# Окно меньше 46 × 24: подсказка, цифры не действуют, q — выход.
NAVCOLS=40 nav 1 q
check [ "$(navtr0)" = "1 menu|q menu" ]
check grep -q 'Нужно не меньше 46 × 24' "$NAV/out"
check neg grep -q '^RUN\|^OPEN' "$NAV/act"
# Новая версия goInstaller: u — вопрос, 1 — обновление.
NAVSTUB='ver_cache_get() { if [ "$1" = "$SELF_ID" ] && [ "$2" = main ]; then printf 9.9.9; return 0; fi; return 1; }' nav u 1 '~\n'
check [ "$(navtr0)" = "u menu|1 selfupd" ]
# REVIEW-4 №2: экран обещает ветку — и обновление идёт ровно из неё.
check grep -qx 'SELFUPDATE main' "$NAV/act"; check grep -q '→ 9.9.9 · ветка main' <(plain < "$NAV/out")
# REVIEW-8 №3 (решение владельца 04.11: обновления между ветками обязаны
#    проходить): «Аркада» берёт ту же лучшую ветку, что нумерованное меню, —
#    запомненная test-shield новее main — из неё; без записи — main.
NAVSB='ver_cache_get() { [ "$1" = "$SELF_ID" ] || return 1; case "$2" in main) printf 9.9.8 ;; test-shield) printf 9.9.9 ;; *) return 1 ;; esac; }'
printf 'test-shield\n' > "$NAV/gi/.self-ref"
NAVSTUB="$NAVSB" nav u 1 '~\n'
check [ "$(navtr0)" = "u menu|1 selfupd" ]
check grep -qx 'SELFUPDATE test-shield' "$NAV/act"; check grep -q '→ 9.9.9 · ветка test-shield' <(plain < "$NAV/out")
NAVCOLS=46 NAVSTUB="$NAVSB" nav u 1 '~\n'
check grep -qx 'SELFUPDATE test-shield' "$NAV/act"; check grep -q '→ 9.9.9$' <(plain < "$NAV/out"); check grep -q '^  ветка test-shield$' <(plain < "$NAV/out")
rm -f "$NAV/gi/.self-ref"
NAVSTUB="$NAVSB" nav u 1 '~\n'
check grep -qx 'SELFUPDATE main' "$NAV/act"; check grep -q '→ 9.9.8 · ветка main' <(plain < "$NAV/out")
# Нет новой версии — u ничего не делает.
nav u q
check [ "$(navtr0)" = "u menu|q menu" ]
# Открытое меню само спрашивает GitHub со своим шагом (в жизни 3 минуты)…
NAVREFRESH=1 nav @2.5 q
check grep -qx POLL "$NAV/act"
# …при исчерпанном лимите — нет: ответ известен заранее…
printf '%s\n' "$(( $(date +%s) + 900 ))" > "$NAV/vc/@ratelimit"
NAVREFRESH=1 nav @2.5 q
check neg grep -q POLL "$NAV/act"
rm -f "$NAV/vc/@ratelimit"
# …а с шагом 0 — не спрашивает вовсе.
NAVREFRESH=0 nav @2.5 q
check neg grep -q POLL "$NAV/act"
# И пока ничего не меняется, экран не перерисовывается: кадр — ровно один,
# а не раз в секунду (по SSH с телефона это лишние килобайты в секунду).
check [ "$(grep -o $'\033\\[H' "$NAV/out" | wc -l | tr -d ' ')" -eq 1 ]
# «Цифра, Enter» в человеческом темпе: Enter относится к прошлому экрану и
# на новом ничего не жмёт — на подтверждении он запустил бы установщик.
nav 3 '\n' q
check [ "$(navtr0)" = "3 menu|swallow product|q product" ]
# Осмысленный Enter после паузы работает как обычно.
nav 3 %product @0.6 '\n' q
check [ "$(navtr0)" = "3 menu|enter product|q check" ]
# Несколько Enter, нажатых, пока экран думал: действует первый, остальные
# относятся к прошлому экрану и глотаются — мастер насквозь не проходит.
nav 3 %product @0.6 '\n' '~\n' '~\n' @0.3 q
check [ "$(navtr0)" = "3 menu|enter product|swallow check|q check" ]
check neg grep -q '^RUN' "$NAV/act"
# Enter как \r (терминал без icrnl после меню продукта) — тот же Enter.
nav 3 %product @0.6 '\r' q
check [ "$(navtr0)" = "3 menu|enter product|q check" ]
# Окно меньше 46 × 24: выход и по 0, не только по q.
NAVCOLS=40 nav 0
check [ "$(navtr0)" = "0 menu" ]
check grep -qx 'EXIT 0' "$NAV/act"
# Пачкой: «0 и Enter» — это «Выход», а не вставка.
nav '0\n'
check [ "$(navtr0)" = "0 menu" ]
check grep -qx 'EXIT 0' "$NAV/act"
# Одна клавиша трижды — одно нажатие.
nav 777 0 q
check [ "$(navtr0)" = "7 menu|0 ports|q menu" ]
# Вставка пропускается, но не молча: внизу сказано, что случилось.
nav 12 q
check [ "$(navtr0)" = "paste menu|q menu" ]
check grep -q 'несколько клавиш разом' "$NAV/out"
# Меню упало посреди экрана — терминал возвращается, и сказано, как быть.
NAVSTUB='ui_scr_ports() { echo "$NO_SUCH_VAR"; }' nav 7
check grep -q 'Меню goInstaller упало' "$NAV/err"
check grep -q 'GOINST_PLAIN_MENU=1' "$NAV/err"
: > "$NAV/err-all"   # эта ошибка — нарочная
# Ни одна из прогулок не споткнулась: ошибки bash видны в stderr цикла.
errs=$(cat "$NAV/err-all")
for w in 'unbound variable' 'не заданы границы' 'command not found' 'команда не найдена' 'syntax error' 'синтаксическая ошибка' 'bad array subscript' 'неправильный индекс'; do
    check hasnt "$errs" "$w"
done

echo "── «Аркада»: ключ из окружения сохраняется, когда подтвердился"
pfin() {  # pfin <ответ проверки ключа> — итог опроса с ключом из окружения
    rm -rf "$T/pd" "$T/tok-env"; mkdir -p "$T/pd" "$T/vc-pf"; printf '%s|\n' "$1" > "$T/pd/key"
    GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TOKEN_FILE="$T/tok-env" GOINST_VER_CACHE="$T/vc-pf" \
        bash -c ". '$SCRIPT'; UI_POLLDIR='$T/pd'; TOKEN=envkey; TOKEN_FROM=env; ui_poll_finish" >/dev/null 2>&1
    cat "$T/tok-env" 2>/dev/null
}
check [ "$(pfin ok)" = envkey ]
check [ -z "$(pfin bad)" ]
check [ -z "$(pfin limited)" ]
check [ -z "$(pfin nonet)" ]

echo "── «Аркада»: сертификаты по карте продуктов"
# Кто выпустил сертификат, знает карта продуктов (design/README.md): домен
# берётся из config.json стоящего продукта, подсказка — проверка, которая
# подходит ЕМУ. Команд, которые трогают чужой сертификат, в подсказках нет.
if command -v openssl >/dev/null 2>&1; then
    mkcert() {  # mkcert <файл> <дней>
        mkdir -p "$(dirname "$1")"
        openssl req -x509 -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1" -days "$2" -subj "/CN=t" >/dev/null 2>&1
    }
    CR="$T/certfs"; CLE="$T/cert-le"
    mkcert "$CLE/live/vpn.example.com/cert.pem" 5
    mkcert "$CLE/live/tg.example.com/cert.pem" 60
    mkcert "$CLE/live/amz.example.com/cert.pem" 3
    mkcert "$CR/root/cert/ip/203.0.113.7.crt" 1
    mkcert "$CR/root/cert/ip/203.0.113.8.crt" 5
    mkdir -p "$CR/opt/govless" "$CR/opt/gotelegram" "$CR/opt/goamnezia" "$CR/opt/godns"
    printf '{\n  "domain": "vpn.example.com"\n}\n' > "$CR/opt/govless/config.json"
    printf '{\n  "domain": "tg.example.com",\n  "mode": "pro"\n}\n' > "$CR/opt/gotelegram/config.json"
    printf '{\n  "domain": "amz.example.com",\n  "cert": "letsencrypt",\n  "mode": "pro"\n}\n' > "$CR/opt/goamnezia/config.json"
    # goDNS pro на сертификате соседа: домен тот же, повторной строки нет.
    printf '{\n  "domain": "vpn.example.com"\n}\n' > "$CR/opt/godns/config.json"
    cs() {  # cs <что стоит> [язык] — строки замечаний «домен|что|коротко|шаг»
        GOINST_SOURCE_ONLY=1 GOINST_LANG="${2:-ru}" GOINST_FS_ROOT="$CR" GOINST_LE_ROOT="$CLE" GOINST_FAKE_INSTALLED="$1" \
            bash -c ". '$SCRIPT'; cert_scan; printf '%s\n' \"\${UI_CERTP[@]}\""
    }
    out=$(cs "govless gotelegram goamnezia godns")
    # Пять дней выпуска — это «4 дня» полных: так же считает certbot.
    check has "$out" 'vpn.example.com|сертификат истекает через 4 дня|сертификат vpn.example.com: 4 дня|certbot certificates'
    check has "$out" 'amz.example.com|сертификат истекает через 2 дня|сертификат amz.example.com: 2 дня|goamnezia: Сертификат'
    # Меньше 3 дней у доменного — уже ✗: certbot продлевает за 30 и сам не успеет.
    check has "$out" 'goamnezia: Сертификат|err'
    check has "$out" 'certbot certificates|warn'
    check has "$out" 'acme.sh --list|warn'
    al=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none bash -c ". '$SCRIPT'; UD_PROB=('a.example|истёк|a: истёк|шаг|err' 'b.example|скоро|b: скоро|шаг2'); UI_BODY=(); ui_alerts 80; printf '%s\n' \"\${UI_BODY[@]}\"")
    check has "$al" '✗ '
    check has "$al" '! '
    check hasnt "$out" 'tg.example.com'                    # 60 дней — не тревога
    check [ "$(grep -c '^vpn.example.com|' <<<"$out")" -eq 1 ]
    # IP-сертификат панели Lite живёт ~6 дней: тревога только ближе 2 дней.
    check has "$out" '203.0.113.7|сертификат истекает меньше чем через сутки|сертификат 203.0.113.7: меньше суток|acme.sh --list'
    check hasnt "$out" '203.0.113.8'
    # goTelegram в Lite сертификата не держит; goAmnezia с самоподписанным — тоже.
    printf '{\n  "domain": "tg.example.com",\n  "mode": "lite"\n}\n' > "$CR/opt/gotelegram/config.json"
    mkcert "$CLE/live/tg.example.com/cert.pem" 3
    check hasnt "$(cs gotelegram)" 'tg.example.com'
    printf '{\n  "domain": "tg.example.com",\n  "mode": "pro"\n}\n' > "$CR/opt/gotelegram/config.json"
    check has "$(cs gotelegram)" 'tg.example.com|сертификат истекает через 2 дня|сертификат tg.example.com: 2 дня|gotelegram: Сайт / SSL'
    printf '{\n  "domain": "amz.example.com",\n  "cert": "selfsigned"\n}\n' > "$CR/opt/goamnezia/config.json"
    check hasnt "$(cs goamnezia)" 'amz.example.com'
    # goDNS pro со своим сертификатом — со своей подсказкой.
    printf '{\n  "domain": "dns.example.com",\n  "cert_owned_by_godns": "yes"\n}\n' > "$CR/opt/godns/config.json"
    mkcert "$CLE/live/dns.example.com/cert.pem" 10
    check has "$(cs godns)" 'dns.example.com|сертификат истекает через 9 дней|сертификат dns.example.com: 9 дней|godns: Сертификат'
    check has "$(cs godns en)" 'dns.example.com|certificate expires in 9 days|dns.example.com cert: 9 days left|godns: Certificate'
    # Не стоит продукт — его сертификат не наш вопрос, IP-сертификаты тоже.
    check [ -z "$(cs "")" ]
else
    echo "  (нет openssl — проверка сертификатов пропущена)"
fi
# Подсказки — только проверки. Ни renew, ни force, ни revoke/delete, ни
# --install-cert: чужие сертификаты goInstaller не трогает никогда.
csb=$(sed -n '/^cert_scan()/,/^}/p' "$SCRIPT" | grep -v '^[[:space:]]*#')
check [ -n "$csb" ]
for w in 'renew' 'force' 'revoke' 'delete' '--install-cert' '--remove' '--nginx' 'reconfigure'; do check hasnt "$csb" "$w"; done
check [ "$(ml 'for n in 1 3 5 11 12 21 22 25; do ui_plural $n день дня дней; printf "%s," "$UI_TX"; done')" = "1 день,3 дня,5 дней,11 дней,12 дней,21 день,22 дня,25 дней," ]
check [ "$(GOINST_SOURCE_ONLY=1 GOINST_LANG=en bash -c ". '$SCRIPT'; ui_plural 1 x y z product products; printf '%s,' \"\$UI_TX\"; ui_plural 4 x y z product products; printf '%s' \"\$UI_TX\"")" = "1 product,4 products" ]

echo "── «Аркада»: службы продукта — только те, что стоят"
# goWARP pro ставит warp-svc только для 3X-UI, warp-bot — только с ботом. До
# 1.0.8 сводка при входе звала отсутствующие службы упавшими: на сервере, где
# их нет вовсе, висело «warp-svc не работает» и «warp-bot не работает».
# systemctl поддельный: состояние каждой службы — в SVC («юнит:состояние»).
SV="$T/svc"; mkdir -p "$SV/bin" "$SV/vc"
cat > "$SV/bin/systemctl" <<'EOF'
#!/bin/sh
eval "u=\${$#}"
st=$(printf '%s\n' $SVC | sed -n "s/^$u://p")
case "$1:$st" in
    show:|show:none) echo LoadState=not-found; exit 0 ;;
    show:*) echo LoadState=loaded; exit 0 ;;
    is-active:run|is-enabled:run|is-enabled:down) exit 0 ;;
esac
exit 1
EOF
chmod +x "$SV/bin/systemctl"
svc() {  # svc "<юнит:состояние …>" <команды>
    PATH="$SV/bin:$PATH" SVC="$1" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 \
    GOINST_SS_FIXTURE="$T/ss-govless" GOINST_UNIT_FIXTURE="$T/units-govless" GOINST_DOCKER_FIXTURE="$T/docker-empty" \
    GOINST_NGINX_ROOT="$T/nginx-govless" GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_ARCH=x86_64 \
    GOINST_FAKE_INSTALLED=gowarp GOINST_LE_ROOT="$T/le-empty" GOINST_VER_CACHE="$SV/vc" GOINST_FS_ROOT="$SV/fs" \
    GOINST_UI_SYS="10 20 0.1" GOINST_NO_NET=1 bash -c ". '$SCRIPT'; $2"
}
check [ "$(svc "" 'unit_state warp-svc')" = none ]
check [ "$(svc "warp-svc:run" 'unit_state warp-svc')" = run ]
check [ "$(svc "warp-svc:down" 'unit_state warp-svc')" = down ]
check [ "$(svc "warp-svc:off" 'unit_state warp-svc')" = off ]
sm() { svc "$1" "os_detect; ui_model_load; printf 'svc=%s\n' \"\${UD_SVC[@]}\"; printf 'ok=%s\n' \"\${UD_SVCOK[@]}\"; printf 'prob=%s\n' \${UD_PROB[@]+\"\${UD_PROB[@]}\"}"; }
# Служб нет на машине — ни тревоги, ни строки в карточке.
out=$(sm "")
check has "$out" 'svc='
check hasnt "$out" 'не работает'
check hasnt "$out" 'warp-svc'
# Упала — тревога; работает — нет.
out=$(sm "warp-svc:run warp-bot:down")
check has "$out" 'prob=goWARP pro|warp-bot не работает|goWARP pro: warp-bot не работает|journalctl -u warp-bot'
check hasnt "$out" 'warp-svc не работает'
check has "$out" 'svc=warp-svc warp-bot'
# Выключена человеком — в карточке, но не тревога.
out=$(sm "warp-svc:run warp-bot:off")
check hasnt "$out" 'не работает'
check has "$out" ' warp-bot:2'

echo "── «Аркада»: сводка при входе"
# Ставится только с согласия и снимается целиком. systemctl — поддельный:
# на сервере с установленным goInstaller набор не должен трогать настоящий
# таймер.
SUMT="$T/sum"; mkdir -p "$SUMT/bin"
printf '#!/bin/sh\necho "systemctl $*" >> "%s/log"\nexit 0\n' "$SUMT" > "$SUMT/bin/systemctl"; chmod +x "$SUMT/bin/systemctl"
printf '#!/bin/sh\necho "goinstall $*" >> "%s/log"\n' "$SUMT" > "$SUMT/bin/goinstall"; chmod +x "$SUMT/bin/goinstall"
sx() {
    PATH="$SUMT/bin:$PATH" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru \
    GOINST_SYSTEMD_DIR="$SUMT/systemd" GOINST_PROFILE_HOOK="$SUMT/profile.d/goinstall-summary.sh" \
    GOINST_SUM_CHOICE="$SUMT/choice" GOINST_SUM_FILE="$SUMT/summary" GOINST_BIN=/usr/local/bin/goinstall \
    bash -c ". '$SCRIPT'; $*"
}
: > "$SUMT/log"
sx summary_enable
TIMER="$SUMT/systemd/goinstall-watch.timer"; HOOK="$SUMT/profile.d/goinstall-summary.sh"
check grep -qx 'OnUnitActiveSec=30min' "$TIMER"          # фон — раз в 30 минут…
check grep -qx 'RandomizedDelaySec=10min' "$TIMER"       # …вразброс: клуб не бьёт в GitHub разом
check grep -qx 'Persistent=true' "$TIMER"
check grep -qx 'ExecStart=/usr/local/bin/goinstall --watch' "$SUMT/systemd/goinstall-watch.service"
check grep -qx 'systemctl enable --now goinstall-watch.timer' "$SUMT/log"
check [ "$(cat "$SUMT/choice")" = yes ]
check sx summary_enabled
# Скрипт входа: только root, только терминал, не при ~/.hushlogin, и сеть не ждёт.
check grep -q '\[ -t 1 \]' "$HOOK"
check grep -q '\[ -t 0 \]' "$HOOK"
# Ctrl-C во время сводки обрывает её, а не остаток профиля оболочки входа.
check grep -qx '    trap : INT' "$HOOK"
check grep -qx '    trap - INT' "$HOOK"
# Скрипт входа прежней версии обновляется с первым же опросом таймера.
printf '# старый скрипт входа\n' > "$HOOK"
sx "unset GH_TOKEN GOTELEGRAM_PAT GITHUB_PAT GOINST_TOKEN; TOKEN_FILE='$SUMT/no-token'; summary_watch"
check grep -qx '    trap : INT' "$HOOK"
check grep -q 'id -u' "$HOOK"
check grep -q 'hushlogin' "$HOOK"
check grep -q 'goinstall --motd' "$HOOK"
check sh -n "$HOOK"
: > "$SUMT/log"
PATH="$SUMT/bin:$PATH" sh "$HOOK" > "$SUMT/hook.out" 2>&1 </dev/null
check neg grep -q goinstall "$SUMT/log"                    # не терминал — молчит
# Выключить — снять всё, что поставили, и запомнить ответ.
sx summary_disable
check [ ! -e "$TIMER" ]
check [ ! -e "$SUMT/systemd/goinstall-watch.service" ]
check [ ! -e "$HOOK" ]
check grep -qx 'systemctl disable --now goinstall-watch.timer' "$SUMT/log"
check [ "$(cat "$SUMT/choice")" = no ]
check sx '! summary_enabled'
# Сводка печатается из файла, без сети.
printf '%s\n' 'sved=14:05' 'ninst=3' 'host=vpn-fin-1' \
    'news=↑|update|goTelegram pro|2.10.46 → 2.10.49|обновление в main' \
    'prob=vpn.example.com|сертификат истекает через 9 дней|сертификат vpn.example.com: 9 дней|certbot certificates' > "$SUMT/summary"
out=$(sx 'GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 GOINST_UI_SYS="10 20 0.1" summary_print')
check has "$out" 'goTelegram pro'
check has "$out" '2.10.46 → 2.10.49'
check has "$out" 'certbot certificates'
check has "$out" 'сведения от 14:05'
check hasnt "$out" $'\033[H'                             # вниз по экрану, не поверх
# Всё актуально — одна короткая строка, число продуктов склоняется.
printf '%s\n' 'sved=09:00' 'ninst=1' 'host=h' > "$SUMT/summary"
out=$(sx 'GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 GOINST_UI_SYS="1 2 0.1" summary_print' | plain)
check has "$out" 'всё актуально, 1 продукт, проблем нет'
# Есть что делать — под сводкой отсчёт на 5 секунд: Enter — меню (код 10),
# другая клавиша — консоль, тишина — тоже консоль.
cd_run() {  # cd_run <ввод> — сводка с новостями и отсчётом; печатает вывод и «rc=N»
    printf '%s\n' 'sved=14:05' 'ninst=3' 'host=h' 'news=↑|update|goTelegram pro|2.10.46 → 2.10.49|обновление в main' > "$SUMT/summary"
    { sleep 0.3; printf '%b' "$1"; } | sx 'GOINST_COUNTDOWN_FORCE=1 GOINST_COUNTDOWN_MS=900 GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 GOINST_UI_SYS="1 2 0.1" summary_print; echo "rc=$?"'
}
out=$(cd_run '\n')
check has "$out" 'rc=10'
check has "$(plain <<<"$out")" 'Enter — открыть goinstall · любая другая клавиша — в консоль'
check has "$(cd_run 'x')" 'rc=0'
check has "$(cd_run '\r')" 'rc=10'
# К5-15 (стенд 03.11): в 46 строка макета (46 знаков) не влезала в 45 и
#    обрезалась «…консо…» — теперь короче и целиком; в 50 — строка макета.
cdw_run() {  # cdw_run <колонки> [en] — строка отсчёта
    printf '%s\n' 'sved=14:05' 'ninst=3' 'host=h' 'news=↑|update|goTelegram pro|2.10.46 → 2.10.49|обновление в main' > "$SUMT/summary"
    { sleep 0.3; printf 'x'; } | sx "${2:+LANG_CODE=en; }GOINST_COUNTDOWN_FORCE=1 GOINST_COUNTDOWN_MS=900 GOINST_COLOR=none GOINST_UI_COLS=$1 GOINST_UI_LINES=24 GOINST_UI_SYS='1 2 0.1' summary_print" | plain | grep 'Enter —'
}
l=$(cdw_run 46); check has "$l" '  Enter — goinstall · иначе — консоль'; check hasnt "$l" '…'
l=$(cdw_run 50); check has "$l" '  Enter — goinstall · другая клавиша — консоль'; check hasnt "$l" '…'
l=$(cdw_run 46 en); check has "$l" '  Enter — goinstall · other key — shell'; check hasnt "$l" '…'
# Стрелка на отсчёте — в консоль, и её хвост «[A» не остаётся вводом.
out=$({ sleep 0.3; printf '\033[A'; sleep 0.3; printf 'Z\n'; } | sx 'printf "%s\n" sved=1 ninst=1 host=h "prob=a|b|c|d" > "$SUM_FILE"; GOINST_COUNTDOWN_FORCE=1 GOINST_COUNTDOWN_MS=2000 GOINST_COLOR=none summary_print; echo "rc=$?"; IFS= read -r rest; echo "rest=[$rest]"')
check has "$out" 'rc=0'
check has "$out" 'rest=[Z]'
# Уже что-то набрано (печатают команду, ssh со вводом из скрипта) — отсчёта
# нет: он съел бы первую букву, а перевод строки открыл бы меню.
out=$(printf 'ls\n' | sx 'printf "%s\n" sved=1 ninst=1 host=h "prob=a|b|c|d" > "$SUM_FILE"; GOINST_COUNTDOWN_FORCE=1 GOINST_COLOR=none summary_print; echo "rc=$?"; IFS= read -r rest; echo "rest=[$rest]"')
check has "$out" 'rc=0'
check has "$out" 'rest=[ls]'
check hasnt "$out" 'открыть goinstall'
check has "$(sleep 1 | sx 'printf "%s\n" sved=1 ninst=1 host=h "prob=a|b|c|d" > "$SUM_FILE"; GOINST_COUNTDOWN_FORCE=1 GOINST_COUNTDOWN_MS=400 GOINST_COLOR=none summary_print; echo "rc=$?"')" 'rc=0'
# Всё актуально — отсчёта нет: ждать нечего.
printf '%s\n' 'sved=09:00' 'ninst=1' 'host=h' > "$SUMT/summary"
out=$(printf '\n' | sx 'GOINST_COUNTDOWN_FORCE=1 GOINST_COLOR=none summary_print; echo "rc=$?"')
check has "$out" 'rc=0'
check hasnt "$out" 'открыть goinstall ·'
# Не терминал — отсчёта нет: входу по ssh с командой ждать некого.
printf '%s\n' 'sved=14:05' 'ninst=3' 'host=h' 'prob=a|b|c|d' > "$SUMT/summary"
check hasnt "$(printf '\n' | sx 'GOINST_COLOR=none summary_print')" 'открыть goinstall'
# --motd: Enter открывает меню той же командой, что и goinstall.
printf '#!/bin/sh\necho MENU >> "%s/menu.log"\n' "$SUMT" > "$SUMT/fake-goinstall"; chmod +x "$SUMT/fake-goinstall"
rm -f "$SUMT/menu.log"
{ sleep 0.3; printf '\n'; } | PATH="$SUMT/bin:$PATH" GOINST_SUM_FILE="$SUMT/summary" GOINST_BIN="$SUMT/fake-goinstall" GOINST_COUNTDOWN_FORCE=1 \
    GOINST_COUNTDOWN_MS=900 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_SYS="1 2 0.1" bash "$SCRIPT" --motd >/dev/null 2>&1
check grep -qx MENU "$SUMT/menu.log"
rm -f "$SUMT/menu.log"
{ sleep 0.3; printf 'x'; } | PATH="$SUMT/bin:$PATH" GOINST_SUM_FILE="$SUMT/summary" GOINST_BIN="$SUMT/fake-goinstall" GOINST_COUNTDOWN_FORCE=1 \
    GOINST_COUNTDOWN_MS=900 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_SYS="1 2 0.1" bash "$SCRIPT" --motd >/dev/null 2>&1
check [ ! -e "$SUMT/menu.log" ]
# Нет файла — тишина и успех: вход по SSH не должен спотыкаться.
rm -f "$SUMT/summary"
check [ -z "$(sx summary_print)" ]
# --motd через main: без root, без вопроса о языке, без сети.
printf '%s\n' 'sved=09:00' 'ninst=5' 'host=h' > "$SUMT/summary"
out=$(PATH="$SUMT/bin:$PATH" GOINST_SUM_FILE="$SUMT/summary" GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 \
      GOINST_LANG=ru GOINST_LANG_FILE="$SUMT/no-lang" GOINST_UI_SYS="1 2 0.1" bash "$SCRIPT" --motd </dev/null 2>&1); rc=$?
check [ "$rc" -eq 0 ]
check has "$(plain <<<"$out")" '5 продуктов'
# --watch пишет файл сводки: время опроса, сколько стоит, имя машины.
out=$(PATH="$SUMT/bin:$PATH" GH_TOKEN=x GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 \
      GOINST_SS_FIXTURE="$T/ss-govless" GOINST_UNIT_FIXTURE="$T/units-govless" GOINST_NGINX_ROOT="$T/nginx-govless" \
      GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_FAKE_INSTALLED=govless GOINST_LE_ROOT="$T/le-empty" GOINST_ARCH=x86_64 \
      GOINST_VER_CACHE="$SUMT/vc" GOINST_DIR="$SUMT/gi" GOINST_SUM_FILE="$SUMT/summary-w" GOINST_UI_SYS="1 2 0.1" GOINST_DOCKER_FIXTURE="$T/docker-empty" \
      bash -c ". '$SCRIPT'; os_detect; versions_fetch() { :; }; self_fetch_versions() { :; }; token_check() { TOKEN_STATUS=ok; }; summary_watch; cat '$SUMT/summary-w'")
check has "$out" 'sved='
check has "$out" 'ninst=1'
check has "$out" 'host='
# Без ключа --watch ничего не пишет: спрашивать GitHub нечем.
rm -f "$SUMT/summary-w"
sx "unset GH_TOKEN GOTELEGRAM_PAT GITHUB_PAT GOINST_TOKEN; GOINST_TOKEN_FILE='$SUMT/no-token' TOKEN_FILE='$SUMT/no-token'; SUM_FILE='$SUMT/summary-w'; summary_watch"
check [ ! -e "$SUMT/summary-w" ]

echo "── «Аркада»: когда меню новое, а когда прежнее"
# Страж на сам набор: «check ! …» краснеет всегда (см. neg).
check [ "$(grep -cE '^[[:space:]]*check ! ' "$HERE/test_goinstaller.sh")" -eq 0 ]
uc=$(sed -n '/^ui_can_run()/,/^}/p' "$SCRIPT")
check has "$uc" '[ -t 0 ]'
check has "$uc" '[ -t 1 ]'
check has "$uc" 'dumb'
check has "$uc" 'GOINST_PLAIN_MENU'
check ml '! ui_can_run </dev/null'
mainb=$(sed -n '/^main() {/,/^}/p' "$SCRIPT")
# Сводка при входе — раньше проверки root и вопроса о языке.
check [ "$(grep -n -- '--motd)' <<<"$mainb" | head -1 | cut -d: -f1)" -lt "$(grep -n 'lang_startup' <<<"$mainb" | head -1 | cut -d: -f1)" ]
# «Аркада» — до старого пути: ключ и версии спрашиваются под заставкой, не до неё.
check [ "$(grep -n 'ui_can_run' <<<"$mainb" | head -1 | cut -d: -f1)" -lt "$(grep -n '^    token_startup' <<<"$mainb" | head -1 | cut -d: -f1)" ]
# Шаги опроса — решение заказчика: меню раз в 3 минуты, фон раз в 30.
check grep -q 'GOINST_MENU_REFRESH:-180' "$SCRIPT"

echo "── сводка версий для клуба: собирает GitHub Actions, сервер берёт одним запросом"
# Поддельный GitHub (FG, fg_set — из раздела про лимит): у каждого продукта
# main и dev, у goInstaller — main и сама ветка versions (её список веток
# отбрасывает: refs_sort берёт только main и dev).
DG="$T/dg"; mkdir -p "$DG"
SHAM=2222222222222222222222222222222222222222; SHAD=3333333333333333333333333333333333333333
DG_IDS="govless gotelegram godns gokaskad gowarp goamnezia"
BR2=$'[\n  {\n    "name": "dev"\n  },\n  {\n    "name": "main"\n  }\n]'
for id in $DG_IDS; do
    repo=$(ml "prod_repo $id"); spec=$(ml "prod_ver_spec $id"); path="${spec%%|*}"; var="${spec#*|}"
    fg_set "https://api.github.com/repos/$repo/branches?per_page=100" 200 "$BR2" "\"br-$id\""
    fg_set "https://api.github.com/repos/$repo/commits/main" 200 "$SHAM" "\"m-$id\""
    fg_set "https://api.github.com/repos/$repo/commits/dev" 200 "$SHAD" "\"d-$id\""
    fg_set "https://raw.githubusercontent.com/$repo/$SHAM/$path" 200 "$var=\"1.2.3\""
    fg_set "https://raw.githubusercontent.com/$repo/$SHAD/$path" 200 "$var=\"1.3.0\""
done
fg_set "https://api.github.com/repos/duboshin52/goInstaller/branches?per_page=100" 200 $'[\n  {\n    "name": "main"\n  },\n  {\n    "name": "versions"\n  }\n]' '"br-self"'
fg_set "https://api.github.com/repos/duboshin52/goInstaller/commits/main" 200 "$SHAM" '"m-self"'
fg_set "https://raw.githubusercontent.com/duboshin52/goInstaller/$SHAM/go-installer.sh" 200 'GOINST_VERSION="9.9.9"'
dgx() {  # функции скрипта с поддельным GitHub и своим кешем
    PATH="$T/fakegh:$PATH" FAKEGH="$FG" T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru \
    GOINST_VER_CACHE="${DGC:-$DG/vc}" GOINST_DIR="$DG/gi" bash -c "mkdir -p '${DGC:-$DG/vc}'; . '$SCRIPT'; $*"
}
# Сборка — тем же кодом, что у сервера, через --digest, ключ из GH_TOKEN.
: > "$FG/log"
out=$(PATH="$T/fakegh:$PATH" FAKEGH="$FG" GH_TOKEN=canary-club-key GOINST_DIR="$DG/build" GOINST_VER_CACHE="$DG/build/vc" \
      GOINST_LANG=ru bash "$SCRIPT" --digest 2>"$DG/build.err"); rc=$?
check [ "$rc" -eq 0 ]
check has "$out" 'format=1'
check has "$out" 'generated='
check has "$out" 'godns @refs main dev'
check has "$out" "godns main 1.2.3 $SHAM"
check has "$out" "godns dev 1.3.0 $SHAD"
check has "$out" "gowarp main 1.2.3 $SHAM"
check has "$out" '@self @refs main'
check has "$out" "@self main 9.9.9 $SHAM"
check [ "$(grep -c ' @refs ' <<<"$out")" -eq 7 ]          # шесть продуктов и сам
check hasnt "$out$(cat "$DG/build.err")" 'canary-club-key' # ключ не печатается
check hasnt "$out" 'versions'                              # своя ветка сводки — не ветка
# Не видно веток хоть у одного — сборка падает, публиковать нечего.
fg_set "https://api.github.com/repos/duboshin52/go_warp_pro/branches?per_page=100" 404 '{}'
out=$(PATH="$T/fakegh:$PATH" FAKEGH="$FG" GH_TOKEN=x GOINST_DIR="$DG/b2" GOINST_VER_CACHE="$DG/b2/vc" \
      GOINST_LANG=ru bash "$SCRIPT" --digest 2>&1); rc=$?
check [ "$rc" -ne 0 ]
check has "$out" 'gowarp: веток не видно'
fg_set "https://api.github.com/repos/duboshin52/go_warp_pro/branches?per_page=100" 200 "$BR2" '"br-gowarp"'
# Без ключа — отказ, а не пустая сводка.
out=$(env -u GH_TOKEN -u GOTELEGRAM_PAT -u GITHUB_PAT -u GOINST_TOKEN GOINST_DIR="$DG/b3" GOINST_TOKEN_FILE="$DG/no-token" \
      GOINST_LANG=ru bash "$SCRIPT" --digest 2>&1); rc=$?
check [ "$rc" -ne 0 ]
check hasnt "$out" 'format=1'

# Приём: всё проверяется до записи, в кеш — ровно то, что спросил бы сам.
now=$(date +%s)
mkdg() {  # mkdg <generated> — сводка на шесть продуктов и сам goInstaller
    local id
    printf 'format=1\ngenerated=%s\n' "$1"
    for id in $DG_IDS; do printf '%s @refs main dev\n%s main 1.2.3 %s\n%s dev 1.3.0 %s\n' "$id" "$id" "$SHAM" "$id" "$SHAD"; done
    printf '@self @refs main\n@self main 9.9.9 %s\n' "$SHAM"
}
mkdg "$now" > "$DG/ok.txt"
rm -rf "$DG/vc"
check dgx "digest_apply '$DG/ok.txt'"
check [ "$(dgx 'ver_cache_get godns dev')" = 1.3.0 ]
check [ "$(dgx 'ver_cache_get @self main')" = 9.9.9 ]
check [ "$(dgx 'prod_refs godns')" = "main dev" ]
check [ "$(cat "$DG/vc/godns.dev.sha")" = "$SHAD 1.3.0" ]
check [ "$(dgx 'self_best')" = "main 9.9.9" ]
# Ей нельзя верить — в кеш не попадает ничего.
bad_dg() {  # bad_dg <имя> — сводка не принята, кеш пуст
    rm -rf "$DG/vc"
    check dgx "! digest_apply '$DG/$1'"
    check [ ! -e "$DG/vc/godns.main" ]
}
mkdg $(( now - 50000 )) > "$DG/old.txt";                              bad_dg old.txt    # старше 12 часов
sed 's/^format=1$/format=2/' "$DG/ok.txt" > "$DG/f2.txt";              bad_dg f2.txt     # чужой формат
grep -v '^gowarp ' "$DG/ok.txt" > "$DG/part.txt";                      bad_dg part.txt   # неполная
# Незнакомый продукт (сводку собирает goInstaller из main, он новее
# сервера) пропускается, а не роняет всю сводку.
{ cat "$DG/ok.txt"; printf 'gonew @refs main\ngonew main 0.1.0 -\n'; } > "$DG/new.txt"
rm -rf "$DG/vc"
check dgx "digest_apply '$DG/new.txt'"
check [ "$(dgx 'ver_cache_get godns main')" = 1.2.3 ]
check [ ! -e "$DG/vc/gonew.main" ]
{ cat "$DG/ok.txt"; printf 'godns ../../etc 1.0 -\n'; } > "$DG/path.txt"; bad_dg path.txt # путь вместо ветки
sed "s/^godns main 1.2.3 /godns main 1.2.3$(printf '\033')[31m /" "$DG/ok.txt" > "$DG/esc.txt"; bad_dg esc.txt  # управляющие символы
sed "s/^godns main 1.2.3 $SHAM/godns main 1.2.3 zzz/" "$DG/ok.txt" > "$DG/sha.txt";  bad_dg sha.txt  # не хеш
printf 'format=1\n' > "$DG/nogen.txt";                                 bad_dg nogen.txt  # без времени

# Запрос условный: вторая сводка — 304, в лимит не идёт; продукты не трогаются.
DURL="https://api.github.com/repos/duboshin52/goInstaller/contents/versions.txt?ref=versions"
fg_set "$DURL" 200 "$(cat "$DG/ok.txt")" '"dg1"'
rm -rf "$DG/vc"; : > "$FG/log"
check dgx 'TOKEN=x; digest_fetch'
check dgx 'TOKEN=x; digest_fetch'
check [ "$(lg_count 'versions.txt_ref_versions cond=no 200')" -eq 1 ]
check [ "$(lg_count 'versions.txt_ref_versions cond=yes 304')" -eq 1 ]
check [ "$(wc -l < "$FG/log")" -eq 2 ]
# Нет ветки versions (Actions ещё не собрал сводку) — rc 1, решает зовущий.
fg_set "$DURL" 404 '{}'
rm -rf "$DG/vc"
check [ "$(dgx 'TOKEN=x; digest_fetch; echo $?')" = 1 ]

# --watch: сводка есть — один запрос на всё, и новости из неё.
printf '{\n  "godns_version": "1.0.0"\n}\n' > "$DG/godns.json"
wx() {  # summary_watch на стенде с goVLESS pro, стоит goDNS pro 1.0.0
    PATH="$T/fakegh:$PATH" FAKEGH="$FG" GH_TOKEN=x GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 \
    GOINST_SS_FIXTURE="$T/ss-govless" GOINST_UNIT_FIXTURE="$T/units-govless" GOINST_NGINX_ROOT="$T/nginx-govless" \
    GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_FAKE_INSTALLED=godns GOINST_GODNS_CONFIG="$DG/godns.json" \
    GOINST_LE_ROOT="$T/le-empty" GOINST_ARCH=x86_64 GOINST_FS_ROOT="$DG/fs" GOINST_UI_SYS="1 2 0.1" GOINST_DOCKER_FIXTURE="$T/docker-empty" \
    GOINST_VER_CACHE="$DG/vc" GOINST_DIR="$DG/gi" GOINST_SUM_FILE="$DG/summary" \
    bash -c ". '$SCRIPT'; os_detect; summary_watch"
}
fg_set "$DURL" 200 "$(mkdg "$(date +%s)")" '"dg2"'
rm -rf "$DG/vc" "$DG/gi" "$DG/summary"; : > "$FG/log"
wx
check [ "$(wc -l < "$FG/log")" -eq 1 ]
check grep -q 'news=↑|update|goDNS pro|1.0.0 → 1.2.3' "$DG/summary"
check grep -q '^sved=[0-9][0-9]:[0-9][0-9]$' "$DG/summary"
# Сводки нет — спрашивает сам, но только про стоящий продукт и себя, и
# ключ по шести репозиториям не проверяет.
fg_set "$DURL" 404 '{}'
rm -rf "$DG/vc"; : > "$FG/log"
wx
check [ "$(lg_count 'anten-ka_goDNS')" -gt 0 ]
check [ "$(lg_count 'anten-ka_goInstaller_commits')" -gt 0 ]
for r in goVLESS gotelegram_pro kaskad-pro go_warp_pro goamnezia_pro; do check [ "$(lg_count "anten-ka_$r")" -eq 0 ]; done
# Лимит исчерпан — сеть не трогаем вовсе; время сведений остаётся прежним.
printf 'sved=08:00\n' > "$DG/summary"
printf '%s\n' "$(( $(date +%s) + 900 ))" > "$DG/vc/@ratelimit"
: > "$FG/log"
wx
check [ "$(wc -l < "$FG/log")" -eq 0 ]
check grep -qx 'sved=08:00' "$DG/summary"
rm -f "$DG/vc/@ratelimit"

# Публикация: локальный «origin» вместо GitHub — та же логика, что в Actions.
if command -v git >/dev/null 2>&1; then
    PB="$T/pub"; mkdir -p "$PB"
    git init -q --bare "$PB/origin.git"; git init -q "$PB/work"; git -C "$PB/work" remote add origin "$PB/origin.git"
    pub() { (cd "$PB/work" && GOINST_DIGEST_HEARTBEAT="${HB:-21600}" bash "$HERE/.github/versions-publish.sh" "$1") >/dev/null 2>&1; }
    vsha() { git -C "$PB/origin.git" rev-parse -q --verify refs/heads/versions 2>/dev/null || true; }
    mkdg $(( now - 300 )) > "$PB/a.txt"
    check pub "$PB/a.txt"
    s1=$(vsha)
    check [ -n "$s1" ]
    check [ "$(git -C "$PB/origin.git" show versions:versions.txt)" = "$(cat "$PB/a.txt")" ]
    # То же содержимое, другое время сборки — не публикуем.
    mkdg $(( now - 240 )) > "$PB/a2.txt"
    check pub "$PB/a2.txt"
    check [ "$(vsha)" = "$s1" ]
    # Изменилось — новый коммит, и он один: история не растёт.
    sed 's/^godns dev 1.3.0/godns dev 1.3.1/' "$PB/a2.txt" > "$PB/b.txt"
    check pub "$PB/b.txt"
    s2=$(vsha)
    check [ "$s2" != "$s1" ]
    check [ "$(git -C "$PB/origin.git" rev-list --count versions)" -eq 1 ]
    # Прошлой сводке больше шести часов — публикуем даже без изменений.
    sed "s/^generated=.*/generated=$(( now - 120 ))/" "$PB/b.txt" > "$PB/b2.txt"
    HB=0 pub "$PB/b2.txt"
    check [ "$(vsha)" != "$s2" ]
    # Битую сводку не публикуем.
    s3=$(vsha)
    printf 'garbage\n' > "$PB/bad.txt"
    check neg pub "$PB/bad.txt"
    check [ "$(vsha)" = "$s3" ]
fi

# Workflow: что, когда и с каким доступом.
WF="$HERE/.github/workflows/versions.yml"
check [ -f "$WF" ]
wf=$(cat "$WF" 2>/dev/null)
check has "$wf" "cron: '23 * * * *'"         # раз в час, не в :00 — там очередь GitHub
check has "$wf" 'workflow_dispatch'
check has "$wf" 'contents: write'
check has "$wf" 'secrets.GOINST_READ_TOKEN'
check has "$wf" 'go-installer.sh --digest'
check has "$wf" 'versions-publish.sh'
check has "$wf" 'concurrency:'
check has "$wf" 'timeout-minutes:'
check hasnt "$wf" 'set -x'
check hasnt "$wf" 'pull_request'   # секрет не должен доставаться чужим веткам
# Ветка, которую пишет Actions, — та, что читает сервер.
check [ "$(ml 'printf %s "$DIGEST_REF"')" = versions ]
check has "$(cat "$HERE/.github/versions-publish.sh")" 'branch="${GOINST_DIGEST_REF:-versions}"'

echo "── goKaskad pro 3 в dev: ветка стоящего, Enter не уводит на 2.x"
# goKaskad pro 3 живёт в dev (на main — 2.x). Ветку обновлений 3.x пишет в
# /etc/kaskad/config (KASKAD_BRANCH); 2.x веток не знает.
K3="$T/k3"; mkdir -p "$K3/vc" "$K3/fs3/usr/local/bin" "$K3/fs3/etc/kaskad" "$K3/fs2/usr/local/bin" "$K3/fs2/etc/kaskad" "$K3/fs3n/usr/local/bin"
GOINST_SOURCE_ONLY=1 GOINST_VER_CACHE="$K3/vc" bash -c ". '$SCRIPT'; ver_cache_write gokaskad @refs 'main dev'; ver_cache_write gokaskad main 2.13; ver_cache_write gokaskad dev 3.3.3"
printf '#!/bin/bash\nKASKAD_VERSION="3.3.1"\n' > "$K3/fs3/usr/local/bin/gokaskad"; printf 'KASKAD_BRANCH="dev"\n' > "$K3/fs3/etc/kaskad/config"
printf '#!/bin/bash\nKASKAD_VERSION="2.13"\n' > "$K3/fs2/usr/local/bin/gokaskad"; printf 'KASKAD_BRANCH="dev"\n' > "$K3/fs2/etc/kaskad/config"
printf '#!/bin/bash\nKASKAD_VERSION="3.3.1"\n' > "$K3/fs3n/usr/local/bin/gokaskad"
mkdir -p "$K3/fsk3/usr/local/bin" "$K3/fsk3/etc/kaskad"
printf '#!/bin/bash\nKASKAD_VERSION="3.3.1"\n' > "$K3/fsk3/usr/local/bin/gokaskad"; printf 'KASKAD_BRANCH="k3"\n' > "$K3/fsk3/etc/kaskad/config"
k3x() {  # k3x <корень ФС> <команды>
    T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_VER_CACHE="$K3/vc" GOINST_VER_TTL=99999 GOINST_NO_NET=1 \
    GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_ARCH=x86_64 GOINST_FS_ROOT="$1" GOINST_DIR="$K3/gi" bash -c ". '$SCRIPT'; $2"
}
check [ "$(k3x "$K3/fs3" 'prod_installed_ref gokaskad')" = dev ]
# 2.x: строка от прежней 3.x — не ветка.
check k3x "$K3/fs2" '! prod_installed_ref gokaskad'
# 3.x сам пишет себе k3 (цепочка main → test → k3) или ничего — это dev:
# иначе умолчанием была бы main, и Enter откатил бы 3.x на 2.x.
check [ "$(k3x "$K3/fsk3" 'prod_installed_ref gokaskad')" = dev ]
check [ "$(k3x "$K3/fs3n" 'prod_installed_ref gokaskad')" = dev ]
# Сверке после установки — записанное как есть: k3 после оборванного
# установщика не выдаётся за dev.
check [ "$(k3x "$K3/fsk3" 'prod_installed_ref gokaskad raw')" = k3 ]
check k3x "$K3/fs3n" '! prod_installed_ref gokaskad raw'
check has "$(code | sed -n '/^installer_verdict()/,/^}/p')" 'prod_installed_ref "$id" raw'
check [ "$(printf '\n' | k3x "$K3/fsk3" 'ask_ref gokaskad >/dev/null 2>&1; echo "$REF"')" = dev ]
check [ "$(printf '\n' | k3x "$K3/fs3n" 'ask_ref gokaskad >/dev/null 2>&1; echo "$REF"')" = dev ]
# Ветки нет в списке — «Enter — оставить» не обещается.
check hasnt "$(printf '1\n' | GOINST_REFS_gotelegram="main" k3x "$K3/none" 'prod_installed_ref() { printf k3; }; ask_ref gotelegram 2>&1')" 'k3'
# Номером — dev; Enter у стоящего с dev — dev, у 2.x — main.
check [ "$(printf '2\n' | k3x "$K3/none" 'ask_ref gokaskad >/dev/null 2>&1; echo "$REF"')" = dev ]
check [ "$(printf '\n' | k3x "$K3/fs3" 'ask_ref gokaskad >/dev/null 2>&1; echo "$REF"')" = dev ]
check [ "$(printf '\n' | k3x "$K3/fs2" 'ask_ref gokaskad >/dev/null 2>&1; echo "$REF"')" = main ]
# «Аркада»: стоит с dev — обновление по dev, пометки и курсор на dev.
out=$(GOINST_FAKE_INSTALLED=gokaskad k3x "$K3/fs3" 'os_detect; ui_model_load; p=3; echo "ref=${UD_DEVREF[p]} dev=${UD_DEV[p]} br=${UD_BRANCH[p]} upd=${UD_UPD[p]} updv=${UD_UPDV[p]}"
      ui_scr_branch $p 1 >/dev/null; printf "it=%s|%s|%s\n" "${IT_LABEL[1]}" "${IT_ACT[1]}" "${IT_NOTE[1]}"; printf "it0=%s\n" "${IT_NOTE[0]}"
      UI_PBRANCH=dev; ui_scr_confirm $p 0 >/dev/null; echo "q=$UI_Q"' 2>/dev/null)
check has "$out" 'ref=dev dev=3.3.3 br=dev upd=1 updv=3.3.3'
check has "$out" 'it=dev 3.3.3|branch:dev|экспериментальная; сейчас стоит 3.3.1; ↑ новее'
check has "$out" 'it0=стабильная'
check hasnt "$out" 'it0=стабильная;'
check has "$out" 'ветка dev, 3.3.3?'
# Действие «дальше» в мастере: стоит с dev — курсор на dev, подсказка о нём.
for fs in fs3 fsk3; do
    out=$(GOINST_FAKE_INSTALLED=gokaskad GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 k3x "$K3/$fs" 'ui_detect; ui_model_load; TOKEN=t; UI_SCR=mode; UI_CUR=0; UI_STACK=(); UI_WP=3; ui_act continue; echo "scr=$UI_SCR cur=$UI_CUR"; ui_scr_branch 3 "$UI_CUR"; ui_compose; ui_dump' 2>/dev/null | cut -f1)
    check has "$out" 'scr=branch cur=1'
    check has "$out" 'Enter — 2, dev'
    check has "$out" '▸ 2  dev 3.3.3'
done
out=$(GOINST_FAKE_INSTALLED=gokaskad k3x "$K3/fs2" 'ui_detect; ui_model_load; TOKEN=t; UI_SCR=mode; UI_CUR=0; UI_STACK=(); UI_WP=3; ui_act continue; echo "scr=$UI_SCR cur=$UI_CUR"' 2>/dev/null)
check has "$out" 'scr=branch cur=0'
# Карточка: «↑ новее» на строке dev, а не main.
card=$(GOINST_FAKE_INSTALLED=gokaskad GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 k3x "$K3/fs3" 'ui_detect; ui_model_load; ui_scr_product 3 0; ui_compose; ui_dump' 2>/dev/null | cut -f1)
check grep -qE 'dev +3\.3\.1 +3\.3\.3 +↑ новее' <<<"$card"
check neg grep -qE 'main .*↑' <<<"$card"
# 2.x с main — обновления нет: 3.3.3 в dev — не обновление ветки, с которой стоит.
out=$(GOINST_FAKE_INSTALLED=gokaskad k3x "$K3/fs2" 'os_detect; ui_model_load; p=3; echo "br=${UD_BRANCH[p]} upd=${UD_UPD[p]}"' 2>/dev/null)
check has "$out" 'br=main upd=0'
# Ветка уходит установщику 3.x в KASKAD_BRANCH (2.x её не читает).
check has "$(code)" 'KASKAD_BRANCH="$ref" KASKAD_LANG="$(gokaskad_lang_env)" ./install.sh'
# `--install gokaskad dev`: у продукта без режимов третье слово — ветка, и она
# доходит до установщика (локальный источник — поддельный install.sh).
mkdir -p "$K3/src"; printf '#!/bin/bash\necho "KB=${KASKAD_BRANCH:-} KL=${KASKAD_LANG:-}"\n' > "$K3/src/install.sh"; chmod +x "$K3/src/install.sh"
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_UNIT_FIXTURE="$T/units-empty" \
      GOINST_DOCKER_FIXTURE=/dev/null GOINST_NO_NET=1 GOINST_DIR="$K3/gi2" GOINST_SRC_gokaskad="$K3/src" GOINST_ARCH=x86_64 \
      bash "$SCRIPT" --install gokaskad dev </dev/null 2>&1); rc=$?
check has "$out" 'KB=dev KL=ru'
# П3 (третий круг): поддельный установщик вышел с 0, а продукта нет — «не
# встал» и код 1, а не 0: для скриптов это отказ.
check has "$out" 'goKaskad pro не встал'
check [ "$rc" -eq 1 ]
# Язык, выбранный в goInstaller, уходит установщику: 3.x иначе спрашивает его
# снова и предлагает английский.
out=$(GOINST_TEST=1 GOINST_LANG=en GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_UNIT_FIXTURE="$T/units-empty" \
      GOINST_DOCKER_FIXTURE=/dev/null GOINST_NO_NET=1 GOINST_DIR="$K3/gi7" GOINST_SRC_gokaskad="$K3/src" GOINST_ARCH=x86_64 \
      bash "$SCRIPT" --install gokaskad dev </dev/null 2>&1)
check has "$out" 'KB=dev KL=en'
# Свой язык у продукта уже записан (меню, панель, бот) — обновление его не
# переписывает: KASKAD_LANG не передаётся.
mkdir -p "$K3/fsl/etc/kaskad"; printf 'KASKAD_LANG="en"\n' > "$K3/fsl/etc/kaskad/config"
check [ -z "$(GOINST_FS_ROOT="$K3/fsl" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; gokaskad_lang_env")" ]
check [ "$(GOINST_FS_ROOT="$K3/none" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; gokaskad_lang_env")" = ru ]
check [ "$(GOINST_FS_ROOT="$K3/none" GOINST_SOURCE_ONLY=1 GOINST_LANG=de bash -c ". '$SCRIPT'; gokaskad_lang_env")" = ru ]
# Стоит (2.x или 3.x) — язык не передаётся: переход с 2.x 3.x оставляет русским сам.
check [ -z "$(GOINST_FAKE_INSTALLED=gokaskad GOINST_FS_ROOT="$K3/none" GOINST_SOURCE_ONLY=1 GOINST_LANG=en bash -c ". '$SCRIPT'; gokaskad_lang_env")" ]
# Порты goKaskad pro 3 — к сведению: вердикт «готов» у 2.x они не меняют,
# занятые 443 и 80 (goVLESS pro рядом) — не препятствие и не замечание.
printf 'tcp LISTEN 0 4096 0.0.0.0:443 0.0.0.0:* users:(("xray",pid=10,fd=3))\ntcp LISTEN 0 511 0.0.0.0:80 0.0.0.0:* users:(("nginx",pid=11,fd=6))\n' > "$K3/ss-web"
pk=$(ml 'prod_ports_opt gokaskad')
for r in 'tcp|1980|info' 'tcp|443|info' 'tcp|8443|info' 'tcp|80|info' 'udp|51820|info' 'tcp|4443|info' 'udp|4443|info' 'udp|1194|info' \
         'tcp|1080|info' 'udp|1080|info' 'tcp|4433|info' 'udp|500|info' 'udp|4500|info' 'udp|1701|info' 'tcp|1723|info'; do check has "$pk" "$r"; done
check [ "$(grep -c '' <<<"$pk")" -eq "$(grep -c '|info|' <<<"$pk")" ]   # только info
check hasnt "$(ml 'prod_ports gokaskad')" '1980'                         # не в «НУЖНЫ»
check has "$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$K3/ss-web" GOINST_UNIT_FIXTURE="$T/units-empty" \
    GOINST_DOCKER_FIXTURE=/dev/null bash "$SCRIPT" --check gokaskad 2>&1)" '1723/tcp'                  # а в проверке портов — да
# Без сети опрос «Аркады» не стартует и по таймеру меню (затирал кеш версий).
check [ "$(GOINST_SOURCE_ONLY=1 GOINST_NO_NET=1 bash -c ". '$SCRIPT'; ui_poll_start; echo \$?")" = 1 ]
# «Аркада»: свободные порты функций — одной строкой, занятые — своими; иначе
# экран без прокрутки терял пункт «Продолжить».
out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$K3/ss-web" GOINST_UNIT_FIXTURE="$T/units-empty" \
      GOINST_DOCKER_FIXTURE=/dev/null bash -c ". '$SCRIPT'; ui_pf_load gokaskad pro; printf '%s\n' \"\${UI_PFR_PORT[@]}\"")
check [ "$(printf '%s\n' "$out" | tr '\n' ' ')" = "10808/tcp 10851/tcp 443/tcp 80/tcp +13 " ]
out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_UNIT_FIXTURE="$T/units-empty" \
      GOINST_DOCKER_FIXTURE=/dev/null GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 GOINST_NO_NET=1 GOINST_ARCH=x86_64 GOINST_DIR="$K3/gi8" bash -c ". '$SCRIPT'; ui_detect; ui_model_load >/dev/null 2>&1; ui_pf_load gokaskad pro; ui_scr_check 3 0 1; ui_compose; ui_dump" 2>/dev/null | cut -f1)
check has "$out" 'Продолжить'
check has "$out" '+15'
check has "$out" 'порты функций продукта свободны'
GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$K3/ss-web" GOINST_UNIT_FIXTURE="$T/units-empty" \
    GOINST_DOCKER_FIXTURE=/dev/null bash "$SCRIPT" --check gokaskad >/dev/null 2>&1; check [ $? -eq 0 ]
# Слово, которое не ветка, — прежний «режим» без смысла, как до 1.0.9; а
# ветка-опечатка четвёртым словом — код 64 до всякой сети.
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_UNIT_FIXTURE="$T/units-empty" \
      GOINST_DOCKER_FIXTURE=/dev/null GOINST_NO_NET=1 GOINST_DIR="$K3/gi3" GOINST_SRC_gokaskad="$K3/src" GOINST_ARCH=x86_64 \
      bash "$SCRIPT" --install gokaskad pro main </dev/null 2>&1); rc=$?
check [ "$rc" -eq 1 ]                                     # не встал (П3)
check has "$out" 'KB=main'
# Установщик вышел с кодом — он и уходит, «не встал» его не подменяет.
printf '#!/bin/bash
exit 7
' > "$K3/src7"; mkdir -p "$K3/s7"; mv "$K3/src7" "$K3/s7/install.sh"; chmod +x "$K3/s7/install.sh"
GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_UNIT_FIXTURE="$T/units-empty"     GOINST_DOCKER_FIXTURE=/dev/null GOINST_NO_NET=1 GOINST_DIR="$K3/gi3" GOINST_SRC_gokaskad="$K3/s7" GOINST_ARCH=x86_64     bash "$SCRIPT" --install gokaskad pro main </dev/null >/dev/null 2>&1; check [ $? -eq 7 ]
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_NO_NET=1 GOINST_DIR="$K3/gi4" \
      GOINST_SRC_gokaskad="$K3/src" bash "$SCRIPT" --install gokaskad pro Dev </dev/null 2>&1); rc=$?
check [ "$rc" -eq 64 ]
check has "$out" 'нет ветки «Dev»'
check hasnt "$out" 'KB='
# Три слова со словом не-веткой — как до 1.0.9: вопрос о ветке (здесь без
# ввода — отмена), установщик не запускается.
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_NO_NET=1 GOINST_DIR="$K3/gi5" \
      GOINST_VER_CACHE="$K3/vce" GOINST_SRC_gokaskad="$K3/src" bash "$SCRIPT" --install gokaskad pro </dev/null 2>&1); rc=$?
check [ "$rc" -eq 1 ]
check hasnt "$out" 'KB='
# Ветка сверяется со списком, а не угадывается: в кеше сервера список без
# dev (опрос был до её появления, сети нет) — честный отказ, а не тихая main.
mkdir -p "$K3/vcs"; GOINST_SOURCE_ONLY=1 GOINST_VER_CACHE="$K3/vcs" bash -c ". '$SCRIPT'; ver_cache_write gokaskad @refs main; ver_cache_write gowarp @refs main"
for a in "gokaskad dev" "gokaskad pro dev" "gowarp dev"; do
    out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_NO_NET=1 GOINST_DIR="$K3/gi6" \
          GOINST_VER_CACHE="$K3/vcs" GOINST_VER_TTL=99999 GOINST_SRC_gokaskad="$K3/src" bash "$SCRIPT" --install $a </dev/null 2>&1); rc=$?
    check [ "$rc" -eq 64 ]
    check has "$out" 'нет ветки «dev». Есть: main'
    check hasnt "$out" 'KB='
done
# У продукта с режимами третье слово по-прежнему режим: опечатка — код 64.
out=$(GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" bash "$SCRIPT" --install govless dev </dev/null 2>&1); rc=$?
check [ "$rc" -eq 64 ]

echo "── удаление самого goInstaller"
# Уносит только своё; продукты и их команды остаются. Ключ — по выбору:
# его как запасной читает goKaskad pro.
UN="$T/uninst"
un_seed() {
    rm -rf "$UN"; mkdir -p "$UN/bin" "$UN/gi/vc" "$UN/systemd" "$UN/profile" "$UN/prod"
    printf '#!/bin/bash\nGOINST_VERSION="1.0.6"\n' > "$UN/bin/goinstall"; chmod +x "$UN/bin/goinstall"
    ln -s "$UN/bin/goinstall" "$UN/bin/go-installer"
    printf 'ghp_test\n' > "$UN/gi/token"; printf 'ru\n' > "$UN/gi/.language"; printf 'full\n' > "$UN/gi/.ui-size"; : > "$UN/gi/vc/govless.main"
    : > "$UN/systemd/goinstall-watch.timer"; : > "$UN/systemd/goinstall-watch.service"; : > "$UN/profile/goinstall-summary.sh"
    printf '#!/bin/bash\nKASKAD_VERSION="2.13"\n' > "$UN/prod/gokaskad"; chmod +x "$UN/prod/gokaskad"
}
un() {  # un <аргументы --uninstall> → вывод; всё во временном дереве
    ( export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 PATH="$NAV/bin:$PATH"
      export GOINST_DIR="$UN/gi" GOINST_BIN="$UN/bin/goinstall" GOINST_BIN_ALIAS="$UN/bin/go-installer"
      export GOINST_SYSTEMD_DIR="$UN/systemd" GOINST_PROFILE_HOOK="$UN/profile/goinstall-summary.sh"
      # Обновление Ubuntu: скрипт входа, apt.conf, Prompt — тоже во временном
      # дереве. Иначе goinst_remove под root снёс бы настоящие.
      export GOINST_FS_ROOT="$UN/fs" GOINST_OSUP_HOOK="$UN/fs/etc/profile.d/goinstall-osupgrade.sh"
      . "$SCRIPT"; "${UNFN:-goinst_uninstall}" "$@" ) 2>&1
}
# Все пути удаления — во временном дереве (З3, третий круг).
unpaths() { _osup_paths; printf '%s\n' "$GOINST_DIR" "$GOINST_BIN" "$GOINST_BIN_ALIAS" "$SUM_HOOK" "$SUM_UNIT_DIR" \
    "$OSUP_DIR" "$OSUP_APTCONF" "$OSUP_RU" "$OSUP_SL" "$OSUP_UNITF" "$OSUP_HOOK" "$OSUP_RUNNER"; }
out=$(UNFN=unpaths un)
check [ "$(grep -c '' <<<"$out")" -eq 12 ]
check [ "$(grep -c "^$UN/" <<<"$out")" -eq 12 ]
un_seed
out=$(un --yes)
check has "$out" 'goInstaller удалён'
check neg test -e "$UN/bin/goinstall"
check neg test -L "$UN/bin/go-installer"
check neg test -e "$UN/gi"
check neg test -e "$UN/systemd/goinstall-watch.timer"
check neg test -e "$UN/profile/goinstall-summary.sh"
# Продукт не тронут.
check test -x "$UN/prod/gokaskad"
# Ключ можно оставить: остальное из каталога уходит, ключ остаётся 0600-файлом.
un_seed
out=$(un --yes --keep-key)
check has "$out" 'Ключ оставлен'
check test -f "$UN/gi/token"
check [ "$(ls -A "$UN/gi")" = token ]
check neg test -e "$UN/bin/goinstall"
# Без --yes и без терминала — отказ, ничего не тронуто.
un_seed
out=$(un </dev/null)
check has "$out" 'goinstall --uninstall --yes'
check test -e "$UN/bin/goinstall"
check has "$(un </dev/null; echo "rc=$?")" 'rc=3'             # тот же код, что у --components update
check hasnt "$out" 'Удалить и ключ'      # отказ — до вопросов
# Чужой файл на месте псевдонима или команды не удаляется.
un_seed; rm -f "$UN/bin/go-installer"; printf '#!/bin/bash\necho чужой\n' > "$UN/bin/go-installer"
un --yes >/dev/null
check test -e "$UN/bin/go-installer"
# Странный каталог — ничего не удаляется (rm -rf «/» недопустим).
un_seed
out=$( ( export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_BIN="$UN/bin/goinstall"; . "$SCRIPT"; GOINST_DIR=/; goinst_remove drop ) 2>&1 ); rc=$?
check [ "$rc" = 1 ]
check has "$out" 'задан странно'
check test -e "$UN/bin/goinstall"
# Уже удалён — так и сказано.
un_seed; un --yes >/dev/null
check has "$(un --yes)" 'уже не стоит'
# Команда и пункты меню на месте.
check has "$(code | sed -n '/^main()/,/^}/p')" '--uninstall) shift'
check has "$(ml usage)" '--uninstall'

echo "── размер пакета: путь до GitHub уже сетевой карты"
# На 177.3.218.172 карта стояла на 1500, путь пропускал 1452, и TLS до GitHub
# рвался через раз. Системные вызовы подменены: сеть и карта не трогаются.
NETFS="$T/fsnet"; rm -rf "$NETFS"; mkdir -p "$NETFS/etc/network" "$NETFS/etc/netplan" "$T/net"
nt() {  # nt <путь_пропускает> <выражение>; карта 1500, ping отвечает как настоящий
    ( export T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_NET_TEST=1
      export GOINST_FS_ROOT="$NETFS" GOINST_NET_DECLINE_FILE="$T/net/declined" PATHMTU="$1"
      . "$SCRIPT"
      _net_resolve() { echo 140.82.112.6; }
      _net_route_dev() { echo ens3; }
      _net_if_mtu() { cat "$T/net/ifmtu" 2>/dev/null || echo 1500; }
      _net_set_mtu() { echo "$2" > "$T/net/ifmtu"; echo "set $1 $2" >> "$T/net/calls"; }
      _net_ping_df() {
          local cur; cur=$(_net_if_mtu)
          [ $(( $2 + 28 )) -le "$PATHMTU" ] && return 0
          [ "${NOMSG:-}" ] && return 1
          echo "From 10.0.0.1 icmp_seq=1 Frag needed and DF set (mtu = $PATHMTU)"; return 1
      }
      eval "$2" )
}
rm -f "$T/net/"*
# Путь пропускает всё — тихо.
check [ "$(nt 1500 'net_mtu_probe; echo $?')" = 0 ]
check [ -z "$(nt 1500 'net_mtu_offer' 2>&1)" ]
# Путь уже — размер узнаётся из ответа узкого места.
check [ "$(nt 1452 'net_mtu_probe; echo "$?:$NET_DEV:$NET_IFMTU:$NET_PMTU"')" = "1:ens3:1500:1452" ]
# Два узких места: первый узел называет 1472, путь дальше — 1452 (так было
# на 177.3.218.172). Верить первому ответу нельзя.
check [ "$(nt 1452 '_net_ping_df() { [ $(( $2 + 28 )) -le 1452 ] && return 0; if [ $(( $2 + 28 )) -gt 1472 ]; then echo "Frag needed (mtu = 1472)"; else echo "message too long, mtu=1452"; fi; return 1; }; net_mtu_probe; echo "$?:$NET_PMTU"')" = "1:1452" ]
# Ответа о размере нет — ищется сам, до байта.
check [ "$(NOMSG=1 nt 1452 'net_mtu_probe; echo "$?:$NET_PMTU"')" = "1:1452" ]
# ICMP режут целиком — молчим, а не выдумываем.
check [ "$(NOMSG=1 nt 1000 'net_mtu_probe; echo $?')" = 2 ]
# Кто настраивает карту: блок iface этой карты — ifupdown.
printf 'auto lo\niface lo inet loopback\n\nauto ens3\niface ens3 inet static\n    address 177.3.218.172\n    mtu 1500\n    gateway 10.0.0.1\n\nauto ens4\niface ens4 inet dhcp\n    mtu 9000\n' > "$NETFS/etc/network/interfaces"
check [ "$(nt 1452 'net_persist_kind ens3')" = ifupdown ]
# netplan про ДРУГУЮ карту (enp1s0, как на том сервере) — не наш случай.
printf 'network:\n    ethernets:\n        enp1s0:\n            dhcp4: true\n' > "$NETFS/etc/netplan/50-cloud-init.yaml"
check [ "$(nt 1452 'net_persist_kind ens5')" = none ]
check [ "$(nt 1452 'net_persist_kind enp1s0')" = netplan ]
# Отказ: ничего не меняется, запоминается, второй раз не спрашивает.
rm -f "$T/net/calls" "$T/net/ifmtu"
out=$(printf '2\n' | nt 1452 'net_mtu_offer' 2>&1)
check has "$out" 'путь до GitHub пропускает только 1452'
check has "$out" 'Ключ тут ни при чём'
check has "$out" 'Изменить размер пакета сетевой карты ens3 на 1452?'
check neg test -e "$T/net/calls"
check [ "$(cat "$T/net/declined")" = "ens3:1452" ]
check [ -z "$(printf '1\n' | nt 1452 'net_mtu_offer' 2>&1)" ]
# --net спрашивает и после отказа.
check has "$(printf '2\n' | nt 1452 'net_mtu_offer force' 2>&1)" 'Изменить размер пакета'
# Согласие: карта меняется, проверка повторяется, блок ens3 получает mtu,
# соседний блок ens4 со своим mtu 9000 не тронут, копия рядом.
rm -f "$T/net/declined"
out=$(printf '1\n' | nt 1452 'net_mtu_offer' 2>&1)
check has "$out" 'Размер пакета ens3: 1452'
check has "$out" 'Записано в /etc/network/interfaces'
check [ "$(cat "$T/net/calls")" = "set ens3 1452" ]
ifc=$(cat "$NETFS/etc/network/interfaces")
check [ "$(grep -c 'mtu 1452' <<<"$ifc")" = 1 ]
check neg grep -q 'mtu 1500' <<<"$ifc"
check has "$ifc" '    mtu 9000'
check [ "$(sed -n '/^iface ens3/{n;p;}' <<<"$ifc")" = "    mtu 1452" ]
check ls "$NETFS"/etc/network/interfaces.bak-goinstall-*
check neg test -e "$T/net/declined"
# После правки путь всё равно уже — вернуть прежний размер и ничего не писать.
rm -f "$T/net/calls" "$T/net/ifmtu"; cp "$NETFS/etc/network/interfaces" "$T/net/before"
out=$( ( export T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_NET_TEST=1 GOINST_FS_ROOT="$NETFS" GOINST_NET_DECLINE_FILE="$T/net/declined"
        . "$SCRIPT"
        _net_resolve() { echo 140.82.112.6; }; _net_route_dev() { echo ens3; }
        _net_if_mtu() { cat "$T/net/ifmtu" 2>/dev/null || echo 1500; }
        _net_set_mtu() { echo "$2" > "$T/net/ifmtu"; echo "set $1 $2" >> "$T/net/calls"; }
        _net_ping_df() { [ "$2" -le 1200 ] && return 0; echo "Frag needed (mtu = 1400)"; return 1; }
        net_mtu_probe; NET_PMTU=1452; net_mtu_apply ifupdown ) 2>&1 )
check has "$out" 'вернул 1500'
check [ "$(tr '\n' ' ' < "$T/net/calls")" = "set ens3 1452 set ens3 1500 " ]
check cmp -s "$T/net/before" "$NETFS/etc/network/interfaces"
# Без терминала не спрашивает и отказ не записывает.
rm -f "$T/net/declined" "$T/net/calls"
out=$( ( export GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_NET_TEST=1 GOINST_FS_ROOT="$NETFS" GOINST_NET_DECLINE_FILE="$T/net/declined"
        . "$SCRIPT"; GOINST_NET_TEST=""; GOINST_TEST=""
        _net_resolve() { echo 140.82.112.6; }; _net_route_dev() { echo ens3; }; _net_if_mtu() { echo 1500; }
        _net_set_mtu() { echo called >> "$T/net/calls"; }
        _net_ping_df() { [ $(( $2 + 28 )) -le 1452 ] && return 0; echo "Frag needed (mtu = 1452)"; return 1; }
        command() { [ "$2" = ping ] && return 0; builtin command "$@"; }
        net_mtu_offer </dev/null ) 2>&1 )
check has "$out" 'Исправить: goinstall --net'
check hasnt "$out" 'Изменить размер пакета'
check neg test -e "$T/net/declined"
check neg test -e "$T/net/calls"
# Без подделок набор сеть не трогает.
check [ -z "$(GOINST_SOURCE_ONLY=1 GOINST_TEST=1 bash -c ". '$SCRIPT'; _net_ping_df() { echo CALLED; }; net_mtu_offer" 2>&1)" ]
# Проверка стоит до первого обращения к GitHub — и в меню, и в --install.
mb=$(code | sed -n '/^main()/,/^}/p')
check [ "$(grep -n -m1 'net_mtu_offer$' <<<"$mb" | cut -d: -f1)" -lt "$(grep -n -m1 '^    self_install$' <<<"$mb" | cut -d: -f1)" ]
check has "$(sed -n '/--install)/,/;;/p' <<<"$mb")" 'net_mtu_offer'
check has "$mb" '--net) reattach_tty; net_mtu_offer force'
# Сетевой сбой скачивания не винит ключ и повторяется (обёрткой gh_curl).
fr=$(code | sed -n '/^fetch_raw()/,/^}/p')
check has "$fr" 'gh_curl --config'
check has "$fr" 'local GH_SAY=1'
check has "$fr" 'Ключ тут ни при чём'

echo "── связь с GitHub: ожидание, повторы, причина словами"
# 6.10 у подписчика каждый запрос шёл 5–9 с, а проверка ключа обрывала его
# через 5 с: «GitHub недоступен» при живом GitHub. Поддельный curl для
# каждого адреса первые FAIL_K раз «не отвечает» с кодом FAIL_RC, потом
# отдаёт OK_OUT (по -w) и пишет файл (по -o).
NF="$T/netfake"; rm -rf "$NF"; mkdir -p "$NF/bin"
cat > "$NF/bin/curl" <<'FAKE'
#!/bin/bash
of="" hf="" url=""
while [ $# -gt 0 ]; do
    case "$1" in -o) of="$2"; shift ;; -D) hf="$2"; shift ;; -w|-H|--max-time|--config|-K) shift ;; http*) url="$1" ;; esac
    shift
done
k="${url//[^A-Za-z0-9]/_}"; n=$(( $(cat "$NFD/$k" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$NFD/$k"
echo "$url" >> "$NFD/calls"
[ -n "$hf" ] && : > "$hf"
if [ "$n" -le "${FAIL_K:-0}" ]; then [ -n "${FAIL_SLEEP:-}" ] && sleep "$FAIL_SLEEP"; printf '000'; exit "${FAIL_RC:-28}"; fi
[ -n "$of" ] && [ "$of" != /dev/null ] && printf '#!/bin/bash\nX_VERSION="1.2.3"\n' > "$of"
printf '%s' "${OK_OUT:-200}"; exit "${OK_RC:-0}"
FAKE
chmod +x "$NF/bin/curl"
nf() {  # nf <выражение> — функции скрипта с поддельным curl и без пауз
    rm -rf "$NF/d"; mkdir -p "$NF/d"
    ( export PATH="$NF/bin:$PATH" NFD="$NF/d" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
      export GOINST_GH_RETRY_DELAY=0 GOINST_VER_CACHE="$NF/vc" GOINST_TOKEN_FILE="$NF/token"
      mkdir -p "$NF/vc"; . "$SCRIPT"; eval "$1" ) 2>&1
}
ncalls() { wc -l < "$NF/d/calls" 2>/dev/null | tr -d ' '; }
# Ожидание — длинное и настраивается.
check [ "$(nf 'printf "%s %s %s" "$GH_CT" "$GH_MT" "$GH_TRIES"')" = "30 60 4" ]
check has "$(nf 'gh_cfg_net')" 'connect-timeout = 30'
check has "$(GOINST_GH_CONNECT_TIMEOUT=45 nf 'gh_cfg_net')" 'connect-timeout = 45'
check [ -z "$(code | grep -n "connect-timeout = 5\|TIMEOUT:-8")" ]
# Двa сбоя — третья попытка удалась, наружу — ответ GitHub.
out=$(FAIL_K=2 FAIL_RC=28 nf 'gh_curl https://api.github.com/x; echo " rc=$?"')
check [ "$out" = "200 rc=0" ]
check [ "$(ncalls)" = 3 ]
# Ответ GitHub окончателен: 404 и 401 не повторяются.
check [ "$(OK_OUT=404 nf 'gh_curl https://api.github.com/x >/dev/null; cat "$NFD/calls" | wc -l | tr -d " "')" = 1 ]
check [ "$(OK_OUT=401 nf 'gh_curl https://api.github.com/x >/dev/null; cat "$NFD/calls" | wc -l | tr -d " "')" = 1 ]
# С опцией fail 4xx — код 22: тоже не повторяем.
check [ "$(OK_RC=22 OK_OUT=- nf 'gh_curl https://api.github.com/x >/dev/null; cat "$NFD/calls" | wc -l | tr -d " "')" = 1 ]
# Временная ошибка самого GitHub (503) повторяется.
check [ "$(OK_OUT=503 nf 'gh_curl https://api.github.com/x >/dev/null; cat "$NFD/calls" | wc -l | tr -d " "')" = 4 ]
# Все попытки — сбой: код сбоя наружу и метка «сети нет»; следующий запрос
# этого запуска не ждёт по кругу и в сеть не идёт.
out=$(FAIL_K=99 FAIL_RC=7 nf 'GH_DOWN_FILE="$NFD/down"; gh_curl https://api.github.com/a >/dev/null; echo "rc=$? down=$(cat "$NFD/down")"; gh_curl https://api.github.com/b; echo " rc2=$? calls=$(wc -l < "$NFD/calls" | tr -d " ")"')
check has "$out" 'rc=7 down=7'
check has "$out" '000 rc2=7 calls=4'
# Повторы — в журнал и, при GH_SAY, на экран: номер попытки и причина.
out=$(FAIL_K=1 FAIL_RC=6 nf 'GH_RETRY_LOG="$NFD/log"; GH_SAY=1 gh_curl https://api.github.com/x >/dev/null; cat "$NFD/log"')
check has "$out" 'попытка 1 из 4 не удалась'
check has "$out" 'Повтор через 0 с'
check has "$out" 'не работает DNS'
check has "$out" '6 2 4'
# Причины словами.
check has "$(nf 'gh_net_reason 28')" 'время ожидания вышло'
check has "$(nf 'gh_net_reason 60')" 'неверное время на сервере'
check has "$(nf 'gh_net_reason 7')" 'путь закрыт'
check has "$(nf 'gh_net_reason 35')" 'goinstall --net'
# Проверка ключа: медленная сеть с одним сбоем — ключ «ok», и сказано, что
# понадобились повторы и почему.
out=$(FAIL_K=1 FAIL_RC=28 FAIL_SLEEP=1.5 nf 'GH_DELAY=2; TOKEN=t; token_check; echo "status=$TOKEN_STATUS"')
check has "$out" 'status=ok'
check has "$out" 'ответ получен после повторов (6)'
check has "$out" 'Попытка 2 из 4'            # ход ожидания — по мере попыток
# GitHub молчит совсем — «сети нет» с причиной, и каждый запрос пробовали.
out=$(FAIL_K=99 FAIL_RC=6 nf 'TOKEN=t; token_check; echo "status=$TOKEN_STATUS rc=$TOKEN_NETRC"')
check has "$out" 'status=nonet rc=6'
out=$(FAIL_K=99 FAIL_RC=28 GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_TOKEN_FILE="$NF/token" GOINST_VER_CACHE="$NF/vc" GOINST_GH_RETRY_DELAY=0 NFD="$NF/d" PATH="$NF/bin:$PATH" GH_TOKEN=t bash "$SCRIPT" --key check 2>&1)
check has "$out" 'До GitHub не достучаться'
check has "$out" 'Причина: время ожидания вышло'
check has "$out" 'Пробовал 4 раза на каждый запрос'
check hasnt "$out" 'неустойчива'                 # ответа не было — не «неустойчива»
# Медленный DNS: адрес узнаётся один раз и закрепляется; быстрый — нет.
out=$(nf 'GOINST_PIN_TEST=1; _net_resolve() { sleep 1.1; echo 140.82.121.6; }; gh_cfg_net')
check has "$out" 'resolve = "api.github.com:443:140.82.121.6"'
check has "$out" 'resolve = "raw.githubusercontent.com:443:140.82.121.6"'
check hasnt "$(nf 'GOINST_PIN_TEST=1; _net_resolve() { echo 140.82.121.6; }; gh_cfg_net')" 'resolve ='
# Закрепление — один раз за запуск, а не на каждый конфиг.
check [ "$(nf 'GOINST_PIN_TEST=1; _net_resolve() { echo x >> "$NFD/res"; sleep 1.1; echo 1.2.3.4; }; gh_cfg_net >/dev/null; gh_cfg_net >/dev/null; wc -l < "$NFD/res" | tr -d " "')" = 2 ]
# Заставка опроса показывает повторы и причину, пока опрос идёт.
out=$(nf 'UI_POLLDIR="$NFD"; printf "28 2 4\n" > "$NFD/retries"; ui_detect; ui_poll_state; UI_C=80; UI_R=24; UI_COLS=80; ui_scr_splash; printf "%s\n" "${UI_BODY[@]}"')
check has "$out" 'GitHub отвечает с трудом, повтор 2 из 4'
# Экран ошибки — причина и сколько было попыток; без причины текст прежний.
out=$(nf 'ui_detect; UI_C=80; UI_R=24; UI_NETRC=28; ui_scr_err github 0; printf "%s\n" "${UI_BODY[@]}"')
check has "$out" 'Причина: время ожидания вышло'
check has "$out" 'Попыток на каждый запрос: 4'
check has "$(nf 'ui_detect; UI_C=80; UI_R=24; UI_NETRC=; ui_scr_err github 0; printf "%s\n" "${UI_BODY[@]}"')" 'curl -I https://api.github.com'
# Скачивание: сообщения о повторах видны и для хеша ветки, и для файла, а
# исчерпал попытки первый запрос — второй не ждёт по новой.
out=$(FAIL_K=99 FAIL_RC=28 nf 'TOKEN=""; fetch_raw o/r main f.sh "$NFD/f"; echo "rc=$? calls=$(wc -l < "$NFD/calls" | tr -d " ")"')
check has "$out" 'rc=1 calls=4'
check [ "$(grep -c 'попытка' <<<"$out")" = 3 ]
check has "$out" 'Хеш ветки main: попытка 1 из 4'   # видно, какой запрос
check has "$out" 'GitHub не ответил ни на одну из 4 попыток'
check has "$out" '(код curl 28)'
check hasnt "$out" 'curl: ('                  # свои слова вместо сообщений curl
# В «Аркаде» (UI_ALT=1) проверка ключа ничего не печатает поверх экрана.
check [ -z "$(FAIL_K=1 FAIL_RC=28 nf 'UI_ALT=1; TOKEN=t; token_check')" ]
# Ждём только свои запросы: чужая фоновая задача проверку не держит.
out=$(nf 'sleep 30 & bg=$!; t0=$SECONDS; TOKEN=t; token_check >/dev/null 2>&1; echo "waited=$(( SECONDS - t0 ))"; kill $bg')
check [ "${out#waited=}" -lt 10 ]
# Опрос в фоне делит журнал повторов и метку «сети нет» на весь заход.
check has "$(code | sed -n '/^ui_poll_start()/,/^}/p')" 'GH_DOWN_FILE="$UI_POLLDIR/down"'

echo "── компоненты: пакеты apt продуктов, обновление только стоящего"
# Система не трогается: dpkg-query, apt-cache, apt-mark и apt-get — заглушки в
# PATH. Они читают фикстуры из APTFX и пишут в $APTFX/calls, что их вызвали;
# «обновление» переписывает версию в фикстуре на кандидата.
AP="$T/apt"
mkapt() {  # mkapt <каталог> — заглушки в <каталог>/bin и фикстуры рядом
    local d="$1"
    mkdir -p "$d/bin" "$d/lists" "$d/fs/usr/bin"
    cat > "$d/bin/dpkg-query" <<'S'
#!/bin/sh
echo "dpkg-query $*" >> "$APTFX/calls"
cat "$APTFX/dpkg"
S
    cat > "$d/bin/apt-cache" <<'S'
#!/bin/sh
echo "apt-cache $*" >> "$APTFX/calls"
shift
for p in "$@"; do
    c=$(sed -n "s/^$p=//p" "$APTFX/cand" | head -1)
    v=$(sed -n "s/^$p|\([^|]*\)|.*/\1/p" "$APTFX/dpkg" | head -1)
    echo "$p:"; echo "  Installed: ${v:-(none)}"; echo "  Candidate: ${c:-$v}"; echo "  Version table:"
done
S
    # dpkg --compare-versions по правилам Debian (эпоха, upstream, ревизия,
    # «~» раньше всего): без него _deb_newer считал бы «новее» любую другую
    # версию, и ошибку сравнения набор не увидел бы.
    cat > "$d/bin/dpkg" <<'S'
#!/bin/sh
[ "$1" = --compare-versions ] || exit 2
exec python3 -I - "$2" "$3" "$4" <<'PY'
import sys
def order(c):
    if c == "~": return -1
    if c.isdigit(): return 0
    if c.isalpha(): return ord(c)
    return ord(c) + 256
def part(a, b):
    i = j = 0
    while i < len(a) or j < len(b):
        d = 0
        while (i < len(a) and not a[i].isdigit()) or (j < len(b) and not b[j].isdigit()):
            ac = order(a[i]) if i < len(a) and not a[i].isdigit() else 0
            bc = order(b[j]) if j < len(b) and not b[j].isdigit() else 0
            if ac != bc: return ac - bc
            i += 1; j += 1
        na = nb = ""
        while i < len(a) and a[i].isdigit(): na += a[i]; i += 1
        while j < len(b) and b[j].isdigit(): nb += b[j]; j += 1
        d = int(na or 0) - int(nb or 0)
        if d: return d
    return 0
def split(v):
    e, _, r = v.partition(":") if ":" in v else ("0", "", v)
    u, _, rev = r.rpartition("-") if "-" in r else (r, "", "0")
    return int(e or 0), u, rev
def cmp(a, b):
    ea, ua, ra = split(a); eb, ub, rb = split(b)
    return (ea - eb) or part(ua, ub) or part(ra, rb)
a, op, b = sys.argv[1:4]
c = cmp(a, b)
ok = {"gt": c > 0, ">>": c > 0, "ge": c >= 0, "lt": c < 0, "<<": c < 0, "le": c <= 0, "eq": c == 0, "ne": c != 0}[op]
sys.exit(0 if ok else 1)
PY
S
    cat > "$d/bin/apt-mark" <<'S'
#!/bin/sh
echo "apt-mark $*" >> "$APTFX/calls"
cat "$APTFX/hold" 2>/dev/null
exit 0
S
    cat > "$d/bin/apt-get" <<'S'
#!/bin/sh
echo "apt-get $*" >> "$APTFX/calls"
echo "env DEBIAN_FRONTEND=$DEBIAN_FRONTEND NEEDRESTART_MODE=$NEEDRESTART_MODE" >> "$APTFX/calls"
case " $* " in
    *" update "*) [ -f "$APTFX/update-sleep" ] && sleep "$(cat "$APTFX/update-sleep")"
                  [ -f "$APTFX/update-out" ] && cat "$APTFX/update-out"; exit "$(cat "$APTFX/update-rc" 2>/dev/null || echo 0)" ;;
    *" -s "*)
        [ -f "$APTFX/dry-out" ] && { cat "$APTFX/dry-out"; exit "$(cat "$APTFX/dry-rc" 2>/dev/null || echo 0)"; }
        for p in "$@"; do
            case "$p" in -*|install|*=*) continue ;; esac
            grep -qx "$p" "$APTFX/kept" 2>/dev/null && continue
            c=$(sed -n "s/^$p=//p" "$APTFX/cand" | head -1)
            [ -n "$c" ] && echo "Inst $p [old] ($c Ubuntu:24.04/noble-updates [amd64])"
        done
        if [ -s "$APTFX/kept" ]; then echo "The following packages have been kept back:"; sed 's/^/  /' "$APTFX/kept"; fi
        exit 0 ;;
    *" install "*)
        for p in "$@"; do
            case "$p" in -*|install|*=*) continue ;; esac
            grep -qx "$p" "$APTFX/kept" 2>/dev/null && continue
            c=$(sed -n "s/^$p=//p" "$APTFX/cand" | head -1)
            [ -n "$c" ] || continue
            sed "s/^$p|[^|]*|/$p|$c|/" "$APTFX/dpkg" > "$APTFX/dpkg.new" && mv "$APTFX/dpkg.new" "$APTFX/dpkg"
            echo "Setting up $p ($c) ..."
        done
        [ -f "$APTFX/nr" ] && cat "$APTFX/nr"
        exit "$(cat "$APTFX/install-rc" 2>/dev/null || echo 0)" ;;
esac
exit 0
S
    chmod +x "$d/bin/"*
    # Стоящие пакеты «пакет|версия|исходный|статус»; ocserv снят (un).
    cat > "$d/dpkg" <<'D'
nginx|1.24.0-2ubuntu7.1|nginx|ii
nginx-common|1.24.0-2ubuntu7.1|nginx|ii
libnginx-mod-stream|1.24.0-2ubuntu7.1|nginx|ii
libnginx-mod-http-geoip2|1.24.0-2ubuntu7.1|nginx|ii
certbot|2.9.0-1|python-certbot|ii
python3-certbot|2.9.0-1|python-certbot|ii
docker.io|26.1.3-0ubuntu1~24.04.1|docker.io|ii
containerd|1.7.12-0ubuntu4.1|containerd|ii
runc|1.1.12-0ubuntu3.1|runc|ii
python3|3.12.3-0ubuntu2|python3-defaults|ii
python3-minimal|3.12.3-0ubuntu2|python3-defaults|ii
python3.12|3.12.3-1ubuntu0.8|python3.12|ii
python3.12-minimal|3.12.3-1ubuntu0.8|python3.12|ii
libpython3.12-stdlib|3.12.3-1ubuntu0.8|python3.12|ii
libpython3.12-minimal|3.12.3-1ubuntu0.8|python3.12|ii
python3.12-venv|3.12.3-1ubuntu0.8|python3.12|ii
iptables|1.8.10-3ubuntu2|iptables|ii
libip4tc2|1.8.10-3ubuntu2|iptables|ii
curl|8.5.0-2ubuntu10.6|curl|ii
libcurl4t64|8.5.0-2ubuntu10.6|curl|ii
git|1:2.43.0-1ubuntu7.3|git|ii
openssl|3.0.13-0ubuntu3.5|openssl|ii
jq|1.7.1-3build1|jq|ii
ca-certificates|20240203|ca-certificates|ii
ocserv|1.2.4-1|ocserv|un
D
    cat > "$d/cand" <<'C'
nginx=1.24.0-2ubuntu7.4
nginx-common=1.24.0-2ubuntu7.4
libnginx-mod-stream=1.24.0-2ubuntu7.4
libnginx-mod-http-geoip2=1.24.0-2ubuntu7.4
docker.io=27.5.1-0ubuntu3~24.04.2
curl=8.5.0-2ubuntu10.7
libcurl4t64=8.5.0-2ubuntu10.7
C
    : > "$d/hold"; : > "$d/kept"
    : > "$d/lists/archive.ubuntu.com_ubuntu_dists_noble_InRelease"
    ln -sf python3.12 "$d/fs/usr/bin/python3"
}
mkeng() {  # mkeng <fs> — движки продуктов и окружения ботов
    local f="$1" b
    mkdir -p "$f/usr/local/x-ui/bin" "$f/usr/local/bin" "$f/opt/goamnezia" "$f/sys/module/amneziawg" "$f/etc/govless/egress" "$f/root/.acme.sh"
    printf '#!/bin/sh\necho "v2.6.2"\n' > "$f/usr/local/x-ui/x-ui"
    printf '#!/bin/sh\necho "Xray 25.3.6 (Xray, Penetrates Everything.) 8f2a0d (go1.24 linux/amd64)"\necho "A unified platform"\n' > "$f/usr/local/x-ui/bin/xray-linux-amd64"
    printf '#!/bin/sh\necho "telemt 3.4.18"\n' > "$f/usr/local/bin/telemt"
    printf '#!/bin/sh\necho "Xray 26.3.27 (Xray, Penetrates Everything.)"\n' > "$f/etc/govless/egress/xray"
    printf '#!/bin/sh\necho "https://github.com/acmesh-official/acme.sh"\necho "v3.0.7"\n' > "$f/root/.acme.sh/acme.sh"
    chmod +x "$f/usr/local/x-ui/x-ui" "$f/usr/local/x-ui/bin/xray-linux-amd64" "$f/usr/local/bin/telemt" "$f/etc/govless/egress/xray" "$f/root/.acme.sh/acme.sh"
    printf '{"installed": true, "profiles": {"awg1": {"image_tag": "3.1.20260828"}, "awg2": {"image_tag": "3.1.20260828"}}}\n' > "$f/opt/goamnezia/config.json"
    echo "1.0.20260906" > "$f/sys/module/amneziawg/version"
    # Исправное окружение (python 3.12) и сломанное: от 3.10, ссылка висит.
    b="$f/opt/govless/venv"; mkdir -p "$b/bin"; printf 'home = /usr/bin\nversion = 3.12.3\n' > "$b/pyvenv.cfg"
    printf '#!/bin/sh\necho "Python 3.12.3"\n' > "$b/bin/python"; chmod +x "$b/bin/python"
    b="$f/opt/godns/bot/venv"; mkdir -p "$b/bin"; printf 'home = /usr/bin\nversion_info = 3.10.12.final.0\n' > "$b/pyvenv.cfg"
    ln -sf /nonexistent/python3.10 "$b/bin/python"
}
ap() {  # ap <выражение> — функции скрипта на свежих фикстурах; APREP — правка фикстур
    rm -rf "$AP"; mkapt "$AP"; mkeng "$AP/fs"; eval "${APREP:-}"
    APTFX="$AP" PATH="$AP/bin:$PATH" GOINST_APT_OK=1 GOINST_TEST=1 GOINST_FS_ROOT="$AP/fs" GOINST_APT_LISTS="$AP/lists" \
    GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_FAKE_INSTALLED="${APINST-govless godns}" GOINST_DIR="$AP/gi" GOINST_COLOR=none APK="${APK:-}" \
    bash -c ". '$SCRIPT'; $1" 2>&1
}
rows='for ((i=0;i<${#CA_ID[@]};i++)); do echo "${CA_ID[$i]}|${CA_VER[$i]}|${CA_CAND[$i]}|${CA_UP[$i]}|${CA_HOLD[$i]}|${CA_N[$i]}|${CA_PROD[$i]}|${CA_PRODM[$i]}"; done; echo "nup=$COMP_NUP"'
out=$(ap "comp_apt_load; $rows")
# nginx тянет родню по исходному пакету одной версией.
check has "$out" 'nginx|1.24.0-2ubuntu7.1|1.24.0-2ubuntu7.4|nginx=1.24.0-2ubuntu7.4 nginx-common=1.24.0-2ubuntu7.4 libnginx-mod-stream=1.24.0-2ubuntu7.4 libnginx-mod-http-geoip2=1.24.0-2ubuntu7.4||4|goVLESS pro|0'
# Ни один продукт строки не стоит — весь список приглушённо.
check has "$out" 'docker|26.1.3-0ubuntu1~24.04.1|27.5.1-0ubuntu3~24.04.2|docker.io=27.5.1-0ubuntu3~24.04.2||3|goAmnezia pro, goWARP pro|1'
# python — тот, на который указывает /usr/bin/python3.
check has "$out" 'python3|3.12.3-1ubuntu0.8||||7|goVLESS pro, goDNS pro|0'
# Утилиты — группа без главного: «N пакетов», libcurl — родня curl.
check has "$out" 'tools|||curl=8.5.0-2ubuntu10.7 libcurl4t64=8.5.0-2ubuntu10.7||5|'
check has "$out" 'certbot|2.9.0-1|||'
check has "$out" 'nup=3'
# Главный пакет не стоит — строки нет (ocserv снят, dnsdist не ставили).
check hasnt "$out" 'ocserv|'
check hasnt "$out" 'dnsdist|'
# Один dpkg-query, один apt-cache policy и один apt-mark на всё, а не по пакету.
calls=$(ap 'comp_apt_load >/dev/null; cat "$APTFX/calls"')
check [ "$(grep -c '^dpkg-query' <<<"$calls")" = 1 ]
check [ "$(grep -c '^apt-cache policy' <<<"$calls")" = 1 ]
check [ "$(grep -c '^apt-mark showhold' <<<"$calls")" = 1 ]
# Закреплённый пакет не обновляется и в «всё» не входит.
out=$(APREP='echo nginx-common > "$AP/hold"' ap "comp_apt_load; $rows; comp_table")
check has "$out" 'nginx|1.24.0-2ubuntu7.1|1.24.0-2ubuntu7.4|nginx=1.24.0-2ubuntu7.4 libnginx-mod-stream=1.24.0-2ubuntu7.4 libnginx-mod-http-geoip2=1.24.0-2ubuntu7.4|nginx-common|4|'
check has "$out" '! закреплён (apt-mark hold): nginx-common'
out=$(APREP='echo nginx-common > "$AP/hold"' ap 'comp_update all --yes >/dev/null 2>&1; grep "^apt-get -y" "$APTFX/calls"')
check hasnt "$out" 'nginx-common'
check has "$out" 'docker.io'
# Без apt (тесты без заглушек, нет apt-get) строк нет, меню пишет «—».
check [ "$(ml 'GOINST_TEST=1; comp_apt_load; echo "rc=$? apt=$COMP_APT n=${#CA_ID[@]}"')" = "rc=1 apt=0 n=0" ]

echo "── компоненты: apt-get — только --only-upgrade --no-remove, confold"
out=$(ap 'comp_update nginx --yes >/dev/null 2>&1; echo "rc=$?"; grep "^apt-get\|^env" "$APTFX/calls"')
check has "$out" 'rc=0'
check has "$out" 'apt-get -s -y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install --only-upgrade --no-remove nginx nginx-common libnginx-mod-stream libnginx-mod-http-geoip2'
check has "$out" 'apt-get -y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install --only-upgrade --no-remove nginx nginx-common libnginx-mod-stream libnginx-mod-http-geoip2'
check has "$out" 'env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a'
# Страж: в коде apt-get не делает upgrade, dist-upgrade, autoremove, remove,
# не понижает версии и ставит только с --only-upgrade --no-remove (исключение
# — curl при первом запуске на голой машине).
apt_guard() {  # apt_guard <код> → нарушения
    grep -E '(^|[^-_[:alnum:]])apt-get([^-_[:alnum:]]|$)' <<<"$1" | grep -E '(^|[[:space:]])(upgrade|dist-upgrade|full-upgrade|autoremove|autopurge|remove|purge)([[:space:]]|$)|--allow-downgrades'
    grep -E '(^|[^-_[:alnum:]])apt-get([^-_[:alnum:]]|$)' <<<"$1" | grep -E '(^|[[:space:]])install([[:space:]]|$)' \
        | grep -vF -- 'install --only-upgrade --no-remove' | grep -vF -- 'install --no-install-recommends curl ca-certificates'
    return 0
}
# Исключений два — исполнитель обновления Ubuntu (osup_apt): обновление
# выпуска по определению dist-upgrade, и shield_apt_nft: ровно пакет
# nftables для защиты от сканеров, по «Да». Оба стерегутся отдельно ниже.
check [ -z "$(apt_guard "$(code | sed '/^osup_apt()/,/^}/d; /^shield_apt_nft()/,/^}/d')")" ]
check [ -n "$(apt_guard 'apt-get -y dist-upgrade')" ]                  # страж видит нарушение
check [ -n "$(apt_guard 'apt-get -y install nginx')" ]
check [ -n "$(apt_guard 'apt-get -y install --only-upgrade nginx')" ]   # без --no-remove
check [ -n "$(apt_guard 'apt-get -y autoremove')" ]
# Пробный прогон: что обновится и что apt отложил (kept back и поэтапный выпуск).
out=$(APREP='echo docker.io > "$AP/kept"' ap 'comp_dry nginx docker.io; echo "inst=$COMP_DRY_INST|kept=$COMP_DRY_KEPT|err=$COMP_DRY_ERR"')
check has "$out" 'inst=nginx|kept=docker.io|err='
printf '%s\n' 'The following upgrades have been deferred due to phasing:' '  docker.io containerd' 'The following packages will be upgraded:' '  nginx' 'Inst nginx [1] (2 Ubuntu:24.04/noble-updates [amd64])' 'Conf nginx (2 Ubuntu:24.04/noble-updates [amd64])' > "$T/dry-phasing"
out=$(APREP='cp "$T/dry-phasing" "$AP/dry-out"' ap 'comp_dry nginx; echo "inst=$COMP_DRY_INST|kept=$COMP_DRY_KEPT"')
check has "$out" 'inst=nginx|kept=docker.io containerd'
# Пробный прогон не прошёл — ошибка apt словами, обновления нет, код 1.
out=$(APREP='printf "E: Could not get lock /var/lib/dpkg/lock-frontend\n" > "$AP/dry-out"; echo 100 > "$AP/dry-rc"' ap 'comp_update nginx --yes; echo "rc=$?"; grep -c "^apt-get -y" "$APTFX/calls"')
check has "$out" 'Could not get lock'
check has "$out" 'rc=1'
check [ "$(tail -1 <<<"$out")" = 0 ]

echo "── компоненты: --components update — коды и отказ без терминала"
# Без терминала и без --yes — отказ ДО вопросов и до apt.
out=$(ap 'comp_update all </dev/null; echo "rc=$?"; cat "$APTFX/calls" 2>/dev/null | grep -c "^apt-get"')
check has "$out" 'Без терминала спросить некого'
check has "$out" 'rc=3'                                   # свой код: 1 — ошибка apt
check [ "$(tail -1 <<<"$out")" = 0 ]
check has "$(ap 'comp_update nosuch --yes; echo "rc=$?"')" 'rc=64'
check has "$(ap 'comp_update xui --yes; echo "rc=$?"')" 'rc=64'          # движок обновляет продукт
check has "$(ap 'comp_update dnsdist --yes; echo "rc=$?"')" 'rc=2'       # не стоит
check has "$(ap 'comp_update certbot --yes; echo "rc=$?"')" 'rc=2'       # новее нет
check has "$(APREP='echo 100 > "$AP/install-rc"' ap 'comp_update nginx --yes; echo "rc=$?"')" 'rc=1'
# Итог по строкам: стала новая, осталась — apt отложил, apt вышел с кодом.
out=$(ap 'comp_update nginx --yes 2>&1')
check has "$out" 'nginx: стала 1.24.0-2ubuntu7.4'
check has "$out" '/gi/logs/components-'
check has "$(APREP='echo docker.io > "$AP/kept"' ap 'comp_update nginx docker --yes 2>&1')" 'Docker: осталась 26.1.3-0ubuntu1~24.04.1 — apt отложил'
check has "$(APREP='echo 100 > "$AP/install-rc"' ap 'comp_update nginx --yes 2>&1')" 'nginx: apt вышел с кодом 100'
# Журнал — в каталоге 0700.
check [ "$(ap 'comp_update nginx --yes >/dev/null 2>&1; ls -ld "$GOINST_DIR/logs" | cut -c1-10')" = "drwx------" ]
# Команда целиком: таблица и коды через main.
apcli() { rm -rf "$AP"; mkapt "$AP"; mkeng "$AP/fs"; eval "${APREP:-}"
    APTFX="$AP" PATH="$AP/bin:$PATH" GOINST_APT_OK=1 GOINST_TEST=1 GOINST_FS_ROOT="$AP/fs" GOINST_APT_LISTS="$AP/lists" \
    GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_FAKE_INSTALLED="govless godns" GOINST_DIR="$AP/gi" GOINST_NO_SELF_INSTALL=1 \
    bash "$SCRIPT" "$@" 2>&1 </dev/null; echo "rc=$?"; }
out=$(apcli --components)
check has "$out" 'rc=0'
check has "$(plain <<<"$out")" 'компонент    стоит                    доступно                   для'
# Колонки — по длинному значению: кандидат и образы не режутся.
check has "$(plain <<<"$out")" 'Docker       26.1.3-0ubuntu1~24.04.1  ↑ 27.5.1-0ubuntu3~24.04.2  goAmnezia pro, goWARP pro (не стоят)'
check has "$(plain <<<"$out")" 'утилиты      5 пакетов                ↑ 1 из 5 '
check has "$out" 'Движки продуктов (обновляет продукт)'
check has "$out" 'списки apt от'
check has "$(apcli --components update nosuch)" 'rc=64'
check has "$(apcli --components update nginx --yes)" 'rc=0'
check has "$(apcli --components update dnsdist --yes)" 'rc=2'
check has "$(apcli --components frobnicate)" 'rc=64'
check has "$(bash "$SCRIPT" --help 2>&1)" 'goinstall --components update <id…|all> [--yes]'

echo "── компоненты: списки apt — свежесть и проверка"
out=$(ap 'comp_refresh; echo "rc=$?"; grep "^apt-get" "$APTFX/calls"')
check has "$out" 'rc=0'
check has "$out" 'apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o DPkg::Lock::Timeout=60 update'
out=$(APREP='printf "E: Could not get lock /var/lib/apt/lists/lock. It is held by process 123 (apt-get)\n" > "$AP/update-out"; echo 100 > "$AP/update-rc"' ap 'comp_refresh; echo "rc=$? why=$COMP_REFRESH_WHY"')
check has "$out" 'rc=1 why=apt занят другим процессом'
out=$(APREP='printf "W: Failed to fetch http://archive.ubuntu.com  Temporary failure resolving\n" > "$AP/update-out"; echo 100 > "$AP/update-rc"' ap 'comp_refresh; echo "why=$COMP_REFRESH_WHY"')
check has "$out" 'why=нет связи с репозиториями'
# Свежесть — по самому новому *Release; старше 12 часов — пора проверить.
check [ "$(ap 'comp_lists_age; comp_lists_stale && echo stale || echo fresh')" = fresh ]
check [ "$(APREP='touch -t 202601020304 "$AP/lists/"*' ap 'comp_lists_age; comp_lists_when; comp_lists_stale && echo "stale $COMP_LISTS_TXT"')" = "stale 02.01" ]
check [ "$(APREP='rm -f "$AP/lists/"*' ap 'comp_lists_age; comp_lists_stale && echo stale; comp_lists_label')" = "stale"$'\n'"списки apt не скачаны" ]

echo "── компоненты: движки продуктов и окружения ботов"
out=$(ap 'comp_engines_load; for ((i=0;i<${#CE_ID[@]};i++)); do echo "${CE_ID[$i]}|${CE_VER[$i]}|${CE_PROD[$i]}|${CE_BAD[$i]}"; done')
check has "$out" 'xui|2.6.2|goVLESS pro, goWARP pro|0'
check has "$out" 'xray|25.3.6|goVLESS pro|0'
check has "$out" 'telemt|3.4.18|goTelegram pro|0'
check has "$out" 'awgimg|3.1.20260828|goAmnezia pro|0'
check has "$out" 'awgmod|1.0.20260906|'
check has "$out" 'egress|26.3.27|goVLESS pro|0'
check has "$out" 'acme|3.0.7|goVLESS pro|0'
check has "$out" 'bot:govless|python 3.12|goVLESS pro|0'
check has "$out" 'bot:godns|python 3.10|goDNS pro|1'
check hasnt "$out" 'accel|'                                   # нет файла — нет строки
# Сломанное окружение — замечание с шагом-командой продукта; у goDNS pro —
# предупреждение про «снять бота».
out=$(ap 'comp_bots_load; comp_bot_probs; printf "%s\n" "${COMP_BOTP[@]}"; comp_bot_fix godns')
check has "$out" 'goDNS pro|python 3.10 окружения бота не запускается|goDNS pro: бот не запустится, python 3.10|godns|err'
check hasnt "$out" 'goVLESS pro|'
check has "$out" 'не через «снять бота»: так пропадёт токен'
# Окружение запускается, но python другой — тоже сломано.
check has "$(APREP='printf "#!/bin/sh\necho \"Python 3.11.9\"\n" > "$AP/fs/opt/govless/venv/bin/python"' ap 'comp_bots_load; echo "${CB_ID[*]}|${CB_OK[*]}"')" 'govless godns|0 0'
# Замечание идёт под меню и в сводку при входе.
out=$(ap 'GOINST_SS_FIXTURE="'"$T"'/ss-empty" GOINST_UNIT_FIXTURE="'"$T"'/units-empty" GOINST_DOCKER_FIXTURE="'"$T"'/docker-empty" GOINST_LE_ROOT="'"$T"'/le-empty" GOINST_NGINX_ROOT="'"$T"'/nginx-empty" GOINST_UI_SYS="1 2 0.1" GOINST_VER_CACHE="$GOINST_DIR/vc"; mkdir -p "$GOINST_VER_CACHE"; os_detect; ui_model_load >/dev/null 2>&1; printf "prob=%s\n" "${UD_PROB[@]}"')
check has "$out" 'prob=goDNS pro|python 3.10 окружения бота не запускается'

echo "── компоненты: нумерованное меню"
# Пункт «c» в главном: «↑N», «актуальны» или «—» без apt.
check has "$(ap 'OS_PRETTY=x; prod_readiness() { printf g:; }; menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}"')" 'c|Компоненты|y:↑3||версии пакетов продуктов, обновление'
check has "$(APREP=': > "$AP/cand"' ap 'OS_PRETTY=x; prod_readiness() { printf g:; }; menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}"')" 'c|Компоненты|d:актуальны|'
check has "$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}"')" 'c|Компоненты|d:—|'
# «c» открывает меню компонентов, а не что-то соседнее.
check has "$(pf_env ss-godns units-godns nginx-empty os-ubuntu2604 godns 'components_menu() { echo COMPS; }; prod_readiness() { printf g:; }; printf "c\n0\n" | main_menu 2>/dev/null')" 'COMPS'
# Пункты: строка на компонент apt, движки — строками без ключа, действия.
cm_keys=$(ap 'comp_apt_load >/dev/null; comp_engines_load; menu_items_components; printf "%s " "${MENU_ITEMS[@]%%|*}"')
check [ "$(tr -d ' -' <<<"$cm_keys")" = "123456ar0" ]
check [ -z "$(tr ' ' '\n' <<<"$cm_keys" | grep -vE '^-?$' | sort | uniq -d)" ]
out=$(ap 'comp_apt_load >/dev/null; comp_engines_load; COLUMNS=80; tput() { return 1; }; menu_items_components; printf "%s\n" "${MENU_ITEMS[@]}"')
check has "$out" '-|3X-UI|d:2.6.2|d:|'
check has "$out" '-||||  goVLESS pro, goWARP pro: goVLESS pro панель не обновляет'
# Каждый ключ доходит до своего действия.
cm() {  # cm <клавиши> → что вызвало меню
    APK="$1" ap 'LOG="$APTFX/log"; : > "$LOG"; sleep() { :; }; comp_update() { echo "update $*" >> "$LOG"; return 0; }
        comp_refresh() { echo refresh >> "$LOG"; return 0; }; printf "%s\n" $APK | components_menu >/dev/null 2>&1; cat "$LOG"'
}
check [ "$(cm '1 x 0')" = "update --ask nginx" ]
check [ "$(cm '3 x 0')" = "update --ask docker" ]
check [ "$(cm '6 x 0')" = "update --ask tools" ]
check [ "$(cm 'a x 0')" = "update --ask all" ]
check [ "$(cm 'r 0')" = "refresh" ]
check [ -z "$(cm '0')" ]
for k in $(tr -d '-' <<<"$cm_keys"); do
    [ "$k" = 0 ] && continue
    check [ -n "$(cm "$k x 0")" ]
done
# Из меню вопрос задаётся и через канал: «2» — нет, ничего не обновлено.
out=$(APK='1 2 x 0' ap 'printf "%s\n" $APK | components_menu 2>&1; grep -c "^apt-get -y" "$APTFX/calls"')
check has "$out" 'Отменено, ничего не обновлено'
check [ "$(tail -1 <<<"$out")" = 0 ]

echo "── компоненты: «Аркада»"
# Строки карточки «c» в главном меню: что обновится, окружения ботов.
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example
    COMP_BOTP=('goDNS pro|x|goDNS pro: бот на python 3.10|godns|err'); ui_scr_menu 9; ui_compose; ui_dump" | cut -f1)
check has "$out" '▸ c Компоненты                ↑2'
check has "$out" 'nginx 1.24.0-2ubuntu7.1 → …7.4'
check has "$out" 'Docker 26.1.3-0ubuntu1~24.04.1 → 27.…'
check has "$out" '✗ goDNS pro: бот на python 3.10'
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example
    CA_UP=('' '' ''); UD_COMPUP=0; ui_scr_menu 9; ui_compose; ui_dump" | cut -f1)
check has "$out" '✓ всё актуально · списки apt от 14:05'
check hasnt "$out" '↑2'
# Длинный список: 20 компонентов — срез вокруг курсора, строки не шире экрана.
sl() {  # sl <ширина> <курсор> → дамп и «max=N»
    T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS="$1" GOINST_UI_LINES=24 bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example
        CA_ID=(); CA_NAME=(); CA_VER=(); CA_CAND=(); CA_UP=(); CA_HOLD=(); CA_N=(); CA_PROD=(); CA_PRODM=(); CA_WHAT=(); CA_NOTE=(); CE_ID=()
        for ((i = 1; i <= 20; i++)); do CA_ID+=(c\$i); CA_NAME+=(пакет\$i); CA_VER+=(1.\$i); CA_CAND+=(''); CA_UP+=(''); CA_HOLD+=(''); CA_N+=(1); CA_PROD+=('goVLESS pro'); CA_PRODM+=(0); CA_WHAT+=(что); CA_NOTE+=(''); done
        ui_scr_comps $2; ui_compose; ui_dump | cut -f1; m=0; for r in \"\${UI_ROWS[@]}\"; do ui_len \"\$r\"; [ \$UI_N -gt \$m ] && m=\$UI_N; done; echo max=\$m"
}
for w in 46 80; do
    out=$(sl "$w" 15)
    check has "$out" '▸   [ ] пакет16'                # десятая и дальше — без цифры
    check has "$out" '↑ ещё'
    check has "$out" '↓ ещё'
    check [ "$(tail -1 <<<"$out")" = "max=$w" ]
    check [ "$(grep -vc '^max=' <<<"$out")" = 24 ]
    out=$(sl "$w" 23)                       # курсор на «0 Назад» — в самом низу
    check has "$out" '▸ 0  Назад'
    check hasnt "$out" '↓ ещё'
    out=$(sl "$w" 0)
    check has "$out" '▸ 1 [ ] пакет1 '
    check hasnt "$out" '↑ ещё'
done
# Настоящим циклом: c — экран, Пробел — отметить nginx, u — подтверждение по
# пробному прогону, 1 — apt с пакетами nginx, потом снова «Компоненты».
anav() { rm -rf "$AP"; mkapt "$AP"; rm -f "$NAV/gi/.apt-check" "$NAV/gi/.apt-ok"; eval "${APREP:-}"; APTFX="$AP" PATH="$AP/bin:$PATH" GOINST_APT_OK=1 GOINST_APT_LISTS="$AP/lists" nav "$@"; }
anav c ' ' u 1 '~\n' %comps q
check grep -q 'apt-get -s -y .* install --only-upgrade --no-remove nginx nginx-common libnginx-mod-stream libnginx-mod-http-geoip2$' "$AP/calls"
check grep -q 'apt-get -y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install --only-upgrade --no-remove nginx nginx-common libnginx-mod-stream libnginx-mod-http-geoip2$' "$AP/calls"
check [ "$(tr '\n' ' ' < "$NAV/trace.draw" | grep -o 'comps compconfirm comps')" = "comps compconfirm comps" ]
check [ "$(grep -c '^  comps' "$NAV/trace")" = 1 ]       # Пробел прочитан на «Компонентах»
check grep -q 'nginx: стала 1.24.0-2ubuntu7.4' "$NAV/err"
# После обновления отметки сняты, nginx новее не ждёт.
check grep -q 'Обновить отмеченные (0)' "$NAV/out"
# u без отметок — строка под курсором, если у неё есть обновление.
anav c u 2 q
check [ "$(navtr0)" = "c menu|u comps|2 compconfirm|q comps" ]
check neg grep -q '^apt-get -y' "$AP/calls"
# …а на строке без обновления — заметка, экран прежний.
anav c '\033[B' u q
check [ "$(navtr0)" = "c menu|down comps|u comps|q comps" ]
check grep -q 'Отметьте компоненты: Пробел или Enter' "$NAV/out"
# a — всё, где есть новее; 2 — нет.
anav c a 2 q
check [ "$(navtr0)" = "c menu|a comps|2 compconfirm|q comps" ]
check grep -q 'apt-get -s .*--no-remove nginx nginx-common libnginx-mod-stream libnginx-mod-http-geoip2 docker.io curl libcurl4t64$' "$AP/calls"
check neg grep -q '^apt-get -y' "$AP/calls"
# r — apt-get update в фоне; экран живёт, потом заметка.
anav c r @1.5 q
check grep -q 'apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o DPkg::Lock::Timeout=60 update' "$AP/calls"
check grep -q 'Списки apt обновлены' "$NAV/out"
# Списки старше 12 часов — проверка сама, при входе на экран.
APREP='touch -t 202601020304 "$AP/lists/"*' anav c @1.5 q
check grep -q ' update$' "$AP/calls"
# Русская раскладка: с — это c, ф — это a.
anav 'с' 'ф' 2 q
check [ "$(navtr0)" = "c menu|a comps|2 compconfirm|q comps" ]
check [ "$(rk 'с')" = c ]
check [ "$(rk 'Ф')" = a ]
check [ "$(rk 'с' 1)" = 'с' ]                 # при вводе ключа — буква
# Без apt экран открывается и говорит об этом.
nav c q
check grep -q 'apt недоступен' "$NAV/out"
errs=$(cat "$NAV/err-all")
for w in 'unbound variable' 'не заданы границы' 'command not found' 'команда не найдена' 'syntax error' 'синтаксическая ошибка' 'bad array subscript' 'неправильный индекс'; do
    check hasnt "$errs" "$w"
done

echo "── 1.1.0 по проверке: компоненты"
# Закреплён ГЛАВНЫЙ пакет — вся группа стоит: родня по исходному без него
# разъехалась бы с ним версиями. Строка «!», кандидата нет, в «всё» не входит.
out=$(APREP='echo nginx > "$AP/hold"' ap "comp_apt_load; $rows")
check has "$out" 'nginx|1.24.0-2ubuntu7.1|||nginx|4|'
check has "$out" 'nup=2'
out=$(APREP='echo nginx > "$AP/hold"' ap 'comp_update all --yes >/dev/null 2>&1; grep "^apt-get -y" "$APTFX/calls"')
check hasnt "$out" 'nginx'
check has "$out" 'docker.io'
check has "$(APREP='echo nginx > "$AP/hold"' ap 'comp_update nginx --yes; echo "rc=$?"')" 'закреплён (apt-mark hold), не обновляется'
out=$(APREP='echo nginx > "$AP/hold"' ap 'comp_apt_load >/dev/null; comp_engines_load; GOINST_UI_COLS=80; GOINST_UI_LINES=24; ui_detect; ui_scr_comps 0; ui_compose; ui_dump | cut -f1')
check has "$out" '! закреплён (apt-mark hold)'
check grep -q 'nginx *!' <<<"$out"
check hasnt "$out" 'ДОСТУПНО  ↑'
# Закреплён не главный — не берётся только он (как было).
check has "$(APREP='echo nginx-common > "$AP/hold"' ap "comp_apt_load; $rows")" 'nginx|1.24.0-2ubuntu7.1|1.24.0-2ubuntu7.4|nginx=1.24.0-2ubuntu7.4 libnginx-mod-stream'
# «↑ K из N» у утилит — утилиты, а не родня: curl с libcurl — одна.
check has "$(ap 'comp_apt_load >/dev/null; comp_idx tools; echo "upn=${CA_UPN[$COMP_I]} n=${CA_N[$COMP_I]}"')" 'upn=1 n=5'
# Новее — по правилам Debian, заглушкой dpkg: эпоха, тильда, числа, ревизия.
check ap '_deb_newer 2.0 1:1.0'
check ap '! _deb_newer 1.0 1.0~rc1'
check ap '_deb_newer 1.0~rc1 1.0'
check ap '_deb_newer 2.9 2.10'
check ap '_deb_newer 1.18.0-6ubuntu14.4 1.18.0-6ubuntu14.6'
check ap '! _deb_newer 1.18.0-6ubuntu14.6 1.18.0-6ubuntu14.4'
check has "$(ap 'command -v dpkg')" "$AP/bin/dpkg"
# Кандидат ниже стоящего (пин) — не «↑» и в обновление не идёт.
out=$(APREP='sed -i.b "s/^docker.io=.*/docker.io=24.0.7-0ubuntu4/" "$AP/cand"' ap "comp_apt_load; $rows")
check has "$out" 'docker|26.1.3-0ubuntu1~24.04.1||||3|'
check has "$out" 'nup=2'
# Образы AmneziaWG: только теги профилей, откатный previous — нет; JSON
# многострочный, как пишет jq.
AWGCFG='{
  "installed": true,
  "profiles": {
    "awg1": {
      "image_tag": "3.1.20260828",
      "previous": { "image_tag": "3.1.20260601" }
    },
    "awg2": { "image_tag": "2.9.20240505" }
  }
}'
out=$(APREP='printf "%s\n" "$AWGCFG" > "$AP/fs/opt/goamnezia/config.json"' AWGCFG="$AWGCFG" ap 'comp_engines_load; for ((i=0;i<${#CE_ID[@]};i++)); do echo "${CE_ID[$i]}|${CE_VER[$i]}"; done')
check has "$out" 'awgimg|2.9.20240505, 3.1.20260828'
check hasnt "$out" '20260601'
# Нет python3 — строки нет, а не догадка грепом.
out=$(ap 'command() { [ "${2:-}" = python3 ] && return 1; builtin command "$@"; }; comp_engines_load; printf "%s\n" "${CE_ID[@]}"')
check hasnt "$out" 'awgimg'
# Окружение бота собрано на 3.10, системный python 3.12, а 3.10 на месте —
# исправно: с системным не сравниваем.
out=$(APREP='rm -f "$AP/fs/opt/godns/bot/venv/bin/python"; printf "#!/bin/sh\necho \"Python 3.10.12\"\n" > "$AP/fs/opt/godns/bot/venv/bin/python"; chmod +x "$AP/fs/opt/godns/bot/venv/bin/python"' ap 'comp_bots_load; comp_bot_probs; echo "${CB_ID[*]}|${CB_OK[*]}|py=$COMP_PYMM|probs=${#COMP_BOTP[@]}"')
check has "$out" 'govless godns|1 1|py=3.12|probs=0'
# Собрано на 3.12, а запускается 3.11 — сломано, причина словами.
out=$(APREP='printf "#!/bin/sh\necho \"Python 3.11.9\"\n" > "$AP/fs/opt/govless/venv/bin/python"' ap 'comp_bots_load; echo "${CB_WHY[0]}"')
check has "$out" 'окружение бота собрано на python 3.12, а запускается 3.11'
# Строка без индекса после обновления — не берётся индекс прошлой строки.
check has "$(ap 'comp_apt_load >/dev/null; COMP_BEFORE="ocserv=1.2.4-1="; COMP_I=1; comp_after 0 ocserv 2>&1')" 'ocserv: осталась 1.2.4-1'
# needrestart: на вопросе — строка о перезапуске, в итоге — какие службы.
out=$(APREP='printf "Restarting services...\n systemctl restart nginx.service x-ui.service\nNo containers need to be restarted.\n" > "$AP/nr"' ap 'comp_update nginx --yes 2>&1')
check has "$out" 'перезапустятся сами (needrestart): VPN-клиенты переподключатся'
check has "$out" 'needrestart перезапустил службы: nginx, x-ui'
anav c a %compconfirm 2 q
check grep -q 'перезапустятся сами' <(plain < "$NAV/out")
check [ "$(ap 'printf "a\nRestarting services...\n systemctl restart a.service\n systemctl restart b.service a.service\nService restarts being deferred:\n systemctl restart c.service\n" > "$APTFX/l"; comp_nr_units "$APTFX/l" 1')" = "a, b" ]
# --components: колонки не режут кандидата и образы.
out=$(plain <<<"$(apcli --components)")
check has "$out" '↑ 27.5.1-0ubuntu3~24.04.2'
check hasnt "$out" '…'

echo "── 1.1.0 по проверке: проверка списков apt при входе"
# Попытка запоминается всегда, удачная или нет.
check [ -s "$(ap 'APREP=; echo 100 > "$APTFX/update-rc"; comp_refresh; comp_try_file')" ]
# Свежие списки — проверки при входе нет.
check [ "$(ap 'comp_lists_age; comp_autocheck_due && echo due || echo no')" = no ]
# Старые списки, попытки не было — пора.
check [ "$(APREP='touch -t 202601020304 "$AP/lists/"*' ap 'comp_lists_age; comp_autocheck_due && echo due || echo no')" = due ]
# Старые списки, но прошлая попытка меньше часа назад — не повторяем.
check [ "$(APREP='touch -t 202601020304 "$AP/lists/"*' ap 'comp_lists_age; comp_try_mark; comp_autocheck_due && echo due || echo no')" = no ]
# …а час назад — снова пора.
check [ "$(APREP='touch -t 202601020304 "$AP/lists/"*' ap 'comp_lists_age; mkdir -p "$GOINST_DIR"; echo $(( $(date +%s) - 3700 )) > "$(comp_try_file)"; comp_autocheck_due && echo due || echo no')" = due ]
# В «Аркаде»: свежие списки — apt-get update при входе не зовётся.
anav c @1 q
check neg grep -q ' update$' "$AP/calls"
# Метки sleep — свои на каждый прогон ($$): параллельный набор из другого
# worktree не должен попадать в pgrep. gone — процесс исчез (ждём до 2 с).
L1="37.71$$" L2="37.72$$" L3="37.73$$" L4="37.74$$"
gone() { local i; for ((i = 0; i < 40; i++)); do pgrep -f "$1" >/dev/null 2>&1 || return 0; sleep 0.05; done; return 1; }
# Проверка в фоне не держит u: прерывается, обновление — по прежним спискам.
APREP='touch -t 202601020304 "$AP/lists/"*; echo '"$L1"' > "$AP/update-sleep"; mkdir -p "$AP/tmp"' TMPDIR="$AP/tmp" anav c "?sleep $L1" u %compconfirm 2 q
check [ "$(navtr0)" = "c menu|u comps|2 compconfirm|q comps" ]
check grep -q 'Проверку обновлений прервал' "$NAV/out"
check grep -q '^apt-get -s ' "$AP/calls"
check gone "sleep $L1"
check [ -z "$(ls -d "$AP/tmp"/goinst-apt.* 2>/dev/null)" ]
# Ушли с экрана — проверка погашена сразу, а не при выходе из меню.
STOPLOG='eval "$(declare -f ui_comp_refresh_stop | sed "1s/ui_comp_refresh_stop/_stop0/")"; ui_comp_refresh_stop() { [ -n "${UI_APTPID:-}" ] && act "STOP $UI_SCR"; _stop0; }'
APREP='touch -t 202601020304 "$AP/lists/"*; echo '"$L2"' > "$AP/update-sleep"' NAVSTUB="$STOPLOG" anav c "?sleep $L2" 0 q
check grep -qx 'STOP menu' "$NAV/act"
check gone "sleep $L2"
# Стоп сразу после старта — в окне, где фон ещё порождает apt-get: сирот нет.
# До шестого круга TERM шёл по снимку дерева, и рождённое после снимка
# выживало (6 из 6 при стопе через 0–5 мс). Теперь фон — своя группа
# процессов, стоп гасит её целиком.
out=$(APREP='echo '"$L4"' > "$AP/update-sleep"' ap 'for d in 0 0 0.003 0.005 0.008 0.01 0.015 0.02 0.03 0.05 0.1; do ui_comp_refresh_start; sleep $d; ui_comp_refresh_stop; done; echo ok')
check [ "$out" = ok ]
check gone "sleep $L4"
# Фон — своя группа, номер группы — UI_APTPID.
check [ "$(APREP='echo '"$L4"' > "$AP/update-sleep"' ap 'ui_comp_refresh_start; p=$UI_APTPID; g=$(ps -o pgid= -p "$p" | tr -d " "); m=$(ps -o pgid= -p $$ | tr -d " "); ui_comp_refresh_stop; [ -n "$p" ] && [ "$g" = "$p" ] && [ "$g" != "$m" ] && echo own')" = own ]
# Ctrl-C и падение: ловушка EXIT гасит всё дерево и убирает каталог.
out=$(ml '( sleep '"$L3"'; echo x ) & UI_APTPID=$!; UI_APTDIR=$(mktemp -d "${TMPDIR:-/tmp}/goinst-apt.XXXXXX"); d=$UI_APTDIR; UI_ALT=0; sleep 0.3; ui_crash_exit; sleep 0.3; pgrep -f "sleep '"$L3"'" && echo alive; [ -d "$d" ] && echo dir; echo done')
check [ "$out" = done ]
check has "$(code | sed -n '/^ui_run_installer()/,/^}/p')" 'ui_comp_refresh_stop'
check has "$(code | sed -n '/^ui_act()/,/^}/p' | grep 'selfyes)')" 'ui_comp_refresh_stop'
# r без apt — заметка, а не тишина.
nav c r q
check grep -q 'apt недоступен — проверять нечем' "$NAV/out"

echo "── 1.1.0 по проверке: «Компоненты» — цифры, c с любого экрана, срез"
# Цифра отмечает строку и ставит на неё курсор.
anav c 3 q
check [ "$(navtr0)" = "c menu|3 comps|q comps" ]
check grep -q 'Обновить отмеченные (1)' "$NAV/out"
check grep -q '▸ 3 \[✓\] Docker' <(plain < "$NAV/out")
# c — с любого экрана, как p.
nav p c 0 0 q
check [ "$(navtr0)" = "p menu|c ports|0 comps|0 ports|q menu" ]
# Срез у нижнего края не оставляет пустых строк: курсор на «0 Назад».
out=$(sl 80 23)
check [ "$(grep -c '║  *║░║' <<<"$out")" = 0 ]
check [ "$(grep -c '▸ 0  Назад' <<<"$out")" = 1 ]
# Нумерованное меню на 80 колонках: действия целиком, у движков — кто
# обновляет, у сломанного окружения — что и как починить; строки не шире 80.
out=$(ap 'comp_apt_load >/dev/null; comp_engines_load; COLUMNS=80; tput() { return 1; }; menu_items_components; menu_build_rows; printf "0\n" | _pick_menu_plain 2>&1' | plain)
check has "$out" 'a) Обновить всё (3)'
check has "$out" 'r) Проверить обновления'
check has "$out" 'goVLESS pro: обновляется вместе с 3X-UI'
check has "$out" '✗ python 3.10 окружения бота не запускается'
check has "$out" 'Починить: rm -rf /opt/godns/bot/venv'
check has "$out" 'так пропадёт токен'
check [ "$(python3 -c 'import sys; print(max(len(l.rstrip("\n")) for l in sys.stdin))' <<<"$out")" -le 80 ]

echo "── 1.1.0 по проверке: размер пакета — несколько адресов GitHub"
# Первый адрес из DNS отвечает только на малые пакеты (как 20.250.119.72):
# цель — первый ответивший на 1200, правка и проверка — по нему же.
mtu2() { NETLOG="$T/net/pings" nt 1452 '_net_resolve() { printf "20.250.119.72\n140.82.121.5\n"; }
    _net_ping_df() { echo "$1 $2" >> "$NETLOG"; if [ "$1" = 20.250.119.72 ]; then [ "$2" -le 56 ]; return; fi
        [ $(( $2 + 28 )) -le "$(_net_if_mtu)" ] && [ $(( $2 + 28 )) -le 1452 ] && return 0; echo "Frag needed (mtu = 1452)"; return 1; }
    '"$1"; }
rm -f "$T/net/"*
check [ "$(mtu2 'net_mtu_probe; echo "$?:$NET_IP:$NET_PMTU"')" = "1:140.82.121.5:1452" ]
rm -f "$T/net/"*
out=$(printf '1\n' | mtu2 'net_mtu_offer' 2>&1)
check has "$out" 'путь до GitHub пропускает только 1452'
check has "$out" 'могут рваться'
check hasnt "$out" 'через раз'
check has "$out" 'Размер пакета ens3: 1452'
check hasnt "$out" 'вернул'
check [ "$(cat "$T/net/calls")" = "set ens3 1452" ]
check [ "$(tail -1 "$T/net/pings")" = "140.82.121.5 1424" ]       # проверка — тот же адрес
# Одна потеря при проверке правку не откатывает: две попытки.
rm -f "$T/net/"*
out=$(printf '1\n' | mtu2 '_p0="$(declare -f _net_ping_df)"; eval "${_p0/_net_ping_df/_ping0}"
    _net_ping_df() { if [ "$2" = 1424 ] && [ ! -e "$T/net/lost" ] && [ "$(_net_if_mtu)" = 1452 ]; then : > "$T/net/lost"; return 1; fi; _ping0 "$@"; }; net_mtu_offer' 2>&1)
check has "$out" 'Размер пакета ens3: 1452'
check hasnt "$out" 'вернул'
# Не ответил ни один — «узнать нельзя», адресов пробуем не больше трёх, по
# одной пробе на адрес; --net называет причину.
rm -f "$T/net/"*
out=$(NETLOG="$T/net/pings" nt 1452 '_net_resolve() { printf "1.1.1.1\n2.2.2.2\n3.3.3.3\n4.4.4.4\n"; }; _net_ping_df() { echo "$1 $2" >> "$NETLOG"; [ "$1" = 4.4.4.4 ]; }
    net_mtu_probe; echo "rc=$? why=$NET_WHY n=$NET_NIPS"; net_mtu_offer force' 2>&1)
check has "$out" 'rc=2 why=mute n=3'
check [ "$(wc -l < "$T/net/pings" | tr -d ' ')" = 12 ]         # 3 адреса × 2 пробы × (проба + повтор в offer)
check neg grep -q 4.4.4.4 "$T/net/pings"
check has "$out" 'адреса GitHub (3) не отвечают на ping нужного размера'
# Повторы адресов в DNS — один раз.
check [ "$(ml 'getent() { printf "1.2.3.4 STREAM x\n1.2.3.4 DGRAM\n5.6.7.8 STREAM\n"; }; _net_resolve x | tr "\n" " "')" = "1.2.3.4 5.6.7.8 " ]

echo "── 1.1.0 по проверке: отказ по ОС называет систему"
out=$(pf_env ss-empty units-empty nginx-empty os-debian11 "" 'preflight govless pro 2>&1')
check has "$out" 'Ставить нельзя: на этой системе goVLESS pro не ставится — см. выше.'
check hasnt "$out" 'Освободите порты'
check hasnt "$out" 'обновить Ubuntu'                     # пункта обновления ОС пока нет
out=$(pf_env ss-govless units-govless nginx-govless os-ubuntu2404 govless 'preflight gotelegram pro 2>&1')
check has "$out" 'Снимите препятствия выше и запустите проверку снова'
check hasnt "$out" 'на этой системе'

echo "── 1.1.0 по проверке: мелочи меню"
# Карта портов: обрезанный процесс не слипается с «что это».
out=$(ml 'UI_PG_ROWS=("53/udp|systemd-resolve|loopback: DNS"); UI_PG_CUR=0; _ui_b_ports_group 60; printf "%s\n" "${UI_LS[@]}"; _ui_b_ports_group 40; printf "%s\n" "${UI_LS[@]}"')
check has "$out" 'systemd-re… '
check has "$out" 'systemd… '
# Нумерованное меню: ширина подписи — по самой длинной, ничего не режется.
out=$(pf_env ss-govless units-govless nginx-govless os-ubuntu2404 govless 'TOKEN=t; COLUMNS=80; tput() { return 1; }; prod_readiness() { printf g:; }; menu_items_main; menu_build_rows; printf "%s\n" "${MENU_ROW[@]}"' | sed 's/\\033\[[0-9;]*m//g')
check has "$out" 'Обновить сведения о версиях'
check has "$out" 'Удалить goInstaller  '
check [ "$(python3 -c 'import sys; print(max(len(l.rstrip("\n")) for l in sys.stdin))' <<<"$out")" -le 74 ]
# Подтверждение без сведений о версии — без «, ?».
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example; UD_MAIN[1]=''; UI_PBRANCH=main; ui_scr_confirm 1 0 >/dev/null; echo \"\$UI_Q\"")
check [ "$out" = "Запустить установщик goTelegram pro — ветка main?" ]
# «Обновляются сами раз в N мин» — по GOINST_MENU_REFRESH; без сети и при 0 — нет.
mi() { GOINST_MENU_REFRESH="$1" GOINST_NO_NET="${2:-}" ml "TOKEN='${3-t}'"'; UI_POLL=""; UI_POLLERR=""; UD_SVED=14:05; UI_C=80; ui_menu_info; printf "%s" "$UI_INFO"'; }
check has "$(mi 300)" 'обновляются сами раз в 5 мин'
check has "$(mi 180)" 'раз в 3 мин'
check hasnt "$(mi 0)" 'обновляются сами'
check hasnt "$(mi 180 1)" 'обновляются сами'
# Карточка ключа: «сохранён … 0600» — только с файлом, «6 из 6» — только после проверки.
kc() { ml "UD_KEYDENIED=''; UI_KEYCHECKING=''; UD_SVED=14:05; TOKEN_STATUS='$1'; token_saved() { $2; }; _ui_b_key_card 40; printf '%s\n' \"\${UI_LS[@]}\""; }
check has "$(kc ok true)" 'открывает 6 из 6'
check has "$(kc ok true)" '0600'
check hasnt "$(kc ok false)" '0600'
check has "$(kc ok false)" 'не сохранён — только на этот запуск'
check hasnt "$(kc '' true)" 'открывает 6 из 6'
check has "$(kc '' true)" 'не проверен'
check has "$(kc nonet true)" 'не проверен: GitHub недоступен'
# Заставка: ответ 401 — «ключ не принят», а не «нет ответа».
out=$(ml 'UI_POLLDIR=$(mktemp -d); echo "bad||" > "$UI_POLLDIR/key"; ui_poll_state; echo "${UI_PI_ST[1]}|${UI_PI_RES[1]}"; rm -rf "$UI_POLLDIR"')
check [ "$out" = "fail|401: ключ не принят" ]
out=$(T="$T" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example; ui_example_more; UI_PI_ST[1]=fail; UI_PI_RES[1]='401: ключ не принят'; UI_POLLERR=''; ui_scr_splash; ui_compose; ui_dump" | cut -f1)
check has "$out" '401: ключ не принят'
# С итога установки «В главное меню» — курсор на этом продукте.
check [ "$(ml 'UI_SCR=result; UI_WP=3; UI_STACK=(); ui_act root; echo "$UI_SCR $UI_CUR"')" = "menu 3" ]
check [ "$(ml 'UI_SCR=err; UI_WP=3; UI_STACK=(); ui_act root; echo "$UI_SCR $UI_CUR"')" = "menu 0" ]

echo "── 1.1.0 по проверке: «Аркада» без ключа"
# «2 Продолжить без ключа» — меню; проверка портов работает; установка
# ведёт на ввод ключа, после ключа — снова мастер того же продукта.
NAVTOKEN= nav 2 3 2 0 1 k e y '\n' q
check [ "$(navtr0)" = "2 nokey|3 menu|2 product|0 check|1 product|k keyinput|e keyinput|y keyinput|enter keyinput|q check" ]
check grep -q 'Продолжаю без ключа' "$NAV/out"
check grep -q 'Для установки нужен ключ доступа' "$NAV/out"
check grep -qx 'KEYSAVE key' "$NAV/act"
check neg grep -q '^RUN' "$NAV/act"
# Esc при вводе ключа — назад, установка не идёт.
NAVTOKEN= nav 2 3 1 '\033' q
check [ "$(navtr0)" = "2 nokey|3 menu|1 product|esc keyinput|q product" ]
check neg grep -q 'KEYSAVE\|^RUN' "$NAV/act"
# С ключом установка не просит его снова.
nav 3 1 q
check neg grep -q 'keyinput' "$NAV/trace"

echo "── 1.1.0 по проверке: сводка версий публикуется не реже раза в 2 часа"
check grep -q 'GOINST_DIGEST_HEARTBEAT:-7200' "$HERE/.github/versions-publish.sh"
check neg grep -q 'раз в полчаса' "$HERE/CLAUDE.md"
check neg grep -q 'не реже раза в 6' "$SCRIPT"

echo "── обновление Ubuntu: стенд"
# Система не трогается: do-release-upgrade, apt-get, apt-mark, dpkg,
# dpkg-query, apt-cache, systemctl, systemd-detect-virt, dkms, curl, docker,
# df, nginx, ufw, netfilter-persistent — заглушки в PATH. Пишут вызовы в
# $OSFX/calls. do-release-upgrade переписывает VERSION_ID в фикстуре
# os-release и делает с «системой» то, что делал настоящий на прыжке в 24.04:
# списки в .distUpgrade, libnginx-mod-stream и ufw снесены, nginx упал.
OSFX="$T/osup"; export OSFX
mkos() {  # mkos <выпуск> — свежий стенд
    local v="$1" d="$OSFX"
    rm -rf "$d"; mkdir -p "$d/bin" "$d/gi" "$d/fs/etc/apt/sources.list.d" "$d/fs/etc/update-manager" "$d/fs/etc/systemd/system" \
        "$d/fs/var/log/dist-upgrade" "$d/fs/var/run" "$d/fs/var/lib/dpkg/updates" "$d/fs/proc" "$d/fs/etc/ssh" "$d/fs/etc/iptables"
    osrel "$d/os-release" ubuntu "$v"
    cat > "$d/bin/do-release-upgrade" <<'S'
#!/bin/sh
echo "do-release-upgrade $*" >> "$OSFX/calls"
if [ -f "$OSFX/dru-fail" ]; then echo "2026-10-14 14:20:01,1 ERROR Could not calculate the upgrade" >> "$OSFX/fs/var/log/dist-upgrade/main.log"; exit 1; fi
v0=$(sed -n 's/^VERSION_ID="\(.*\)"/\1/p' "$OSFX/os-release")
case "$v0" in 24.04|26.04) echo "do-release-upgrade на $v0" >> "$OSFX/calls" ;; esac
v=$(sed -n 's/^VERSION_ID="\(.*\)"/\1/p' "$OSFX/os-release")
case "$v" in 20.04) n=22.04 ;; 22.04) n=24.04 ;; *) exit 1 ;; esac
sed "s/$v/$n/g" "$OSFX/os-release" > "$OSFX/os.tmp" && mv "$OSFX/os.tmp" "$OSFX/os-release"
if [ "$n" = 24.04 ]; then
    for l in cloudflare-client.list godns-dnsdist.list foreign.list; do
        [ -f "$OSFX/fs/etc/apt/sources.list.d/$l" ] && mv "$OSFX/fs/etc/apt/sources.list.d/$l" "$OSFX/fs/etc/apt/sources.list.d/$l.distUpgrade"
    done
    grep -v '^libnginx-mod-stream|\|^ufw|' "$OSFX/dpkg" > "$OSFX/dpkg.tmp"; mv "$OSFX/dpkg.tmp" "$OSFX/dpkg"
    sed 's/^nginx=run/nginx=down/; s/^dnsdist=run/dnsdist=down/' "$OSFX/units" > "$OSFX/units.tmp"; mv "$OSFX/units.tmp" "$OSFX/units"
    [ -f "$OSFX/ss-lost" ] && cp "$OSFX/ss-lost" "$OSFX/ss"
    [ -f "$OSFX/docker-lost" ] && : > "$OSFX/docker"
fi
: > "$OSFX/fs/var/run/reboot-required"
# Упал посреди установки: base-files уже новый, код 1 (Б-2); dru-break —
# и dpkg недонастроен так, что восстановление не помогает.
if [ -f "$OSFX/dru-rc1" ]; then
    echo "2026-10-14 14:20:01,1 ERROR Could not install the upgrades" >> "$OSFX/fs/var/log/dist-upgrade/main.log"
    [ -f "$OSFX/dru-break" ] && echo ' libc6  half-configured' > "$OSFX/audit"
    exit 1
fi
exit 0
S
    cat > "$d/bin/apt-get" <<'S'
#!/bin/sh
echo "apt-get $*" >> "$OSFX/calls"
case " $* " in
    *" dist-upgrade "*)
        # dist-bump: источники уже noble (оборванный прыжок) — пакеты сами
        # доводят выпуск до 24.04 (Б-1).
        if [ -f "$OSFX/dist-bump" ]; then sed 's/22.04/24.04/g' "$OSFX/os-release" > "$OSFX/o.t" && mv "$OSFX/o.t" "$OSFX/os-release"; fi
        exit "$(cat "$OSFX/dist-rc" 2>/dev/null || echo 0)" ;;
    *" install "*)
        if [ -s "$OSFX/install-fail-pkg" ]; then for p in "$@"; do grep -qx -- "$p" "$OSFX/install-fail-pkg" && exit 100; done; fi
        on=0
        for p in "$@"; do
            [ "$p" = install ] && { on=1; continue; }
            [ "$on" = 1 ] || continue
            case "$p" in -*) continue ;; esac
            echo "$p|9.9-new|$p|ii" >> "$OSFX/dpkg"
        done
        exit 0 ;;
esac
exit 0
S
    cat > "$d/bin/apt-mark" <<'S'
#!/bin/sh
echo "apt-mark $*" >> "$OSFX/calls"
[ "$1" = showmanual ] && cat "$OSFX/manual"
exit 0
S
    cat > "$d/bin/dpkg" <<'S'
#!/bin/sh
echo "dpkg $*" >> "$OSFX/calls"
case " $* " in
    *" --audit "*) cat "$OSFX/audit" 2>/dev/null ;;
    *" --configure "*) [ -f "$OSFX/audit-fix" ] && : > "$OSFX/audit" ;;
esac
exit 0
S
    printf '#!/bin/sh\ncat "$OSFX/dpkg"\n' > "$d/bin/dpkg-query"
    cat > "$d/bin/apt-cache" <<'S'
#!/bin/sh
shift
for p in "$@"; do
    c=$(sed -n "s/^$p=//p" "$OSFX/cand" | head -1)
    echo "$p:"; echo "  Installed: (none)"; echo "  Candidate: ${c:-(none)}"
done
S
    cat > "$d/bin/systemctl" <<'S'
#!/bin/sh
echo "systemctl $*" >> "$OSFX/calls"
u=""; for a in "$@"; do case "$a" in -*|show|is-active|is-enabled|restart|enable|disable) ;; *) u="$a" ;; esac; done
st=$(sed -n "s/^$u=//p" "$OSFX/units" 2>/dev/null | head -1)
case "$1" in
    show) case " $* " in *" -p Job "*) cat "$OSFX/job-$u" 2>/dev/null; exit 0 ;;
                           *" -p MainPID "*) echo "MainPID=$(cat "$OSFX/mainpid-$u" 2>/dev/null || echo 0)"; exit 0 ;; esac
          if [ -f "$OSFX/masked-$u" ]; then echo "LoadState=masked"
          elif [ -n "$st" ]; then echo "LoadState=loaded"; else echo "LoadState=not-found"; fi ;;
    is-active) a=$(cat "$OSFX/active-$u" 2>/dev/null)
               if [ -n "$a" ]; then echo "$a"; [ "$a" = active ]; exit; fi
               [ "$st" = run ] ;;
    is-enabled) [ "$st" = run ] || [ "$st" = down ] || [ -f "$OSFX/enabled-$u" ] ;;
    enable) [ -f "$OSFX/enable-fail" ] && exit 1; : > "$OSFX/enabled-$u"; exit 0 ;;
    disable) rm -f "$OSFX/enabled-$u"; exit 0 ;;
    restart)
        if grep -qx "$u" "$OSFX/restart-ok" 2>/dev/null; then
            sed "s/^$u=.*/$u=run/" "$OSFX/units" > "$OSFX/units.tmp"; mv "$OSFX/units.tmp" "$OSFX/units"
            [ "$u" = ssh.socket ] && [ -f "$OSFX/ss-good" ] && cp "$OSFX/ss-good" "$OSFX/ss"
        fi; exit 0 ;;
    reboot) [ -f "$OSFX/reboot-fail" ] && exit 1; rm -f "$OSFX/fs/var/run/reboot-required"; exit 0 ;;
    start) rc=$(cat "$OSFX/start-rc" 2>/dev/null || echo 0); [ "$rc" = 0 ] && { echo 7 > "$OSFX/job-$u"; rm -f "$OSFX/active-$u"; }; exit "$rc" ;;
    *) exit 0 ;;
esac
S
    cat > "$d/bin/systemd-detect-virt" <<'S'
#!/bin/sh
if [ "${1:-}" = --container ]; then
    if [ -s "$OSFX/cont" ]; then cat "$OSFX/cont"; exit 0; fi
    echo none; exit 1
fi
echo kvm
S
    cat > "$d/bin/dkms" <<'S'
#!/bin/sh
echo "dkms $*" >> "$OSFX/calls"
[ "$1" = status ] && cat "$OSFX/dkms" 2>/dev/null
exit 0
S
    cat > "$d/bin/curl" <<'S'
#!/bin/sh
for a in "$@"; do u="$a"; done
echo "curl $u" >> "$OSFX/calls"
grep -qF "$u" "$OSFX/curl-fail" 2>/dev/null && exit 22
exit 0
S
    printf '#!/bin/sh\necho "docker $*" >> "$OSFX/calls"\ncat "$OSFX/docker" 2>/dev/null\n' > "$d/bin/docker"
    cat > "$d/bin/df" <<'S'
#!/bin/sh
for a in "$@"; do p="$a"; done
echo "Filesystem 1024-blocks Used Available Capacity Mounted"
l=$(grep "^$p " "$OSFX/df" | head -1)
[ -n "$l" ] || l=$(grep '^/ ' "$OSFX/df" | head -1)
set -- $l
echo "/dev/vda1 30000000 1000 $2 5% $3"
S
    printf '#!/bin/sh\necho "nginx: [emerg] unknown directive \\"stream\\" in /etc/nginx/nginx.conf:86" >&2\nexit 1\n' > "$d/bin/nginx"
    printf '#!/bin/sh\necho "netfilter-persistent $*" >> "$OSFX/calls"\n' > "$d/bin/netfilter-persistent"
    printf '#!/bin/sh\ncat "$OSFX/ufw-status" 2>/dev/null || echo "Status: inactive"\n' > "$d/bin/ufw"
    # sshd -T — действующие настройки; файла нет — «не вышло», разбор файлов.
    # sshd -t — проверка настроек: файл sshd-check — её ответ с ошибкой (не
    # sshd-t: на macOS имена файлов без учёта регистра, это был бы sshd-T).
    printf '#!/bin/sh\n[ "$1" = -T ] && [ -f "$OSFX/sshd-T" ] && { cat "$OSFX/sshd-T"; exit 0; }\nif [ "$1" = -t ]; then [ -f "$OSFX/sshd-check" ] || exit 0; cat "$OSFX/sshd-check" >&2; exit 255; fi\nexit 1\n' > "$d/bin/sshd"
    chmod +x "$d/bin/"*
    cat > "$d/dpkg" <<'D'
nginx|1.18.0-6ubuntu14|nginx|ii
nginx-core|1.18.0-6ubuntu14|nginx|ii
nginx-common|1.18.0-6ubuntu14|nginx|ii
libnginx-mod-stream|1.18.0-6ubuntu14|nginx|ii
python3|3.10.6-1|python3-defaults|ii
python3.10|3.10.12-1|python3.10|ii
python3.10-venv|3.10.12-1|python3.10|ii
docker.io|24.0.7-0ubuntu2|docker.io|ii
dnsdist|2.0.11-1pdns|dnsdist|ii
curl|7.81.0-1|curl|ii
ufw|0.36.1-4|ufw|ii
iptables-persistent|1.0.16|iptables-persistent|ii
nginx-full|1.18.0-6ubuntu14|nginx|un
D
    printf 'nginx\npython3\ncurl\n' > "$d/manual"
    printf 'libnginx-mod-stream=1.24.0-2ubuntu7.4\nnginx-core=1.24.0-2ubuntu7.4\nlinux-headers-6.8.0-85-generic=6.8.0-85.85\n' > "$d/cand"
    printf 'nginx=run\ndnsdist=run\ndocker=run\nssh.socket=run\nnetfilter-persistent=run\n' > "$d/units"
    printf 'nginx\nssh.socket\n' > "$d/restart-ok"
    printf '/ 22000000 /\n' > "$d/df"
    printf 'amnezia-awg\n' > "$d/docker"
    printf 'MemTotal:        2014000 kB\n' > "$d/fs/proc/meminfo"
    printf '[DEFAULT]\nPrompt=never\n' > "$d/fs/etc/update-manager/release-upgrades"
    printf 'Port 2222\n' > "$d/fs/etc/ssh/sshd_config"
    printf 'tcp   LISTEN 0      128          0.0.0.0:2222      0.0.0.0:*    users:(("sshd",pid=500,fd=3))\n' > "$d/ss"
    cp "$d/ss" "$d/ss-good"
    # GOINST_BIN стенда — копия: self_update и запуск исполнителя пишут в
    # неё, а не в рабочий скрипт.
    cp "$SCRIPT" "$d/goinstall"; chmod 755 "$d/goinstall"
    printf 'deb [signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ focal main\n' > "$d/fs/etc/apt/sources.list.d/cloudflare-client.list"
    printf 'deb [arch=amd64 signed-by=/etc/apt/keyrings/dnsdist.asc] http://repo.powerdns.com/ubuntu jammy-dnsdist-20 main\n' > "$d/fs/etc/apt/sources.list.d/godns-dnsdist.list"
    printf 'deb http://ppa.launchpad.net/foo/bar/ubuntu jammy main\n' > "$d/fs/etc/apt/sources.list.d/foreign.list"
    : > "$d/calls"; : > "$d/audit"
}
ox() {  # ox <выражение> — функции скрипта на стенде обновления
    PATH="$OSFX/bin:$PATH" GOINST_SOURCE_ONLY=1 GOINST_TEST=1 GOINST_LANG=ru GOINST_DIR="$OSFX/gi" GOINST_FS_ROOT="$OSFX/fs" \
    GOINST_OS_RELEASE="$OSFX/os-release" GOINST_SYSTEMD_DIR="$OSFX/fs/etc/systemd/system" GOINST_OSUP_REBOOT_WAIT=0 \
    GOINST_OSUP_DOCKER_WAIT=0 GOINST_OSUP_SETTLE=0 GOINST_OSUP_LOCK_WAIT=0 GOINST_OSUP_CHECK_WAIT=0 GOINST_KERNEL=6.8.0-85-generic \
    GOINST_FAKE_INSTALLED="${OSINST-gowarp godns}" GOINST_SS_FIXTURE="$OSFX/ss" GOINST_UNIT_FIXTURE="$T/units-empty" GOINST_BIN="$OSFX/goinstall" \
    GOINST_BIN_ALIAS="$OSFX/go-installer" GOINST_PROFILE_HOOK="$OSFX/fs/etc/profile.d/goinstall-summary.sh" \
    GOINST_COLOR=none GOINST_DOCKER_FIXTURE="$T/docker-empty" bash -c ". '$SCRIPT'; os_detect; $1" 2>&1
}
osst() { sed -n "s/^$1=//p" "$OSFX/gi/os-upgrade/state" 2>/dev/null | head -1; }   # поле состояния
# Служба обновления стоит и включена — «идёт» без неё теперь «прервано».
# Задание systemd (job-…) — служба ждёт запуска; без него включённая и
# неработающая служба — исполнитель упал.
osunit() { : > "$OSFX/fs/etc/systemd/system/goinstall-os-upgrade.service"; : > "$OSFX/enabled-goinstall-os-upgrade.service"; echo 7 > "$OSFX/job-goinstall-os-upgrade.service"; }
oscalls() { grep -c -- "$1" "$OSFX/calls" 2>/dev/null || true; }
# Отметка запуска (kick) старше минуты: окно «только что запущено» прошло.
osage() { local f="$OSFX/gi/os-upgrade/state"; sed 's/^kick=.*/kick=1/' "$f" > "$f.t" && mv "$f.t" "$f"; }
# Исполнитель упал, как у настоящего systemd: failed, задания нет, окно прошло.
oscrash() { echo failed > "$OSFX/active-goinstall-os-upgrade.service"; rm -f "$OSFX/job-goinstall-os-upgrade.service"; osage; }

echo "── обновление Ubuntu: пункт «o» — только на 20.04 и 22.04"
okeys() { ox 'OS_PRETTY=x; prod_readiness() { printf g:; }; menu_items_main; printf "%s " "${MENU_ITEMS[@]%%|*}"' | tr -d ' -'; }
mkos 20.04; check [ "$(okeys)" = "123456oplcsx0" ]
mkos 22.04; check [ "$(okeys)" = "123456oplcsx0" ]
check has "$(ox 'OS_PRETTY=x; prod_readiness() { printf g:; }; menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}"')" 'o|Ubuntu 22.04 → 24.04|g:↑ 24.04||'
for v in 24.04 18.04 26.04; do mkos "$v"; check [ "$(okeys)" = "123456plcsx0" ]; done
mkos 22.04; osrel "$OSFX/os-release" debian 12; check [ "$(okeys)" = "123456plcsx0" ]
# В контейнере пункт есть, но запуска нет: проверка говорит, что делать.
mkos 22.04; echo lxc > "$OSFX/cont"
check [ "$(okeys)" = "123456oplcsx0" ]
out=$(ox 'osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"; echo "bad=$OSUP_BAD"; osup_start; echo "rc=$? err=$OSUP_ERR"')
check has "$out" 'bad|контейнер (lxc): ядро задаёт хостер, обновить выпуск отсюда нельзя — переустановите сервер на 24.04 в панели хостера'
check has "$out" 'rc=1 err=контейнер (lxc)'
check [ ! -e "$OSFX/fs/etc/systemd/system/goinstall-os-upgrade.service" ]
# Есть состояние — пункт виден на любой версии: идёт, прервано, итог не просмотрен.
mkos 24.04; mkdir -p "$OSFX/gi/os-upgrade"; osunit
for st in "running|o|Ubuntu: обновление, шаг 1 из 7|y:идёт" "failed|o|Ubuntu: обновление прервано|r:✗ прервано" "done|o|Ubuntu 24.04: итог обновления|g:✓ готово"; do
    printf 'status=%s\nfrom=20.04\nstarted=1\nseen=0\n' "${st%%|*}" > "$OSFX/gi/os-upgrade/state"
    check has "$(ox 'OS_PRETTY=x; prod_readiness() { printf g:; }; menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}"')" "${st#*|}"
done
printf 'status=done\nfrom=20.04\nseen=1\n' > "$OSFX/gi/os-upgrade/state"
check [ "$(okeys)" = "123456plcsx0" ]                      # итог просмотрен — пункта нет

echo "── обновление Ubuntu: проверка перед запуском"
mkos 22.04
out=$(ox 'osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"; echo "bad=$OSUP_BAD"')
check has "$out" 'bad=0'
check has "$out" 'ok|виртуалка KVM'
check has "$out" 'ok|20 ГБ свободно'
check has "$out" 'ok|apt свободен'
check has "$out" 'ok|changelogs.ubuntu.com отвечает'
check has "$out" 'warn|в release-upgrades стоит Prompt=never — на время обновления будет lts'
check has "$out" 'do|вернёт на 24.04 источники apt: dnsdist (goDNS pro), cloudflare-warp (goWARP pro)'
check has "$out" 'do|сохранит модули nginx'
check has "$out" 'info|ufw удалится на 24.04 — он несовместим с iptables-persistent'
check has "$out" 'info|контейнеры с автоперезапуском поднимутся сами'
check hasnt "$out" 'cloudflared'
# ufw активен — правила сохранятся (Д2), это замечание и пункт «сделает сам».
out=$(echo 'Status: active' > "$OSFX/ufw-status"; ox 'osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"'); rm -f "$OSFX/ufw-status"
check has "$out" 'do|сохранит правила файрвола (netfilter-persistent save)'
check has "$out" 'warn|ufw удалится на 24.04 (несовместим с iptables-persistent goKaskad pro). Перед этим goInstaller сохранит текущие правила'
# Возврат источников выключен одним флагом — экран его не обещает.
check hasnt "$(GOINST_OSUP_FIX_LISTS=0 ox 'osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"')" 'источники apt'
# Препятствия.
printf '/ 4000000 /\n/boot 200000 /boot\n' > "$OSFX/df"
printf 'The following packages are only half configured:\n nginx\n' > "$OSFX/audit"
echo 'https://changelogs.ubuntu.com/meta-release-lts' > "$OSFX/curl-fail"
mkdir -p "$OSFX/fs/proc/4242/fd"; ln -sf /var/lib/dpkg/lock-frontend "$OSFX/fs/proc/4242/fd/3"; echo unattended-upgr > "$OSFX/fs/proc/4242/comm"
printf 'MemTotal:         950000 kB\n' > "$OSFX/fs/proc/meminfo"
out=$(ox 'osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"; echo "bad=$OSUP_BAD"')
check has "$out" 'bad|на / свободно 3 ГБ, нужно не меньше 5 ГБ'
check has "$out" 'bad|на /boot свободно 195 МБ, нужно не меньше 300 МБ'
check has "$out" 'bad|dpkg не в порядке: The following packages are only half configured: — dpkg --configure -a'
check has "$out" 'bad|идут автообновления (unattended-upgrades) — подождите и откройте снова'
check has "$out" 'bad|нет связи с changelogs.ubuntu.com'
check has "$out" 'warn|памяти 927 МБ — обновление пойдёт медленнее'
check has "$out" 'bad=5'
echo apt-get > "$OSFX/fs/proc/4242/comm"
check has "$(ox 'osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"')" 'bad|apt занят процессом apt-get (4242)'
printf '/ 6500000 /\n' > "$OSFX/df"
check has "$(ox 'osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"')" 'warn|на / свободно 6 ГБ — впритык'
# Окружение бота, goKaskad pro 3, DKMS — сведения.
mkos 22.04
mkdir -p "$OSFX/fs/opt/godns/bot/venv/bin" "$OSFX/fs/usr/bin" "$OSFX/fs/usr/local/bin"
printf 'home = /usr/bin\nversion = 3.10.12\n' > "$OSFX/fs/opt/godns/bot/venv/pyvenv.cfg"
printf 'amneziawg/1.0.20260906, 5.15.0-125-generic, x86_64: installed\n' > "$OSFX/dkms"
out=$(OSINST="godns gokaskad" ox 'prod_version() { echo 3.3.3; }; osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"')
check has "$out" 'info|бот goDNS pro после обновления не запустится, пока не переустановить его в меню продукта: rm -rf /opt/godns/bot/venv, затем мастер бота godns; не через «снять бота»'
check has "$out" 'info|после обновления запустите gokaskad — он предложит перейти на nftables'
check has "$out" 'info|модуль amneziawg пересоберётся под новое ядро: goInstaller поставит заголовки ядра'
check has "$(OSINST="gokaskad" ox 'prod_version() { echo 2.13; }; osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"')" 'info|после обновления запустите gokaskad и проверьте проброс'

echo "── обновление Ubuntu: запуск"
mkos 20.04
out=$(ox 'osup_start; echo "rc=$? err=$OSUP_ERR"')
check has "$out" 'rc=0 err='
G="$OSFX/gi/os-upgrade"
check [ "$(osst status)" = running ]
check [ "$(osst from)" = 20.04 ]
check [ "$(osst attempt)" = 1 ]
check [ "$(ls -ld "$G" | cut -c1-10)" = "drwx------" ]
check cmp -s "$SCRIPT" "$G/runner.sh"                           # служба зовёт копию
check grep -qx 'Dpkg::Options { "--force-confdef"; "--force-confold"; };' "$OSFX/fs/etc/apt/apt.conf.d/99goinstall-os-upgrade"
check grep -qx 'Prompt=lts' "$OSFX/fs/etc/update-manager/release-upgrades"
check grep -qx never "$G/before/prompt"
U="$OSFX/fs/etc/systemd/system/goinstall-os-upgrade.service"
check grep -qx 'Type=oneshot' "$U"
check grep -qx 'TimeoutStartSec=0' "$U"
check grep -qx 'WantedBy=multi-user.target' "$U"
check grep -qx 'Environment=DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 APT_LISTCHANGES_FRONTEND=none' "$U"
check grep -qx "ExecStart=/bin/bash $G/runner.sh --os-upgrade-run" "$U"
check grep -qx "StandardOutput=append:$G/log" "$U"
check grep -qx 'systemctl daemon-reload' "$OSFX/calls"
check grep -qx 'systemctl enable goinstall-os-upgrade.service' "$OSFX/calls"
check grep -qx 'systemctl start --no-block goinstall-os-upgrade.service' "$OSFX/calls"
# apt-mark manual — только стоящим пакетам групп, без пакетов python3.10.
am=$(grep '^apt-mark manual' "$OSFX/calls")
for p in nginx nginx-core libnginx-mod-stream docker.io dnsdist curl iptables-persistent; do check has "$am" " $p"; done
check hasnt "$am" 'nginx-full'
check hasnt "$am" 'python3.10'
check grep -qx libnginx-mod-stream "$G/before/marked"
check neg grep -qx nginx "$G/before/marked"               # был вручную — не наша пометка
check grep -qx 2222 "$G/before/ssh"
check grep -qx nginx "$G/before/units"
check grep -qx amnezia-awg "$G/before/docker"
check grep -qx 1 "$G/before/ufw"
# Уже идёт — второй раз не запускается.
check has "$(ox 'osup_start; echo "rc=$? $OSUP_ERR"')" 'rc=1 обновление уже идёт'
# Служба не стартовала — прервано и уборка.
mkos 22.04; echo 1 > "$OSFX/start-rc"
ox 'osup_start' >/dev/null
check [ "$(osst status)" = failed ]
check [ ! -e "$OSFX/fs/etc/apt/apt.conf.d/99goinstall-os-upgrade" ]
check [ ! -e "$OSFX/fs/etc/systemd/system/goinstall-os-upgrade.service" ]

echo "── обновление Ubuntu: цепочка 20.04 → 24.04 исполнителем"
mkos 20.04; : > "$OSFX/fs/var/run/reboot-required"
ox 'osup_start' >/dev/null; : > "$OSFX/calls"
runs=""
for i in 1 2 3 4 5; do
    ox 'osup_run; echo "rc=$?"' > "$OSFX/run$i"
    runs+="$(osst step):$(osst status) "
done
check [ "$runs" = "dist-20.04:running boot-22.04:running boot-24.04:running fin:done fin:done " ]
check [ "$(oscalls '^systemctl reboot')" = 3 ]
check [ "$(oscalls '^do-release-upgrade -f DistUpgradeViewNonInteractive')" = 2 ]
check [ "$(oscalls 'dist-upgrade')" = 2 ]
check [ "$(osst reboots)" = 4 ]                             # пятый запуск — уже не running
check grep -q 'VERSION_ID="24.04"' "$OSFX/os-release"
for l in dist-20.04 rel-20.04 boot-22.04 dist-22.04 rel-22.04 boot-24.04 fin; do check grep -q "^t:$l=[0-9]* [0-9]*\$" "$G/state"; done
# Завершение: источники продуктов — на noble, чужой не тронут.
SL="$OSFX/fs/etc/apt/sources.list.d"
check grep -qx 'deb \[signed-by=/usr/share/keyrings/cloudflare-warp.gpg\] https://pkg.cloudflareclient.com/ noble main' "$SL/cloudflare-client.list"
check grep -qx 'deb \[arch=amd64 signed-by=/etc/apt/keyrings/dnsdist.asc\] http://repo.powerdns.com/ubuntu noble-dnsdist-20 main' "$SL/godns-dnsdist.list"
check [ ! -e "$SL/cloudflare-client.list.distUpgrade" ]
check grep -qx 'deb http://ppa.launchpad.net/foo/bar/ubuntu jammy main' "$SL/foreign.list.distUpgrade"
check grep -qF 'curl http://repo.powerdns.com/ubuntu/dists/noble-dnsdist-20/InRelease' "$OSFX/calls"
check grep -q '^note=apt|выключены обновлением: foreign.list — включите сами, если нужны' "$G/state"
# Пропавший libnginx-mod-stream — поставлен снова; python3.10 — нет.
check grep -q '^apt-get .*--no-install-recommends --no-remove install libnginx-mod-stream$' "$OSFX/calls"
check grep -q '^did=поставлены снова: libnginx-mod-stream' "$G/state"
# Службы: nginx поднялся перезапуском, dnsdist — нет, замечание с journalctl.
check grep -qx 'systemctl restart nginx' "$OSFX/calls"
check grep -q '^did=служба nginx перезапущена' "$G/state"
check grep -q '^note=dnsdist|служба не запускается после обновления|dnsdist: не работает|journalctl -u dnsdist|err' "$G/state"
# ufw удалён — замечание; DKMS нет — заголовков не ставим.
check grep -q '^note=ufw|удалён обновлением' "$G/state"
check neg grep -q 'linux-headers' "$OSFX/calls"
# Уборка.
check [ ! -e "$OSFX/fs/etc/apt/apt.conf.d/99goinstall-os-upgrade" ]
check [ ! -e "$U" ]
check [ ! -e "$G/runner.sh" ]
check grep -qx 'systemctl disable goinstall-os-upgrade.service' "$OSFX/calls"
check grep -qx 'Prompt=never' "$OSFX/fs/etc/update-manager/release-upgrades"
check [ -s "$G/log" ]
check [ -d "$G/before" ]
check [ "$(osst seen)" = 0 ]
check grep -q '── шаг: 20.04 → 22.04 (rel-20.04)' "$G/log"
check grep -q '── готово: Пакеты 20.04 за [0-9]* с' "$G/log"
# На 24.04 do-release-upgrade не зовётся никогда — даже со статусом «идёт».
sed -i.bak 's/^status=.*/status=running/' "$G/state"; : > "$OSFX/calls"
ox 'osup_run' >/dev/null
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
check [ "$(osst status)" = done ]

echo "── обновление Ubuntu: сбои исполнителя"
# do-release-upgrade не поднял выпуск — прервано без перезагрузки, служба выключена.
mkos 22.04; touch "$OSFX/dru-fail"; ox 'osup_start' >/dev/null; : > "$OSFX/calls"
ox 'osup_run; echo "rc=$?"' > "$OSFX/run1"
check grep -qx 'rc=1' "$OSFX/run1"
check [ "$(osst status)" = failed ]
check has "$(osst msg)" 'Could not calculate the upgrade'
check [ "$(oscalls '^systemctl reboot')" = 0 ]
check grep -qx 'systemctl disable goinstall-os-upgrade.service' "$OSFX/calls"
check [ ! -e "$OSFX/fs/etc/apt/apt.conf.d/99goinstall-os-upgrade" ]
check grep -qx 'Prompt=never' "$OSFX/fs/etc/update-manager/release-upgrades"
check grep -q '^t:dist-22.04=[0-9]* [0-9]*$' "$G/state"        # пакеты отмечены, прыжок — нет
check neg grep -q '^t:rel-22.04=[0-9]* [0-9]*$' "$G/state"
# Повтор: попытка 2, сделанное остаётся, прыжок идёт снова.
rm -f "$OSFX/dru-fail"; : > "$OSFX/calls"
check has "$(ox 'osup_start; echo "rc=$?"')" 'rc=0'
check [ "$(osst attempt)" = 2 ]
ox 'osup_run' >/dev/null
check [ "$(oscalls 'dist-upgrade')" = 0 ]
check [ "$(oscalls '^do-release-upgrade')" = 1 ]
check grep -qx 'VERSION_ID="24.04"' "$OSFX/os-release"
# Третья неудача — попыток больше нет.
mkos 22.04; mkdir -p "$G"; printf 'status=failed\nfrom=22.04\nattempt=3\n' > "$G/state"
check has "$(ox 'osup_start; echo "rc=$? $OSUP_ERR"')" 'rc=1 попыток больше нет'
# dist-upgrade с ошибкой — прервано, прыжка нет, перезагрузки нет.
mkos 22.04; echo 100 > "$OSFX/dist-rc"; ox 'osup_start' >/dev/null; : > "$OSFX/calls"
ox 'osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check has "$(osst msg)" 'dist-upgrade) вышло с кодом 100'
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
check [ "$(oscalls '^systemctl reboot')" = 0 ]
# Круг перезагрузок.
mkos 22.04; ox 'osup_start' >/dev/null; sed -i.bak 's/^reboots=.*/reboots=8/' "$G/state"; : > "$OSFX/calls"
ox 'osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check has "$(osst msg)" 'круг перезагрузок'
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
# dpkg недонастроен (обрыв) — dpkg --configure -a и apt-get -f install при старте.
mkos 22.04; ox 'osup_start' >/dev/null; : > "$OSFX/calls"
echo ' nginx-common  half-configured' > "$OSFX/audit"; touch "$OSFX/audit-fix"
ox 'osup_run' >/dev/null
check grep -qx 'dpkg --force-confdef --force-confold --configure -a' "$OSFX/calls"
check grep -q '^apt-get .* -f -y install$' "$OSFX/calls"
check [ "$(osst status)" = running ]
# …не помогло — прервано.
mkos 22.04; ox 'osup_start' >/dev/null; echo ' nginx-common  half-configured' > "$OSFX/audit"
ox 'osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check has "$(osst msg)" 'dpkg не в порядке и не восстановился'
# Прыжок оборвался (начат, выпуск прежний): пакеты заново и один повтор…
mkos 22.04; ox 'osup_start' >/dev/null
printf 't:dist-22.04=1 2\nt:rel-22.04=3\nn:rel-22.04=1\nstep=rel-22.04\n' >> "$G/state"; : > "$OSFX/calls"
ox 'osup_run' >/dev/null
check [ "$(oscalls 'dist-upgrade')" = 1 ]
check [ "$(oscalls '^do-release-upgrade')" = 1 ]
check [ "$(osst n:rel-22.04)" = 2 ]
# …второй обрыв — прервано.
mkos 22.04; ox 'osup_start' >/dev/null
printf 't:dist-22.04=1 2\nt:rel-22.04=3\nn:rel-22.04=2\nstep=rel-22.04\n' >> "$G/state"; : > "$OSFX/calls"
ox 'osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check has "$(osst msg)" 'оборвался дважды'
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
# Прыжок прошёл, отметка не успела — отметить и идти дальше.
mkos 20.04; ox 'osup_start' >/dev/null
printf 't:dist-20.04=1 2\nt:rel-20.04=3\nn:rel-20.04=1\nstep=rel-20.04\n' >> "$G/state"
osrel "$OSFX/os-release" ubuntu 22.04
ox 'osup_run' >/dev/null
check grep -q '^t:rel-20.04=3 [0-9]*$' "$G/state"
check [ "$(osst status)" = running ]
# Замок держат дольше ожидания — прыжка нет.
mkos 22.04; ox 'osup_start' >/dev/null
mkdir -p "$OSFX/fs/proc/77/fd"; ln -sf /var/lib/dpkg/lock "$OSFX/fs/proc/77/fd/4"; echo apt-get > "$OSFX/fs/proc/77/comm"
ox 'osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check has "$(osst msg)" 'замок apt держит apt-get'
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
# ufw активен — перед прыжком в 24.04 правила сохраняются.
mkos 22.04; echo 'Status: active' > "$OSFX/ufw-status"; ox 'osup_start' >/dev/null
ox 'osup_run' >/dev/null
check grep -qx 'netfilter-persistent save' "$OSFX/calls"
check [ "$(grep -n 'netfilter-persistent save\|^do-release-upgrade' "$OSFX/calls" | head -1 | cut -d: -f2)" = "netfilter-persistent save" ]

echo "── обновление Ubuntu: завершение — SSH, списки, docker, DKMS"
# SSH не слушает 2222 после прыжка — перезапуск ssh.socket возвращает его.
mkos 22.04; printf 'tcp   LISTEN 0      128          0.0.0.0:22      0.0.0.0:*    users:(("systemd",pid=1,fd=3))\n' > "$OSFX/ss-lost"
ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check grep -qx 'systemctl restart ssh.socket' "$OSFX/calls"
check grep -q '^did=SSH снова слушает 2222 (перезапущен ssh.socket)' "$G/state"
check [ "$(grep -n 'restart ssh.socket\|apt-get' "$OSFX/calls" | head -1 | cut -d: -f2)" = 'systemctl restart ssh.socket' ]   # SSH — первым
# …не вернулся — замечание err.
mkos 22.04; printf 'tcp   LISTEN 0      128          0.0.0.0:22      0.0.0.0:*    users:(("systemd",pid=1,fd=3))\n' > "$OSFX/ss-lost"; rm -f "$OSFX/ss-good"
ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; ox 'osup_run' >/dev/null
check grep -q '^note=SSH|не слушает порт 2222 — зайдите через консоль хостера|SSH: порт 2222|journalctl -u ssh.socket|err' "$G/state"
# Репозиторий без noble — список остаётся выключенным, замечание.
mkos 22.04; echo 'http://repo.powerdns.com/ubuntu/dists/noble-dnsdist-20/InRelease' > "$OSFX/curl-fail"; echo 'http://repo.powerdns.com/ubuntu/dists/noble-dnsdist-20/Release' >> "$OSFX/curl-fail"
ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; ox 'osup_run' >/dev/null
check [ -e "$SL/godns-dnsdist.list.distUpgrade" ]
check [ ! -e "$SL/godns-dnsdist.list" ]
check grep -q '^note=apt|источник godns-dnsdist: в репозитории нет выпуска для 24.04 — оставлен выключенным' "$G/state"
check [ -e "$SL/cloudflare-client.list" ]
# Флаг «не трогать источники» — только замечание.
mkos 22.04; GOINST_OSUP_FIX_LISTS=0 ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; GOINST_OSUP_FIX_LISTS=0 ox 'osup_run' >/dev/null
check [ -e "$SL/cloudflare-client.list.distUpgrade" ]
check grep -q '^note=apt|источник cloudflare-client выключен обновлением — верните его установщиком продукта' "$G/state"
# Контейнер не поднялся, DKMS — заголовки и пересборка.
mkos 22.04; touch "$OSFX/docker-lost"; printf 'amneziawg/1.0.0, 5.15.0-125-generic, x86_64: installed\n' > "$OSFX/dkms"
ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; ox 'osup_run' >/dev/null
check grep -q '^note=Docker|не поднялись контейнеры: amnezia-awg|' "$G/state"
check grep -q '^apt-get .*install linux-headers-6.8.0-85-generic$' "$OSFX/calls"
check grep -qx 'dkms autoinstall' "$OSFX/calls"
check grep -q '^did=модуль amneziawg собран под ядро 6.8.0-85-generic' "$G/state"

echo "── обновление Ubuntu: пока идёт — ничего не ставим"
mkos 22.04; mkdir -p "$G"; printf 'status=running\nfrom=22.04\nstarted=1\n' > "$G/state"; osunit
BUSY='идёт обновление Ubuntu — дождитесь окончания (goinstall покажет ход)'
check has "$(ox 'run_product_installer govless; echo "rc=$?"')" "$BUSY"
check has "$(ox 'run_product_installer govless; echo "rc=$?"')" 'rc=1'
check has "$(ox 'install_flow govless </dev/null')" "$BUSY"
check has "$(ox 'self_update; echo "rc=$?"')" "$BUSY"
# Копия вместо набора: удаление, если бы прошло, стёрло бы GOINST_BIN.
cp "$SCRIPT" "$OSFX/gi-bin"
check has "$(ox 'GOINST_BIN="$OSFX/gi-bin"; goinst_uninstall --yes; echo "rc=$?"')" 'rc=1'
check has "$(ox 'GOINST_BIN="$OSFX/gi-bin"; goinst_remove drop; echo "rc=$?"')" "$BUSY"
check [ -e "$OSFX/gi-bin" ]
check [ -d "$OSFX/gi" ]
check has "$(ox 'GOINST_APT_OK=1; comp_update all --yes; echo "rc=$?"')" "$BUSY"
check has "$(ox 'comp_refresh; echo "why=$COMP_REFRESH_WHY"')" "why=$BUSY"
check [ "$(oscalls '^apt-get')" = 0 ]
check [ "$(ox 'GOINST_NO_SELF_INSTALL=; GOINST_BIN="$OSFX/new-bin"; self_install; [ -e "$OSFX/new-bin" ] && echo written || echo kept')" = kept ]
out=$(PATH="$OSFX/bin:$PATH" GOINST_TEST=1 GOINST_LANG=ru GOINST_DIR="$OSFX/gi" GOINST_FS_ROOT="$OSFX/fs" GOINST_OS_RELEASE="$OSFX/os-release" GOINST_NO_SELF_INSTALL=1 bash "$SCRIPT" --install godns 2>&1 </dev/null; echo "rc=$?")
check has "$out" "$BUSY"
check has "$out" 'rc=1'
# «Аркада»: мастер и обновление компонентов — заметкой, без запуска.
NAVOS="$OSFX/os-release" PATH="$OSFX/bin:$PATH" NAVSTUB="GOINST_DIR='$OSFX/gi'" nav 3 1 q
check grep -q "$BUSY" "$NAV/out"
check neg grep -q '^RUN' "$NAV/act"

echo "── обновление Ubuntu: «Аркада»"
mkos 22.04
# o — предупреждение, курсор на «Назад»: Enter возвращает в меню, ничего не запущено.
NAVOS="$OSFX/os-release" PATH="$OSFX/bin:$PATH" nav o %osupg @0.6 '\n' q
check [ "$(navtr0)" = "o menu|enter osupg|q menu" ]
check grep -q 'Сначала бэкап' "$NAV/out"
check has "$(plain < "$NAV/out")" '▸ 0  Назад'
check neg grep -q 'systemctl start' "$NAV/act"
check [ ! -e "$NAV/gi/os-upgrade/state" ]
# Русская раскладка: щ — это o.
NAVOS="$OSFX/os-release" PATH="$OSFX/bin:$PATH" nav 'щ' 0 q
check [ "$(navtr0)" = "o menu|0 osupg|q menu" ]
check [ "$(rk 'щ')" = o ]
check [ "$(rk 'Щ')" = o ]
# 1 — запуск: служба включена и запущена, на экране ход.
NAVOS="$OSFX/os-release" PATH="$OSFX/bin:$PATH" nav o 1 @0.3 q
check [ "$(navtr0)" = "o menu|1 osupg|q osupg" ]
check grep -qx 'systemctl enable goinstall-os-upgrade.service' "$NAV/act"
check grep -qx 'systemctl start --no-block goinstall-os-upgrade.service' "$NAV/act"
check grep -qx 'status=running' "$NAV/gi/os-upgrade/state"
check grep -q 'Обновление Ubuntu идёт' "$NAV/out"
check grep -q 'Сервер перезагрузится сам' "$NAV/out"
rm -rf "$NAV/gi/os-upgrade" "$NAV/fs/etc"
errs=$(cat "$NAV/err-all")
for w in 'unbound variable' 'не заданы границы' 'command not found' 'команда не найдена' 'syntax error' 'синтаксическая ошибка' 'bad array subscript' 'неправильный индекс'; do
    check hasnt "$errs" "$w"
done

echo "── обновление Ubuntu: экраны на 80 и 46 колонках"
# os <ширина> <cur> <подготовка состояния> → дамп и «max=N rows=N»
osd() {
    ox "UI_C=$1; UI_R=24; ui_detect >/dev/null 2>&1; UI_C=$1; UI_R=24; UD_HOST=vpn-old-2; $3; ui_scr_osupg $2; ui_compose; ui_dump | cut -f1; m=0; for r in \"\${UI_ROWS[@]}\"; do ui_len \"\$r\"; [ \$UI_N -gt \$m ] && m=\$UI_N; done; echo \"max=\$m rows=\${#UI_ROWS[@]} items=\${#IT_KEY[@]}\""
}
mkos 20.04; mkdir -p "$G"; osunit
NOW=$(date +%s)
for w in 80 46; do
    rm -f "$G/state"
    out=$(osd "$w" 1 'osup_check 0')
    check has "$out" 'Сначала бэкап'
    check has "$out" '▸ 0  Назад'
    check has "$out" '1  Бэкап сделан — обновить до 24.04'
    check has "$out" "max=$w rows=24 items=2"
    check has "$out" '→  22.04  →  24.04 LTS'
    # Препятствие — пункта «1» нет.
    out=$(echo lxc > "$OSFX/cont"; osd "$w" 0 'osup_check 0'); rm -f "$OSFX/cont"
    check hasnt "$out" 'Бэкап сделан'
    check has "$out" "max=$w rows=24 items=1"
    printf 'status=running\nfrom=20.04\nstarted=%s\nt:dist-20.04=%s %s\nt:rel-20.04=%s %s\nt:boot-22.04=%s %s\nt:dist-22.04=%s %s\nt:rel-22.04=%s\nstep=rel-22.04\n' \
        $((NOW-2000)) $((NOW-2000)) $((NOW-1900)) $((NOW-1900)) $((NOW-1300)) $((NOW-1300)) $((NOW-1200)) $((NOW-1200)) $((NOW-1100)) $((NOW-840)) > "$G/state"
    printf 'Unpacking libc6:amd64 (2.39-0ubuntu8.6) over (2.35-0ubuntu3.11) ...\nSetting up openssh-server (1:9.6p1-3ubuntu13.13) ...\r\n' > "$G/log"
    out=$(osd "$w" 0 :)
    check has "$out" 'Обновление Ubuntu идёт'
    check has "$out" '✓ Пакеты 20.04'
    check has "$out" '● 22.04 → 24.04'
    check has "$out" 'идёт 14 мин'
    check has "$out" '○ Источники apt, служб'
    check has "$out" 'Setting up openssh-server'
    check has "$out" "max=$w rows=24 items=1"
    printf 'status=failed\nfrom=22.04\nattempt=1\nstarted=1\nt:dist-22.04=1 2\nt:rel-22.04=3\nstep=rel-22.04\nmsg=do-release-upgrade (код 1): Could not calculate the upgrade\n' > "$G/state"
    out=$(osd "$w" 2 :)
    check has "$out" 'Обновление Ubuntu прервано'
    check has "$out" '✗ do-release-upgrade (код 1)'
    check has "$out" '1  Попробовать снова'
    check has "$out" '2  Убрать отметку — обновлять не буду'
    check has "$out" '▸ 0  Назад'
    check has "$out" "max=$w rows=24 items=3"
    printf 'status=done\nfrom=20.04\nto=Ubuntu 24.04\nstarted=%s\nfinished=%s\nreboots=4\nseen=0\ndid=источник apt cloudflare-client снова включён — на noble\nnote=ufw|удалён обновлением|ufw удалён|iptables -S|warn\nnote=dnsdist|служба не запускается после обновления|dnsdist: не работает|journalctl -u dnsdist|err\n' $((NOW-1260)) "$NOW" > "$G/state"
    out=$(osd "$w" 0 :)
    check has "$out" 'Ubuntu обновлена до 24.04'
    check has "$out" 'за 21 мин'
    check has "$out" '· источник apt cloudflare-client'
    check has "$out" '✗ dnsdist: служба не запускается'
    check has "$out" "max=$w rows=24 items=1"
    check grep -qx 'seen=1' "$G/state"                   # итог открыт — просмотрен
done
# Карточка «o» в меню на 80 колонках: как экран 1 концепта.
mkos 20.04
out=$(ox 'UI_C=80; UI_R=24; ui_detect >/dev/null 2>&1; UI_C=80; UI_R=24; prod_readiness() { printf g:; }; ui_model_load >/dev/null 2>&1; ui_menu_items; for ((i=0;i<${#MI_KEY[@]};i++)); do [ "${MI_KEY[$i]}" = o ] && c=$i; done; ui_scr_menu $c; ui_compose; ui_dump | cut -f1')
check has "$out" '▸ o Ubuntu 20.04 → 24.04      ↑'
check has "$out" 'Ubuntu 20.04'
check has "$out" '↑ 2 шага'
check has "$out" 'одной кнопкой: 20.04 → 22.04 → 24.04'
check has "$out" 'СНАЧАЛА   снимок сервера у хостера'
check has "$out" 'Enter или o с любого экрана'

echo "── обновление Ubuntu: сводка при входе"
mkos 24.04; mkdir -p "$G"; osunit
smot() { ox "SUM_FILE='$OSFX/summary'; printf 'sved=10:00\nninst=1\nhost=vpn\nprob=goDNS pro|x|y|godns|err\n' > '$OSFX/summary'; GOINST_UI_SYS='1 2 0.1'; GOINST_UI_COLS=80; GOINST_UI_LINES=24; summary_print" | plain; }
printf 'status=running\nfrom=22.04\nstarted=%s\nt:dist-22.04=%s %s\nt:rel-22.04=%s\nstep=rel-22.04\n' $((NOW-900)) $((NOW-900)) $((NOW-840)) $((NOW-840)) > "$G/state"
out=$(smot)
check has "$out" '! Ubuntu'
check has "$out" 'обновляется до 24.04: шаг 2 из 4, идёт 14 мин'
check has "$out" 'goDNS pro'
printf 'status=failed\nfrom=22.04\nmsg=круг перезагрузок\n' > "$G/state"
check has "$(smot)" '✗ Ubuntu           обновление до 24.04 прервано: круг перезагрузок'
printf 'status=done\nfrom=22.04\nto=Ubuntu 24.04.3 LTS\nstarted=1000\nfinished=5680\nseen=0\nnote=goKaskad pro|после смены ОС проверьте правила и проброс|goKaskad pro: проверьте проброс|gokaskad|warn\n' > "$G/state"
out=$(smot)
check has "$out" '✓ Ubuntu           обновлена до 24.04.3 LTS за 1 ч 18 мин → goinstall'
check has "$out" '! goKaskad pro     после смены ОС проверьте правила и проброс → gokaskad'
sed -i.bak 's/^seen=0/seen=1/' "$G/state"
check hasnt "$(smot)" 'Ubuntu'
# Таймер сводки строк обновления в файл не пишет: они берутся вживую.
printf 'status=running\nfrom=22.04\nstarted=1\n' > "$G/state"
out=$(ox "SUM_FILE='$OSFX/summary2'; GOINST_UI_SYS='1 2 0.1'; GOINST_VER_CACHE='$OSFX/vc'; mkdir -p '$OSFX/vc'; summary_watch; cat '$OSFX/summary2'")
check hasnt "$out" 'prob=Ubuntu'

echo "── обновление Ubuntu: команда"
ocli() { PATH="$OSFX/bin:$PATH" GOINST_TEST=1 GOINST_LANG=ru GOINST_DIR="$OSFX/gi" GOINST_FS_ROOT="$OSFX/fs" GOINST_OS_RELEASE="$OSFX/os-release" \
    GOINST_SYSTEMD_DIR="$OSFX/fs/etc/systemd/system" GOINST_NO_SELF_INSTALL=1 GOINST_OSUP_CHECK_WAIT=0 GOINST_SS_FIXTURE="$OSFX/ss" GOINST_FAKE_INSTALLED="" \
    GOINST_BIN="$OSFX/goinstall" GOINST_BIN_ALIAS="$OSFX/go-installer" GOINST_PROFILE_HOOK="$OSFX/fs/etc/profile.d/goinstall-summary.sh" \
    bash "$SCRIPT" "$@" 2>&1; echo "rc=$?"; }
mkos 22.04
out=$(ocli --os-upgrade </dev/null)
check has "$out" 'Без терминала спросить некого: goinstall --os-upgrade --yes'
check has "$out" 'rc=4'                                   # 3 здесь — «уже идёт»
check [ ! -e "$OSFX/gi/os-upgrade/state" ]
check has "$(ocli --os-upgrade status </dev/null)" 'rc=0'
out=$(ocli --os-upgrade --yes </dev/null)
check has "$out" 'Сначала бэкап'
check has "$out" 'Обновление запущено службой goinstall-os-upgrade.service'
check has "$out" 'rc=0'
check has "$(ocli --os-upgrade status </dev/null)" 'rc=3'
check has "$(ocli --os-upgrade --yes </dev/null)" 'rc=3'
sed -i.bak 's/^status=.*/status=failed/' "$G/state"
check has "$(ocli --os-upgrade status </dev/null)" 'rc=1'
mkos 24.04
check has "$(ocli --os-upgrade --yes </dev/null)" 'rc=1'
check has "$(ocli --os-upgrade frobnicate </dev/null)" 'rc=64'
check has "$(bash "$SCRIPT" --help 2>&1)" 'goinstall --os-upgrade [--yes]'
check hasnt "$(bash "$SCRIPT" --help 2>&1)" 'os-upgrade-run'
# Нумерованное меню: «o» ведёт к обновлению, «2» на вопрос — ничего не запущено.
mkos 22.04
out=$(ox 'prod_readiness() { printf g:; }; printf "o\n2\n\n0\n" | main_menu 2>&1')
check has "$out" 'Бэкап сделан — обновить до 24.04?'
check has "$out" 'Отменено, ничего не менялось.'
check [ ! -e "$G/state" ]
# Страж: apt-get исполнителя — только update, dist-upgrade, -f install и
# install --no-install-recommends --no-remove, и только в osup_apt.
osa=$(code | sed -n '/^osup_apt()/,/^}/p' | grep -E '(^|[^-_[:alnum:]])apt-get([^-_[:alnum:]]|$)')
check [ "$(wc -l <<<"$osa" | tr -d ' ')" = 4 ]
check [ -z "$(grep -vE ' update ;;$| -y dist-upgrade ;;$| -f -y install ;;$| --no-install-recommends --no-remove install "\$@" ;;$' <<<"$osa")" ]
check [ -z "$(code | grep -n 'do-release-upgrade -f' | grep -v 'osup_run\|DistUpgradeViewNonInteractive >> "\$OSUP_LOG"')" ]

echo "── 1.1.0, второй круг: машина шагов обновления Ubuntu"
# Б-1. Оборванный прыжок 22.04→24.04: dist-upgrade по источникам noble сам
# доводит выпуск до 24.04 — do-release-upgrade на 24.04 не зовётся.
mkos 22.04; ox 'osup_start' >/dev/null
printf 't:dist-22.04=1 2\nt:rel-22.04=3\nn:rel-22.04=1\nstep=rel-22.04\n' >> "$G/state"; : > "$OSFX/calls"; touch "$OSFX/dist-bump"
ox 'osup_run' >/dev/null
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
check grep -qx 'VERSION_ID="24.04"' "$OSFX/os-release"
check [ "$(oscalls 'dist-upgrade')" -ge 2 ]                      # после обрыва и доводка на 24.04
check [ "$(osst status)" = done ]
check grep -q 'после пакетов выпуск 24.04' "$G/log"
# То же, если выпуск поднял первый же dist-upgrade (прыжок не начат).
mkos 22.04; ox 'osup_start' >/dev/null; : > "$OSFX/calls"; touch "$OSFX/dist-bump"
ox 'osup_run' >/dev/null; ox 'osup_run' >/dev/null
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
check [ "$(osst status)" = done ]
# Последняя сверка — в самой функции вызова: на 24.04 и при сменившемся выпуске отказ.
mkos 24.04
check [ "$(ox 'osup_dru 22.04; echo "rc=$?"' | tail -1)" = rc=99 ]
check [ "$(ox 'osup_dru 24.04; echo "rc=$?"' | tail -1)" = rc=99 ]
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
# Страж: do-release-upgrade зовётся в коде ровно одной строкой — в osup_dru.
check [ "$(code | grep -c 'do-release-upgrade -f')" = 1 ]
check [ "$(code | sed -n '/^osup_dru()/,/^}/p' | grep -c 'do-release-upgrade -f')" = 1 ]

# Б-2. Код 1 при выросшем выпуске: восстановление и dist-upgrade; чисто —
# дальше с замечанием в журнале, нет — прервано без перезагрузки.
mkos 22.04; touch "$OSFX/dru-rc1"; ox 'osup_start' >/dev/null; : > "$OSFX/calls"
ox 'osup_run' >/dev/null
check grep -qx 'dpkg --force-confdef --force-confold --configure -a' "$OSFX/calls"
check [ "$(grep -nE 'do-release-upgrade -f|dist-upgrade$|^systemctl reboot' "$OSFX/calls" | cut -d: -f2- | sed 's/^apt-get .*dist-upgrade$/dist/' | tr '\n' '|')" = 'dist|do-release-upgrade -f DistUpgradeViewNonInteractive|dist|systemctl reboot|' ]
check grep -q 'ЗАМЕЧАНИЕ: do-release-upgrade вышел с кодом 1, а выпуск уже 24.04' "$G/log"
check grep -q 'ЗАМЕЧАНИЕ: после кода 1 система доведена' "$G/log"
check [ "$(osst status)" = running ]
mkos 22.04; touch "$OSFX/dru-rc1" "$OSFX/dru-break"; ox 'osup_start' >/dev/null; : > "$OSFX/calls"
ox 'osup_run; echo "rc=$?"' > "$OSFX/run1"
check grep -qx 'rc=1' "$OSFX/run1"
check [ "$(osst status)" = failed ]
check has "$(osst msg)" 'система недонастроена — сервер не перезагружен'
check [ "$(oscalls '^systemctl reboot')" = 0 ]
check neg grep -q '^t:rel-22.04=[0-9]* [0-9]*$' "$G/state"
# Перезагрузка вообще не идёт в недонастроенную систему.
mkos 22.04; ox 'osup_start' >/dev/null; ox 'osup_load; echo " x  half-configured" > "$OSFX/audit"; osup_reboot test; echo "rc=$?"' > "$OSFX/run1"
check grep -qx 'rc=1' "$OSFX/run1"
check [ "$(oscalls '^systemctl reboot')" = 0 ]
check has "$(osst msg)" 'сервер не перезагружаю'
# systemctl reboot не прошёл — не «идёт» навсегда, а прервано с подсказкой.
mkos 22.04; touch "$OSFX/reboot-fail"; ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check has "$(osst msg)" 'перезагрузка не прошла'
# Перезагрузка «прошла», а сервер жив через отведённое время — тоже не «идёт» навсегда.
mkos 22.04; ox 'osup_start' >/dev/null; ox 'GOINST_OSUP_REBOOT_WAIT=1; osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check has "$(osst msg)" 'сервер не перезагрузился за 1 с'
check [ ! -e "$OSFX/fs/etc/systemd/system/goinstall-os-upgrade.service" ]

# С-1. «Идёт» без службы — прервано с причиной, запреты сняты.
mkos 22.04; ox 'osup_start' >/dev/null
check has "$(ox 'osup_busy && echo busy || echo free')" busy
rm -f "$OSFX/fs/etc/systemd/system/goinstall-os-upgrade.service"
check has "$(ox 'osup_busy && echo busy || echo free')" busy     # минута после запуска
osage
check has "$(ox 'osup_busy && echo busy || echo free')" free
check [ "$(osst status)" = running ]                            # на диске как было
out=$(ox 'OS_PRETTY=x; prod_readiness() { printf g:; }; menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}"; osup_probs; printf "%s\n" "${OSUP_PROBS[@]}"')
check has "$out" 'o|Ubuntu: обновление прервано|r:✗ прервано'
check has "$out" 'служба обновления не работает (goinstall-os-upgrade.service)'
check hasnt "$(ox 'run_product_installer govless 2>&1 </dev/null; echo "rc=$?"')" 'идёт обновление Ubuntu'
# enable не прошёл — после загрузки служба не пойдёт: тоже не «идёт».
mkos 22.04; touch "$OSFX/enable-fail"; ox 'osup_start' >/dev/null
check has "$(ox 'osup_busy && echo busy || echo free')" busy
osage
check has "$(ox 'osup_busy && echo busy || echo free')" free
check grep -q 'systemctl enable goinstall-os-upgrade.service: ошибка' "$G/log"
# Живой исполнитель держит «идёт» и без службы; «Попробовать снова» из «прервано» работает.
sleep 30 & SLP=$!; echo "$SLP" > "$G/run.pid"
check has "$(ox 'osup_busy && echo busy || echo free')" busy
kill "$SLP" 2>/dev/null; wait "$SLP" 2>/dev/null; rm -f "$OSFX/enable-fail"
check has "$(ox 'osup_start; echo "rc=$?"')" 'rc=0'
check [ "$(osst attempt)" = 2 ]
# З1 (третий круг). Исполнитель упал, служба включена — не «идёт» до
# перезагрузки, а «прервано»: dismiss и «Попробовать снова» работают.
mkos 22.04; ox 'osup_start' >/dev/null
check [ -e "$OSFX/enabled-goinstall-os-upgrade.service" ]
oscrash
check has "$(ox 'osup_busy && echo busy || echo free')" free
out=$(ox 'osup_cli status; echo "rc=$?"')
check has "$out" "исполнитель обновления упал — журнал $G/log"
check has "$out" 'rc=1'
check has "$(ox 'osup_start; echo "rc=$?"')" 'rc=0'
check [ "$(osst attempt)" = 2 ]
oscrash
check has "$(ox 'osup_cli dismiss; echo "rc=$?"')" 'rc=0'
check [ ! -e "$G/state" ]
check [ ! -e "$OSFX/enabled-goinstall-os-upgrade.service" ]
# Включена, не работает и без задания systemd — тоже упал; с заданием
# (ждёт network-online после загрузки) — идёт.
mkos 22.04; ox 'osup_start' >/dev/null
check has "$(ox 'osup_busy && echo busy || echo free')" busy
rm -f "$OSFX/job-goinstall-os-upgrade.service"
check has "$(ox 'osup_busy && echo busy || echo free')" busy   # отметка свежая
osage
check has "$(ox 'osup_busy && echo busy || echo free')" free
check has "$(ox 'osup_load; echo "${OSU[msg]}"')" 'исполнитель обновления упал'
# Н1 (четвёртый круг). «Попробовать снова» в той же загрузке: задание
# поставлено, а служба ещё failed — жив, а не «упал». Задание смотрится
# раньше failed (отметку состарили — держит именно задание).
mkos 22.04; ox 'osup_start' >/dev/null; oscrash
check has "$(ox 'osup_busy && echo busy || echo free')" free
echo 7 > "$OSFX/job-goinstall-os-upgrade.service"
check has "$(ox 'osup_busy && echo busy || echo free')" busy
check has "$(ox 'osup_load; echo "${OSU[status]}"')" running
# Окно между записью «идёт» и start --no-block: задания ещё нет, служба
# failed с прошлого раза или не включена — по свежей отметке жив.
mkos 22.04; ox 'osup_start' >/dev/null
k=$(osst kick); n=$(date +%s)
check [ -n "$k" ]; check [ $(( n - ${k:-0} )) -lt 5 ]
echo failed > "$OSFX/active-goinstall-os-upgrade.service"; rm -f "$OSFX/job-goinstall-os-upgrade.service"
check has "$(ox 'osup_busy && echo busy || echo free')" busy
rm -f "$OSFX/enabled-goinstall-os-upgrade.service" "$OSFX/active-goinstall-os-upgrade.service"
check has "$(ox 'osup_busy && echo busy || echo free')" busy
osage
check has "$(ox 'osup_busy && echo busy || echo free')" free
check has "$(ox 'osup_load; echo "${OSU[msg]}"')" 'служба обновления не работает'
# Отметка в будущем (часы перевели назад) жизнь не продлевает.
f="$OSFX/gi/os-upgrade/state"; sed "s/^kick=.*/kick=$(( n + 600 ))/" "$f" > "$f.t" && mv "$f.t" "$f"
check has "$(ox 'osup_busy && echo busy || echo free')" free

# С-2. Процесс исчез посреди обхода /proc — держатель замка всё равно найден.
mkos 22.04
mkdir -p "$OSFX/fs/proc/11/fd" "$OSFX/fs/proc/77/fd"; chmod 000 "$OSFX/fs/proc/11/fd"
ln -sf /var/lib/dpkg/lock-frontend "$OSFX/fs/proc/77/fd/4"; echo apt-get > "$OSFX/fs/proc/77/comm"
check [ "$(ox 'set -o pipefail; osup_lock_holder')" = "77 apt-get" ]
chmod 755 "$OSFX/fs/proc/11/fd"
# Страж: в osup_lock_holder нет конвейера.
check [ -z "$(code | sed -n '/^osup_lock_holder()/,/^}/p' | grep -E '(^|[^|])[|]([^|]|$)')" ]

# С-3. Пакеты просят перезагрузку перед прыжком — перезагрузка, прыжок не начат.
mkos 22.04; ox 'osup_start' >/dev/null
printf 't:dist-22.04=1 2\n' >> "$G/state"; : > "$OSFX/fs/var/run/reboot-required"; : > "$OSFX/calls"
ox 'osup_run' >/dev/null
check [ "$(oscalls '^systemctl reboot')" = 1 ]
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
check neg grep -q '^t:rel-22.04=' "$G/state"
check [ "$(osst reboots)" = 1 ]
ox 'osup_run' >/dev/null
check [ "$(oscalls '^do-release-upgrade -f')" = 1 ]
# «Попробовать снова» идёт тем же путём.
mkos 22.04; touch "$OSFX/dru-fail"; ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; rm -f "$OSFX/dru-fail"
: > "$OSFX/fs/var/run/reboot-required"; : > "$OSFX/calls"
ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null
check [ "$(oscalls '^systemctl reboot')" = 1 ]
check [ "$(oscalls '^do-release-upgrade')" = 0 ]

# С-4. Прыжок оборвался после base-files: восстановление, dist-upgrade,
# перезагрузка — и только потом отметка и завершение.
mkos 22.04; ox 'osup_start' >/dev/null
printf 't:dist-22.04=1 2\nt:rel-22.04=3\nn:rel-22.04=1\nstep=rel-22.04\n' >> "$G/state"
osrel "$OSFX/os-release" ubuntu 24.04; : > "$OSFX/fs/var/run/reboot-required"; : > "$OSFX/calls"
ox 'osup_run' >/dev/null
check [ "$(grep -nE 'configure -a|-f -y install$|dist-upgrade$|^systemctl reboot' "$OSFX/calls" | cut -d: -f2- | sed 's/^dpkg.*/dpkg/; s/^apt-get .*install$/fix/; s/^apt-get .*dist-upgrade$/dist/' | tr '\n' '|')" = 'dpkg|fix|dist|systemctl reboot|' ]
check grep -q '^t:rel-22.04=3$' "$G/state"                      # ещё не отмечен
check [ "$(osst status)" = running ]
check [ "$(osst step)" = boot-24.04 ]
ox 'osup_run' >/dev/null
check grep -q '^t:rel-22.04=3 [0-9]*$' "$G/state"
check [ "$(osst status)" = done ]
check [ "$(oscalls '^do-release-upgrade')" = 0 ]
# dist-upgrade доводки не прошёл — прервано, без перезагрузки.
mkos 22.04; ox 'osup_start' >/dev/null
printf 't:dist-22.04=1 2\nt:rel-22.04=3\nn:rel-22.04=1\nstep=rel-22.04\n' >> "$G/state"
osrel "$OSFX/os-release" ubuntu 24.04; echo 100 > "$OSFX/dist-rc"; : > "$OSFX/calls"
ox 'osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check [ "$(oscalls '^systemctl reboot')" = 0 ]
check has "$(osst msg)" 'не перезагружаю'
# Повтор после такого сбоя — на 24.04 можно: прыжок остаётся начатым, его доведут.
rm -f "$OSFX/dist-rc"
check has "$(ox 'osup_start; echo "rc=$? $OSUP_ERR"')" 'rc=0 '
check grep -q '^t:rel-22.04=3$' "$G/state"
ox 'osup_run' >/dev/null
check [ "$(osst status)" = done ]

echo "── 1.1.0, второй круг: ход при входе, копия скрипта, мелочи исполнителя"
# З-1. Временный скрипт входа: ставится запуском, молчит при включённой
# сводке, уходит после просмотра итога и при снятии отметки.
mkos 22.04; HK="$OSFX/fs/etc/profile.d/goinstall-osupgrade.sh"
check has "$(ox 'osup_check 0; printf "%s\n" "${OSUP_CHK[@]}"')" 'do|на время обновления покажет ход при входе по SSH (/etc/profile.d/goinstall-osupgrade.sh, уберётся сам)'
ox 'osup_start' >/dev/null
check [ -f "$HK" ]
for w in '[ -t 0 ] && [ -t 1 ]' '"$(id -u)" = 0' '.hushlogin' 'goinstall --os-upgrade status --short'; do check grep -qF -- "$w" "$HK"; done
check has "$(ox 'osup_short')" 'goInstaller · Ubuntu: обновляется до 24.04: шаг 1 из 4'
check [ -z "$(ox "SUM_CHOICE='$OSFX/sc'; SUM_HOOK='$OSFX/sh'; SUM_FILE='$OSFX/sf'; echo yes > \"\$SUM_CHOICE\"; : > \"\$SUM_HOOK\"; : > \"\$SUM_FILE\"; osup_short")" ]
# Командой, как зовёт скрипт входа: без сети, без проверок.
out=$(PATH="$OSFX/bin:$PATH" GOINST_DIR="$OSFX/gi" GOINST_FS_ROOT="$OSFX/fs" GOINST_LANG=ru GOINST_COLOR=none bash "$SCRIPT" --os-upgrade status --short 2>&1)
check has "$out" 'Ubuntu: обновляется до 24.04'
ox 'osup_run' >/dev/null; ox 'osup_run' >/dev/null
check [ "$(osst status)" = done ]
check [ -f "$HK" ]
check has "$(ox 'osup_short' | plain)" '✓ goInstaller · Ubuntu: обновлена до'
ox 'osup_mark_seen' >/dev/null
check [ ! -e "$HK" ]
# З-2. Запуск из bash <(…) со старым goinstall — отказ до всего.
mkos 22.04; printf '#!/bin/bash\nGOINST_VERSION="1.0.12"\n' > "$OSFX/old-goinstall"
out=$(ox "GOINST_SELF_PATH=/dev/fd/63; GOINST_BIN='$OSFX/old-goinstall'; osup_start; echo \"rc=\$? \$OSUP_ERR\"")
check has "$out" 'rc=1 сначала обновите команду goinstall (запустите goinstall)'
check [ ! -e "$OSFX/fs/etc/systemd/system/goinstall-os-upgrade.service" ]
check [ ! -e "$G/state" ]
check [ ! -e "$G/runner.sh" ]
cp "$SCRIPT" "$OSFX/new-goinstall"
check has "$(ox "GOINST_SELF_PATH=/dev/fd/63; GOINST_BIN='$OSFX/new-goinstall'; osup_start; echo \"rc=\$?\"")" 'rc=0'
check cmp -s "$SCRIPT" "$G/runner.sh"
# З-3. Строка nginx -t доходит до замечания.
mkos 22.04; printf 'ssh.socket\n' > "$OSFX/restart-ok"; ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; ox 'osup_run' >/dev/null
check grep -q '^note=nginx|не запускается: \[emerg\] unknown directive "stream"' "$G/state"
# З-4. Общая транзакция не прошла — по одному: libnginx-mod-stream встаёт.
mkos 22.04; ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null
grep -v '^curl|' "$OSFX/dpkg" > "$OSFX/d.t"; mv "$OSFX/d.t" "$OSFX/dpkg"; echo 'curl=8.5.0-2ubuntu10' >> "$OSFX/cand"; echo curl > "$OSFX/install-fail-pkg"
ox 'osup_run' >/dev/null
check grep -q '^apt-get .*--no-remove install libnginx-mod-stream curl$' "$OSFX/calls"
check grep -q '^apt-get .*--no-remove install libnginx-mod-stream$' "$OSFX/calls"
check grep -q '^did=поставлены снова: libnginx-mod-stream$' "$G/state"
check grep -q '^note=apt|не поставились снова: curl|' "$G/state"
# З-5. ListenAddress host:port и [v6]:port — порты SSH.
mkos 22.04
# Голый адрес («::», fe80::1) своего порта не задаёт и слушает порты Port —
# по умолчанию 22, как у sshd (sshd -T покажет [::]:22).
printf 'ListenAddress 0.0.0.0:2222\nListenAddress [::]:2223\nListenAddress ::\nListenAddress fe80::1\n' > "$OSFX/fs/etc/ssh/sshd_config"
check [ "$(ox 'osup_ssh_cfg_ports')" = "22 2222 2223 " ]
printf 'Port 2200\nListenAddress 10.0.0.1\n' > "$OSFX/fs/etc/ssh/sshd_config"
check [ "$(ox 'osup_ssh_cfg_ports')" = "2200 " ]
printf 'tcp   LISTEN 0      128          0.0.0.0:2222      0.0.0.0:*    users:(("systemd",pid=1,fd=3))\n' > "$OSFX/ss"
printf 'ListenAddress 0.0.0.0:2222\n' > "$OSFX/fs/etc/ssh/sshd_config"
check [ "$(ox 'osup_ssh_ports')" = 2222 ]                         # systemd на ssh.socket — засчитан
# Придирки: числа из state — только цифрами; два исполнителя сразу не идут.
mkos 22.04; ox 'osup_start' >/dev/null
sed -i.bak 's/^reboots=.*/reboots=1x/; s/^attempt=.*/attempt=$(id)/' "$G/state"; printf 'n:rel-22.04=zz\nt:dist-22.04=a b\n' >> "$G/state"
ox 'osup_run' > "$OSFX/run1"
check [ "$(osst reboots)" = 1 ]
check hasnt "$(cat "$OSFX/run1")" 'unbound variable'
check hasnt "$(cat "$OSFX/run1")" 'syntax error'
mkos 22.04; ox 'osup_start' >/dev/null; : > "$OSFX/calls"
sleep 30 & SLP=$!; echo "$SLP" > "$G/run.pid"
ox 'osup_run' >/dev/null
check [ "$(oscalls '^apt-get')" = 0 ]
check grep -q 'исполнитель уже работает (pid' "$G/log"
kill "$SLP" 2>/dev/null; wait "$SLP" 2>/dev/null
printf '#!/bin/sh\nexit 1\n' > "$OSFX/bin/flock"; chmod +x "$OSFX/bin/flock"
ox 'osup_run' >/dev/null
check [ "$(oscalls '^apt-get')" = 0 ]
check grep -q 'исполнитель уже работает — второй не запускаю' "$G/log"
rm -f "$OSFX/bin/flock"
ox 'osup_run' >/dev/null
check [ "$(oscalls 'dist-upgrade')" = 1 ]
check [ ! -e "$G/run.pid" ]

echo "── 1.1.0, второй круг: запреты, «прервано», признак зависания"
# З-6. Меню продукта во время обновления — заметкой, без запуска (оба меню).
mkos 22.04; mkdir -p "$G"; printf 'status=running\nfrom=22.04\nstarted=1\n' > "$G/state"; osunit
NAVOS="$OSFX/os-release" PATH="$OSFX/bin:$PATH" NAVSTUB="GOINST_DIR='$OSFX/gi'" nav 1 1 q
check [ "$(navtr0)" = "1 menu|1 product|q product" ]
check grep -q "$BUSY" "$NAV/out"
check neg grep -q '^OPEN' "$NAV/act"
out=$(OSINST=govless ox 'FAKE_RAN=""; prod_cmd() { echo true; }; printf "1\n\n0\n" | product_menu govless 2>&1')
check has "$out" "$BUSY"
# --net и предложение размера пакета — во время обновления не трогают сеть.
out=$(PATH="$OSFX/bin:$PATH" GOINST_TEST=1 GOINST_LANG=ru GOINST_DIR="$OSFX/gi" GOINST_FS_ROOT="$OSFX/fs" GOINST_OS_RELEASE="$OSFX/os-release" GOINST_NO_SELF_INSTALL=1 bash "$SCRIPT" --net 2>&1 </dev/null; echo "rc=$?")
check has "$out" "$BUSY"
check has "$out" 'rc=1'
check [ "$(ox 'GOINST_NET_TEST=1; net_mtu_probe() { echo PROBE; return 1; }; net_mtu_offer; echo "rc=$?"')" = rc=0 ]
# З-8. Шаг идёт больше часа, журнал не растёт 20 минут — строка warn.
NOW=$(date +%s)
printf 'status=running\nfrom=22.04\nstarted=%s\nt:dist-22.04=%s %s\nt:rel-22.04=%s\nstep=rel-22.04\n' $((NOW-5000)) $((NOW-5000)) $((NOW-4900)) $((NOW-4900)) > "$G/state"
echo x > "$G/log"; echo y > "$OSFX/fs/var/log/dist-upgrade/main.log"
touch -t "$(date -r $((NOW-1800)) +%Y%m%d%H%M.%S)" "$G/log" "$OSFX/fs/var/log/dist-upgrade/main.log"
out=$(osd 80 0 :)
check has "$out" 'журнал не растёт 30 мин — возможно, зависло:'
check has "$out" '/var/log/dist-upgrade/main.log'
check has "$(ox 'osup_print_state 2>&1')" 'журнал не растёт 30 мин'
touch "$OSFX/fs/var/log/dist-upgrade/main.log"
check hasnt "$(osd 80 0 :)" 'журнал не растёт'
# Придирка: «✓ Ubuntu обновлена» — не замечание в значке приглашения.
check [ -z "$(ml 'UD_NEWS=(); UD_PROB=("Ubuntu|обновлена|Ubuntu 24.04: готово|goinstall|ok"); ui_badge; printf "%s" "$UI_BADGE"')" ]
check has "$(ml 'UD_NEWS=(); UD_PROB=("Ubuntu|обновлена|x|goinstall|ok" "nginx|не запускается|x|nginx -t|err"); ui_badge; printf "%s" "$UI_BADGE"')" '!1'
# З-7. «Прервано» можно убрать: состояние уходит в state.failed-*, журнал
# остаётся, скрипт входа и служба сняты; пункт на 22.04 снова «обновить».
mkos 22.04; touch "$OSFX/dru-fail"; ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check [ -f "$OSFX/fs/etc/profile.d/goinstall-osupgrade.sh" ]
check has "$(ox 'osup_short' | plain)" '✗ goInstaller · Ubuntu: обновление до 24.04 прервано'
out=$(PATH="$OSFX/bin:$PATH" GOINST_TEST=1 GOINST_LANG=ru GOINST_DIR="$OSFX/gi" GOINST_FS_ROOT="$OSFX/fs" GOINST_OS_RELEASE="$OSFX/os-release" GOINST_SYSTEMD_DIR="$OSFX/fs/etc/systemd/system" GOINST_NO_SELF_INSTALL=1 bash "$SCRIPT" --os-upgrade dismiss 2>&1 </dev/null; echo "rc=$?")
check has "$out" 'Отметка «прервано» снята'
check has "$out" 'rc=0'
check [ ! -e "$G/state" ]
check [ -n "$(ls "$G"/state.failed-* 2>/dev/null)" ]
check [ -s "$G/log" ]
check [ ! -e "$OSFX/fs/etc/profile.d/goinstall-osupgrade.sh" ]
check has "$(ox 'OS_PRETTY=x; prod_readiness() { printf g:; }; menu_items_main; printf "%s\n" "${MENU_ITEMS[@]}"')" 'o|Ubuntu 22.04 → 24.04|g:↑ 24.04'
# «Аркада»: на экране прерванного 2 — убрать; курсор по умолчанию — «Назад».
mkos 22.04; touch "$OSFX/dru-fail"; ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null
cp -R "$OSFX/gi/os-upgrade" "$NAV/gi/" 2>/dev/null
NAVOS="$OSFX/os-release" PATH="$OSFX/bin:$PATH" nav o %osupg @0.6 '\n' q
check [ "$(navtr0)" = "o menu|enter osupg|q menu" ]
check [ -f "$NAV/gi/os-upgrade/state" ]                          # Enter — «Назад», отметка на месте
NAVOS="$OSFX/os-release" PATH="$OSFX/bin:$PATH" nav o %osupg 2 q
check [ "$(navtr0)" = "o menu|2 osupg|q menu" ]
check [ ! -e "$NAV/gi/os-upgrade/state" ]
check grep -q 'Отметка снята' "$NAV/out"
rm -rf "$NAV/gi/os-upgrade"
# Нумерованное меню: 2 — убрать отметку.
mkos 22.04; touch "$OSFX/dru-fail"; ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null
out=$(ox 'printf "2\n\n" | osup_menu 2>&1' | plain)
check has "$out" '2) Убрать отметку — обновлять не буду'
check has "$out" 'Отметка снята'
check [ ! -e "$G/state" ]

echo "── 1.1.0, второй круг: отказ по ОС зовёт к пункту «o»"
out=$(pf_env ss-empty units-empty nginx-empty os-ubuntu2204 "" 'preflight govless pro 2>&1')
check has "$out" 'Ставить нельзя: на этой системе goVLESS pro не ставится'
check has "$out" 'Обновить Ubuntu до 24.04 можно из меню goinstall — пункт o (или goinstall --os-upgrade).'
check hasnt "$(pf_env ss-empty units-empty nginx-empty os-debian11 "" 'preflight govless pro 2>&1')" 'пункт o'
check hasnt "$(pf_env ss-empty units-empty nginx-empty os-ubuntu2404 "" 'preflight govless pro 2>&1')" 'пункт o'
# Отказ по архитектуре обновлением не лечится — к пункту не зовём.
check hasnt "$(ARCH=aarch64 pf_env ss-empty units-empty nginx-empty os-ubuntu2204 "" 'preflight goamnezia lite 2>&1')" 'пункт o'
# Карточка «Аркады»: под ИТОГ — и куда идти.
out=$(pf_env ss-empty units-empty nginx-empty os-ubuntu2204 "" 'ui_model_load >/dev/null 2>&1; echo "${UD_VWHY[0]}"')
check has "$out" 'обновить Ubuntu: пункт o'
# Нумерованное меню: отказ только по ОС — к карте портов не зовёт.
out=$(pf_env ss-empty units-empty nginx-empty os-ubuntu2204 "" 'printf "\n\n\n" | install_flow govless 2>&1')
check has "$out" 'на этой системе goVLESS pro не ставится'
check hasnt "$out" 'Карта портов'
check has "$(pf_env ss-govless units-govless nginx-govless os-ubuntu2404 govless 'printf "\n\n\n" | install_flow gotelegram 2>&1')" 'Карта портов'

echo "── 1.1.0, второй круг: без ключа опроса нет, ширина нумерованного меню, размер пакета"
# Без ключа меню не опрашивает GitHub — ни сразу, ни по таймеру.
NAVNET=1 NAVTOKEN= NAVREFRESH=1 nav 2 @2.5 q
check [ "$(navtr0)" = "2 nokey|q menu" ]
check neg grep -qx POLL "$NAV/act"
NAVNET=1 NAVREFRESH=1 nav @2.5 q
check grep -qx POLL "$NAV/act"                                     # с ключом — опрашивает
check [ "$(ml 'TOKEN=""; GOINST_NO_NET=""; ui_poll_start; echo "rc=$? dir=${UI_POLLDIR:-}"')" = "rc=1 dir=" ]
check hasnt "$(mi 180 '' '')" 'обновляются сами'
check has "$(mi 180 '' t)" 'обновляются сами'
check has "$(code | sed -n '/^ui_main()/,/^}/p' | grep -B1 'ui_poll_start; last_poll=\$SECONDS' | head -1)" '[ -n "${TOKEN:-}" ]'
# Нумерованное главное меню на 80 колонках с сетью: описания продуктов на месте,
# длинные служебные подписи целиком, строки не шире окна.
for lg in ru en; do
    out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=$lg GOINST_TEST=1 GOINST_COLOR=none GOINST_OS_RELEASE="$T/os-ubuntu2204" GOINST_SS_FIXTURE="$T/ss-empty" \
        GOINST_UNIT_FIXTURE="$T/units-empty" GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_FAKE_INSTALLED="" GOINST_LE_ROOT="$T/le-empty" GOINST_DOCKER_FIXTURE="$T/docker-empty" \
        bash -c ". '$SCRIPT'; os_detect; TOKEN=t; COLUMNS=80; tput() { return 1; }; prod_readiness() { printf g:ok; }; VER_NET_OK=yes; VER_NET_TRIED=yes
            menu_items_main; menu_build_rows; for i in \"\${!MENU_ROW[@]}\"; do printf '  %s) %b\n' \"\${MENU_KEY[\$i]}\" \"\${MENU_ROW[\$i]}\"; done
            for id in \"\${PRODUCTS[@]}\"; do d=\$(prod_desc \"\$id\"); printf 'DESC %s\n' \"\${d:0:12}\"; done" 2>&1 | sed $'s/\033\\[[0-9;]*m//g')
    rows=$(grep -v '^DESC ' <<<"$out")
    check [ "$(python3 -c 'import sys; print(max(len(l.rstrip("\n")) for l in sys.stdin))' <<<"$rows")" -le 80 ]
    while IFS= read -r d; do check has "$rows" "${d#DESC }"; done < <(grep '^DESC ' <<<"$out")
    check [ "$(grep -c '^DESC ' <<<"$out")" = 6 ]
    if [ "$lg" = ru ]; then
        check has "$rows" 'r) Обновить сведения о версиях'
        check has "$rows" 'o) Ubuntu 22.04 → 24.04  ↑ 24.04'
        check has "$rows" 'x) Удалить goInstaller'
    else
        check has "$rows" 'r) Refresh version info'
    fi
    # П8 (третий круг): пояснения r) и x) — в той же колонке, что у p) и l).
    cols=$(python3 -c '
import sys
d={"ru":("кто какие","спросить","продукты","сменить"),"en":("who holds","ask GitHub","products stay","change the")}[sys.argv[1]]
rows=sys.stdin.read().splitlines()
print(" ".join(str(next(l.index(w) for l in rows if w in l)) for w in d))' "$lg" <<<"$rows")
    check [ "$(tr ' ' '\n' <<<"$cols" | sort -u | grep -c '')" = 1 ]
done
# Размер пакета: к «немому» адресу — ровно две пробы за всё предложение,
# проверка после правки — тот же адрес; поиск размера потерял ответ — своя причина.
rm -f "$T/net/"*
printf '1\n' | mtu2 'net_mtu_offer' >/dev/null 2>&1
check [ "$(grep -c '^20.250.119.72 ' "$T/net/pings")" = 2 ]
check [ "$(grep -vc '^140.82.121.5 \|^20.250.119.72 ' "$T/net/pings")" = 0 ]
check neg grep -q 'keep' <(code | sed -n '/^net_mtu_probe()/,/^}/p')
rm -f "$T/net/"*
out=$(NETLOG="$T/net/pings" nt 1452 '_net_resolve() { printf "5.5.5.5\n"; }; _net_ping_df() { echo "$1 $2" >> "$NETLOG"; [ "$2" = 1200 ] && [ ! -e "$T/net/once" ] && { : > "$T/net/once"; return 0; }; return 1; }
    net_mtu_probe; echo "rc=$? why=$NET_WHY"; net_why_text' 2>&1)
check has "$out" 'rc=2 why=lost'
check has "$out" 'ответил на ping 1200 байт, а при поиске размера перестал'

echo "── 1.1.0, второй круг: по живой проверке на Aeza 24.04"
# Проба размера пакета: первая ICMP потерялась, вторая прошла — предложение есть.
rm -f "$T/net/"*
out=$(NETLOG="$T/net/pings" nt 1452 '_net_resolve() { printf "140.82.121.5\n"; }
    _p0="$(declare -f _net_ping_df)"; eval "${_p0/_net_ping_df/_ping0}"
    _net_ping_df() { echo "$1 $2" >> "$NETLOG"; if [ "$2" = 1200 ] && [ ! -e "$T/net/lost1" ]; then : > "$T/net/lost1"; return 1; fi; _ping0 "$@"; }
    net_mtu_probe; echo "rc=$? ip=$NET_IP pmtu=$NET_PMTU"')
check has "$out" 'rc=1 ip=140.82.121.5 pmtu=1452'
check [ "$(grep -c '^140.82.121.5 1200$' "$T/net/pings")" -ge 2 ]
# Потолок пробы на старте — общий: исчерпан — дальше не пробуем.
rm -f "$T/net/"*
check has "$(GOINST_NET_PICK_MAX=0 NETLOG="$T/net/pings" nt 1452 '_net_ping_df() { echo "$1 $2" >> "$NETLOG"; return 1; }; net_mtu_pick; echo "rc=$? why=$NET_WHY"')" 'rc=1 why=mute'
check [ ! -s "$T/net/pings" ]
# Строка mtu в interfaces — с отступом соседних строк блока.
printf 'auto enp0s3\niface enp0s3 inet static\n  address 81.19.137.150/24\n  gateway 81.19.137.1\n  dns-nameservers 8.8.8.8\n' > "$NETFS/etc/network/interfaces"
nt 1456 'net_persist_ifupdown enp0s3 1456' >/dev/null 2>&1
check [ "$(sed -n '/^iface enp0s3/{n;p;}' "$NETFS/etc/network/interfaces")" = "  mtu 1456" ]
check [ "$(grep -c 'mtu' "$NETFS/etc/network/interfaces")" = 1 ]
nt 1452 'net_persist_ifupdown enp0s3 1452' >/dev/null 2>&1
check [ "$(grep -c 'mtu' "$NETFS/etc/network/interfaces")" = 1 ]
check grep -qx '  mtu 1452' "$NETFS/etc/network/interfaces"
check grep -qx '  address 81.19.137.150/24' "$NETFS/etc/network/interfaces"
printf 'auto ens5\niface ens5 inet dhcp\n' > "$NETFS/etc/network/interfaces"
nt 1452 'net_persist_ifupdown ens5 1452' >/dev/null 2>&1
check [ "$(tail -1 "$NETFS/etc/network/interfaces")" = "    mtu 1452" ]
rm -f "$NETFS"/etc/network/interfaces.bak-goinstall-*
# Подтверждение компонентов: имена не влезли — «и ещё N», а не молча.
out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 bash -c ". '$SCRIPT'; ui_detect >/dev/null 2>&1; UI_CSEL=0; CA_NAME=(nftables); CA_VER=(1.0.9-1build1); CA_CAND=(1.0.9-1ubuntu0.1); CA_NOTE=(''); COMP_DRY_ERR=''; COMP_DRY_KEPT=''
    COMP_DRY_INST='git git-man libnftables1 nftables python3.12 python3.12-minimal libpython3.12-stdlib libpython3.12-minimal libpython3.12t64 openssl libssl3t64 ca-certificates curl libcurl4t64 libcurl3t64-gnutls'
    ui_scr_compconfirm 0; ui_compose; ui_dump | cut -f1")
check has "$out" 'apt обновит пакетов: 15'
check has "$out" 'libpython3.12t64 и ещё 6'
check hasnt "$out" 'libcurl3t64-gnutls'
# Свежесть списков — время последней удачной проверки, а не mtime Release.
out=$(APREP='touch -t 202601020304 "$AP/lists/"*' ap 'comp_refresh >/dev/null; comp_lists_age; comp_lists_when; comp_lists_stale && echo stale || echo fresh; echo "$COMP_LISTS_TXT"; ls -l "$GOINST_DIR"/logs/components-*.log | cut -c1-10')
check has "$out" 'fresh'
check has "$out" "$(date +%H:)"
check has "$out" '-rw-------'
check [ "$(APREP='touch -t 202601020304 "$AP/lists/"*; mkdir -p "$AP/fs/var/lib/apt/periodic"; touch "$AP/fs/var/lib/apt/periodic/update-success-stamp"' ap 'comp_lists_age; comp_lists_stale && echo stale || echo fresh')" = fresh ]
check [ "$(APREP='touch -t 202601020304 "$AP/lists/"*; mkdir -p "$AP/fs/var/cache/apt"; touch "$AP/fs/var/cache/apt/pkgcache.bin"' ap 'comp_lists_age; comp_lists_stale && echo stale || echo fresh')" = fresh ]
check [ "$(APREP='touch -t 202601020304 "$AP/lists/"*; echo 100 > "$AP/update-rc"' ap 'comp_refresh >/dev/null; comp_lists_age; comp_lists_stale && echo stale || echo fresh')" = stale ]
# Итог по компоненту называется так же, как строка таблицы.
out=$(APREP='echo "python3.12=3.12.3-1ubuntu0.17" >> "$AP/cand"' ap 'comp_update python3 --yes 2>&1')
check has "$out" 'python 3.12: '
check hasnt "$out" 'python3: '

echo "── 1.1.0, второй круг: сверка итога одной проверкой, Enter после правки размера пакета"
# installer_verdict — одна проверка для --install, нумерованного меню и «Аркады».
iv() { ml "prod_installed() { ${1:-return 0}; }; prod_free_edition() { ${2:-return 1}; }; prod_installed_ref() { ${3:-echo main}; }; prod_version() { echo 1.1; }; ver_cache_get() { ${4:-echo 1.1}; }; installer_verdict godns main ${5:-0}; echo \"rc=\$? \$PC_WHY|\$PC_ST|\$PC_TX\""; }
check has "$(iv)" 'rc=0 ok|ok|Проверено: goDNS pro стоит с ветки main, версия 1.1.'
check has "$(iv '' '' '' '' 3)" 'rc=1 rc|err|Установщик goDNS pro вышел с кодом 3: установка не закончена.'
check has "$(iv 'return 1')" 'rc=1 none|err|goDNS pro не встал'
check has "$(iv '' 'echo Lite')" 'rc=1 free|warn|Вместо goDNS pro по-прежнему бесплатный Lite'
check has "$(iv '' '' 'echo dev')" 'rc=1 ref|warn|Ветка не сменилась: goDNS pro стоит с ветки dev, а выбрана main.'
check has "$(iv '' '' '' 'echo 1.2')" 'rc=1 ver|warn|Стоит версия 1.1, а в ветке main лежит 1.2'
# Стоит новее кеша (в ветку пришёл коммит после опроса) — норма, без «!»;
# сравнение по номерам, не строкой: 1.1 против 1.0.9 и 1.10 против 1.9.
check has "$(iv '' '' '' 'echo 1.0.9')" 'rc=0 ok|ok|Проверено'
check has "$(ml 'prod_installed() { return 0; }; prod_free_edition() { return 1; }; prod_installed_ref() { echo dev; }; prod_version() { echo 1.3.10; }; ver_cache_get() { echo 1.3.9; }; installer_verdict govless dev 0; echo "rc=$? $PC_WHY"')" 'rc=0 ok'
check has "$(ml 'prod_installed() { return 0; }; prod_free_edition() { return 1; }; prod_installed_ref() { echo dev; }; prod_version() { echo 1.3.9; }; ver_cache_get() { echo 1.3.10; }; installer_verdict govless dev 0; echo "rc=$? $PC_WHY"')" 'rc=1 ver'
# Текстом — тем же итогом (--install и нумерованное меню).
check has "$(ml 'prod_installed() { return 1; }; installer_postcheck godns main 0 2>&1; echo "rc=$?"')" 'rc=1'
check has "$(ml 'prod_installed() { return 0; }; prod_free_edition() { return 1; }; installer_postcheck godns main 7 2>&1')" 'вышел с кодом 7'
# «Аркада»: установщик «прошёл», а продукт не встал — итог «✗ не встал», не «✓ Проверено».
NAVSTUB='run_product_installer() { act "RUN $1"; return 0; }' nav 3 1 1 1 1 '~\n' %result 0
check grep -q '^RUN godns' "$NAV/act"
check grep -q 'goDNS pro не встал' "$NAV/out"
check grep -q '✗ не встал' "$NAV/out"
# …установщик вышел с кодом — так и сказано.
NAVSTUB='run_product_installer() { act "RUN $1"; return 5; }' nav 3 1 1 1 1 '~\n' %result 0
check grep -q 'вышел с кодом 5' "$NAV/out"
check grep -q '✗ не встал' "$NAV/out"
# П1–П2 (третий круг). Код ≠0, а продукт стоит (обновление не дошло, стоит
# прежний) — не «не встал», а код; где вывод установщика — сказано словами.
for c in 80 46; do
    NAVCOLS=$c NAVSTUB='run_product_installer() { act "RUN $1"; GOINST_FAKE_INSTALLED="$GOINST_FAKE_INSTALLED $1"; return 5; }' nav 3 1 1 1 1 '~\n' %result 0
    # Метка в рамке — только у двух окон (80); на 46 её нет вовсе.
    if [ "$c" = 80 ]; then check grep -q '✗ установщик вышел с кодом 5' "$NAV/out"; fi
    check grep -q 'вышел с кодом 5' "$NAV/out"
    check neg grep -q 'не встал' "$NAV/out"
    check grep -q 'Вывод установщика' "$NAV/out"
    check neg grep -q 'в выводе установщика выше' "$NAV/out"
done
# Шаг «Сверка» — через installer_verdict, второй копии правил нет.
check has "$(code | sed -n '/^ui_run_installer()/,/^}/p')" 'installer_verdict "$id" "$REF" "$rc"'
check hasnt "$(code | sed -n '/^ui_run_installer()/,/^}/p')" 'prod_installed_ref'
# Размер пакета правили — перед «Аркадой» Enter; отказались — нет.
rm -f "$T/net/"*
check has "$(nt 1452 'net_mtu_offer <<<"1" >/dev/null 2>&1; echo "chg=${NET_CHANGED:-}"')" 'chg=1'
rm -f "$T/net/"*
check has "$(nt 1452 'net_mtu_offer <<<"2" >/dev/null 2>&1; echo "chg=${NET_CHANGED:-}"')" 'chg='
check hasnt "$(nt 1452 'net_mtu_offer <<<"2" >/dev/null 2>&1; echo "chg=${NET_CHANGED:-}"')" 'chg=1'
# П9 (третий круг): само поведение main — правили размер пакета, и перед
# «Аркадой» ждут Enter (первая строка ввода уходит на него, меню получает
# вторую); не правили — меню получает первую и без приглашения.
mrun() {  # mrun <1|""> — main до «Аркады» с заглушками сети и меню
    printf 'first\nsecond\n' | GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_DIR="$T/p9" GOINST_OS_RELEASE="$T/os-ubuntu2404" \
        GOINST_COLOR=none P9="$1" bash -c ". '$SCRIPT'
        reattach_tty() { :; }; lang_startup() { :; }; self_install() { :; }; token_load() { :; }
        net_mtu_offer() { NET_CHANGED=\"\$P9\"; }; ui_can_run() { return 0; }
        ui_main() { local l; read -r l; echo \"UI_MAIN got=\$l\"; }
        main" 2>&1
}
out=$(mrun 1)
check has "$out" 'Нажмите Enter, чтобы открыть меню'
check has "$out" 'UI_MAIN got=second'
out=$(mrun '')
check hasnt "$out" 'Нажмите Enter'
check has "$out" 'UI_MAIN got=first'
rm -f "$T/net/"*

echo "── 1.1.0, третий круг: «нет ключа» на неполной ширине, awk без классов"
# П7: пояснение «2» не влезает целиком — короткое, но со смыслом «после ключа».
for lg in ru en; do
    out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=$lg GOINST_TEST=1 GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 \
        bash -c ". '$SCRIPT'; ui_detect; UI_C=66; ui_scr_nokey 1; ui_compose; ui_dump" 2>/dev/null | cut -f1)
    if [ "$lg" = ru ]; then check grep -Eq 'Продолжить без ключа +установка — после ключа' <<<"$out"
    else check grep -Eq 'Continue without a key +install after a key' <<<"$out"; fi
    check hasnt "$out" 'карта портов и'
done
# П6: mawk 1.3.3 (Debian 10) не знает [[:space:]] и других классов — в
# программах awk их нет.
if command -v python3 >/dev/null 2>&1; then
    check [ -z "$(python3 -c '
import re,sys
s=open(sys.argv[1],encoding="utf-8").read()
for m in re.finditer(r"\bawk\b[^\x27\n]*\x27", s):
    a=m.end(); b=s.index("\x27",a)
    if "[[:" in s[a:b]: print(s.count("\n",0,a)+1)
' "$SCRIPT")" ]
fi

echo "── 1.1.0, четвёртый круг: ширина нумерованного меню, код --install, длина в символах"
# П7: длина подписи — в символах и в C-локали (запасные ASCII-рамки): по
# байтам кириллица вдвое длиннее, и на 80 колонках вставало короткое.
nk() { LC_ALL=C LANG=C GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 GOINST_COLOR=none bash -c ". '$SCRIPT'; UI_C=$1; ui_item() { [ \"\$1\" = 2 ] && printf '%s\n' \"\$4\"; return 0; }; ui_scr_nokey 1" 2>/dev/null; }
check [ "$(nk 80)" = 'карта портов и проверка; установка — после ключа' ]
check [ "$(nk 66)" = 'установка — после ключа' ]
check neg grep -q '\${#lb}\|\${#nt}' <(code | sed -n '/^ui_scr_nokey()/,/^}/p')
# Нумерованное главное меню: пояснения видны, служебные — целиком и в одной
# колонке, колонки состояния и «доступно» — по содержимому (раньше 22 и 16
# при «готов» и «—» оставляли описаниям 14 символов). Состояние длинное
# («готов, есть замечания»), версия в ветке — как с сетью.
nmenu() {  # nmenu <язык> <колонки> <yes|no — сеть>
    GOINST_SOURCE_ONLY=1 GOINST_LANG=$1 GOINST_TEST=1 GOINST_COLOR=none GOINST_OS_RELEASE="$T/os-ubuntu2204" GOINST_SS_FIXTURE="$T/ss-empty" \
    GOINST_UNIT_FIXTURE="$T/units-empty" GOINST_NGINX_ROOT="$T/nginx-empty" GOINST_FAKE_INSTALLED="" GOINST_LE_ROOT="$T/le-empty" GOINST_DOCKER_FIXTURE="$T/docker-empty" \
    bash -c ". '$SCRIPT'; os_detect; TOKEN=t; COLUMNS=$2; tput() { return 1; }; VER_NET_OK=$3; VER_NET_TRIED=yes
        prod_readiness() { case \$1 in godns) printf 'y:%s' \"\$(bi 'готов, есть замечания' 'ready, with remarks')\" ;; *) printf 'g:%s' \"\$(bi готов ready)\" ;; esac; }
        prod_avail_cell() { printf 'g:main 1.3.9 ↑'; }
        menu_items_main; menu_build_rows; printf '0\n' | _pick_menu_plain 2>&1 >/dev/null
        for id in \"\${PRODUCTS[@]}\"; do printf 'DESC %s\n' \"\$(prod_desc \"\$id\")\"; done" 2>&1 | sed $'s/\033\\[[0-9;]*m//g'
}
cat > "$T/nmenu.py" <<'PY'
import sys
lg, cols = sys.argv[1], int(sys.argv[2])
lines = sys.stdin.read().splitlines()
desc = [l[5:] for l in lines if l.startswith("DESC ")]
rows = {}
for l in lines:
    s = l.strip()
    if len(s) > 2 and s[1] == ")" and l.startswith("  "): rows[s[0]] = l
svc = {"ru": {"p": "кто какие порты держит", "r": "спросить GitHub заново", "l": "сменить язык установщика", "x": "продукты останутся"},
       "en": {"p": "who holds which ports", "r": "ask GitHub again", "l": "change the installer language", "x": "products stay"}}[lg]
err = []
for k, l in rows.items():
    if len(l) > cols: err.append("шире окна: " + l)
# Служебные: целиком, в одной колонке.
pos = set()
for k, t in svc.items():
    if t not in rows.get(k, ""): err.append("не целиком: %s) %s" % (k, rows.get(k)))
    else: pos.add(rows[k].index(t))
if len(pos) != 1: err.append("служебные не в одной колонке: %s" % sorted(pos))
# Обрезанное пояснение — по границе слова.
for k in "oc":
    l = rows.get(k, "")
    if "…" in l:
        head = l[:l.index("…")].split("  ")[-1]
        if head and not head[-1].isalnum() and head[-1] not in ")": err.append("обрез на знаке: " + l)
# Описания продуктов: видны, места им не меньше 16 символов.
for i, d in enumerate(desc, 1):
    l = rows.get(str(i), "")
    w = d.split()[0]
    if w not in l: err.append("нет описания: " + l); continue
    room = cols - 1 - l.rindex(w)
    if room < 16: err.append("описанию %d символов: %s" % (room, l))
    tail = l[l.rindex(w):]
    if tail.endswith("…"):
        h = tail[:-1]
        if not d.startswith(h) or (len(h) < len(d) and d[len(h)] not in " ,;"): err.append("обрез на полуслове: " + l)
if len(desc) != 6: err.append("описаний %d" % len(desc))
print("\n".join(err) if err else "ok")
PY
for c in 80 100; do for net in yes no; do for lg in ru en; do
    r=$(nmenu $lg $c $net | python3 "$T/nmenu.py" $lg $c)
    [ "$r" = ok ] || echo "    nmenu $lg $c $net: $r"
    check [ "$r" = ok ]
done; done; done
# Длинная подпись с состоянием («o) Ubuntu 22.04 → 24.04») — своей раскладкой,
# пояснение режется по слову, а не на полуслове.
check has "$(nmenu ru 80 yes)" 'o) Ubuntu 22.04 → 24.04  ↑ 24.04  обновить систему одной кнопкой; сначала…'
check [ "$(ml 'cut_words "продукты останутся" 14')" = 'продукты…' ]
check [ "$(ml 'cut_words "сначала — бэкап" 10')" = 'сначала…' ]
check [ "$(ml 'cut_words "abcdefghij" 6')" = 'abcde…' ]
check [ "$(ml 'cut_words "кто какие порты держит" 22')" = 'кто какие порты держит' ]
# Меню «Компоненты» колонку служебных пунктов не берёт (MENU_SVC — только с
# образцом ключей).
check [ -z "$(ml 'MENU_ITEMS=("1|a|d:x|d:y|z"); COLUMNS=80; tput() { return 1; }; MENU_W_STATUS=10; MENU_W_EXTRA=8; menu_fit_widths 12; echo "$MENU_SVC"')" ]
# Пункт 5: --install, а на месте остался бесплатный вариант — код 1, как у
# «не встал»: человек просил pro. Бесплатного нет — 0.
r4i() { GOINST_SOURCE_ONLY=1 GOINST_TEST=1 GOINST_LANG=ru GOINST_OS_RELEASE="$T/os-ubuntu2404" GOINST_SS_FIXTURE="$T/ss-empty" GOINST_UNIT_FIXTURE="$T/units-empty" \
    GOINST_DOCKER_FIXTURE=/dev/null GOINST_NO_NET=1 GOINST_DIR="$T/gi-r4" GOINST_ARCH=x86_64 \
    bash -c ". '$SCRIPT'; run_product_installer() { echo RPI; return 0; }; prod_installed() { return 0; }; prod_free_edition() { $1; }; main --install gokaskad pro main" </dev/null 2>&1; }
out=$(r4i 'echo Kaskad'); rc=$?
check [ "$rc" -eq 1 ]
check has "$out" 'RPI'
check has "$out" 'по-прежнему бесплатный Kaskad'
out=$(r4i 'return 1'); rc=$?
check [ "$rc" -eq 0 ]
check has "$out" 'RPI'

echo "── 1.1.0, пятый круг: SSH по фактическим портам, reset-failed, goinstall из файла"
SC="$OSFX/fs/etc/ssh/sshd_config"
# П-1. Порты из настроек. Строки Port нет — 22 (на сервере B выходил пробел).
mkos 22.04; printf 'PermitRootLogin yes\n' > "$SC"
check [ "$(ox 'osup_ssh_cfg_ports')" = "22 " ]
# Port в drop-in.
mkdir -p "$SC.d"; printf 'Include /etc/ssh/sshd_config.d/*.conf\nPermitRootLogin yes\n' > "$SC"; printf 'Port 2200\n' > "$SC.d/50-port.conf"
check [ "$(ox 'osup_ssh_cfg_ports')" = "2200 " ]
# ListenAddress host:port — свой порт; Port к нему не добавляется (как у sshd).
rm -f "$SC.d/50-port.conf"; printf 'Port 22\nListenAddress 0.0.0.0:2222\n' > "$SC"
check [ "$(ox 'osup_ssh_cfg_ports')" = "2222 " ]
printf 'Port = 2201\n' > "$SC"
check [ "$(ox 'osup_ssh_cfg_ports')" = "2201 " ]
# sshd -T есть — его слово сильнее разбора файлов.
printf 'port 22\nlistenaddress [::]:2244\nlistenaddress 0.0.0.0:2244\n' > "$OSFX/sshd-T"
check [ "$(ox 'osup_ssh_cfg_ports')" = "2244 " ]
rm -f "$OSFX/sshd-T" "$SC"
check [ -z "$(ox 'osup_ssh_cfg_ports')" ]                         # нет настроек — нет и SSH
# systemd засчитывается на переданных портах, а не на портах из настроек.
printf 'Port 22\n' > "$SC"
printf 'tcp   LISTEN 0      4096         0.0.0.0:2222      0.0.0.0:*    users:(("systemd",pid=1,fd=3))\n' > "$OSFX/ss"
check [ -z "$(ox 'osup_ssh_ports')" ]
check [ "$(ox 'osup_ssh_ports 2222')" = 2222 ]
# Сервер B: строки Port нет, до — sshd на 22, после перезагрузки на 24.04
# слушает только ssh.socket (systemd). Ни перезапуска, ни ложного err.
mkos 22.04; printf 'PermitRootLogin yes\n' > "$SC"
printf 'tcp   LISTEN 0      128          0.0.0.0:22      0.0.0.0:*    users:(("sshd",pid=500,fd=3))\n' > "$OSFX/ss"; rm -f "$OSFX/ss-good"
printf 'tcp   LISTEN 0      4096         0.0.0.0:22      0.0.0.0:*    users:(("systemd",pid=1,fd=3))\n' > "$OSFX/ss-lost"
ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check grep -qx 22 "$G/before/ssh"
check [ "$(osst status)" = done ]
check [ "$(oscalls 'restart ssh')" = 0 ]
check neg grep -q '^note=SSH' "$G/state"
check grep -q 'SSH слушает: 22$' "$G/log"
# Снимок «до» есть (sshd на 2222), а в настройках потом 22 — побеждает снимок:
# ssh.socket на 2222 засчитан, 22 не требуется.
mkos 22.04; rm -f "$OSFX/ss-good"
printf 'tcp   LISTEN 0      4096         0.0.0.0:2222      0.0.0.0:*    users:(("systemd",pid=1,fd=3))\n' > "$OSFX/ss-lost"
ox 'osup_start' >/dev/null; printf 'Port 22\n' > "$SC"
ox 'osup_run' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check grep -qx 2222 "$G/before/ssh"
check [ "$(oscalls 'restart ssh')" = 0 ]
check neg grep -q '^note=SSH' "$G/state"
check grep -q 'SSH слушает: 2222$' "$G/log"
# Снимка нет — порты из настроек (sshd -T).
mkos 22.04; rm -f "$OSFX/ss-good"
printf 'tcp   LISTEN 0      4096         0.0.0.0:2244      0.0.0.0:*    users:(("systemd",pid=1,fd=3))\n' > "$OSFX/ss-lost"
ox 'osup_start' >/dev/null; rm -f "$G/before/ssh"; printf 'listenaddress 0.0.0.0:2244\n' > "$OSFX/sshd-T"
ox 'osup_run' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check grep -q 'снимка SSH «до» нет — порты из настроек: 2244$' "$G/log"
check [ "$(oscalls 'restart ssh')" = 0 ]
check neg grep -q '^note=SSH' "$G/state"
# П-2. Уборка снимает «failed» службы: прервано, снято, готово.
mkos 22.04; touch "$OSFX/dru-fail"; ox 'osup_start' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check [ "$(osst status)" = failed ]
check grep -qx 'systemctl reset-failed goinstall-os-upgrade.service' "$OSFX/calls"
: > "$OSFX/calls"; ox 'osup_dismiss' >/dev/null
check [ ! -e "$G/state" ]
check grep -qx 'systemctl reset-failed goinstall-os-upgrade.service' "$OSFX/calls"
mkos 22.04; ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check [ "$(osst status)" = done ]
check grep -qx 'systemctl reset-failed goinstall-os-upgrade.service' "$OSFX/calls"
# Исполнитель службой: прерывание записано — код 0, иначе systemd оставил бы
# службу «failed» без файла юнита (reset-failed изнутри не действует).
orun() { PATH="$OSFX/bin:$PATH" GOINST_TEST=1 GOINST_LANG=ru GOINST_DIR="$OSFX/gi" GOINST_FS_ROOT="$OSFX/fs" GOINST_OS_RELEASE="$OSFX/os-release" \
    GOINST_SYSTEMD_DIR="$OSFX/fs/etc/systemd/system" GOINST_OSUP_REBOOT_WAIT=0 GOINST_OSUP_DOCKER_WAIT=0 GOINST_OSUP_SETTLE=0 GOINST_OSUP_LOCK_WAIT=0 \
    GOINST_KERNEL=6.8.0-85-generic GOINST_FAKE_INSTALLED="" GOINST_SS_FIXTURE="$OSFX/ss" GOINST_UNIT_FIXTURE="$T/units-empty" GOINST_BIN="$OSFX/goinstall" \
    GOINST_DOCKER_FIXTURE="$T/docker-empty" GOINST_COLOR=none bash "$SCRIPT" --os-upgrade-run </dev/null >/dev/null 2>&1; echo "rc=$?"; }
mkos 22.04; touch "$OSFX/dru-fail"; ox 'osup_start' >/dev/null
check [ "$(orun)" = rc=0 ]
check [ "$(osst status)" = failed ]
# П-3. Запуск из файла (`bash go-installer.sh --os-upgrade --yes`) ставит
# команду goinstall; скрипт входа зовёт её по абсолютному пути.
mkos 22.04; NB="$OSFX/nb/goinstall"; mkdir -p "$OSFX/nb"; HK="$OSFX/fs/etc/profile.d/goinstall-osupgrade.sh"
out=$(PATH="$OSFX/bin:$PATH" GOINST_TEST=1 GOINST_LANG=ru GOINST_DIR="$OSFX/gi" GOINST_FS_ROOT="$OSFX/fs" GOINST_OS_RELEASE="$OSFX/os-release" \
    GOINST_SYSTEMD_DIR="$OSFX/fs/etc/systemd/system" GOINST_OSUP_CHECK_WAIT=0 GOINST_SS_FIXTURE="$OSFX/ss" GOINST_FAKE_INSTALLED="" \
    GOINST_BIN="$NB" GOINST_BIN_ALIAS="$OSFX/nb/go-installer" GOINST_PROFILE_HOOK="$OSFX/fs/etc/profile.d/goinstall-summary.sh" \
    bash "$SCRIPT" --os-upgrade --yes 2>&1 </dev/null; echo "rc=$?")
check has "$out" 'rc=0'
check has "$out" 'Команда goinstall установлена.'
check has "$out" 'ход — goinstall или goinstall --os-upgrade status'
check [ -x "$NB" ]
check cmp -s "$SCRIPT" "$NB"
check grep -qF "[ -x $NB ]; then" "$HK"
check grep -qF "    $NB --os-upgrade status --short" "$HK"
check neg grep -q 'command -v goinstall' "$HK"
# П-4. Журнал апгрейдера не создан — путь к своему журналу; создан — оба.
mkos 22.04
check [ "$(ox '_osup_paths; osup_dru_reason 1 22.04')" = "do-release-upgrade вышел с кодом 1, выпуск остался 22.04 — $G/log" ]
echo 'INFO started' > "$OSFX/fs/var/log/dist-upgrade/main.log"
check [ "$(ox '_osup_paths; osup_dru_reason 1 22.04')" = "do-release-upgrade вышел с кодом 1, выпуск остался 22.04 — $G/log, /var/log/dist-upgrade/main.log" ]
# П-5. После «Попробовать снова» время шага — от повтора, а не от первого входа.
mkos 22.04; touch "$OSFX/dru-fail"; ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; rm -f "$OSFX/dru-fail"
NOW=$(date +%s)
# Как на сервере: первый вход в прыжок и отметка запуска — давно.
sed -i.bak "s/^started=.*/started=$((NOW-5000))/; s/^kick=.*/kick=$((NOW-5000))/; s/^t:dist-22.04=.*/t:dist-22.04=$((NOW-5000)) $((NOW-4900))/; s/^t:rel-22.04=.*/t:rel-22.04=$((NOW-4900))/" "$G/state"
check [ "$(ox 'osup_load; osup_progress; echo "$OSUP_CUR $(( $(_osup_now) - OSUP_CURT ))"' | awk '{print $1, ($2 >= 4900)}')" = "rel-22.04 1" ]
ox 'osup_start' >/dev/null
check [ "$(osst attempt)" = 2 ]
check [ "$(ox 'osup_load; osup_progress; echo "$OSUP_CUR $(( $(_osup_now) - OSUP_CURT ))"' | awk '{print $1, ($2 < 60)}')" = "rel-22.04 1" ]

echo "── 1.1.0, шестой круг: снимок SSH только демона, sshd -t, юнит перезапуска"
SC="$OSFX/fs/etc/ssh/sshd_config"
SSL='tcp   LISTEN 0      4096         0.0.0.0:22      0.0.0.0:*    users:(("systemd",pid=1,fd=3))'
# Р-1. Человек вошёл с X11 (MobaXterm) и ssh -R: sshd его сессии слушает
# 127.0.0.1:6010, [::1]:6010 и 0.0.0.0:8080. В снимок «до» — только демон:
# иначе после обновления «не слушает 6010», перезапуск и красная тревога.
mkos 22.04; printf 'PermitRootLogin yes\nX11Forwarding yes\n' > "$SC"; rm -f "$OSFX/ss-good"
mkdir -p "$OSFX/fs/proc/500" "$OSFX/fs/proc/4242"
printf 'Name:\tsshd\nPPid:\t1\n' > "$OSFX/fs/proc/500/status"; printf 'Name:\tsshd\nPPid:\t4200\n' > "$OSFX/fs/proc/4242/status"
printf '%s\n' 'tcp   LISTEN 0      128          0.0.0.0:22      0.0.0.0:*    users:(("sshd",pid=500,fd=3))' \
    'tcp   LISTEN 0      128        127.0.0.1:6010    0.0.0.0:*    users:(("sshd",pid=4242,fd=10))' \
    'tcp   LISTEN 0      128            [::1]:6010       [::]:*    users:(("sshd",pid=4242,fd=9))' \
    'tcp   LISTEN 0      128          0.0.0.0:8080    0.0.0.0:*    users:(("sshd",pid=4242,fd=11))' > "$OSFX/ss"
printf '%s\n' "$SSL" > "$OSFX/ss-lost"
check [ "$(ox 'osup_ssh_ports --daemon')" = 22 ]
check [ "$(ox 'osup_ssh_ports')" = "22 6010 8080" ]        # сверка «после» судит мягко
ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check [ "$(cat "$G/before/ssh")" = 22 ]
check [ "$(osst status)" = done ]
check [ "$(oscalls 'restart ssh')" = 0 ]
check neg grep -q '^note=SSH' "$G/state"
check grep -q 'SSH слушает: 22$' "$G/log"
# Родителя не узнать (/proc не читается) — не судим по нему; loopback с портом
# не из настроек не берём, с портом из настроек — берём.
mkos 22.04; printf 'Port 22\nPort 2200\n' > "$SC"
printf '%s\n' 'tcp   LISTEN 0      128          0.0.0.0:22      0.0.0.0:*    users:(("sshd",pid=500,fd=3))' \
    'tcp   LISTEN 0      128        127.0.0.1:2200    0.0.0.0:*    users:(("sshd",pid=4300,fd=4))' \
    'tcp   LISTEN 0      128        127.0.0.1:6011    0.0.0.0:*    users:(("sshd",pid=4300,fd=10))' > "$OSFX/ss"
check [ "$(ox 'osup_ssh_ports --daemon')" = "22 2200" ]
# Родитель не 1, но это MainPID ssh.service — демон, сессия (8080) — нет.
printf '%s\n' 'tcp   LISTEN 0      128          0.0.0.0:2222      0.0.0.0:*    users:(("sshd",pid=777,fd=3))' \
    'tcp   LISTEN 0      128          0.0.0.0:8080    0.0.0.0:*    users:(("sshd",pid=4242,fd=11))' > "$OSFX/ss"
mkdir -p "$OSFX/fs/proc/777" "$OSFX/fs/proc/4242"
printf 'Name:\tsshd\nPPid:\t5\n' > "$OSFX/fs/proc/777/status"; printf 'Name:\tsshd\nPPid:\t777\n' > "$OSFX/fs/proc/4242/status"
echo 777 > "$OSFX/mainpid-ssh.service"
check [ "$(ox 'osup_ssh_ports --daemon')" = 2222 ]
# Демон не узнан ни одним способом — снимок как прежде, все sshd: пустой
# увёл бы сверку к настройкам, а правка может только убавлять перезапуски.
rm -f "$OSFX/mainpid-ssh.service"
check [ "$(ox 'osup_ssh_ports --daemon')" = "2222 8080" ]
# Р-2. sshd -t не проходит, порты на месте: красное замечание, перезапуска нет.
mkos 22.04; ox 'osup_start' >/dev/null
printf '%s\n' '' '/etc/ssh/sshd_config line 3: Bad configuration option: Foo' '/etc/ssh/sshd_config: terminating, 1 bad configuration options' > "$OSFX/sshd-check"
ox 'osup_run' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check [ "$(osst status)" = done ]
check grep -qxF 'note=SSH|настройки SSH не проходят проверку: /etc/ssh/sshd_config line 3: Bad configuration option: Foo — не закрывайте текущую сессию, проверьте /etc/ssh/sshd_config|SSH: sshd -t|sshd -t|err' "$G/state"
check [ "$(oscalls 'restart ssh')" = 0 ]
check grep -q 'SSH слушает: 2222$' "$G/log"
# …и порт пропал: всё равно не перезапускаем — с битыми настройками
# перезапуск уронил бы SSH; замечаний два.
mkos 22.04; printf '%s\n' "$SSL" > "$OSFX/ss-lost"; ox 'osup_start' >/dev/null
echo '/etc/ssh/sshd_config line 3: Bad configuration option: Foo' > "$OSFX/sshd-check"
ox 'osup_run' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check [ "$(oscalls 'restart ssh')" = 0 ]
check grep -q '^note=SSH|настройки SSH не проходят проверку: ' "$G/state"
check grep -q '^note=SSH|не слушает порт 2222 — зайдите через консоль хостера|SSH: порт 2222|journalctl -u ssh.socket|err' "$G/state"
check grep -q 'SSH не слушает 2222 — настройки не проходят sshd -t, ssh.socket не перезапускаю' "$G/log"
# Нет /run/sshd (24.04 до первого входа) — настройки разобраны, это не ошибка.
mkos 22.04; ox 'osup_start' >/dev/null
echo 'Missing privilege separation directory: /run/sshd' > "$OSFX/sshd-check"
ox 'osup_run' >/dev/null; ox 'osup_run' >/dev/null
check neg grep -q '^note=SSH' "$G/state"
# Пустой ответ — код выхода.
: > "$OSFX/sshd-check"
check [ "$(ox '_osup_sshd_test')" = 'код 255' ]
rm -f "$OSFX/sshd-check"
check [ -z "$(ox '_osup_sshd_test')" ]
# Р-3. Какой юнит перезапускать.
mkos 22.04
check [ "$(ox '_osup_ssh_unit')" = ssh.socket ]                      # включён и слушает
sed 's/^ssh.socket=.*/ssh.socket=down/' "$OSFX/units" > "$OSFX/u.t"; mv "$OSFX/u.t" "$OSFX/units"
check [ "$(ox '_osup_ssh_unit')" = ssh.socket ]                      # включён, не слушает
sed 's/^ssh.socket=.*/ssh.socket=off/' "$OSFX/units" > "$OSFX/u.t"; mv "$OSFX/u.t" "$OSFX/units"
check [ "$(ox '_osup_ssh_unit')" = ssh.service ]                     # выключен человеком
sed 's/^ssh.socket=.*/ssh.socket=run/' "$OSFX/units" > "$OSFX/u.t"; mv "$OSFX/u.t" "$OSFX/units"; : > "$OSFX/masked-ssh.socket"
check [ "$(ox '_osup_ssh_unit')" = ssh.service ]                     # замаскирован — не трогаем
rm -f "$OSFX/masked-ssh.socket"; grep -v '^ssh.socket=' "$OSFX/units" > "$OSFX/u.t"; echo 'sshd.service=run' >> "$OSFX/u.t"; mv "$OSFX/u.t" "$OSFX/units"
check [ "$(ox '_osup_ssh_unit')" = sshd.service ]                    # юнит назван sshd
# Сокет замаскирован, порт пропал — перезапуск ssh.service, сокет не тронут.
mkos 22.04; printf '%s\n' "$SSL" > "$OSFX/ss-lost"; : > "$OSFX/masked-ssh.socket"
ox 'osup_start' >/dev/null; ox 'osup_run' >/dev/null; : > "$OSFX/calls"; ox 'osup_run' >/dev/null
check grep -qx 'systemctl restart ssh.service' "$OSFX/calls"
check [ "$(oscalls 'restart ssh.socket')" = 0 ]

echo "── обновление Ubuntu: предупреждение в нумерованном режиме переносится по словам"
# Терминал рвал абзац посреди слова («обновле|ние», «в|ернуть») — а это
# предупреждение о бэкапе. say_par переносит по словам под ширину окна.
par='Сделайте снимок (бэкап) сервера в панели хостера. Если обновление прервётся, вернуть сервер можно только из снимка.'
out=$(COLUMNS=50 ml "say_par '$par' 2>&1")
check [ -n "$out" ]
# Каждая строка не шире 48 символов (50 − отступ справа), считая символы, а не байты.
check [ -z "$(while IFS= read -r l; do n=$(ml "str_len '$l'"); [ "$n" -gt 48 ] && echo "$n"; done <<<"$out")" ]
# Слова целы: склеенный обратно текст совпадает с исходным.
check [ "$(sed 's/^  //' <<<"$out" | tr '\n' ' ' | sed 's/ $//')" = "$par" ]
check [ "$(wc -l <<<"$out" | tr -d ' ')" -ge 3 ]
# Узкое окно не даёт ширину меньше 30.
check [ -z "$(COLUMNS=10 ml "say_par '$par' 2>&1" | while IFS= read -r l; do n=$(ml "str_len '$l'"); [ "$n" -gt 32 ] && echo "$n"; done)" ]

# Без TERM и с мусором в COLUMNS — ширина 80, а не обрыв под set -u.
out=$(TERM= COLUMNS=abc ml "set -u; say_par '$par' 2>&1; echo rc=\$?")
check has "$out" 'rc=0'
check has "$out" 'Сделайте снимок'
# osup_print_warning печатает все три абзаца, и только в stderr.
out=$(COLUMNS=60 ml "OS_VER=20.04; OS_PRETTY='Ubuntu 20.04.6 LTS'; OSUP_TARGET=24.04; OSUP_CHK=(); osup_print_warning 2>/dev/null")
check [ -z "$out" ]
out=$(COLUMNS=60 ml "OS_VER=20.04; OS_PRETTY='Ubuntu 20.04.6 LTS'; OSUP_TARGET=24.04; OSUP_CHK=(); osup_print_warning 2>&1 >/dev/null")
check has "$out" 'Два шага'
check has "$out" 'SSH будет'
check has "$out" 'вернуть сервер можно только'

echo "── защита от сканеров: списки, правила, предложение, стражи"
# Всё — на заглушках: curl отдаёт фикстуры, nft пишет вызовы и хранит
# «живую» таблицу в файле, systemctl только пишет. Настоящий nft набор не
# зовёт никогда (на Mac его нет, а на сервере он тронул бы систему).
SF="$T/shield"; rm -rf "$SF"; mkdir -p "$SF/bin" "$SF/src" "$SF/fs/etc/ssh"
# Фикстуры в формате AS_Network_List (02.11.2026): общий v4 — 419 сетей
# (частная и сеть с адресом сервера среди них), ВК — подмножество, файл с
# именами AS — блоками, TVK-AS (МТС) — исключение по умолчанию.
{ for a in 0 1; do for b in $(seq 0 199); do echo "45.$a.$b.0/24"; done; done
  echo "178.17.176.0/23"; echo "10.20.0.0/16"; echo "# комментарий"; echo ""
  for b in $(seq 0 16); do echo "46.0.$b.0/24"; done; } > "$SF/src/blacklist-v4.txt"
printf '2a00:1::/32\n2a00:2::/32\n2001:db8:1::/48\n' > "$SF/src/blacklist-v6.txt"
for b in $(seq 0 9); do echo "45.1.$b.0/24"; done > "$SF/src/blacklist-vk-v4.txt"
printf '2a00:2::/32\n' > "$SF/src/blacklist-vk-v6.txt"
cat > "$SF/src/blacklist_with_comments.txt" <<'TXT'
---
# Networks announced by AS43038
# AS-Name (ORG): TVK-AS (ORG-TVK1-RIPE)
178.17.176.0/23
178.17.178.0/23
---
# Networks announced by AS12345
# AS-Name (ORG): OTHER-AS (ORG-X1-RIPE)
45.0.0.0/24
# NET-Name: 46.0.3.0/24 TVK-AS MTS
46.0.3.0/24
# NET-Name: 46.0.4.0/24 TVK-ASX
46.0.4.0/24
TXT
printf 'Port 2222\n' > "$SF/fs/etc/ssh/sshd_config"
printf '%s\n' 'tcp LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=500,fd=3))' > "$SF/ss"
printf '#!/bin/bash\nexit 1\n' > "$SF/bin/sshd"
# systemctl пишет вызовы; show ssh.socket — Listen из SOCK_LISTEN (не пишется);
# show -p ActiveState — active для служб из SC_ACTIVE.
cat > "$SF/bin/systemctl" <<'FAKE'
#!/bin/bash
if [ "$1 $2 $3" = "show -p ActiveState" ]; then
    case " ${SC_ACTIVE:-} " in *" ${5%.service} "*) echo active ;; *) echo inactive ;; esac; exit 0
fi
if [ "$1" = show ]; then for x in ${SOCK_LISTEN:-}; do echo "Listen=$x (Stream)"; done; exit 0; fi
echo "$*" >> "$SFD/systemctl"; exit 0
FAKE
printf '#!/bin/bash\nGOINST_VERSION="%s"\n' "$GIV" > "$SF/goinstall"
cat > "$SF/bin/curl" <<'FAKE'
#!/bin/bash
of="" url="" cfg=""
printf '%s\n' "$*" >> "$SFD/curl.args"
[ -n "${CURL_HOOK:-}" ] && eval "$CURL_HOOK"
while [ $# -gt 0 ]; do
    case "$1" in -o) of="$2"; shift ;; --config|-K) cfg="$2"; shift ;; -w|-H|--max-time) shift ;; http*) url="$1" ;; esac
    shift
done
[ -n "$cfg" ] && cat "$cfg" >> "$SFD/curl.cfg"
echo "$url" >> "$SFD/urls"
case "$url" in
    https://api.github.com/*)
        [ -n "${API_CODE:-}" ] && { printf '%s' "$API_CODE"; exit 0; }
        printf '%s' "${SHA:-0123456789abcdef0123456789abcdef01234567}" > "$of"; printf 200 ;;
    https://raw.githubusercontent.com/*)
        [ -n "${RAW_FAIL:-}" ] && { printf '000'; exit 7; }
        f="$SFS/${url##*/}"
        if [ -f "$f" ]; then cp "$f" "$of"; printf 200; else printf 404; fi ;;
    *) printf 000; exit 6 ;;
esac
FAKE
cat > "$SF/bin/nft" <<'FAKE'
#!/bin/bash
echo "$*" >> "$SFD/nft.calls"
live="$SFD/live"
case "$*" in
    "list tables") [ -n "${NFT_DEAD:-}" ] && { echo "Error: Operation not supported" >&2; exit 1; }; exit 0 ;;
    "-c -f "*) { [ -n "${NFT_BAD:-}" ] || [ -e "$SFD/nft.bad" ]; } && { echo "Error: syntax error" >&2; exit 1; }
               # socket cgroupv2: NFT_NOCG — nft или ядро не умеют (nft < 1.0,
               # ядро < 5.13); путь, как у nft, — существующий каталог cgroup.
               if grep -q 'socket cgroupv2' "$3"; then
                   [ -z "${NFT_NOCG:-}" ] || { echo "Error: syntax error, unexpected cgroupv2" >&2; exit 1; }
                   for p in $(sed -n 's/.*socket cgroupv2 level 2 "\([^"]*\)".*/\1/p' "$3"); do
                       [ -d "$GOINST_SHIELD_CG/$p" ] || { echo "Error: cgroupv2 path fails: No such file or directory" >&2; exit 1; }
                   done
               fi
               # NFT_STAT=N — nft и ядро умеют статистику только до уровня N
               # (0 — без именованных счётчиков, 2 — без счётчика в наборе).
               if [ -n "${NFT_STAT:-}" ]; then
                   lv=0; grep -q 'counter name' "$3" && lv=1; grep -q 'update @seen' "$3" && lv=2; grep -q 'update @ports' "$3" && lv=3
                   [ "$lv" -le "$NFT_STAT" ] || { echo "Error: Could not process rule: Operation not supported" >&2; exit 1; }
               fi; exit 0 ;;
    "-f "*) f="$2"
            # NFT_LOADSTAT=N — nft -c принимает, а загрузка выше уровня N падает.
            # NFT_LOADNOCG — nft -c принял socket cgroupv2, а загрузка нет.
            [ -n "${NFT_LOADNOCG:-}" ] && grep -q 'socket cgroupv2' "$f" && { echo "Error: cgroupv2 path fails: No such file or directory" >&2; exit 1; }
            if [ -n "${NFT_LOADSTAT:-}" ]; then
                lv=0; grep -q 'counter name' "$f" && lv=1; grep -q 'update @seen' "$f" && lv=2; grep -q 'update @ports' "$f" && lv=3
                [ "$lv" -le "$NFT_LOADSTAT" ] || { echo "Error: Could not process rule: Cannot allocate memory" >&2; exit 1; }
            fi
            if grep -q '^table inet goinstall_shield {$' "$f"; then
                sed -e '1,2d' -e 's/counter drop/counter packets 5 bytes 300 drop/' -e 's/counter reject/counter packets 2 bytes 120 reject/' "$f" > "$live"
            else rm -f "$live"; fi; exit 0 ;;
    "list table inet goinstall_shield") [ -f "$live" ] || { echo "Error: No such file or directory" >&2; exit 1; }; cat "$live"; exit 0 ;;
    # -t — без элементов наборов; набор по имени — с элементами.
    "-t list table inet goinstall_shield") [ -f "$live" ] || { echo "Error: No such file or directory" >&2; exit 1; }
        awk '/elements = [{]/ { s = 1 } s { if (/[}]/) s = 0; next } 1' "$live"; exit 0 ;;
    "list set inet goinstall_shield "*) [ -f "$live" ] && [ "$#" = 5 ] || { echo "Error: No such file or directory" >&2; exit 1; }
        o=$(awk -v n="$5" '$0 ~ "^\tset " n " [{]" { f = 1 } f { print } f && /^\t[}]/ { exit }' "$live")
        [ -n "$o" ] || { echo "Error: No such file or directory" >&2; exit 1; }
        printf 'table inet goinstall_shield {\n%s\n}\n' "$o"; exit 0 ;;
    # Листинг для статистики: подложенный ($SFD/nfta) или загруженная таблица.
    "-a list table inet goinstall_shield") [ -f "$SFD/nfta" ] && { cat "$SFD/nfta"; exit 0; }
        [ -f "$live" ] || { echo "Error: No such file or directory" >&2; exit 1; }; sed '1s/{$/{ # handle 1/' "$live"; exit 0 ;;
    "delete table inet goinstall_shield") [ -f "$live" ] || exit 1; rm -f "$live"; exit 0 ;;
esac
echo "unexpected: $*" >&2; exit 2
FAKE
chmod +x "$SF/bin/"* "$SF/goinstall"
sh_reset() { rm -rf "$SF/d" "$SF/dir" "$SF/units" "$SF/gd"; mkdir -p "$SF/d"; }
sh_run() {  # sh_run <выражение> — функции скрипта на заглушках
    ( export PATH="$SF/bin:$PATH" SFD="$SF/d" SFS="${SFS:-$SF/src}" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
      export GOINST_GH_RETRY_DELAY=0 GOINST_SHIELD_DIR="$SF/dir" GOINST_SHIELD_RUN="$SF/d/boot" GOINST_SYSTEMD_DIR="$SF/units"
      export GOINST_SHIELD_CG="$SF/d/cg" GOINST_SHIELD_NFT="$SF/bin/nft" GOINST_SHIELD_ADDRS="45.0.5.7 2a00:1::5" GOINST_SS_FIXTURE="$SF/ss" GOINST_FS_ROOT="$SF/fs"
      export GOINST_BIN="$SF/goinstall" GOINST_DIR="$SF/gd" GH_TOKEN=ghp_shieldtesttoken0000
      . "$SCRIPT"; eval "$1" ) 2>&1
}
# Строгий разбор: хороший список, мусор, шире /8, частная, ввод человека.
sh_reset
out=$(sh_run '_shield_py list "$SFS/blacklist-v4.txt" 4 "$SFD/s4"; echo "rc=$?"')
# Строки и охват: 400 /24 + /23 (2) + /16 (256) + 17 /24 = 675 сетей /24.
check [ "$out" = "$(printf '419 675\nrc=0')" ]
# Охват — после слияния: вложенные и повторы не считаются дважды; v6 — в /48.
printf '45.0.0.0/16\n45.0.1.0/24\n45.0.0.0/25\n9.9.9.9/32\n' > "$SF/d/ov"
check [ "$(sh_run '_shield_py list "$SFD/ov" 4 "$SFD/x"')" = "4 257" ]
printf '2a00:1::/32\n2a00:1:1::/48\n2a00:2::/47\n' > "$SF/d/ov"
check [ "$(sh_run '_shield_py list "$SFD/ov" 6 "$SFD/x"')" = "3 65538" ]
# Вложенность: каждая сеть ВК — внутри общего; первая чужая — с кодом 7.
printf '45.0.0.0/16\n46.0.0.0/24\n' > "$SF/d/sup"; printf '45.0.3.0/24\n46.0.0.128/25\n' > "$SF/d/sub"
check [ "$(sh_run '_shield_py within "$SFD/sub" "$SFD/sup"; echo "rc=$?"')" = "$(printf 'ok\nrc=0')" ]
printf '45.0.3.0/24\n46.0.1.0/24\n' > "$SF/d/sub"
check [ "$(sh_run '_shield_py within "$SFD/sub" "$SFD/sup"; echo "rc=$?"')" = "$(printf 'out 46.0.1.0/24\nrc=7')" ]
printf '44.255.255.0/24\n' > "$SF/d/sub"
check [ "$(sh_run '_shield_py within "$SFD/sub" "$SFD/sup"; echo "rc=$?"')" = "$(printf 'out 44.255.255.0/24\nrc=7')" ]
printf '45.0.0.0/24\n45.0.1.0/24 junk\n' > "$SF/d/bad"
out=$(sh_run '_shield_py list "$SFD/bad" 4 "$SFD/x"; echo "rc=$?"')
check has "$out" 'garbage 2'; check has "$out" 'rc=2'
printf '45.0.0.0/24\n1.2.3.4/24\n' > "$SF/d/bad"
check has "$(sh_run '_shield_py list "$SFD/bad" 4 "$SFD/x"; echo "rc=$?"')" 'rc=2'
printf '45.0.0.0/24\n44.0.0.0/7\n' > "$SF/d/bad"
out=$(sh_run '_shield_py list "$SFD/bad" 4 "$SFD/x"; echo "rc=$?"')
check has "$out" 'wide 44.0.0.0/7'; check has "$out" 'rc=3'
printf '2a00::/15\n' > "$SF/d/bad"
check has "$(sh_run '_shield_py list "$SFD/bad" 6 "$SFD/x"; echo "rc=$?"')" 'rc=3'
printf '45.0.0.0/24\n' > "$SF/d/bad"
check has "$(sh_run '_shield_py list "$SFD/bad" 6 "$SFD/x"; echo "rc=$?"')" 'rc=2'
# Мусор с управляющими символами не попадает в причину сырым.
printf '45.0.0.0/24\n\033[31mevil\\e\n' > "$SF/d/bad"
out=$(sh_run '_shield_py list "$SFD/bad" 4 "$SFD/x"')
check hasnt "$out" $'\033'; check hasnt "$out" '\'
check [ "$(sh_run '_shield_py addr allow 203.0.114.0/24 /dev/null; echo "rc=$?"')" = "$(printf '203.0.114.0/24\nrc=0')" ]
# Исключение целиком внутри частной или служебной сети — незачем: такие
# выкидываются из любого списка. Шире её (часть публичная) — можно.
check has "$(sh_run '_shield_py addr allow 203.0.113.0/24 /dev/null; echo "rc=$?"')" 'rc=5'
check has "$(sh_run '_shield_py addr allow 10.0.0.0/8 /dev/null; echo "rc=$?"')" 'rc=5'
check has "$(sh_run '_shield_py addr allow fd00::1 /dev/null; echo "rc=$?"')" 'rc=5'
check has "$(sh_run '_shield_py addr allow 192.0.0.0/16 /dev/null; echo "rc=$?"')" 'rc=0'
check has "$(sh_run '_shield_py addr block 10.1.0.0/16 /dev/null; echo "rc=$?"')" 'rc=5'
printf '45.0.5.7\n' > "$SF/d/own"
check has "$(sh_run '_shield_py addr block 45.0.5.0/24 "$SFD/own"; echo "rc=$?"')" 'rc=6'
check has "$(sh_run '_shield_py addr block 4.0.0.0/7 /dev/null; echo "rc=$?"')" 'rc=3'
check has "$(sh_run '_shield_py addr block "1.2.3.4/24" /dev/null; echo "rc=$?"')" 'rc=2'
check has "$(sh_run '_shield_py addr block "1.2.3.4; rm -rf /" /dev/null; echo "rc=$?"')" 'rc=2'
# TVK-AS: сети блока AS и строки NET-Name, только пересекающие список;
# чужая AS и похожее имя (TVK-ASX) не в счёт.
out=$(sh_run '_shield_py list "$SFS/blacklist-v4.txt" 4 "$SFD/s4" >/dev/null; : > "$SFD/s6"
    _shield_py tvk "$SFS/blacklist_with_comments.txt" TVK-AS "$SFD/s4" "$SFD/s6" "$SFD/t4" "$SFD/t6"; cat "$SFD/t4"')
check [ "$out" = "$(printf '2\n46.0.3.0/24\n178.17.176.0/23')" ]

# Сборка shield.nft против эталона: наборы (свёрнутые, частные и служебные
# исключения, TVK, свои исключения и добавки), порядок цепочек, сеть с
# адресом сервера выкинута в журнал. Эталон — текст целиком, табуляции.
G="$SF/g"; rm -rf "$G"; mkdir -p "$G/lists"
printf '45.0.0.0/24\n45.0.1.0/24\n46.0.0.0/16\n' > "$G/lists/scan4"; printf '2a00:1::/32\n' > "$G/lists/scan6"
printf '45.0.1.0/24\n' > "$G/lists/vk4"; : > "$G/lists/vk6"; printf '46.0.3.0/24\n' > "$G/lists/tvk4"; : > "$G/lists/tvk6"
printf '198.51.7.0/24\n' > "$G/exclude"; printf '8.8.8.8/32\n' > "$G/block"; printf '46.0.9.1\n' > "$G/addrs"
check [ "$(sh_run '_shield_py render "'"$G"'" 1 1 "22" "'"$G"'/addrs" "'"$G"'/out"')" = "nets=4 nx=3 dropped=1 prx=0" ]
check [ "$(cat "$G/dropped" 2>/dev/null)" = "46.0.0.0/16 own 46.0.9.1" ]
cat > "$G/want" <<'NFT'
table inet goinstall_shield {}
delete table inet goinstall_shield
table inet goinstall_shield {
	set allow4 {
		type ipv4_addr
		flags interval
		auto-merge
		elements = {
			0.0.0.0/8, 10.0.0.0/8, 46.0.3.0/24, 46.0.9.1/32, 100.64.0.0/10, 127.0.0.0/8,
			169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 192.88.99.0/24, 192.168.0.0/16,
			198.18.0.0/15, 198.51.7.0/24, 198.51.100.0/24, 203.0.113.0/24, 224.0.0.0/3
		}
	}
	set allow6 {
		type ipv6_addr
		flags interval
		auto-merge
		elements = {
			::/127, ::ffff:0.0.0.0/96, 64:ff9b::/96, 64:ff9b:1::/48, 100::/64, 2001:db8::/32,
			fc00::/7, fe80::/10, ff00::/8
		}
	}
	set scan4 {
		type ipv4_addr
		flags interval
		auto-merge
		elements = {
			8.8.8.8/32, 45.0.0.0/23
		}
	}
	set scan6 {
		type ipv6_addr
		flags interval
		auto-merge
		elements = {
			2a00:1::/32
		}
	}
	set vk4 {
		type ipv4_addr
		flags interval
		auto-merge
		elements = {
			45.0.1.0/24
		}
	}
	set vk6 {
		type ipv6_addr
		flags interval
		auto-merge
	}
	chain incoming {
		type filter hook prerouting priority -150; policy accept;
		iif "lo" accept
		tcp dport { 22 } accept
		ip saddr @allow4 accept
		ip6 saddr @allow6 accept
		ip saddr @scan4 ct direction original counter drop
		ip6 saddr @scan6 ct direction original counter drop
		ct state established,related accept
		ip saddr @scan4 counter drop
		ip6 saddr @scan6 counter drop
	}
	chain vk_forward {
		type filter hook forward priority 0; policy accept;
		ip daddr @allow4 accept
		ip6 daddr @allow6 accept
		ip daddr @vk4 meta l4proto tcp counter reject with tcp reset
		ip daddr @vk4 counter reject with icmpx type admin-prohibited
		ip6 daddr @vk6 meta l4proto tcp counter reject with tcp reset
		ip6 daddr @vk6 counter reject with icmpx type admin-prohibited
	}
	chain vk_output {
		type filter hook output priority 0; policy accept;
		ip daddr @allow4 accept
		ip6 daddr @allow6 accept
		ip daddr @vk4 meta l4proto tcp counter reject with tcp reset
		ip daddr @vk4 counter reject with icmpx type admin-prohibited
		ip6 daddr @vk6 meta l4proto tcp counter reject with tcp reset
		ip6 daddr @vk6 counter reject with icmpx type admin-prohibited
	}
}
NFT
check cmp -s "$G/want" "$G/out"
cmp -s "$G/want" "$G/out" || diff "$G/want" "$G/out" | head -20
# Без ВК — цепочек исходящих и наборов ВК нет вовсе; без сканеров — нет incoming.
sh_run '_shield_py render "'"$G"'" 1 0 "22 2222" "'"$G"'/addrs" "'"$G"'/o2"' >/dev/null
o2=$(cat "$G/o2" 2>/dev/null)
check has "$o2" 'tcp dport { 22, 2222 } accept'; check hasnt "$o2" 'vk_output'; check hasnt "$o2" 'set vk4'
sh_run '_shield_py render "'"$G"'" 0 1 "22" "'"$G"'/addrs" "'"$G"'/o3"' >/dev/null
o3=$(cat "$G/o3" 2>/dev/null)
check hasnt "$o3" 'chain incoming'; check has "$o3" 'chain vk_output'; check hasnt "$o3" 'set scan4'

sh_run '_shield_py render "'"$G"'" 0 0 "22" "'"$G"'/addrs" "'"$G"'/o4"' >/dev/null
check [ "$(cat "$G/o4" 2>/dev/null)" = "$(printf 'table inet goinstall_shield {}\ndelete table inet goinstall_shield')" ]

# Установка целиком: скачать, проверить, собрать, nft -c, nft -f, юниты.
sh_reset
out=$(sh_run 'shield_install; echo "rc=$?"')
check has "$out" 'rc=0'
check has "$out" 'Защита от сканеров включена'
check [ "$(sed -n 1p "$SF/d/nft.calls")" = "list tables" ]
check grep -qx -- "-c -f $SF/dir/shield.nft.new" "$SF/d/nft.calls"
check grep -qx -- "-f $SF/dir/shield.nft.new" "$SF/d/nft.calls"
check [ "$(grep -n -m1 -- '^-c -f' "$SF/d/nft.calls" | cut -d: -f1)" -lt "$(grep -n -m1 -- '^-f' "$SF/d/nft.calls" | cut -d: -f1)" ]
# Правила: одна транзакция, своя таблица, порядок цепочки входящих по ТЗ.
nf_="$SF/dir/shield.nft"
check [ "$(sed -n 1,3p "$nf_")" = "$(printf 'table inet goinstall_shield {}\ndelete table inet goinstall_shield\ntable inet goinstall_shield {')" ]
inc=$(sed -n '/chain incoming {/,/^\t}/p' "$nf_")
check [ "$(printf '%s\n' "$inc" | sed -n 2,14p | tr -d '\t')" = "$(printf '%s\n' 'type filter hook prerouting priority -150; policy accept;' 'iif "lo" accept' 'tcp dport { 22, 2222 } accept' 'ip saddr @allow4 accept' 'ip6 saddr @allow6 accept' 'ct state new ip saddr @scan4 jump stat4' 'ct state new ip6 saddr @scan6 jump stat6' 'ip saddr @scan4 ct direction original counter drop' 'ip6 saddr @scan6 ct direction original counter drop' 'ct state established,related accept' 'ip saddr @scan4 counter drop' 'ip6 saddr @scan6 counter drop' '}')" ]
# REVIEW-4 №9 (К3-5): что цепочка делает с пакетами — разбором правил по
# порядку (модель nft на нужное подмножество: iif, tcp dport, saddr @набор,
# ct direction, ct state; незнакомое слово — ошибка, а не «совпало»). Пакет
# без conntrack (invalid, untracked) — без direction и state. Соединение,
# открытое сканером, режется и установленным; ответы на исходящие соединения
# сервера (и ICMP-ошибки о них — related reply) проходят; SSH — всегда.
cat > "$SF/nfteval.py" <<'PY'
import sys, re, ipaddress
txt = open(sys.argv[1]).read()
sets = {}
for m in re.finditer(r'\tset (\w+) \{(.*?)\n\t\}', txt, re.S):
    el = re.search(r'elements = \{(.*?)\}', m.group(2), re.S)
    sets[m.group(1)] = [ipaddress.ip_network(x.strip()) for x in el.group(1).split(',')] if el else []
body = re.search(r'chain incoming \{\n(.*?)\n\t\}', txt, re.S).group(1)
rules = [l.strip() for l in body.split('\n') if l.strip() and not l.strip().startswith('type ')]
def match(rule, p):
    t = rule.split()
    v, t, i = t[-1], t[:-1], 0
    if t and t[-1] == 'jump':
        v, t = 'jump ' + v, t[:-1]
    while i < len(t):
        w = t[i]
        if w == 'counter':
            i += 1
        elif w == 'iif':
            if p.get('iif') != t[i + 1].strip('"'): return None
            i += 2
        elif w == 'tcp' and t[i + 1] == 'dport' and t[i + 2] == '{':
            j = t.index('}', i)
            if p.get('proto') != 'tcp' or p.get('dport') not in {int(x.strip(',')) for x in t[i + 3:j]}: return None
            i = j + 1
        elif w in ('ip', 'ip6') and t[i + 1] == 'saddr' and t[i + 2].startswith('@'):
            a = ipaddress.ip_address(p['src'])
            if (a.version == 4) != (w == 'ip') or not any(a in n for n in sets[t[i + 2][1:]]): return None
            i += 3
        elif w == 'ct' and t[i + 1] == 'direction':
            if p.get('dir') != t[i + 2]: return None
            i += 3
        elif w == 'ct' and t[i + 1] == 'state':
            if p.get('state') not in t[i + 2].split(','): return None
            i += 3
        else:
            sys.exit('unknown %r in %r' % (w, rule))
    if v not in ('accept', 'drop') and not re.fullmatch(r'jump stat[46]', v): sys.exit('verdict %r' % v)
    return v
# Прыжок в цепочку счёта ничего не решает (сама цепочка только считает —
# проверено отдельно): отмечается «+stat4» и разбор идёт дальше.
def verdict(p):
    j = ''
    for r in rules:
        v = match(r, p)
        if v and v.startswith('jump '):
            j += '+' + v[5:]
        elif v:
            return v + j
    return 'accept' + j
S = '45.0.4.10'
for name, p in [
        ('new', dict(src=S, proto='tcp', dport=443, dir='original', state='new')),
        ('est', dict(src=S, proto='tcp', dport=443, dir='original', state='established')),
        ('reply', dict(src=S, proto='tcp', dport=40000, dir='reply', state='established')),
        ('icmperr', dict(src=S, proto='icmp', dir='reply', state='related')),
        ('ssh', dict(src=S, proto='tcp', dport=2222, dir='original', state='established')),
        ('invalid', dict(src=S, proto='tcp', dport=443)),
        ('lo', dict(src=S, iif='lo', proto='tcp', dport=443, dir='original', state='new')),
        ('est6', dict(src='2a00:2::5', proto='tcp', dport=443, dir='original', state='established')),
        ('reply6', dict(src='2a00:2::5', proto='tcp', dport=40000, dir='reply', state='established')),
        ('other', dict(src='9.9.9.9', proto='tcp', dport=443, dir='original', state='new')),
        ('new6', dict(src='2a00:2::5', proto='tcp', dport=443, dir='original', state='new'))]:
    print(name, verdict(p))
PY
check [ "$(python3 -I "$SF/nfteval.py" "$nf_" | tr '\n' ' ')" = 'new drop+stat4 est drop reply accept icmperr accept ssh accept invalid drop lo accept est6 drop reply6 accept other accept new6 drop+stat6 ' ]
check grep -q 'flags interval' "$nf_"; check grep -q 'auto-merge' "$nf_"
# Что не будет работать при закрытом ВК — списком, по строке на пункт
# (решение владельца 03.11, 1.2.3). has() — grep -F: многострочный образец
# там — «любая из строк», поэтому подряд идущие строки — has_ml.
has_ml() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
vkl_=$(printf '     • %s\n' 'ВКонтакте и VK Видео' 'Одноклассники' 'Mail.ru (почта, облако)' 'мессенджер Макс' 'Дзен' 'RuStore' 'Юла' 'VK Play' 'VK Cloud' 'и другие сервисы VK')
vkle_=$(printf '     • %s\n' 'VKontakte and VK Video' 'Odnoklassniki (OK)' 'Mail.ru (mail, cloud)' 'Max messenger' 'Dzen' 'RuStore' 'Youla' 'VK Play' 'VK Cloud' 'and other VK services')
vkh_='Сети ВК закрыты — через VPN и с самого сервера не будут работать:'
vko_='Выключить ВК: goinstall --shield vk off или пункт 2 в меню «Защита от сканеров».'
# ВК по умолчанию включён (решение владельца 03.11, 1.2.2): новая установка
# пишет vk=1 и ставит цепочки ВК; об исходящих самого сервера — сказано.
check grep -qx 'vk=1' "$SF/dir/settings"; check grep -qx 'scan=1' "$SF/dir/settings"
check grep -q 'chain vk_forward {' "$nf_"; check grep -q 'chain vk_output {' "$nf_"
check grep -q 'type filter hook forward priority 0; policy accept;' "$nf_"
check has "$(sed -n '/set vk4 {/,/^\t}/p' "$nf_")" '45.1.0.0/21'
check has_ml "$out" "${vkh_}"$'\n'"${vkl_}"$'\n'; check has "$out" "$vko_"
check hasnt "$out" 'клиентов каскада'
check hasnt "$out" 'ВК пуст'
# Явный «vk off» после установки — ВК снят, дальше набор идёт с выключенным ВК.
check has "$(sh_run 'shield_toggle vk 0; echo "rc=$?"')" 'rc=0'
check grep -qx 'vk=0' "$SF/dir/settings"
check neg grep -q 'chain vk_' "$nf_"
# Сеть с адресом сервера и частная — выкинуты и в журнале; TVK — в allow.
s4=$(sed -n '/set scan4 {/,/^\t}/p' "$nf_")
check hasnt "$s4" '45.0.5.0/24'; check hasnt "$s4" '10.20.0.0/16'; check has "$s4" '45.0.4.0/24'
check has "$(sed -n '/set allow4 {/,/^\t}/p' "$nf_")" '178.17.176.0/23'
check has "$(sed -n '/set allow4 {/,/^\t}/p' "$nf_")" '45.0.5.7/32'
check has "$(sed -n '/set scan6 {/,/^\t}/p' "$nf_")" '2a00:2::/32'
check hasnt "$(sed -n '/set scan6 {/,/^\t}/p' "$nf_")" '2a00:1::/32'
check grep -q 'выкинута сеть.*45.0.5.0/24 own 45.0.5.7' "$SF/dir/shield.log"
check grep -q 'выкинута сеть.*10.20.0.0/16 special' "$SF/dir/shield.log"
check grep -q 'список принят: v4 419, v6 3, ВК 10+1, TVK-AS 2' "$SF/dir/shield.log"
# Права: каталог 0700, файлы 0600, юниты 0644.
check [ "$(stat -f %Lp "$SF/dir" 2>/dev/null || stat -c %a "$SF/dir")" = 700 ]
check [ -z "$(find "$SF/dir" -type f ! -perm 600 ! -name runner.sh)" ]
check [ "$(stat -f %Lp "$SF/units/goinstall-shield.timer" 2>/dev/null || stat -c %a "$SF/units/goinstall-shield.timer")" = 644 ]
# Таймер зовёт свою копию скрипта (0700), а не goinstall: его подменяют
# --self-update и bash <(curl …). Здесь goinstall — заглушка без --shield.
check cmp -s "$SCRIPT" "$SF/dir/runner.sh"
check [ "$(stat -f %Lp "$SF/dir/runner.sh" 2>/dev/null || stat -c %a "$SF/dir/runner.sh")" = 700 ]
check grep -qx "ExecStart=/bin/bash $SF/dir/runner.sh --shield tick" "$SF/units/goinstall-shield.service"
check grep -qx "ConditionPathExists=$SF/dir/runner.sh" "$SF/units/goinstall-shield.service"
# Загрузке сеть не нужна (REVIEW-2 №6): network-online только порядком, не Wants.
check neg grep -q '^Wants=' "$SF/units/goinstall-shield.service"
check grep -qx 'After=network.target network-online.target' "$SF/units/goinstall-shield.service"
# Таймер и слежка — тоже только при живой копии (REVIEW-2 №4): после удаления
# goInstaller прежней версией они после загрузки не запускаются.
check grep -qx "ConditionPathExists=$SF/dir/runner.sh" "$SF/units/goinstall-shield.timer"
check grep -qx "ConditionPathExists=$SF/dir/runner.sh" "$SF/units/goinstall-shield.path"
check grep -qx 'PathChanged=/etc/ssh/sshd_config.d' "$SF/units/goinstall-shield.path"
# sshd перезапущен (уже слушает новые порты) — такт сразу: прежний порт уходит
# из правил, а не ждёт следующей сверки (круг 2, мелочь).
check grep -qx 'PathChanged=/run/sshd.pid' "$SF/units/goinstall-shield.path"
check grep -qx 'Unit=goinstall-shield.service' "$SF/units/goinstall-shield.path"
check grep -q 'enable goinstall-shield.service goinstall-shield.timer goinstall-shield.path' "$SF/d/systemctl"
check grep -qx 'OnUnitActiveSec=1h' "$SF/units/goinstall-shield.timer"
check grep -qx 'RandomizedDelaySec=10min' "$SF/units/goinstall-shield.timer"
check grep -q 'enable goinstall-shield.service goinstall-shield.timer' "$SF/d/systemctl"
check neg grep -q 'nftables' "$SF/d/systemctl"
# Ключ клуба к C24Be не уходит: ни в аргументах curl, ни в его конфиге.
check neg grep -qi 'authorization\|ghp_shieldtesttoken' "$SF/d/curl.args" "$SF/d/curl.cfg"
check [ -z "$(grep -v -- '^-q --config ' "$SF/d/curl.args")" ]
check [ "$(sed -n 1p "$SF/d/urls")" = "https://api.github.com/repos/C24Be/AS_Network_List/commits/main" ]
check [ "$(sed -n 2p "$SF/d/urls")" = "https://raw.githubusercontent.com/C24Be/AS_Network_List/0123456789abcdef0123456789abcdef01234567/blacklists/blacklist-v4.txt" ]
check grep -qx 'proto = "=https"' "$SF/d/curl.cfg"
check [ ! -e "$SF/dir/.curl" ]
# Такт через копию: goinstall здесь без --shield, а таймер работает.
sh_cmd() {  # sh_cmd <аргументы> — копия скрипта как из юнита (main, без source)
    ( export PATH="$SF/bin:$PATH" SFD="$SF/d" SFS="${SFS:-$SF/src}" GOINST_LANG=ru GOINST_TEST=1 GOINST_OS_RELEASE="$T/os-ubuntu2604"
      export GOINST_GH_RETRY_DELAY=0 GOINST_SHIELD_DIR="$SF/dir" GOINST_SHIELD_RUN="$SF/d/boot" GOINST_SYSTEMD_DIR="$SF/units"
      export GOINST_SHIELD_CG="$SF/d/cg" GOINST_SHIELD_NFT="$SF/bin/nft" GOINST_SHIELD_ADDRS="45.0.5.7 2a00:1::5" GOINST_SS_FIXTURE="$SF/ss" GOINST_FS_ROOT="$SF/fs"
      export GOINST_BIN="$SF/goinstall" GOINST_DIR="$SF/gd"
      bash "$SF/dir/runner.sh" "$@" ) 2>&1
}
rm -f "$SF/d/boot"
out=$(sh_cmd --shield tick; echo "rc=$?")
check has "$out" 'rc=0'
check [ -e "$SF/d/boot" ]
check grep -q 'применено после загрузки' "$SF/dir/shield.log"
# Прежняя копия и прежний юнит (ExecStart на goinstall) — sync приводит к этой
# версии; копию новее не трогает; без перемен systemctl не зовёт.
sed "s/^GOINST_VERSION=\"$GIV\"\$/GOINST_VERSION=\"1.1.9\"/" "$SCRIPT" > "$SF/dir/runner.sh"
printf '[Service]\nExecStart=%s --shield tick\n' "$SF/goinstall" > "$SF/units/goinstall-shield.service"
: > "$SF/d/systemctl"
out=$(sh_run 'shield_sync; echo "rc=$?"')
check has "$out" 'rc=0'
check cmp -s "$SCRIPT" "$SF/dir/runner.sh"
check grep -qx "ExecStart=/bin/bash $SF/dir/runner.sh --shield tick" "$SF/units/goinstall-shield.service"
check grep -qx 'daemon-reload' "$SF/d/systemctl"
check grep -q "юниты переписаны под версию $GIV" "$SF/dir/shield.log"
: > "$SF/d/systemctl"
out=$(sh_run 'shield_sync; echo "rc=$?"')
check [ ! -s "$SF/d/systemctl" ]
sed "s/^GOINST_VERSION=\"$GIV\"\$/GOINST_VERSION=\"9.9.9\"/" "$SCRIPT" > "$SF/dir/runner.sh"
printf '[Service]\nExecStart=new\n' > "$SF/units/goinstall-shield.service"
out=$(sh_run 'shield_sync; echo "rc=$?"')
check grep -qx 'GOINST_VERSION="9.9.9"' "$SF/dir/runner.sh"
check [ "$(cat "$SF/units/goinstall-shield.service")" = "$(printf '[Service]\nExecStart=new')" ]
cp "$SCRIPT" "$SF/dir/runner.sh"; chmod 700 "$SF/dir/runner.sh"
out=$(sh_run 'shield_units_write; echo "rc=$?"')
# Самообновление на версию без защиты: правила остаются, сказано, как снять.
out=$(sh_run 'shield_self_update_note "$GOINST_BIN"')
check has "$out" "bash $SF/dir/runner.sh --shield remove --yes"
# …и что удаление goInstaller старой версией защиту не снимет (REVIEW-2 №4).
check has "$out" 'до удаления goInstaller: удаление этой версией защиту не снимет'
check has "$out" "юниты goinstall-shield — в $SF/units"
check has "$(sh_run 'LANG_CODE=en; shield_self_update_note "$GOINST_BIN"')" 'removing it with this version does not remove the protection'
check grep -q 'goinstall заменён версией без защиты' "$SF/dir/shield.log"
check [ -z "$(sh_run 'shield_self_update_note "$SCRIPT"')" ]
check grep -q 'shield_self_update_note "$dest"' "$SCRIPT"
check grep -q 'shield_self_update_note "$GOINST_BIN"' "$SCRIPT"
# Состояние и строка меню.
out=$(sh_run 'shield_state --live; echo "$SHS_ST $SHS_N $SHS_NX $SHS_DROPS"; shield_menu_line; echo "$SHS_MST|$SHS_MSUB"')
# Отброшено — сумма всех drop: поддельный nft даёт каждому по 5, drop
# сканеров четыре (direction original и без conntrack, v4 и v6). Настоящий
# пакет попадает только в один из них.
check has "$out" 'ok 418 6 20'
check has "$out" 'g:вкл|418 сетей · список от'
# Строка в главном меню (оба режима) и пункт s, русская раскладка «ы».
check has "$(sh_run 'menu_items_main >/dev/null 2>&1; printf "%s\n" "${MENU_ITEMS[@]}"')" 's|Защита от сканеров|g:вкл'
check [ "$(sh_run 'KEY=ы; _menu_ru_key; echo $KEY')" = s ]
check has "$(code | sed -n '/^main_menu()/,/^}/p')" 's) shield_menu ;;'

# Такт: правила пропали — восстановлено, событие в журнале; на месте — тихо.
check [ "$(sh_run 'shield_check --quiet; echo "rc=$?"')" = "rc=0" ]
rm -f "$SF/d/live"
out=$(sh_run 'shield_tick; shield_state; echo "st=$SHS_ST"')
check has "$out" 'st=ok'
check [ -f "$SF/d/live" ]
check grep -q 'правила пропали (таблицы goinstall_shield нет) — восстановлено' "$SF/dir/shield.log"
# Таблица есть, но пустая (сброс чужим flush) — тоже восстанавливается.
sed -i.b '/elements = {/,/}/d' "$SF/d/live"; rm -f "$SF/d/live.b"
check [ "$(sh_run 'shield_check --quiet; echo "rc=$?"')" = "rc=0" ]
check grep -q 'правила сканеров пусты' "$SF/dir/shield.log"
# Проверка правил не листает таблицу целиком (наборы счёта — до ~139 тыс.
# записей): таблица — с -t, нужные наборы — по имени (REVIEW-6 №5).
: > "$SF/d/nft.calls"
check [ "$(sh_run '_shield_paths; shield_live_ok; echo "rc=$? $SHS_DROPS"')" = 'rc=0 20' ]   # 4 правила drop × 5
check grep -qx -- '-t list table inet goinstall_shield' "$SF/d/nft.calls"
check grep -qx 'list set inet goinstall_shield scan4' "$SF/d/nft.calls"
check neg grep -qx 'list table inet goinstall_shield' "$SF/d/nft.calls"
check neg grep -q 'list set inet goinstall_shield \(seen\|pair\|ports\)' "$SF/d/nft.calls"
: > "$SF/d/nft.calls"; sh_run 'shield_state --live' >/dev/null
check neg grep -qx 'list table inet goinstall_shield' "$SF/d/nft.calls"
# Пустой нужный набор (элементы стёрты только в нём) — замечен.
awk '/set scan4 \{/ { c = 1 } c && /elements = \{/ { skip = 1 } skip { if (/\}/) skip = 0; next } c && /^\t\}/ { c = 0 } { print }' "$SF/d/live" > "$SF/d/live.n" && mv -f "$SF/d/live.n" "$SF/d/live"
check [ "$(sh_run '_shield_paths; shield_live_ok; echo "rc=$? $SHIELD_LIVE"')" = 'rc=1 scan' ]
sh_run 'shield_check --quiet' >/dev/null
# Восстановить не вышло — ✗ и причина; код 1.
rm -f "$SF/d/live"
out=$(NFT_BAD=1 sh_run 'shield_check --quiet; echo "rc=$?"; shield_state; shield_probs; echo "st=$SHS_ST"; printf "%s\n" "${SHIELD_PROBS[@]}"')
check has "$out" 'rc=1'; check has "$out" 'st=bad'
check has "$out" 'nft не принял правила: Error: syntax error'
check has "$out" '|goinstall --shield check|err'
# На 46 колонках — причина коротко, а не «не работает» (круг 2, мелочь).
check has "$out" '|Защита от сканеров: правила не применились|goinstall --shield check|err'
out=$(sh_run 'shield_state; shield_probs; UD_PROB=("${SHIELD_PROBS[@]}"); UI_BODY=(); ui_alerts 46; printf "%s\n" "${UI_BODY[@]}"')
check has "$out" '✗ '; check has "$out" 'Защита от сканеров: правила не применились'
check [ "$(sh_run 'shield_cli check >/dev/null 2>&1; echo $?')" = 0 ]
# Порты SSH сменились — такт пересобирает правила.
sh_run 'shield_tick' >/dev/null
printf 'Port 2200\n' > "$SF/fs/etc/ssh/sshd_config"
sh_run 'shield_tick' >/dev/null
check grep -q 'tcp dport { 22, 2200 } accept' "$SF/dir/shield.nft"
check grep -q 'порты SSH, адреса сервера или службы-прокси сменились' "$SF/dir/shield.log"
# REVIEW-4 №8 (К3-8/15): fe80 у veth и адреса моста Docker правил не меняют
#    (частные и служебные и так в @allow) — в отпечаток не идут, и запуск
#    контейнера правила не пересобирает. Глобальный адрес — идёт.
fpa() { sh_run "_shield_paths; GOINST_SHIELD_ADDRS='$1'; _shield_fp_now"; }
check [ "$(fpa '45.0.5.7 2a00:1::5')" = "$(fpa '2a00:1::5 fe80::1 45.0.5.7 172.17.0.1 fd00::1 fe80::a8c1:abff:fe12:3456 45.0.5.7')" ]
check [ "$(fpa '45.0.5.7 2a00:1::5')" != "$(fpa '45.0.5.7 45.0.5.8 2a00:1::5')" ]
n0=$(grep -c 'службы-прокси сменились' "$SF/dir/shield.log")
sh_run '_shield_paths; GOINST_SHIELD_ADDRS="45.0.5.7 2a00:1::5 fe80::1 172.17.0.1 172.18.0.1 fe80::a8c1:abff:fe12:3456"; _shield_fp_sync' >/dev/null
check [ "$(grep -c 'службы-прокси сменились' "$SF/dir/shield.log")" = "$n0" ]
# Сверх находки: версия текста правил (SHIELD_RULES_REV) — в отпечатке.
#    Отпечаток прежней версии — первый же такт ставит новый текст правил (drop
#    по direction original), не дожидаясь обновления списка. Адрес один —
#    у прежней формулы (sort -u) та же сумма, отличает только версия.
sh_run '_shield_paths; GOINST_SHIELD_ADDRS=45.0.5.7; _shield_set "$SHIELD_DIR/status" "fp=$(shield_ssh_ports)|$(echo 45.0.5.7 | sort -u | cksum)"; _shield_fp_sync' >/dev/null
check [ "$(grep -c 'службы-прокси сменились' "$SF/dir/shield.log")" = "$(( n0 + 1 ))" ]
check [ "$(sh_run '_shield_paths; _shield_get "$SHIELD_DIR/status" fp' | cut -d'|' -f3)" = r4 ]
sh_run '_shield_paths; _shield_fp_sync' >/dev/null   # обратно: адреса набора
check [ "$(grep -c 'службы-прокси сменились' "$SF/dir/shield.log")" = "$(( n0 + 2 ))" ]
# REVIEW-4 №7 (К3-11): порядок адресов в отпечатке — не от языка. Поддельный
#    sort вне C-локали отдаёт обратный порядок (как сравнение по правилам языка);
#    отпечаток в en_US и C один и тот же — и без python (запасной путь).
RSORT=$(command -v sort); mkdir -p "$SF/sortbin" "$SF/nopy"
printf '#!/bin/sh\ncase "${LC_ALL:-${LC_COLLATE:-${LANG:-}}}" in C|C.*|POSIX) exec %s "$@" ;; esac\n%s "$@" | awk %s\n' \
    "$RSORT" "$RSORT" "'{ a[NR] = \$0 } END { for (i = NR; i > 0; i--) print a[i] }'" > "$SF/sortbin/sort"
printf '#!/bin/sh\nexit 1\n' > "$SF/nopy/python3"; chmod +x "$SF/sortbin/sort" "$SF/nopy/python3"
printf '45.0.5.7\n2a00:1::5\n46.0.9.1\n' > "$SF/addrs.fp"
check [ "$(LC_ALL=en_US.UTF-8 "$SF/sortbin/sort" -u "$SF/addrs.fp" | head -1)" = 46.0.9.1 ]
check [ "$(LC_ALL=C "$SF/sortbin/sort" -u "$SF/addrs.fp" | head -1)" = 2a00:1::5 ]
fpl() { sh_run "export PATH=\"${2:-}$SF/sortbin:\$PATH\" LC_ALL=$1; _shield_fp 22 \"$SF/addrs.fp\""; }
check [ "$(fpl en_US.UTF-8)" = "$(fpl C.UTF-8)" ]
check [ "$(fpl en_US.UTF-8 "$SF/nopy:")" = "$(fpl C.UTF-8 "$SF/nopy:")" ]
check [ "$(fpl C.UTF-8 "$SF/nopy:")" != "$(fpl C.UTF-8)" ]   # без python — правда запасной путь
# Порт ssh.socket (ListenStream в override, sshd_config не тронут) — тоже SSH:
# из systemd и из файлов (systemd не ответил).
out=$(SOCK_LISTEN='[::]:2200 0.0.0.0:2299' sh_run 'shield_ssh_ports')
check [ "$out" = "22 2200 2299" ]
mkdir -p "$SF/fs/etc/systemd/system/ssh.socket.d"
printf '[Socket]\nListenStream=\nListenStream=0.0.0.0:2400\nListenStream=[::]:2401\nListenStream=2402\n' > "$SF/fs/etc/systemd/system/ssh.socket.d/override.conf"
check [ "$(sh_run 'shield_ssh_ports')" = "22 2200 2400 2401 2402" ]
check [ "$(sh_run 'shield_check --quiet; echo "rc=$?"')" = "rc=0" ]
check grep -q 'tcp dport { 22, 2200, 2400, 2401, 2402 } accept' "$SF/dir/shield.nft"
rm -rf "$SF/fs/etc/systemd"
# Не только такт: проверка (--shield check, после установщика, меню) и
# состояние для меню сверяют порты сами — новый порт сразу в правилах.
printf 'Port 2201\n' > "$SF/fs/etc/ssh/sshd_config"
check [ "$(sh_run 'shield_check --quiet; echo "rc=$?"')" = "rc=0" ]
check grep -q 'tcp dport { 22, 2201 } accept' "$SF/dir/shield.nft"
printf 'Port 2203\n' > "$SF/fs/etc/ssh/sshd_config"
sh_run 'shield_state --live' >/dev/null
check grep -q 'tcp dport { 22, 2203 } accept' "$SF/dir/shield.nft"
# Пересобрать не вышло — сбой со словами, а не молчание.
printf 'Port 2202\n' > "$SF/fs/etc/ssh/sshd_config"
out=$(NFT_BAD=1 sh_run 'shield_check; echo "rc=$?"; shield_state; shield_probs; echo "st=$SHS_ST"; printf "%s\n" "${SHIELD_PROBS[@]}"')
check has "$out" 'rc=1'; check has "$out" 'st=bad'
check has "$out" 'порты SSH сменились, а правила не пересобрались: nft не принял правила'
check has "$out" '|Защита от сканеров: правила не пересобраны|'
check grep -q 'правила не пересобрались' "$SF/dir/shield.log"
check [ "$(sh_run '_shield_paths; _shield_get "$SHIELD_DIR/status" result')" = fail ]
printf 'Port 2222\n' > "$SF/fs/etc/ssh/sshd_config"
check [ "$(sh_run 'shield_check --quiet; echo "rc=$?"')" = "rc=0" ]
check grep -q 'tcp dport { 22, 2222 } accept' "$SF/dir/shield.nft"
# После загрузки (нет отметки в /run) — применить сохранённое, и только:
# в сеть не ходить, даже если список старше суток (oneshot держит загрузку).
sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" "date=$(( $(_shield_now) - 172800 ))"' >/dev/null
rm -f "$SF/d/boot" "$SF/d/live"; : > "$SF/d/urls"
sh_run 'shield_tick' >/dev/null
check [ -f "$SF/d/live" ]; check [ -f "$SF/d/boot" ]
check grep -q 'применено после загрузки' "$SF/dir/shield.log"
check [ ! -s "$SF/d/urls" ]
# Отметка загрузки — пустой файл только для root (круг 2, мелочь).
check [ "$(stat -f %Lp "$SF/d/boot" 2>/dev/null || stat -c %a "$SF/d/boot")" = 600 ]
check [ ! -s "$SF/d/boot" ]
# Первые 10 минут после загрузки и не загрузочный такт в сеть не ходит: его
# зовёт слежка за sshd.pid, а сеть может быть ещё не поднята (круг 2, мелочь).
GOINST_SHIELD_UPTIME=599 sh_run 'shield_tick' >/dev/null
check [ ! -s "$SF/d/urls" ]
# Пропуск не молча: строка в журнал (REVIEW-3 №4).
check grep -q 'обновление отложено: 599 с после загрузки' "$SF/dir/shield.log"
check [ "$(sh_run '_shield_uptime')" = 999999 ]
# Следующий такт — уже не загрузка: список старше суток обновляется.
GOINST_SHIELD_UPTIME=600 sh_run 'shield_tick' >/dev/null
check [ -s "$SF/d/urls" ]
check [ "$(sh_run '_shield_paths; echo $(( $(_shield_now) - $(_shield_num "$SHIELD_DIR/lists/meta" date) < 60 ))')" = 1 ]
# Порт SSH сменился, пока такт ходил в сеть (К2-3d): запуск от слежки в это
# время сливается с идущим тактом — такт сверяет порты ещё раз в конце.
# GitHub закрыт (обновление не прошло, правила не пересобирало).
sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" "date=$(( $(_shield_now) - 172800 ))"' >/dev/null
out=$(RAW_FAIL=1 SHA=7777777777777777777777777777777777777777 CURL_HOOK='printf "Port 2223\n" > "$GOINST_FS_ROOT/etc/ssh/sshd_config"' sh_run 'shield_tick; echo "rc=$?"')
check has "$out" 'rc=0'
check grep -q 'tcp dport { 22, 2223 } accept' "$SF/dir/shield.nft"
check [ "$(tail -1 "$SF/dir/shield.log" | grep -c 'порты SSH, адреса сервера или службы-прокси сменились — правила пересобраны')" = 1 ]
printf 'Port 2222\n' > "$SF/fs/etc/ssh/sshd_config"
sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" "date=$(_shield_now)"; shield_check --quiet' >/dev/null
check grep -q 'tcp dport { 22, 2222 } accept' "$SF/dir/shield.nft"
# Сломанный nft: в конце такта сверка — только если за такт что-то сменилось;
# одна строка «не пересобрались», а не три (REVIEW-3 №3).
printf 'Port 2224\n' > "$SF/fs/etc/ssh/sshd_config"
n0=$(wc -l < "$SF/dir/shield.log")
NFT_BAD=1 sh_run 'shield_tick' >/dev/null
check [ "$(tail -n +$(( n0 + 1 )) "$SF/dir/shield.log" | grep -c 'не пересобрались')" = 1 ]
check [ "$(sh_run '_shield_paths; _shield_get "$SHIELD_DIR/status" result')" = fail ]
# Начальная сверка не прошла, а к концу такта nft починили и порт сменился —
# итог в status по конечной сверке: ok, а не прежний fail.
sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" "date=$(( $(_shield_now) - 172800 ))"' >/dev/null
: > "$SF/d/nft.bad"
out=$(RAW_FAIL=1 SHA=7777777777777777777777777777777777777777 CURL_HOOK='rm -f "$SFD/nft.bad"; printf "Port 2225\n" > "$GOINST_FS_ROOT/etc/ssh/sshd_config"' sh_run 'shield_tick; echo "rc=$?"; echo "res=$(_shield_get "$SHIELD_DIR/status" result)"')
check has "$out" 'rc=0'; check has "$out" 'res=ok'
check grep -q 'tcp dport { 22, 2225 } accept' "$SF/dir/shield.nft"
check [ ! -e "$SF/d/nft.bad" ]
printf 'Port 2222\n' > "$SF/fs/etc/ssh/sshd_config"
sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" "date=$(_shield_now)"; shield_check --quiet' >/dev/null
check grep -q 'tcp dport { 22, 2222 } accept' "$SF/dir/shield.nft"

# Обновление: хеш тот же — не качаем; новый — качаем; отказы — прежний работает.
: > "$SF/d/urls"
out=$(sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" 'Списки не менялись'
check [ "$(grep -c . "$SF/d/urls")" = 1 ]
# Мало сетей (меньше 300) — отказ всему списку.
mkdir -p "$SF/src2"; cp "$SF/src/"* "$SF/src2/"
head -n 250 "$SF/src/blacklist-v4.txt" > "$SF/src2/blacklist-v4.txt"
cp "$SF/dir/lists/scan4" "$SF/d/scan4.before"
out=$(SFS="$SF/src2" SHA=1111111111111111111111111111111111111111 sh_run 'shield_update; echo "rc=$?"; shield_state; echo "rej=$SHS_REJ"')
check has "$out" 'rc=1'; check has "$out" 'всего 250 сетей'; check has "$out" 'Работает прежний'
check cmp -s "$SF/dir/lists/scan4" "$SF/d/scan4.before"
check has "$out" 'rej=в общем списке v4 всего 250 сетей'
check [ ! -d "$SF/dir/lists.new" ]
# Шире /8 — отказ.
{ cat "$SF/src/blacklist-v4.txt"; echo "44.0.0.0/7"; } > "$SF/src2/blacklist-v4.txt"
check has "$(SFS="$SF/src2" SHA=2222222222222222222222222222222222222222 sh_run 'shield_update')" 'слишком широкая сеть 44.0.0.0/7'
# Мусор — отказ.
{ cat "$SF/src/blacklist-v4.txt"; echo "<html>"; } > "$SF/src2/blacklist-v4.txt"
check has "$(SFS="$SF/src2" SHA=3333333333333333333333333333333333333333 sh_run 'shield_update')" 'не сеть'
# Втрое больше прошлого — отказ; вдвое меньше — отказ.
{ cat "$SF/src/blacklist-v4.txt"; for a in 2 3 4 5 6; do for b in $(seq 0 199); do echo "45.$a.$b.0/24"; done; done; } > "$SF/src2/blacklist-v4.txt"
check has "$(SFS="$SF/src2" SHA=4444444444444444444444444444444444444444 sh_run 'shield_update')" 'вырос больше чем втрое'
check cmp -s "$SF/dir/lists/scan4" "$SF/d/scan4.before"
# Охват, а не строки: все /8, кроме служебных, — 217 строк (меньше втрое
# прошлых 419), но это почти весь IPv4 — отказ по потолку.
check grep -qx 'u4=675' "$SF/dir/lists/meta"
{ cat "$SF/src/blacklist-v4.txt"; for a in $(seq 1 223); do case $a in 10|100|127|169|172|192|198|203) continue ;; esac; echo "$a.0.0.0/8"; done; } > "$SF/src2/blacklist-v4.txt"
out=$(SFS="$SF/src2" SHA=4444444444444444444444444444444444444441 sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=1'; check has "$out" 'список общий v4 накрывает'; check has "$out" 'больше потолка 16384'
check cmp -s "$SF/dir/lists/scan4" "$SF/d/scan4.before"
# Под потолком, но охват вырос больше чем втрое (10 /16: 675 → 3235).
{ cat "$SF/src/blacklist-v4.txt"; for a in $(seq 0 9); do echo "47.$a.0.0/16"; done; } > "$SF/src2/blacklist-v4.txt"
out=$(SFS="$SF/src2" SHA=4444444444444444444444444444444444444442 sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=1'; check has "$out" 'охват списка общий v4 вырос больше чем втрое: 3235 против 675 сетей /24'
sh_acc() {  # sh_acc <выражение> — shield_accept в отдельном каталоге $SFD/acc
    sh_run 'GOINST_SHIELD_DIR="$SFD/acc"; _shield_paths; mkdir -p "$SHIELD_DIR"; '"$1"
}
sh_mk() {  # sh_mk <сетей /24 в ВК v4> <общий v6> <ВК v6> — список в $SF/d/dl
    local i; mkdir -p "$SF/d/dl"
    for i in $(seq 0 399); do echo "45.$(( i / 200 + 10 )).$(( i % 200 )).0/24"; done > "$SF/d/dl/blacklist-v4.txt"
    for i in $(seq 0 $(( $1 - 1 ))); do echo "45.10.$i.0/24"; done > "$SF/d/dl/blacklist-vk-v4.txt"
    echo "$2" > "$SF/d/dl/blacklist-v6.txt"; echo "$3" > "$SF/d/dl/blacklist-vk-v6.txt"; : > "$SF/d/dl/blacklist_with_comments.txt"
}
sh_meta='grep -E "^u(vk)?[46]=" "$SHIELD_DIR/lists/meta" | tr "\n" " "'
# ВК проверяется отдельно от общего (REVIEW-2 №2): ВК не прошёл — остаётся
# прежний ВК, общий принимается, причина — в журнал, status, меню, «Аркаду».
# ВК v4 вне общего (такой ВК отрезал бы исходящие сервера).
cp "$SF/src/blacklist-v4.txt" "$SF/src2/blacklist-v4.txt"
cp "$SF/dir/lists/vk4" "$SF/d/vk4.before"; cp "$SF/dir/lists/vk6" "$SF/d/vk6.before"
{ cat "$SF/src/blacklist-vk-v4.txt"; echo "140.82.112.0/20"; } > "$SF/src2/blacklist-vk-v4.txt"
out=$(SFS="$SF/src2" SHA=4444444444444444444444444444444444444443 sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" 'Новый список ВК не прошёл проверку: в списке ВК v4 сеть 140.82.112.0/20 вне общего списка'
check has "$out" 'Списки обновлены'
check grep -qx 'sha=4444444444444444444444444444444444444443' "$SF/dir/lists/meta"
check cmp -s "$SF/dir/lists/vk4" "$SF/d/vk4.before"
check grep -q 'список ВК отклонён: в списке ВК v4 сеть 140.82.112.0/20 вне общего списка — похоже на порчу источника; работает прежний ВК' "$SF/dir/shield.log"
check grep -q 'список принят: .*ВК 10+1 (прежний)' "$SF/dir/shield.log"
out=$(sh_run 'shield_status_print' | sed $'s/\033\\[[0-9;]*m//g')
# ВК выключен — заметка серая, без «!» (REVIEW-3 №5): закрывать нечего.
check has "$out" 'ℹ  Последний список ВК отклонён, оставлен прежний (ВК выключен): в списке ВК v4 сеть 140.82.112.0/20'
out=$(sh_run 'shield_state; menu_items_shield >/dev/null 2>&1; printf "%s\n" "${MENU_ITEMS[@]}"')
check has "$out" '-||||  ! список ВК отклонён, оставлен прежний (ВК выключен):'
sh_ui='shield_state; GOINST_UI_COLS=80; GOINST_UI_LINES=24; ui_detect; UI_BODY=(); ui_scr_shield 0; printf "%s\n" "${UI_BODY[@]}"'
# В «Аркаде» заметка — в карточке справа (1.2.4), по словам в её ширину.
out=$(sh_run "$sh_ui" | tr '\037\036' '|#')
check has "$out" 'muted|Список ВК отклонён, оставлен прежний'; check has "$out" 'muted|(ВК выключен): в списке ВК v4 сеть'
# ВК включён — заметка жёлтая, без пометки.
sh_vk1='_shield_paths; cp "$SHIELD_DIR/settings" "$SFD/set.bak"; _shield_set "$SHIELD_DIR/settings" vk=1; '
out=$(sh_run "$sh_vk1"'shield_status_print; cp "$SFD/set.bak" "$SHIELD_DIR/settings"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" '!  Последний список ВК отклонён, оставлен прежний: в списке ВК v4 сеть 140.82.112.0/20'
out=$(sh_run "$sh_vk1"'shield_state; menu_items_shield >/dev/null 2>&1; printf "%s\n" "${MENU_ITEMS[@]}"; cp "$SFD/set.bak" "$SHIELD_DIR/settings"')
check has "$out" '-||||y:  ! список ВК отклонён, оставлен прежний:'
out=$(sh_run "$sh_vk1$sh_ui"'; cp "$SFD/set.bak" "$SHIELD_DIR/settings"' | tr '\037\036' '|#')
check has "$out" 'warn|! Список ВК отклонён, оставлен'; check has "$out" 'warn|прежний: в списке ВК v4 сеть'
# Хеш тот же (качать нечего) — причина ВК остаётся: список тот же.
out=$(SFS="$SF/src2" SHA=4444444444444444444444444444444444444443 sh_run 'shield_update >/dev/null; shield_state; echo "vk=$SHS_VKREJ"')
check has "$out" 'vk=в списке ВК v4 сеть 140.82.112.0/20'
# ВК v6 шире потолка.
cp "$SF/src/blacklist-vk-v4.txt" "$SF/src2/blacklist-vk-v4.txt"
printf '2a00:2::/32\n2a00::/16\n' > "$SF/src2/blacklist-vk-v6.txt"
out=$(SFS="$SF/src2" SHA=4444444444444444444444444444444444444444 sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" 'список ВК v6 накрывает 4294967296 сетей /48, больше потолка 16777216'
check cmp -s "$SF/dir/lists/vk6" "$SF/d/vk6.before"
cp "$SF/src/blacklist-vk-v6.txt" "$SF/src2/blacklist-vk-v6.txt"
check cmp -s "$SF/dir/lists/scan4" "$SF/d/scan4.before"
# Сеть ВК с адресом GitHub (К2-6C): vk_output отрезал бы сервер от
# обновлений — отказ ВК, v4 и v6.
out=$(GOINST_SHIELD_GH_ADDRS="140.82.121.6 45.1.3.7" SFS="$SF/src2" SHA=4444444444444444444444444444444444444446 sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" 'в списке ВК сеть 45.1.3.0/24 с адресом GitHub 45.1.3.7 — она отрезала бы сервер от обновлений'
out=$(GOINST_SHIELD_GH_ADDRS="2a00:2::154" SFS="$SF/src2" SHA=4444444444444444444444444444444444444447 sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" 'в списке ВК сеть 2a00:2::/32 с адресом GitHub 2a00:2::154'
check cmp -s "$SF/dir/lists/vk4" "$SF/d/vk4.before"
# Адреса GitHub вне ВК — ВК принят, причина прошлого отказа сброшена.
out=$(GOINST_SHIELD_GH_ADDRS="140.82.121.6 2606:50c0:8000::154" SFS="$SF/src2" SHA=4444444444444444444444444444444444444448 sh_run 'shield_update; echo "rc=$?"; shield_state; echo "vk=$SHS_VKREJ"')
check has "$out" 'rc=0'; check has "$out" 'vk='; check neg has "$out" 'ВК не прошёл'
check neg grep -q '^vkwhy=.' "$SF/dir/status"
# Адреса GitHub не разрешились — сверка ВК не молчит (REVIEW-3 №2а).
n0=$(wc -l < "$SF/dir/shield.log")
out=$(GOINST_SHIELD_GH_ADDRS="" SFS="$SF/src2" SHA=4444444444444444444444444444444444444449 sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=0'
check has "$(tail -n +$(( n0 + 1 )) "$SF/dir/shield.log")" 'сверка ВК с адресами GitHub пропущена: адреса GitHub не разрешились'
n0=$(wc -l < "$SF/dir/shield.log")
out=$(GOINST_SHIELD_GH_ADDRS="140.82.121.6 -raw.githubusercontent.com" SFS="$SF/src2" SHA=444444444444444444444444444444444444444a sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=0'
out=$(tail -n +$(( n0 + 1 )) "$SF/dir/shield.log")
check has "$out" 'сверка ВК с адресами GitHub неполная: не разрешились raw.githubusercontent.com'; check neg has "$out" 'пропущена'
# Принятый ВК сверяется с адресами GitHub и при «vk on», и в такте при
# включённом ВК (REVIEW-3 №2б): GitHub сменил адрес — vk_output отрезал бы
# сервер от обновлений, а обновление само это не вылечит.
out=$(GOINST_SHIELD_GH_ADDRS="45.1.3.7" sh_run 'shield_cli vk on; echo "rc=$?"')
check has "$out" 'rc=1'; check has "$out" 'ВК не включаю: в списке ВК сеть 45.1.3.0/24 с адресом GitHub 45.1.3.7'
check grep -qx 'vk=0' "$SF/dir/settings"
check grep -q 'ВК не включён: в списке ВК сеть 45.1.3.0/24 с адресом GitHub 45.1.3.7' "$SF/dir/shield.log"
check has "$(GOINST_SHIELD_GH_ADDRS="140.82.121.6" sh_run 'shield_cli vk on; echo "rc=$?"')" 'rc=0'
check grep -qx 'vk=1' "$SF/dir/settings"
out=$(GOINST_SHIELD_GH_ADDRS="45.1.3.7" sh_run 'shield_tick; echo "rc=$?"; shield_state; shield_probs; echo "st=$SHS_ST"; printf "%s\n" "${SHIELD_PROBS[@]}"')
check has "$out" 'rc=0'; check has "$out" 'st=bad'
check has "$out" '|Защита от сканеров: ВК закрыл GitHub|'
check grep -qx 'result=fail' "$SF/dir/status"; check grep -qx 'wk=gh' "$SF/dir/status"
check grep -qx 'ghhit=45.1.3.0/24 45.1.3.7' "$SF/dir/status"
check grep -q '^why=в списке ВК сеть 45.1.3.0/24 с адресом GitHub 45.1.3.7 — сервер не дойдёт до обновлений; выключите ВК' "$SF/dir/status"
check grep -q 'в списке ВК сеть 45.1.3.0/24 с адресом GitHub 45.1.3.7 — сервер не дойдёт до обновлений: выключите ВК' "$SF/dir/shield.log"
check [ "$(sh_run 'shield_cli check >/dev/null 2>&1; echo $?')" = 1 ]
# Повторный «vk on» находку не стирает.
check has "$(sh_run 'shield_cli vk on')" '«ВК: не выпускать» уже включено.'
check grep -qx 'ghhit=45.1.3.0/24 45.1.3.7' "$SF/dir/status"
# Адрес в исключениях (цепочки ВК его пропускают) — сбой снят сразу, без DNS;
# такт стирает находку.
cp -p "$SF/dir/exclude" "$SF/d/exclude.before" 2>/dev/null || rm -f "$SF/d/exclude.before"
echo 45.1.3.7 >> "$SF/dir/exclude"
check [ "$(sh_run 'shield_cli check >/dev/null 2>&1; echo $?')" = 0 ]
GOINST_SHIELD_GH_ADDRS="45.1.3.7" sh_run 'shield_tick' >/dev/null
check grep -qx 'ghhit=' "$SF/dir/status"; check grep -q 'адресов GitHub в списке ВК больше нет' "$SF/dir/shield.log"
if [ -e "$SF/d/exclude.before" ]; then cp -p "$SF/d/exclude.before" "$SF/dir/exclude"; else rm -f "$SF/dir/exclude"; fi
# «vk off» снимает находку и сбой.
GOINST_SHIELD_GH_ADDRS="45.1.3.7" sh_run 'shield_tick' >/dev/null
check grep -qx 'ghhit=45.1.3.0/24 45.1.3.7' "$SF/dir/status"
check has "$(sh_run 'shield_cli vk off; echo "rc=$?"')" 'rc=0'
check grep -qx 'ghhit=' "$SF/dir/status"; check grep -qx 'result=ok' "$SF/dir/status"
check [ "$(sh_run 'shield_cli check >/dev/null 2>&1; echo $?')" = 0 ]
# Повтор проверяльщика: ВК выключен, общий вырос на 50 /24, в ВК v4 сеть
# вне общего — общий принят (n4 450), ВК прежний.
sh_mk 1 2a00:1::/32 2a00:1::/48
sh_acc 'shield_accept "$SFD/dl"' >/dev/null
for i in $(seq 0 49); do echo "46.1.$i.0/24"; done >> "$SF/d/dl/blacklist-v4.txt"
echo "93.186.224.0/24" >> "$SF/d/dl/blacklist-vk-v4.txt"
out=$(sh_acc 'printf "scan=1\nvk=0\n" > "$SHIELD_DIR/settings"; shield_accept "$SFD/dl"; echo "rc=$? vkerr=$SHIELD_VKERR"; grep -E "^(n4|vk4)=" "$SHIELD_DIR/lists/meta" | tr "\n" " "')
check has "$out" 'rc=0 vkerr=в списке ВК v4 сеть 93.186.224.0/24 вне общего'
check has "$out" 'n4=450 vk4=1 '; check grep -qx '45.10.0.0/24' "$SF/d/acc/lists/vk4"; check neg grep -q '93.186' "$SF/d/acc/lists/vk4"
# ВК не прошёл, а прежнего нет (первая установка) — ВК пуст, общий принят.
rm -rf "$SF/d/acc"
out=$(sh_acc 'shield_accept "$SFD/dl"; echo "rc=$?"; wc -c < "$SHIELD_DIR/lists/vk4"; grep -E "^(n4|vk4)=" "$SHIELD_DIR/lists/meta" | tr "\n" " "')
check has "$out" 'rc=0'; check has "$out" 'n4=450 vk4=0 '
check [ "$(sed -n 2p <<<"$out" | tr -d ' ')" = 0 ]
# Рост охвата — от прошлого, но не меньше пола (REVIEW-2 №1): однажды
# принятый крошечный список (ВК из одной /24, общий v6 из одной /48) не
# отклоняет следующий нормальный — иначе обновления вставали навсегда.
sh_mk 1 2a00:1::/48 2a00:1::/48
out=$(sh_acc 'shield_accept "$SFD/dl"; echo "rc=$? $SHIELD_ERR"; '"$sh_meta")
check has "$out" 'rc=0'; check has "$out" 'u6=1 '; check has "$out" 'uvk4=1 '; check has "$out" 'uvk6=1 '
sh_mk 100 2a00:1::/32 2a00:1::/40
out=$(sh_acc 'shield_accept "$SFD/dl"; echo "rc=$? $SHIELD_ERR"; '"$sh_meta")
check has "$out" 'rc=0'; check has "$out" 'u6=65536 '; check has "$out" 'uvk4=100 '; check has "$out" 'uvk6=256 '
# Пол не отменяет предел: втрое от пола (3 145 728 /48) — уже отказ.
sh_mk 100 2a00::/26 2a00:1::/40
out=$(sh_acc 'shield_accept "$SFD/dl"; echo "rc=$? $SHIELD_ERR"; '"$sh_meta")
check has "$out" 'rc=1 охват списка общий v6 вырос больше чем втрое: 4194304 против 65536 сетей /48'
check has "$out" 'u6=65536 '
# Хеша нет (403 от API) — качаем по ветке, не падаем.
: > "$SF/d/urls"
out=$(API_CODE=403 sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=0'
check grep -q '/AS_Network_List/main/blacklists/blacklist-v4.txt$' "$SF/d/urls"
# Хеш не того вида — тоже по ветке, в адрес не подставляется.
: > "$SF/d/urls"
SHA='../../evil/x' sh_run 'shield_update' >/dev/null
check neg grep -q 'evil' "$SF/d/urls"
{ cat "$SF/src/blacklist-v4.txt"; echo "<html>"; } > "$SF/src2/blacklist-v4.txt"
SFS="$SF/src2" SHA=4444444444444444444444444444444444444445 sh_run 'shield_update' >/dev/null
check [ "$(sh_run 'shield_state; echo "rej=$SHS_REJ"')" != "rej=" ]
# Сеть упала — причина словами, прежний работает.
out=$(RAW_FAIL=1 SHA=5555555555555555555555555555555555555555 sh_run 'shield_update; echo "rc=$?"')
check has "$out" 'rc=1'; check has "$out" 'Списки не скачались'
check cmp -s "$SF/dir/lists/scan4" "$SF/d/scan4.before"
# Прежний отказ (чужой список) больше не последний — его причина сброшена.
check [ "$(sh_run 'shield_state; echo "rej=$SHS_REJ"')" = "rej=" ]
# Причина последней неудачи видна в status, меню и «Аркаде» (SPEC: «сказать
# причину»); список старше 3 суток — check тоже сбой (код 1), как status.
mkdir -p "$SF/empty"
SFS="$SF/empty" SHA=6666666666666666666666666666666666666666 sh_run 'shield_update' >/dev/null
out=$(sh_run 'shield_status_print; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=0'; check has "$out" 'Последнее обновление не скачалось: '
check has "$out" '404'
check has "$(sh_run 'shield_state; menu_items_shield >/dev/null 2>&1; printf "%s\n" "${MENU_ITEMS[@]}"')" 'последнее обновление не скачалось'
# Пункт без состояния — пояснение в той же колонке, что у пунктов с состоянием.
out=$(sh_run 'menu_items_shield >/dev/null 2>&1; GREEN= YELLOW= RED= DIM= NC= BOLD=; menu_build_rows; for i in "${!MENU_KEY[@]}"; do r="${MENU_ROW[$i]}"; case "${MENU_KEY[$i]}" in 1) a="${r%%Сервер*}" ;; 9) b="${r%%Спросит*}" ;; esac; done; echo "$(str_len "$a")=$(str_len "$b")"')
check [ "${out%%=*}" -gt 20 ]; check [ "${out%%=*}" = "${out#*=}" ]
# Нумерованное меню понимает русскую раскладку, как стрелочное: «ы» — s.
check [ "$(sh_run 'MENU_TITLE=x; MENU_SUB=; MENU_ITEMS=("s|Защита|d:|" "0|Назад|d:|"); menu_build_rows; _pick_menu_plain <<<"ы" >/dev/null 2>&1; echo "k=$PICK_KEY"')" = "k=s" ]
check [ "$(sh_run 'MENU_TITLE=x; MENU_SUB=; MENU_ITEMS=("s|Защита|d:|" "0|Назад|d:|"); menu_build_rows; _pick_menu_plain <<<"0" >/dev/null 2>&1; echo "k=$PICK_KEY"')" = "k=0" ]
check has "$(sh_run 'shield_state; GOINST_UI_COLS=80; GOINST_UI_LINES=24; ui_detect; ui_scr_shield 0; ui_compose; ui_dump')" 'Последнее обновление не скачалось'
sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" "date=$(( $(_shield_now) - 345600 ))"' >/dev/null
check [ "$(sh_run 'shield_cli check >/dev/null 2>&1; echo $?')" = 1 ]
out=$(sh_run 'shield_status_print; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=1'; check has "$out" 'список не обновлялся больше 3 суток'
check has "$out" '— не скачался: '
# ✗ один: err сам ставит крестик.
check [ "$(grep -o '✗' <<<"$out" | wc -l | tr -d ' ')" = 1 ]
# Хеш прежний — свежий, причина сброшена.
sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" "sha=0123456789abcdef0123456789abcdef01234567"' >/dev/null
out=$(sh_run 'shield_update')
check has "$out" 'Списки не менялись'
out=$(sh_run 'shield_status_print; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=0'; check hasnt "$out" 'не скачалось'
check has "$out" 'отброшено пакетов 20 (с '
# Список старше 3 суток — ✗ в меню и сводке.
out=$(sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" "date=$(( $(_shield_now) - 300000 ))"; shield_state; shield_probs; echo "st=$SHS_ST $SHS_WHY"; printf "%s\n" "${SHIELD_PROBS[@]}"')
check has "$out" 'st=bad список не обновлялся больше 3 суток'
check has "$out" '|Защита от сканеров: список старше 3 суток|'
# Короткие причины влезают в 46 колонок: «  ✗ » и до 42 знаков.
out=$(sh_run 'for k in stale gh ports rules x; do for LANG_CODE in ru en; do l="$(bi "Защита от сканеров" "Scanner protection"): $(_shield_why_short $k)"; echo "$(str_len "$l") $l"; done; done')
check [ "$(grep -c . <<<"$out")" = 10 ]
check [ "$(awk '$1 > 42' <<<"$out")" = "" ]
sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" "date=$(_shield_now)"' >/dev/null

# Свои исключения и добавки, ВК: ввод проверяется строго.
out=$(sh_run 'shield_list_add exclude 45.0.7.0/24; echo "rc=$? $SHIELD_ADDED"; shield_list_add exclude 45.0.7.0/24; echo "rc=$? $SHIELD_ERR"
    shield_list_add block 10.0.0.1; echo "rc=$? $SHIELD_ERR"; shield_list_add block 45.0.5.7; echo "rc=$?"; shield_list_add block "8.8.8.8 junk"; echo "rc=$?"
    shield_list_add block 8.8.8.8; echo "rc=$? $SHIELD_ADDED"')
check has "$out" 'rc=0 45.0.7.0/24'; check has "$out" 'rc=1 уже в списке'; check has "$out" 'rc=1 частная или служебная'
check has "$out" 'rc=0 8.8.8.8/32'
check [ "$(grep -c '^rc=1' <<<"$out")" = 4 ]
check has "$(sh_run 'shield_list_add exclude 10.0.0.0/8; echo "rc=$? $SHIELD_ERR"')" 'rc=1 частная или служебная сеть — её и так не блокируем, исключать незачем'
check neg grep -q '^10\.' "$SF/dir/exclude"
# Убрали последнее исключение — файл пуст, добавлять можно: «grep -c . || echo 0»
# на пустом файле давал «0\n0», и добавление отвечало «уже 1000 строк».
out=$(sh_run 'shield_list_del exclude 1; echo "rc=$?"; shield_list_add exclude 45.0.7.0/24; echo "rc=$? $SHIELD_ADDED$SHIELD_ERR"; shield_list_del exclude 2; echo "rc=$?"')
check [ "$out" = "$(printf 'rc=0\nrc=0 45.0.7.0/24\nrc=1')" ]
check [ "$(cat "$SF/dir/exclude")" = 45.0.7.0/24 ]
out=$(sh_run 'shield_toggle vk 1; echo "rc=$?"')
check has "$out" '«ВК: не выпускать»: включено.'; check has_ml "$out" "${vkh_}"$'\n'"${vkl_}"$'\n'; check has "$out" "$vko_"
check has_ml "$(sh_run 'shield_toggle vk 0 >/dev/null; LANG_CODE=en; shield_toggle vk 1')" 'VK networks are closed — these will not work over the VPN or from the server itself:'$'\n'"${vkle_}"$'\n'
# Из меню список — до вопроса и один раз; после «Да» — как выключить.
out=$(sh_run 'shield_toggle vk 0 >/dev/null; _shield_paths; shield_do_vk <<<"1"; echo "rc=$?"')
check has_ml "$out" 'Соединения к сетям ВК будут отклоняться — через VPN и с самого сервера не будут работать:'$'\n'"${vkl_}"$'\n'
check [ "$(grep -c 'ВКонтакте и VK Видео' <<<"$out")" = 1 ]; check hasnt "$out" "$vkh_"
check has "$out" '«ВК: не выпускать»: включено.'; check has "$out" "$vko_"; check has "$out" 'rc=0'
check [ "$(awk '/ВКонтакте и VK Видео/ { a = NR } /Включить «ВК: не выпускать»\?/ { b = NR } END { print (a && b && a < b) }' <<<"$out")" = 1 ]
check grep -q 'chain vk_output {' "$SF/dir/shield.nft"; check grep -q 'chain vk_forward {' "$SF/dir/shield.nft"
check grep -q 'type filter hook output priority 0; policy accept;' "$SF/dir/shield.nft"
check grep -q 'ip daddr @vk4 meta l4proto tcp counter reject with tcp reset' "$SF/dir/shield.nft"
check grep -q 'counter reject with icmpx type admin-prohibited' "$SF/dir/shield.nft"
check has "$(sed -n '/set allow4 {/,/^\t}/p' "$SF/dir/shield.nft")" '45.0.7.0/24'
check has "$(sed -n '/set scan4 {/,/^\t}/p' "$SF/dir/shield.nft")" '8.8.8.8'
check [ "$(sh_run 'shield_state --live; echo "$SHS_REJS"')" = 16 ]
# Самопроверка сверяет ядро с загруженным shield.nft: набор ВК опустел в
# ядре (чужой flush set) — поломка, восстановлено; список ВК пуст на самом
# деле — не поломка, и такт не пересобирает правила каждый час.
awk '/set vk4 \{/ { c = 1 } c && /elements = \{/ { skip = 1 } skip { if (/^\t\t\}/) skip = 0; next } c && /^\t\}/ { c = 0 } { print }' "$SF/d/live" > "$SF/d/live.n" && mv -f "$SF/d/live.n" "$SF/d/live"
check hasnt "$(sed -n '/set vk4 {/,/^	}/p' "$SF/d/live")" 'elements'
check [ "$(sh_run 'shield_check --quiet; echo "rc=$?"')" = "rc=0" ]
check grep -q 'правила ВК пусты или неполны' "$SF/dir/shield.log"
check has "$(sed -n '/set vk4 {/,/^	}/p' "$SF/d/live")" 'elements'
cp "$SF/dir/lists/vk4" "$SF/d/vk4.keep"; cp "$SF/dir/lists/vk6" "$SF/d/vk6.keep"
: > "$SF/dir/lists/vk4"; : > "$SF/dir/lists/vk6"; sh_run '_shield_paths; shield_apply' >/dev/null
check hasnt "$(sed -n '/set vk4 {/,/^	}/p' "$SF/d/live")" 'elements'
n0=$(grep -c 'восстановлено' "$SF/dir/shield.log")
check [ "$(sh_run 'shield_check --quiet; echo "rc=$?"; shield_state --live; echo "st=$SHS_ST"')" = "$(printf 'rc=0\nst=ok')" ]
check [ "$(grep -c 'восстановлено' "$SF/dir/shield.log")" = "$n0" ]
cp "$SF/d/vk4.keep" "$SF/dir/lists/vk4"; cp "$SF/d/vk6.keep" "$SF/dir/lists/vk6"; sh_run '_shield_paths; shield_apply' >/dev/null
# Выключить всё — защиты нет; таблица остаётся только для счёта (1.2.4):
# ни drop, ни reject. Уровень 0 (счёта нет) — таблица снимается, как прежде.
sh_run 'shield_toggle scan 0; shield_toggle vk 0' >/dev/null
check [ -f "$SF/d/live" ]; check neg grep -q 'drop\|reject' "$SF/d/live"; check grep -q 'jump stat4' "$SF/d/live"
check [ "$(sh_run 'shield_state --live; echo "$SHS_ST"')" = off ]
NFT_STAT=0 sh_run '_shield_paths; shield_apply' >/dev/null
check [ ! -f "$SF/d/live" ]
check [ "$(sh_run 'shield_state --live; echo "$SHS_ST"')" = off ]
check [ "$(sh_run 'shield_cli on >/dev/null 2>&1; echo $?')" = 0 ]
check [ -f "$SF/d/live" ]

# Замок занят (такт или другой сеанс) — действие человека СРАЗУ говорит, что
# ждёт, без догадки, кто держит (REVIEW-2 №5), и ждёт до 3 минут; не дождалось —
# отказ словами, а не молчаливый возврат. Файл замка — только root.
# Поддельный flock пишет аргументы; FLOCK_BUSY0 — занят только без ожидания.
printf '#!/bin/bash\necho "$*" >> "$SFD/flock"\n[ -n "${FLOCK_RC:-}" ] && exit "$FLOCK_RC"\n[ -n "${FLOCK_BUSY0:-}" ] && [ "$2" = 0 ] && exit 1\nexit 0\n' > "$SF/bin/flock"; chmod +x "$SF/bin/flock"
rm -f "$SF/dir/.lock" "$SF/d/flock"
out=$(FLOCK_RC=1 sh_run 'shield_cli check; echo "rc=$?"')
check has "$out" 'rc=1'
check has "$out" 'Защиту сейчас занимает другая операция — жду её завершения (до 3 мин)'
check has "$out" 'Защита всё ещё занята другой операцией — попробуйте позже.'
check neg has "$out" 'по таймеру'
# Сначала без ожидания (сказать сразу), потом ждать 180 с (до них — shield_sync, тоже без ожидания).
check [ "$(tail -2 "$SF/d/flock" | sed 's/ [0-9]*$//' | tr '\n' '|')" = '-w 0|-w 180|' ]
check [ -n "$(find "$SF/dir/.lock" -perm 600)" ]
check has "$(FLOCK_RC=1 sh_run 'shield_cli update; echo "rc=$?"')" 'Защита всё ещё занята'
out=$(FLOCK_RC=1 sh_run 'printf "+\n45.1.2.3\n0\n" | shield_list_menu exclude')
check has "$out" 'Защита всё ещё занята'; check neg grep -q '45.1.2.3' "$SF/dir/exclude"
# Включить/выключить и удалить — те же слова (а не «через минуту»); ничего не тронуто.
out=$(FLOCK_RC=1 sh_run 'shield_cli vk on; echo "rc=$?"; shield_cli remove --yes; echo "rc=$?"')
check [ "$(grep -c 'Защита всё ещё занята' <<<"$out")" = 2 ]; check neg has "$out" 'rc=0'
check [ -f "$SF/dir/settings" ]; check neg grep -q '^vk=1' "$SF/dir/settings"
check neg grep -q 'попробуйте через минуту' "$SCRIPT"
# Освободилось за время ожидания — сказано «жду», и дело сделано.
: > "$SF/d/flock"
out=$(FLOCK_BUSY0=1 sh_run 'shield_cli check; echo "rc=$?"')
check has "$out" 'жду её завершения'; check neg has "$out" 'всё ещё занята'; check neg has "$out" 'rc=1'
# Свободно — молча.
check neg has "$(sh_run 'shield_cli check')" 'жду её завершения'
rm -f "$SF/bin/flock"
# Журнал после ротации — тоже только root (0600).
cp "$SF/dir/shield.log" "$SF/d/log.keep"
head -c 300000 /dev/zero | tr '\0' 'x' | fold -w 99 > "$SF/dir/shield.log"; chmod 644 "$SF/dir/shield.log"
sh_run 'shield_log "проба ротации"' >/dev/null
check [ -n "$(find "$SF/dir/shield.log" -perm 600)" ]
check [ "$(wc -l < "$SF/dir/shield.log")" -le 2000 ]; check grep -q 'проба ротации' "$SF/dir/shield.log"
cp "$SF/d/log.keep" "$SF/dir/shield.log"

# Команды: коды и вопросы без терминала.
check [ "$(sh_run 'shield_cli status >/dev/null 2>&1; echo $?')" = 0 ]
check [ "$(sh_run 'shield_cli bogus >/dev/null 2>&1; echo $?')" = 64 ]
check [ "$(sh_run 'shield_cli vk maybe >/dev/null 2>&1; echo $?')" = 64 ]
# Нет --yes без терминала — 64 (ошибка вызова), а не 3 («не стоит»).
out=$(sh_run 'shield_cli off </dev/null; echo "rc=$?"')
check has "$out" 'rc=64'; check has "$out" 'goinstall --shield off --yes'
check [ -f "$SF/d/live" ]
check has "$(sh_run 'shield_cli remove </dev/null; echo "rc=$?"')" 'rc=64'
out=$(sh_run 'shield_cli remove --yes </dev/null; echo "rc=$?"')
check has "$out" 'rc=0'
check [ ! -f "$SF/d/live" ]; check [ ! -e "$SF/units/goinstall-shield.timer" ]; check [ ! -e "$SF/dir/lists" ]
check grep -qx removed "$SF/dir/declined"
check [ "$(sh_run 'shield_cli status >/dev/null 2>&1; echo $?')" = 3 ]
check [ "$(sh_run 'shield_cli check >/dev/null 2>&1; echo $?')" = 3 ]
# Сервер без nft (контейнер): сказать словами, отметить, не ставить.
sh_reset
out=$(NFT_DEAD=1 sh_run 'shield_install; echo "rc=$?"; shield_state; echo "unsup=$SHS_UNSUP"')
check has "$out" 'rc=2'; check has "$out" 'unsup=nft есть, но не работает'
check [ ! -e "$SF/dir/settings" ]; check [ ! -e "$SF/units/goinstall-shield.timer" ]
# Списки не скачались — не ставим, предложим снова (отказ не записан).
sh_reset
out=$(RAW_FAIL=1 sh_run 'shield_install; echo "rc=$?"')
check has "$out" 'rc=1'; check has "$out" 'предложу в следующий раз'
check [ ! -e "$SF/dir/declined" ]; check [ ! -e "$SF/dir/settings" ]
check neg grep -q -- '-f ' "$SF/d/nft.calls"
# Нет файла этой версии (bash <(curl …), goinstall другой) — таймеру нечего
# запускать: не ставим и не предлагаем.
sh_reset
out=$(sh_run 'GOINST_SELF_PATH=/nonexistent; shield_install; echo "rc=$?"')
check has "$out" 'rc=1'; check has "$out" 'Таймеру защиты нечего запускать'
check [ ! -e "$SF/dir/settings" ]; check [ ! -e "$SF/d/urls" ]
check [ -z "$(GOINST_SHIELD_TEST=1 GOINST_SHIELD_TTY=1 sh_run 'GOINST_SELF_PATH=/nonexistent; shield_offer <<<"1"; echo "$SHIELD_SAID"')" ]
# Нет nft — ставим пакет; замок apt занят — сказать, кто держит и сколько ждём.
sh_reset
mkdir -p "$SF/fs/proc/4242/fd"; ln -sf /var/lib/dpkg/lock-frontend "$SF/fs/proc/4242/fd/3"; echo unattended-upgr > "$SF/fs/proc/4242/comm"
cat > "$SF/bin/apt-get" <<'APT'
#!/bin/bash
echo "$*" >> "$SFD/apt.calls"
case " $* " in *" install "*) cp "$SF_NFT" "$SFD/nft-new" ;; esac
APT
chmod +x "$SF/bin/apt-get"
out=$(SF_NFT="$SF/bin/nft" sh_run 'GOINST_SHIELD_NFT="$SFD/nft-new"; shield_install; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" 'Ставлю пакет nftables'
check has "$out" 'Пакетами сейчас занят процесс 4242 unattended-upgr'; check has "$out" 'до 15 минут'
check grep -q 'install --no-install-recommends nftables' "$SF/d/apt.calls"
# Замок свободен — о замке молчим.
sh_reset; rm -rf "$SF/fs/proc"
out=$(SF_NFT="$SF/bin/nft" sh_run 'GOINST_SHIELD_NFT="$SFD/nft-new"; shield_install; echo "rc=$?"')
check has "$out" 'rc=0'; check hasnt "$out" 'Пакетами сейчас занят'
rm -f "$SF/bin/apt-get"
# Первая установка, ВК не прошёл проверку, прежнего нет — ВК пуст и выглядит
# пустым (REVIEW-3 №1): причина в status и журнале, предупреждение, «vk on»
# отказывает; ВК не включается и при умолчании «вкл» (1.2.2) — сказано словами.
sh_reset
mkdir -p "$SF/src3" "$SF/dir"; cp "$SF/src/"* "$SF/src3/"
echo "140.82.112.0/20" >> "$SF/src3/blacklist-vk-v4.txt"
out=$(SFS="$SF/src3" sh_run 'shield_install; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=0'
check has "$out" 'Список ВК не прошёл проверку: в списке ВК v4 сеть 140.82.112.0/20 вне общего списка'
check has "$out" 'Прежнего нет — ВК пуст: «ВК: не выпускать» оставляю выключенным. Включить — пункт 2 в меню «Защита от сканеров», когда придёт исправный список.'
check hasnt "$out" 'Сети ВК закрыты'
check grep -q '^vkwhy=в списке ВК v4 сеть 140.82.112.0/20 вне общего списка' "$SF/dir/status"
check grep -q 'список ВК отклонён: в списке ВК v4 сеть 140.82.112.0/20 вне общего списка — похоже на порчу источника; прежнего нет — ВК пуст' "$SF/dir/shield.log"
check grep -q 'список принят: .*(пуст: прежнего нет)' "$SF/dir/shield.log"
check grep -qx 'vk=0' "$SF/dir/settings"; check [ ! -s "$SF/dir/lists/vk4" ]
check neg grep -q 'vk_forward' "$SF/d/live"
out=$(sh_run 'shield_cli vk on; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=1'
check has "$out" 'ВК не включаю: список ВК пуст — последний не прошёл проверку (в списке ВК v4 сеть 140.82.112.0/20'
# Не обещает включиться сам: после update ВК остаётся, как был (REVIEW-5 №5).
check has "$out" 'Включить можно, когда придёт исправный список: goinstall --shield update, затем goinstall --shield vk on.'
check hasnt "$out" 'Включится, когда'
check grep -qx 'vk=0' "$SF/dir/settings"; check neg grep -q 'vk_forward' "$SF/d/live"
# Из меню — отказ до пояснения и вопроса.
out=$(sh_run '_shield_paths; shield_do_vk </dev/null; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=1'; check has "$out" 'список ВК пуст'; check hasnt "$out" 'Включить «ВК: не выпускать»'
# status, меню, «Аркада»: «прежнего нет — ВК пуст», а не «оставлен прежний».
out=$(sh_run 'shield_status_print' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'Последний список ВК отклонён, прежнего нет — ВК пуст (ВК выключен): в списке ВК v4'
check hasnt "$out" 'оставлен прежний'
check has "$(sh_run 'shield_state; menu_items_shield >/dev/null 2>&1; printf "%s\n" "${MENU_ITEMS[@]}"')" 'список ВК отклонён, прежнего нет — ВК пуст (ВК выключен):'
out=$(sh_run 'shield_state; GOINST_UI_COLS=80; GOINST_UI_LINES=24; ui_detect; ui_scr_shield 0; ui_compose; ui_dump')
check has "$out" 'Список ВК отклонён, прежнего нет — ВК'; check has "$out" 'пуст (ВК выключен): в списке ВК v4'
# Список ВК принят, но пуст (в источнике пусто) — ВК не включается и при
# умолчании «вкл»; сказано словами, цепочек ВК нет.
sh_reset
mkdir -p "$SF/src3"; rm -f "$SF/src3/"*; cp "$SF/src/"* "$SF/src3/"
: > "$SF/src3/blacklist-vk-v4.txt"; : > "$SF/src3/blacklist-vk-v6.txt"
out=$(SFS="$SF/src3" sh_run 'shield_install; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=0'
check has "$out" 'Список ВК пуст — закрывать нечего: «ВК: не выпускать» оставляю выключенным. Включить — пункт 2 в меню «Защита от сканеров», когда придёт непустой список.'
check hasnt "$out" 'Сети ВК закрыты'; check hasnt "$out" 'не прошёл проверку'
check grep -qx 'vk=0' "$SF/dir/settings"; check grep -qx 'scan=1' "$SF/dir/settings"
check neg grep -q 'chain vk_' "$SF/dir/shield.nft"
check has "$(SFS="$SF/src3" sh_run 'LANG_CODE=en; _shield_paths; rm -f "$SHIELD_DIR/settings"; shield_install' | sed $'s/\033\\[[0-9;]*m//g')" 'The VK list is empty — nothing to block: “VK: block outbound” stays off. Turn it on with item 2 in the “Scanner protection” menu'
check grep -qx 'vk=0' "$SF/dir/settings"
# Стоящая защита (настройки 1.2.0/1.2.1): выбор ВК не переключается молча —
# ни при явном vk=0, ни без ключа vk (прежнее умолчание «выкл»). Предложение
# (стоит — только sync), такт, проверка, обновление, после установщика,
# «on» и повторная установка наперегонки ВК не включают.
for sv in 'scan=1\nvk=0\n' 'scan=1\n'; do
    sh_reset
    sh_run 'shield_install' >/dev/null
    check grep -qx 'vk=1' "$SF/dir/settings"
    printf "$sv" > "$SF/dir/settings"; cp "$SF/dir/settings" "$SF/d/set.old"
    sh_run '_shield_paths; shield_apply' >/dev/null
    check neg grep -q 'chain vk_' "$SF/dir/shield.nft"
    out=$(GOINST_SHIELD_TEST=1 GOINST_SHIELD_TTY=1 sh_run 'shield_offer <<<"1"; echo "said=$SHIELD_SAID"')
    check [ "$out" = "said=" ]
    sh_run 'shield_tick; shield_cli check; shield_cli status; shield_postcheck; shield_state --live; menu_items_shield' >/dev/null
    sh_run '_shield_paths; _shield_set "$SHIELD_DIR/lists/meta" date=1; shield_cli update' >/dev/null
    check cmp -s "$SF/dir/settings" "$SF/d/set.old"
    check neg grep -q 'chain vk_' "$SF/dir/shield.nft"; check neg grep -q 'vk_forward' "$SF/d/live"
    check [ "$(sh_run 'shield_state; echo "$SHS_VK"')" = 0 ]
    sh_run 'shield_cli on' >/dev/null
    check grep -qx 'vk=0' "$SF/dir/settings"; check neg grep -q 'chain vk_' "$SF/dir/shield.nft"
    printf "$sv" > "$SF/dir/settings"
    sh_run 'shield_install' >/dev/null
    check grep -qx 'vk=0' "$SF/dir/settings"; check neg grep -q 'chain vk_' "$SF/dir/shield.nft"
done
# «goinstall --shield on» там, где защиты не было, — тоже с ВК.
sh_reset
check [ "$(sh_run 'shield_cli on >/dev/null 2>&1; echo $?')" = 0 ]
check grep -qx 'vk=1' "$SF/dir/settings"; check grep -q 'chain vk_forward {' "$SF/dir/shield.nft"
check has "$(sh_run 'shield_cli check' | sed $'s/\033\\[[0-9;]*m//g')" 'Защита от сканеров работает.'
# Пункт меню «Включить защиту» (shield_do_on, «Аркада» sh:on) — тоже с ВК (REVIEW-5 №7).
cp "$SF/dir/settings" "$SF/set.on"; sh_reset
check [ "$(sh_run 'shield_do_on >/dev/null 2>&1; echo $?')" = 0 ]
check grep -qx 'vk=1' "$SF/dir/settings"; check grep -q 'chain vk_output {' "$SF/dir/shield.nft"
check cmp -s "$SF/dir/settings" "$SF/set.on"; rm -f "$SF/set.on"
# «off» сканеров при включённом ВК — сказано, что ВК остаётся.
out=$(sh_run 'shield_cli off --yes; echo "rc=$?"; shield_state; echo "st=$SHS_ST vk=$SHS_VK"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=0'; check has "$out" '«ВК: не выпускать» остаётся включённым. Выключить: goinstall --shield vk off или пункт 2 в меню «Защита от сканеров».'
check has "$out" 'st=ok vk=1'; check grep -qx 'scan=0' "$SF/dir/settings"; check grep -qx 'vk=1' "$SF/dir/settings"
# check в этом состоянии не говорит «защита от сканеров работает» (REVIEW-5 №3).
out=$(sh_run 'shield_cli check; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" '«ВК: не выпускать» работает (защита входа выключена).'; check has "$out" 'rc=0'
check hasnt "$out" 'Защита от сканеров работает'
check hasnt "$(sh_run 'shield_cli vk off >/dev/null; shield_cli on >/dev/null; shield_cli off --yes')" 'остаётся включённым'
# Страж: настройки пишут только установка и переключатель человека — иначе
# стоящим серверам ВК мог бы включиться молча. Любое упоминание файла
# настроек, кроме чтений (_shield_get, [ -f ]), — только в этих двух
# функциях: запись через cp, mv, tee или переменную тоже видна (REVIEW-5 №6).
sh_writers() { awk '/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { f = $1; sub(/\(\).*/, "", f) }
    /^[ \t]*#/ { next }
    { l = $0; gsub(/_shield_get "\$SHIELD_DIR\/settings"/, "", l); gsub(/\[ (! )?-f "\$SHIELD_DIR\/settings" \]/, "", l)
      if (l ~ /SHIELD_DIR\}?"?\/settings/) print f }' "$1" | sort -u | tr '\n' ' '; }
check [ "$(grep -c '> "\$SHIELD_DIR/settings"' "$SCRIPT")" = 2 ]
check [ "$(sh_writers "$SCRIPT")" = 'shield_install shield_toggle ' ]
# Страж ловит то, ради чего написан: запись копией и через переменную.
printf 'shield_sync() {\n    cp x "$SHIELD_DIR/settings"\n}\nshield_tick() {\n    f="${SHIELD_DIR}/settings"; _shield_set "$f" vk=1\n    [ -f "$SHIELD_DIR/settings" ] && _shield_get "$SHIELD_DIR/settings" vk\n}\n' > "$SF/d/w.sh"
check [ "$(sh_writers "$SF/d/w.sh")" = 'shield_sync shield_tick ' ]
printf 'shield_state() {\n    [ ! -f "$SHIELD_DIR/settings" ] && _shield_get "$SHIELD_DIR/settings" vk\n}\n' > "$SF/d/w.sh"
check [ -z "$(sh_writers "$SF/d/w.sh")" ]
# Новая установка после неудачной (apt не поставил nftables — списки
# остались, настроек нет): новый список ВК отклонён (сеть с адресом GitHub),
# прежний не сверен с этим отказом — ВК не включается, сказано (REVIEW-5 №2).
sh_reset
printf '#!/bin/bash\nexit 1\n' > "$SF/bin/apt-get"; chmod +x "$SF/bin/apt-get"
out=$(sh_run '_shield_have_nft(){ return 1; }; shield_apt_nft(){ return 1; }; osup_lock_holder(){ :; }; shield_install; echo "rc=$?"')
rm -f "$SF/bin/apt-get"
check has "$out" 'rc=1'; check [ -s "$SF/dir/lists/vk4" ]; check [ ! -e "$SF/dir/settings" ]
out=$(GOINST_SHIELD_GH_ADDRS=45.1.3.9 sh_run 'shield_install; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=0'
check has "$out" 'Список ВК не прошёл проверку: в списке ВК сеть 45.1.3.0/24 с адресом GitHub 45.1.3.9'
check has "$out" '«ВК: не выпускать» оставляю выключенным. Включить — пункт 2 в меню «Защита от сканеров», когда придёт исправный список.'
check hasnt "$out" 'Работает прежний ВК'; check hasnt "$out" 'Сети ВК закрыты'
check grep -qx 'vk=0' "$SF/dir/settings"; check neg grep -q 'chain vk_' "$SF/dir/shield.nft"
check [ -s "$SF/dir/lists/vk4" ]
# «vk on» по тому же списку отказывает так же.
out=$(GOINST_SHIELD_GH_ADDRS=45.1.3.9 sh_run 'shield_cli vk on; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=1'; check has "$out" 'ВК не включаю: в списке ВК сеть 45.1.3.0/24 с адресом GitHub 45.1.3.9'
# Стоящая защита с vk=1 при том же отказе — выбор человека остаётся.
printf 'scan=1\nvk=1\n' > "$SF/dir/settings"
out=$(GOINST_SHIELD_GH_ADDRS=45.1.3.9 sh_run 'shield_install' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'Работает прежний ВК.'; check grep -qx 'vk=1' "$SF/dir/settings"
# Чистая установка, GitHub в сети ВК: прежнего нет — ВК пуст, выключен.
sh_reset
out=$(GOINST_SHIELD_GH_ADDRS=45.1.3.7 sh_run 'shield_install' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'Прежнего нет — ВК пуст: «ВК: не выпускать» оставляю выключенным.'
check grep -qx 'vk=0' "$SF/dir/settings"; check neg grep -q 'chain vk_' "$SF/dir/shield.nft"
# goVLESS pro или бесплатный Lite в режиме Reality маскируется под сайт из ВК
# (vk.com, ok.ru — в его списке для РФ): Xray набирает этот сайт на каждое
# соединение, закрытый ВК остановил бы VLESS (REVIEW-5 №1). Умолчание — выкл
# и словами; «vk on» — отказ; после установщика goVLESS — предупреждение.
GV_="$SF/fs/opt/govless"; mkdir -p "$GV_"
gv_() { printf '%s' "$1" > "$GV_/config.json"; }
# По адресу домена: адрес — в принятом ВК.
sh_reset; gv_ '{"mode":"lite","mask_domain":"example.org"}'
out=$(GOINST_FAKE_INSTALLED=govless GOINST_SHIELD_MASK_ADDRS="9.9.9.9 45.1.3.7" sh_run 'shield_install; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=0'
check has "$out" 'VLESS Reality маскируется под example.org: адрес 45.1.3.7 — в сети ВК 45.1.3.0/24. С закрытым ВК VLESS этого сервера перестал бы работать — «ВК: не выпускать» оставляю выключенным; включить — пункт 2 в меню «Защита от сканеров»'
check hasnt "$out" 'Сети ВК закрыты'
check grep -qx 'vk=0' "$SF/dir/settings"; check grep -qx 'scan=1' "$SF/dir/settings"; check neg grep -q 'chain vk_' "$SF/dir/shield.nft"
# «vk on» — отказ словами, в журнал; настройки прежние.
out=$(GOINST_FAKE_INSTALLED=govless GOINST_SHIELD_MASK_ADDRS=45.1.3.7 sh_run 'shield_cli vk on; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=1'
check has "$out" 'ВК не включаю: VLESS Reality маскируется под example.org: адрес 45.1.3.7 — в сети ВК'
check has "$out" 'Смените домен маскировки (команда govless) на сайт вне ВК.'
check grep -qx 'vk=0' "$SF/dir/settings"; check neg grep -q 'vk_forward' "$SF/d/live"
check grep -q 'ВК не включён: домен маскировки VLESS Reality example.org — в ВК' "$SF/dir/shield.log"
# Из меню — отказ до пояснения и вопроса.
out=$(GOINST_FAKE_INSTALLED=govless GOINST_SHIELD_MASK_ADDRS=45.1.3.7 sh_run '_shield_paths; shield_do_vk </dev/null; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=1'; check has "$out" 'ВК не включаю: VLESS Reality маскируется под example.org'
check hasnt "$out" 'Включить «ВК: не выпускать»'; check grep -qx 'vk=0' "$SF/dir/settings"
# Адрес в своих исключениях — цепочки ВК его пропускают: помехи нет.
printf '45.1.3.7\n' > "$SF/dir/exclude"
check [ "$(GOINST_FAKE_INSTALLED=govless GOINST_SHIELD_MASK_ADDRS=45.1.3.7 sh_run '_shield_paths; _shield_mask_vk; echo $?')" = 0 ]
rm -f "$SF/dir/exclude"
# Адреса не разрешились — по имени: домен ВК (и поддомен, и точка в конце).
for d_ in vk.com www.ok.ru. m.dzen.ru; do
    sh_reset; gv_ '{"mode":"lite","mask_domain":"'"$d_"'"}'
    out=$(GOINST_FAKE_INSTALLED=govless sh_run 'shield_install' | sed $'s/\033\\[[0-9;]*m//g')
    check has "$out" "VLESS Reality маскируется под ${d_%.}: это домен ВК. С закрытым ВК"
    check grep -qx 'vk=0' "$SF/dir/settings"
done
check hasnt "$(GOINST_FAKE_INSTALLED=govless sh_run '_shield_paths; _shield_mask_known notvk.com && echo hit; _shield_mask_known vk.com.evil.org && echo hit')" 'hit'
# Состав сверен с сетями ВК 03.11 (1.2.3): VK Play — в них, boosty.to — нет.
check [ "$(sh_run '_shield_mask_known vkplay.ru && echo a; _shield_mask_known store.vkplay.live && echo b; _shield_mask_known boosty.to || echo c')" = "$(printf 'a\nb\nc')" ]
# Адрес разрешился и он вне ВК — помехи нет, хоть имя и ВК: ВК закрывает
# только сети списка.
sh_reset; gv_ '{"mode":"lite","mask_domain":"vk.com"}'
GOINST_FAKE_INSTALLED=govless GOINST_SHIELD_MASK_ADDRS=9.9.9.9 sh_run 'shield_install' >/dev/null
check grep -qx 'vk=1' "$SF/dir/settings"
# Домен не прочитать (нет, мусор, не JSON) — не включать молча: выкл и словами.
for c_ in '{"mode":"lite"}' '{"mode":"lite","mask_domain":"vk.com; rm -rf /"}' '{"mode":"lite","mask_domain":["vk.com"]}' 'not json'; do
    sh_reset; gv_ "$c_"
    out=$(GOINST_FAKE_INSTALLED=govless sh_run 'shield_install' | sed $'s/\033\\[[0-9;]*m//g')
    check has "$out" "Не прочитать, под какой сайт маскируется VLESS Reality ($GV_/config.json). Если это сайт из сетей ВК, закрытый ВК остановил бы VLESS"
    check grep -qx 'vk=0' "$SF/dir/settings"; check hasnt "$out" 'rm -rf'
done
# «vk on» при непрочитанном домене — просит человек: включает, но предупреждает.
out=$(GOINST_FAKE_INSTALLED=govless sh_run 'shield_cli vk on; echo "rc=$?"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'rc=0'; check has "$out" 'Если это сайт из сетей ВК, VLESS перестанет работать. Выключить: goinstall --shield vk off.'
check has_ml "$out" "${vkh_}"$'\n''     • VLESS Reality этого сервера — у всех клиентов, если он маскируется под сайт из ВК'$'\n'"${vkl_}"
check grep -qx 'vk=1' "$SF/dir/settings"
# Режим pro (TLS, маскировки нет) и goVLESS не стоит — ВК по умолчанию вкл.
sh_reset; gv_ '{"mode":"pro","mask_domain":"vk.com"}'
GOINST_FAKE_INSTALLED=govless sh_run 'shield_install' >/dev/null
check grep -qx 'vk=1' "$SF/dir/settings"
sh_reset; gv_ '{"mode":"lite","mask_domain":"vk.com"}'
GOINST_FAKE_INSTALLED=gotelegram sh_run 'shield_install' >/dev/null
check grep -qx 'vk=1' "$SF/dir/settings"
# Стоящая защита с vk=0 — проверка маскировки ничего не меняет.
printf 'scan=1\nvk=0\n' > "$SF/dir/settings"
GOINST_FAKE_INSTALLED=govless sh_run 'shield_install' >/dev/null
check grep -qx 'vk=0' "$SF/dir/settings"
# Защита ставится до продуктов: goVLESS встал потом с сайтом из ВК — после
# его установщика предупреждение; выбор ВК не меняется.
printf 'scan=1\nvk=1\n' > "$SF/dir/settings"; sh_run '_shield_paths; shield_apply' >/dev/null
out=$(GOINST_FAKE_INSTALLED=govless sh_run 'shield_postcheck govless' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'VLESS Reality маскируется под vk.com: это домен ВК. «ВК: не выпускать» включено — VLESS этого сервера не будет работать.'
check has_ml "$out" "${vkh_}"$'\n''     • VLESS Reality этого сервера (маскировка под vk.com) — у всех клиентов'$'\n'"${vkl_}"$'\n'
check has "$out" "$vko_"; check has "$out" 'Или смените домен маскировки (команда govless) на сайт вне ВК.'
check grep -qx 'vk=1' "$SF/dir/settings"
check hasnt "$(GOINST_FAKE_INSTALLED=govless sh_run 'shield_postcheck gotelegram')" 'VLESS Reality'
check hasnt "$(GOINST_FAKE_INSTALLED=govless sh_run 'shield_postcheck')" 'VLESS Reality'
out=$(GOINST_FAKE_INSTALLED=govless sh_run 'LANG_CODE=en; shield_postcheck govless' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'VLESS Reality masquerades as vk.com: a VK domain. “VK: block outbound” is on — this server'"'"'s VLESS will not work.'
check has_ml "$out" '     • This server'"'"'s VLESS Reality (masquerading as vk.com) — for all clients'$'\n'"${vkle_}"$'\n'
check has "$out" 'To turn VK off: goinstall --shield vk off or item 2 in the “Scanner protection” menu.'
printf 'scan=1\nvk=0\n' > "$SF/dir/settings"
check hasnt "$(GOINST_FAKE_INSTALLED=govless sh_run 'shield_postcheck govless')" 'VLESS Reality'
sh_reset; out=$(GOINST_FAKE_INSTALLED=govless sh_run 'LANG_CODE=en; shield_install' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" 'VLESS Reality masquerades as vk.com: a VK domain. With VK closed, this server'"'"'s VLESS would stop working — “VK: block outbound” stays off; to turn it on, change the masking domain (the govless command) to a site outside VK, then use item 2 in the “Scanner protection” menu.'
rm -rf "$SF/fs/opt"
# Узел РФ goKaskad pro (решение владельца 03.11): ВК закрыт и для клиентов
# каскада — без исключения, одной строкой при включении и после установщика.
kn_='goKaskad pro: ВК закрыт и для клиентов каскада — у них всё это тоже не откроется.'
sh_reset
out=$(GOINST_FAKE_INSTALLED=gokaskad sh_run 'shield_install' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" "$kn_"; check grep -qx 'vk=1' "$SF/dir/settings"; check grep -q 'chain vk_forward {' "$SF/dir/shield.nft"
check has_ml "$out" "${vkl_}"$'\n'"  ℹ  ${kn_}"$'\n'"  ℹ  ${vko_}"
out=$(GOINST_FAKE_INSTALLED=gokaskad sh_run 'shield_postcheck gokaskad' | sed $'s/\033\\[[0-9;]*m//g')
check has_ml "$out" "${vkh_}"$'\n'"${vkl_}"$'\n'"  ℹ  ${kn_}"$'\n'"  ℹ  ${vko_}"
check hasnt "$(GOINST_FAKE_INSTALLED=gokaskad sh_run 'shield_postcheck godns')" 'клиентов каскада'
sh_run 'shield_cli vk off' >/dev/null
check hasnt "$(GOINST_FAKE_INSTALLED=gokaskad sh_run 'shield_postcheck gokaskad')" 'клиентов каскада'
check has "$(GOINST_FAKE_INSTALLED=gokaskad sh_run 'shield_cli vk on' | sed $'s/\033\\[[0-9;]*m//g')" "$kn_"
check has "$(GOINST_FAKE_INSTALLED=gokaskad sh_run 'LANG_CODE=en; shield_postcheck gokaskad' | sed $'s/\033\\[[0-9;]*m//g')" 'goKaskad pro: VK is closed to the cascade clients too — none of this will open for them either.'
sh_reset
check hasnt "$(GOINST_FAKE_INSTALLED= sh_run 'shield_install')" 'клиентов каскада'

# Предложение: один раз, по tty, отказ запоминается.
sh_reset
out=$(GOINST_SHIELD_TEST=1 GOINST_SHIELD_TTY=1 sh_run 'shield_offer <<<"2"; echo "said=$SHIELD_SAID"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" '1) Да'; check has "$out" '2) Нет'; check has "$out" 'AS_Network_List'; check has "$out" 'SSH открыт всегда'
check has "$out" 'said=1'
# Текст (1.2.2): ВК закрыт по умолчанию — зачем, и что выключить можно в меню;
# 3–4 строки между заголовком и вопросом.
check has "$out" 'Ещё закрывает сети ВК для клиентов VPN и самого сервера, чтобы ВК не засветил его адрес: не откроются ВКонтакте и VK Видео, Одноклассники, Mail.ru, Макс, Дзен, RuStore, Юла, VK Play, VK Cloud и другие сервисы VK.'
check has "$out" 'Выключить — в меню.'
n_=$(awk '/Защита от сканеров и ботов/ { s = 1; next } /Включить защиту от сканеров\?/ { s = 0 } s' <<<"$out" | grep -c 'ℹ')
check [ "$n_" -ge 3 ]; check [ "$n_" -le 4 ]
out=$(GOINST_SHIELD_TEST=1 GOINST_SHIELD_TTY=1 sh_run '_shield_paths; rm -f "$SHIELD_DIR/declined"; LANG_CODE=en; shield_offer <<<"2"' | sed $'s/\033\\[[0-9;]*m//g')
check has "$out" "It also closes VK networks to VPN clients and the server itself, so VK cannot expose its address: VKontakte and VK Video, Odnoklassniki, Mail.ru, Max, Dzen, RuStore, Youla, VK Play, VK Cloud and other VK services will not open."
check has "$out" 'Turn it off in the menu.'; check has "$out" '1) Yes'; check has "$out" '2) No'
check grep -qx declined "$SF/dir/declined"
check [ -n "$(find "$SF/dir/declined" -perm 600)" ]
check [ ! -e "$SF/dir/settings" ]
check [ -z "$(GOINST_SHIELD_TEST=1 GOINST_SHIELD_TTY=1 sh_run 'shield_offer <<<"1"; echo "$SHIELD_SAID"')" ]
# Enter, нажатый до вопроса (отсчёт сводки, вопрос о MTU), ответом не
# становится: умолчание «Да», и без сброса ввода он ставил бы пакет и фильтр.
# Настоящий терминал (pty): Enter уходит сразу, «2» — когда вопрос напечатан.
sh_reset
cat > "$SF/d/pty.py" <<'PY'
import os, pty, select, sys, time
bash, script = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.execv(bash, [bash, '-c', '. "$1"; shield_offer; echo "said=$SHIELD_SAID"', 'pty', script])
os.write(fd, b'\n')
buf, sent, end = b'', False, time.time() + 60
while time.time() < end:
    if not select.select([fd], [], [], 0.5)[0]:
        continue
    try:
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    buf += d
    if not sent and 'по умолчанию'.encode() in buf:
        time.sleep(0.3); os.write(fd, b'2\n'); sent = True
os.waitpid(pid, 0)
sys.stdout.write(buf.decode('utf-8', 'replace'))
PY
out=$(GOINST_SHIELD_TEST=1 sh_run 'python3 -I "$SFD/pty.py" "$BASH" "$SCRIPT"')
check has "$out" 'said=1'
check grep -qx declined "$SF/dir/declined"
check [ ! -e "$SF/dir/settings" ]
# Без терминала — не спрашивает; в наборе без GOINST_SHIELD_TEST — тоже.
sh_reset
check [ -z "$(GOINST_SHIELD_TEST=1 sh_run 'shield_offer </dev/null; echo "$SHIELD_SAID"')" ]
check [ -z "$(GOINST_SHIELD_TTY=1 sh_run 'shield_offer <<<"1"; echo "$SHIELD_SAID"')" ]
check [ ! -e "$SF/dir" ]
# «Да» — ставит.
out=$(GOINST_SHIELD_TEST=1 GOINST_SHIELD_TTY=1 sh_run 'shield_offer <<<"1"')
check has "$out" 'Защита от сканеров включена'; check [ -f "$SF/dir/settings" ]
# «Да» включает и ВК (умолчание 1.2.2): в настройках и в правилах.
check grep -qx 'vk=1' "$SF/dir/settings"; check grep -q 'chain vk_output {' "$SF/dir/shield.nft"
check has_ml "$out" "${vkh_}"$'\n'"${vkl_}"$'\n'
# Стоит — не спрашивает, а приводит копию для таймера к этой версии.
printf 'shield_cli() { :; }\nGOINST_VERSION="1.1.0"\n' > "$SF/dir/runner.sh"
out=$(GOINST_SHIELD_TEST=1 GOINST_SHIELD_TTY=1 sh_run 'shield_offer </dev/null; echo "said=$SHIELD_SAID"')
check [ "$out" = "said=" ]
check cmp -s "$SCRIPT" "$SF/dir/runner.sh"
# После установщика продукта — проверка; правила пропали — восстановлены.
rm -f "$SF/d/live"
sh_run 'shield_postcheck' >/dev/null
check [ -f "$SF/d/live" ]
# Удаление goInstaller снимает и защиту.
mkdir -p "$SF/gd"; out=$(sh_run 'goinst_remove_list')
check has "$out" "$SF/units/goinstall-shield.timer"
check has "$out" "$SF/units/goinstall-shield.path"
check has "$out" "$SF/dir"
sh_run 'GOINST_BIN_ALIAS="$SFD/alias"; goinst_remove drop' >/dev/null
check [ ! -f "$SF/d/live" ]; check [ ! -e "$SF/units/goinstall-shield.service" ]; check [ ! -e "$SF/units/goinstall-shield.path" ]; check [ ! -e "$SF/dir" ]
cp "$SF/bin/curl" /dev/null; printf '#!/bin/bash\nGOINST_VERSION="%s"\n' "$GIV" > "$SF/goinstall"; chmod +x "$SF/goinstall"

# Порядок в main: после языка и root (lang_persist), до ключа и продуктов —
# и в меню, и в --install.
mb=$(code | sed -n '/^main()/,/^}/p')
ln_() { grep -n -m1 -- "$1" <<<"$mb" | cut -d: -f1; }
check [ "$(ln_ '^    lang_persist$')" -lt "$(ln_ '^    shield_offer$')" ]
check [ "$(ln_ '^    shield_offer$')" -lt "$(ln_ '^        ui_main$')" ]
check [ "$(ln_ '^    shield_offer$')" -lt "$(ln_ '^    token_startup')" ]
check [ "$(ln_ '^    self_install$')" -lt "$(ln_ '^    shield_offer$')" ]
ib=$(sed -n '/^        --install)$/,/;;/p' <<<"$mb")
check has "$ib" 'self_install; shield_offer'
check [ "$(grep -n -m1 'shield_offer' <<<"$ib" | cut -d: -f1)" -lt "$(grep -n -m1 'versions_fetch' <<<"$ib" | cut -d: -f1)" ]
check has "$ib" 'shield_postcheck'
# --watch (таймер сводки, раз в 30 минут) приводит копию для таймера защиты
# к стоящей версии; предложения там нет.
wb=$(grep -- '^        --watch)' <<<"$mb")
check has "$wb" 'shield_sync'; check hasnt "$wb" 'shield_offer'
check has "$(code | sed -n '/^ui_run_installer()/,/^}/p')" 'shield_postcheck'
check has "$(code | sed -n '/^install_flow()/,/^}/p')" 'shield_postcheck'

# Стражи: чужие правила и таблицы не трогаем, служба nftables — никогда,
# nft — только через _shield_nft, apt — ровно nftables, ключ — не к C24Be.
check [ -z "$(code | grep -n 'flush ruleset')" ]
check [ -z "$(code | grep -n 'nftables\.conf')" ]
check [ -z "$(code | grep -n -E 'nftables\.service|systemctl[^|;]*[[:space:]]nftables')" ]
check [ -z "$(code | grep -v 'bi "' | grep -n -E '(^|[;&|(]|[[:space:]])nft[[:space:]]+(-[a-z]|list|add|delete|flush|insert|replace|create)' | grep -v -E '^[0-9]+:[[:space:]]+nft "\$@"$')" ]
shm=$(code | sed -n '/^SHIELD_REPO=/,/^shield_list_menu()/p')
check [ -n "$shm" ]
check [ -z "$(grep -v 'bi "' <<<"$shm" | grep -n -E 'iptables|ufw|docker|ip kaskad|table ip |list ruleset')" ]
sa=$(code | sed -n '/^shield_apt_nft()/,/^}/p')
check [ "$(grep -c 'apt-get' <<<"$sa")" = 3 ]
check [ -z "$(grep 'install' <<<"$sa" | grep -v 'install --no-install-recommends nftables >/dev/null')" ]
sfe=$(code | sed -n '/^shield_fetch()/,/^}/p')
check [ -z "$(grep -n -E 'TOKEN|Authorization|auth_header|token_' <<<"$sfe")" ]
check has "$sfe" 'gh_curl -q --config'
check [ -z "$(grep -n -E '\$TOKEN|\$\{TOKEN' <<<"$shm")" ]
# Чужой текст на экран — без управляющих символов и обратных косых.
check [ "$(sh_run '_shield_clean "$(printf "a\\033[31mb\\\\nc\\nd")"')" = 'a[31mbnc d' ]

# Находка владельца (живой сервер, 03.11.2026): `bash <(curl …/test-shield/…)`
# при goinstall = main 1.0.12 ставил в goinstall main, и защите нечего было
# дать таймеру. Теперь self_install ищет ветку ровно этой версии. Поддельный
# GitHub для duboshin52/goInstaller — крючок CURL_HOOK к curl защиты: список
# веток с хешами, хеш ветки, файл по хешу; вызовы — в $SELFD/calls.
echo "── защита от сканеров: статистика (1.2.4)"
# Листинг «nft -a list table» — как у настоящего nft (форматы 0.9.3 и 1.0.9
# сняты на стендах Lima): nfa key=value… пишет его в $SF/d/nfta, заглушка
# nft отдаёт его на «-a list table». Время — числом: снимки по часам.
cat > "$SF/nfta.py" <<'PY'
# h — номер таблицы; in4 in6 out_fwd out_srv — счётчики; seen4/seen6 —
# адрес:попытки:сколько секунд назад («-» — без счётчика); ports — proto.port:n;
# pair4/pair6 — адрес.proto.port; ord=a — счётчик элемента после срока (1.0.9).
import sys
a = dict(x.split('=', 1) for x in sys.argv[1:])
def d(s):
    s = int(s); o = ''
    for u, k in (('d', 86400), ('h', 3600), ('m', 60), ('s', 1)):
        if s >= k: o += '%d%s' % (s // k, u); s %= k
    return o or '0s'
def st(name, typ, size, tmo, els):
    print('\tset %s { # handle 9\n\t\ttype %s\n\t\tsize %s' % (name, typ, size))
    print('\t\tflags dynamic%s' % (',timeout' if tmo else ''))
    if tmo: print('\t\ttimeout %s' % d(tmo))
    if els: print('\t\telements = { ' + ',\n\t\t\t     '.join(els) + ' }')
    print('\t}\n')
print('table inet goinstall_shield { # handle %s' % a.get('h', '23'))
for c in ('in4', 'in6', 'out_fwd', 'out_srv'):
    if c in a: print('\tcounter %s { # handle 5\n\t\tpackets %s bytes 0\n\t}\n' % (c, a[c]))
print('\tset scan4 { # handle 7\n\t\ttype ipv4_addr\n\t\tflags interval\n\t\tauto-merge\n\t\telements = { 45.0.0.0/16, 46.0.0.0/16 }\n\t}\n')
for v in ('4', '6'):
    k = 'seen' + v
    if k not in a: continue
    els = []
    for x in filter(None, a[k].split(',')):
        ad, n, ago = x.rsplit(':', 2)
        tm = 'timeout 35d expires %s' % d(35 * 86400 - int(ago))
        c = '' if n == '-' else 'counter packets %s bytes 0' % n
        els.append(' '.join(filter(None, [ad, c, tm] if a.get('ord') == 'a' else [ad, tm, c])))
    st(k, 'ipv%s_addr' % v, 65536, 35 * 86400, els)
if 'ports' in a:
    st('ports', 'inet_proto . inet_service', 8192, 0,
       ['%s . %s counter packets %s bytes 0' % (x.split('.')[0], x.split('.')[1].split(':')[0], x.split(':')[1]) for x in filter(None, a['ports'].split(','))])
for v in ('4', '6'):
    k = 'pair' + v
    if k in a:
        st(k, 'ipv%s_addr . inet_proto . inet_service' % v, 32768, 7200,
           ['%s . %s . %s timeout 2h expires 1h50m' % tuple(x.rsplit('.', 2)) for x in filter(None, a[k].split(','))])
print('\tchain incoming { # handle 30\n\t\ttype filter hook prerouting priority -150; policy accept;\n\t}\n}')
PY
nfa() { python3 -I "$SF/nfta.py" "$@" > "$SF/d/nfta"; }
STD="$SF/d/st"
# snapx <boot> <время> — снимок прямо в $STD (без защиты, без блокировки).
snapx() { sh_run '_shield_spy snap "$SFD/st" "$SFD/nfta" "$SFD/own" '"$1 $2"'; echo "rc=$?"'; }
sget() { sed -n "s/^$1=//p" "$2"; }
T0=1793700000                                   # ровно час: 03.11.2026 по UTC
sh_reset; : > "$SF/d/own"
# Первый снимок: всё, что в таблице, — за последний час; v4 и v6 вместе.
nfa h=23 in4=100 in6=2 out_fwd=4 out_srv=1
check has "$(snapx b1 $((T0+600)))" 'rc=0'
check [ "$(sget tin "$STD/summary") $(sget tfw "$STD/summary") $(sget tsr "$STD/summary")" = "102 4 1" ]
check [ "$(sget lvl "$STD/summary")" = 1 ]                   # только счётчики — уровень 1
# Та же таблица — разница; счётчик меньше прошлого (сброшен) — дельта = значение.
nfa h=23 in4=150 in6=2 out_fwd=4 out_srv=1; snapx b1 $((T0+4200)) >/dev/null
check [ "$(sget tin "$STD/summary")" = 152 ]
nfa h=23 in4=20 in6=2 out_fwd=4 out_srv=1; snapx b1 $((T0+7800)) >/dev/null
check [ "$(sget tin "$STD/summary")" = 172 ]
# Пересборка (другой номер таблицы) и перезагрузка (другой boot, номер тот же).
nfa h=24 in4=30 in6=0 out_fwd=1 out_srv=0; snapx b1 $((T0+11400)) >/dev/null
check [ "$(sget tin "$STD/summary") $(sget tfw "$STD/summary")" = "202 5" ]
nfa h=24 in4=5 in6=0 out_fwd=0 out_srv=0; snapx b2 $((T0+15000)) >/dev/null
check [ "$(sget tin "$STD/summary")" = 207 ]
snapx b2 $((T0+18600)) >/dev/null                             # ничего нового — ноль
check [ "$(sget tin "$STD/summary")" = 207 ]
# Таблицы не видно (nft не ответил) — снимка нет, та же таблица потом без двойного счёта.
mv "$SF/d/nfta" "$SF/d/nfta.keep"
snapx b2 $((T0+22200)) >/dev/null
check [ "$(sget snap "$STD/meta")" = $((T0+18600)) ]; check [ "$(sget key "$STD/meta")" = b2:24 ]
mv "$SF/d/nfta.keep" "$SF/d/nfta"; nfa h=24 in4=8 in6=0 out_fwd=0 out_srv=0; snapx b2 $((T0+25800)) >/dev/null
check [ "$(sget tin "$STD/summary")" = 210 ]
# Часы и дни сходятся с итогом; файлы — 0600, каталог — 0700.
check [ "$(awk '{s+=$2} END {print s}' "$STD/hours")" = 210 ]
check [ "$(awk '{s+=$2} END {print s}' "$STD/days")" = 210 ]
check [ "$(stat -f %Lp "$STD" 2>/dev/null || stat -c %a "$STD")" = 700 ]
check [ -z "$(find "$STD" -type f ! -perm 600)" ]
check [ -z "$(find "$STD" -name '*.tmp')" ]
# Обнуление (base=1): первый снимок только запоминает, откуда считать.
printf 'started=%s\nbase=1\n' $((T0+26000)) > "$STD/meta"; rm -f "$STD/hours" "$STD/days" "$STD/summary"
nfa h=24 in4=500 in6=0 out_fwd=7 out_srv=0; snapx b2 $((T0+29400)) >/dev/null
check [ "$(sget tin "$STD/summary") $(sget tfw "$STD/summary")" = "0 0" ]
nfa h=24 in4=510 in6=0 out_fwd=9 out_srv=0; snapx b2 $((T0+33000)) >/dev/null
check [ "$(sget tin "$STD/summary") $(sget tfw "$STD/summary")" = "10 2" ]
# Обнуление без таблицы — новая таблица считается целиком.
printf 'started=%s\nbase=1\n' $((T0+33100)) > "$STD/meta"; rm -f "$SF/d/nfta"
snapx b2 $((T0+33200)) >/dev/null
nfa h=25 in4=6 in6=0; snapx b2 $((T0+36600)) >/dev/null
check [ "$(sget tin "$STD/summary")" = 6 ]
# Адреса, порты, владельцы (оба формата nft), предел базы адресов.
sh_reset
# Подпись AS — чужой ввод: ESC-последовательности, BEL, C1 (CSI), смена
# направления, широкие знаки, разделители сводки, длина.
{ printf '%s\n' '---' '# Networks announced by AS64500' '# AS-Name (ORG): EXAMPLE-NET (ORG-EX1-RIPE)' '45.0.4.0/24' '---' '# Networks announced by AS64501'
  printf '# AS-Name (ORG): EVIL\033[31mRED\033]0;title\007\302\233\342\200\256NAME \346\235\261 | a\\b %s\n' "$(printf 'A%.0s' $(seq 1 70))"
  printf '%s\n' '45.0.5.0/24'; } > "$SF/d/bwc"
sh_run '_shield_spy owners "$SFD/bwc" "$SFD/own"' >/dev/null
check grep -qx $'45.0.4.0/24\t64500\tEXAMPLE-NET (ORG-EX1-RIPE)' "$SF/d/own"
lab=$(awk -F'\t' '$2 == 64501 { print $3 }' "$SF/d/own")
check has "$lab" 'EVIL[31mRED]0;titleNAME ? / a/b AAAA'
check neg grep -q $'[\001-\010\012-\037\177]' "$SF/d/own"         # без управляющих
check neg grep -q $'\302[\200-\237]' "$SF/d/own"                  # и C1
check neg grep -q $'\342\200\256' "$SF/d/own"                     # без смены направления
check [ "$(printf '%s' "$lab" | python3 -I -c 'import sys; print(len(sys.stdin.read()))')" = 60 ]
check has "$lab" '…'
for ord in b a; do
    rm -rf "$STD"
    nfa h=23 in4=12 in6=1 out_fwd=0 out_srv=0 ord=$ord \
        seen4=45.0.4.10:5:100,45.0.4.11:3:200,45.0.5.9:2:300,45.0.9.1:1:400,45.0.9.2:1:500 \
        seen6=2a00:1:2:3:::1:50 ports=tcp.443:6,tcp.22:4,udp.53:2 pair4=45.0.4.10.tcp.443,45.0.5.9.tcp.22
    GOINST_SHIELD_STATS_MAX=3 snapx b1 $((T0+600)) >/dev/null
    check [ "$(sget lvl "$STD/summary")" = 3 ]
    check [ "$(sget naddr "$STD/summary")" = 6 ]                 # всего — отдельный счётчик
    check [ "$(grep -c '' "$STD/addrs")" = 3 ]                   # в базе — предел, свежие
    check [ "$(cut -d' ' -f1 "$STD/addrs" | sort | tr '\n' ' ')" = '2a00:1:2:3:: 45.0.4.10 45.0.4.11 ' ]
    check grep -q '^45.0.4.10 [0-9]* [0-9]* 5 ' "$STD/addrs"
    check grep -q 'tcp/443\|443/tcp' "$STD/ports_all"
    check [ "$(sget t24_1 "$STD/summary" | cut -d'|' -f1,2)" = '64500|EXAMPLE-NET (ORG-EX1-RIPE)' ]
done
# Чужая подпись не ломает вывод: ни управляющих, ни разделителей в сводке.
check neg grep -q $'[\001-\037\177]' "$STD/summary"
out=$(sh_run 'mkdir -p "$GOINST_SHIELD_DIR"; mv "$SFD/st" "$GOINST_SHIELD_DIR/stats"; shield_cli stats top 24h </dev/null; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" 'AS64500'; check has "$out" 'EXAMPLE-NET'
check neg grep -q $'\033' <<<"$out"; check neg grep -q $'\342\200\256' <<<"$out"; check has "$out" 'EVIL[31mRED'
check has "$(sh_run 'shield_cli stats size </dev/null; echo "rc=$?"')" 'rc=0'
# Команды: неверный период — 64; защиты и статистики нет — 3.
check [ "$(sh_run 'shield_cli stats week </dev/null >/dev/null 2>&1; echo $?')" = 64 ]
check [ "$(sh_run 'shield_cli stats top 1y </dev/null >/dev/null 2>&1; echo $?')" = 64 ]
check [ "$(sh_run 'shield_cli stats size x </dev/null >/dev/null 2>&1; echo $?')" = 64 ]
sh_reset
check [ "$(sh_run 'shield_cli stats </dev/null >/dev/null 2>&1; echo $?')" = 3 ]
check has "$(sh_run 'shield_cli stats reset </dev/null; echo "rc=$?"')" 'rc=0'   # нечего обнулять

# Установка: правила со статистикой (уровень 3) одной транзакцией, nft -c до -f.
sh_reset
out=$(sh_run 'shield_install; echo "rc=$?"')
check has "$out" 'rc=0'
nf_="$SF/dir/shield.nft"
check [ "$(sed -n 's/^stl=//p' "$SF/dir/status")" = 3 ]
check [ "$(grep -c -- '^-f ' "$SF/d/nft.calls")" = 1 ]
check [ "$(sed -n 1,3p "$nf_")" = "$(printf 'table inet goinstall_shield {}\ndelete table inet goinstall_shield\ntable inet goinstall_shield {')" ]
# Цепочки счёта только считают: ни одного решения о пакете.
check [ -z "$(sed -n '/chain stat[46] {/,/^\t}/p' "$nf_" | grep -E -w 'accept|drop|reject|return|jump|goto|queue')" ]
check grep -q 'flags dynamic,timeout' "$nf_"; check grep -q 'timeout 35d' "$nf_"; check grep -q 'size 65536' "$nf_"
# REVIEW-6 №7з: набор портов — со сроком записи 2 ч: полный набор освобождается сам.
check [ "$(sed -n '/set ports {/,/^\t}/p' "$nf_" | tr -d '\t' | grep -E '^(flags|timeout|size)' | tr '\n' ' ')" = 'size 8192 flags dynamic,timeout timeout 2h ' ]
# Выход: счётчик новых соединений к ВК — после allow, до reject.
vkf=$(sed -n '/chain vk_forward {/,/^\t}/p' "$nf_" | tr -d '\t')
check [ "$(grep -n 'counter name "out_fwd"' <<<"$vkf" | head -1 | cut -d: -f1)" -gt "$(grep -n 'daddr @allow6 accept' <<<"$vkf" | cut -d: -f1)" ]
check [ "$(grep -n 'counter name "out_fwd"' <<<"$vkf" | tail -1 | cut -d: -f1)" -lt "$(grep -n 'reject' <<<"$vkf" | head -1 | cut -d: -f1)" ]
check grep -q 'counter name "out_srv"' "$nf_"
# Модель цепочки: прыжок в счёт ничего не решает — те же ответы, что без него.
check [ "$(python3 -I "$SF/nfteval.py" "$nf_" | tr '\n' ' ')" = 'new drop+stat4 est drop reply accept icmperr accept ssh accept invalid drop lo accept est6 drop reply6 accept other accept new6 drop+stat6 ' ]
# Сканеры выкл — сервер не блокирует, только считает: прыжок в счёт есть, drop нет.
out=$(sh_run 'shield_cli off --yes </dev/null')
check has "$out" 'Защита (вход): выключена — сервер не блокирует, только считает.'
check grep -q 'jump stat4' "$nf_"; check neg grep -q '@scan4 counter drop' "$nf_"; check neg grep -q '@scan4 ct direction' "$nf_"
check [ "$(python3 -I "$SF/nfteval.py" "$nf_" | tr '\n' ' ')" = 'new accept+stat4 est accept reply accept icmperr accept ssh accept invalid accept lo accept est6 accept reply6 accept other accept new6 accept+stat6 ' ]
check has "$(sh_run 'shield_state; echo "$SHS_ST $SHS_SCAN"')" 'ok 0'
sh_run 'shield_cli on </dev/null' >/dev/null
# Нет поддержки: nft не умеет счётчика в наборе — уровень 2; не умеет
# именованных счётчиков — уровень 0, правила как в 1.2.3, защита работает.
sh_reset
NFT_STAT=2 sh_run 'shield_install' >/dev/null
check [ "$(sed -n 's/^stl=//p' "$SF/dir/status")" = 2 ]
check grep -q 'update @seen4 { ip saddr }' "$SF/dir/shield.nft"; check neg grep -q '@ports' "$SF/dir/shield.nft"
sh_reset
out=$(NFT_STAT=0 sh_run 'shield_install; echo "rc=$?"')
check has "$out" 'rc=0'
check [ "$(sed -n 's/^stl=//p' "$SF/dir/status")" = 0 ]
check neg grep -q 'stat4\|counter name\|update @' "$SF/dir/shield.nft"
check grep -q 'статистика: nft или ядро не умеют счётчиков' "$SF/dir/shield.log"
check [ "$(grep -c -- '^-c -f ' "$SF/d/nft.calls")" = 4 ]; check [ "$(grep -c -- '^-f ' "$SF/d/nft.calls")" = 1 ]
check [ "$(NFT_STAT=0 sh_run 'shield_cli check >/dev/null 2>&1; echo $?')" = 0 ]
out=$(NFT_STAT=0 sh_run 'shield_cli stats </dev/null; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" 'нет данных — nft или ядро не умеют счётчиков'
# Сводка при входе без данных (уровень 0) — без строк статистики.
out=$(NFT_STAT=0 sh_run 'SUM_FILE="$SFD/sum"; printf "sved=10:00\nninst=1\nhost=h\n" > "$SUM_FILE"; GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 GOINST_UI_SYS="1 2 0.1" summary_print </dev/null')
check hasnt "$out" 'Защита: вкл'
# REVIEW-6 №7в: счёт не поднялся (stl=0) — «только считает» неправда, ни при
#    выключении, ни в отчёте.
out=$(NFT_STAT=0 sh_run 'shield_toggle scan 0')
check has "$out" 'Защита (вход): выключена — сервер не блокирует.'; check hasnt "$out" 'только считает'
out=$(NFT_STAT=0 sh_run 'shield_cli stats </dev/null')
check has "$out" 'вход       выкл · не блокирует'; check hasnt "$out" 'только считает'
out=$(sh_run '_shield_paths; shield_apply; shield_stats_snap; shield_cli stats </dev/null')     # уровень 3
check has "$out" 'вход       выкл · только считает'
# Слито вручную (test-shield + экраны): обе половины bi — с новым именем пункта.
out=$(sh_run 'LANG_CODE=en; shield_toggle scan 0')
check has "$out" 'Protection (inbound): off — the server does not block, only counts.'
out=$(NFT_STAT=0 sh_run 'LANG_CODE=en; shield_toggle scan 0')
check has "$out" 'Protection (inbound): off — the server does not block.'; check hasnt "$out" 'only counts'
# nft -c принял счёт, а загрузка не прошла — защита всё равно встаёт, без счёта.
sh_reset
out=$(NFT_LOADSTAT=0 sh_run 'shield_install; echo "rc=$?"')
check has "$out" 'rc=0'
check [ "$(sed -n 's/^stl=//p' "$SF/dir/status")" = 0 ]
check neg grep -q 'counter name' "$SF/dir/shield.nft"; check [ -f "$SF/d/live" ]
check [ "$(grep -c -- '^-f ' "$SF/d/nft.calls")" = 2 ]
check grep -q 'статистика: nft или ядро не умеют счётчиков' "$SF/dir/shield.log"
# REVIEW-6 №6: выход служб-прокси к ВК — клиенты VPN, а не сервер. Каталоги
#    cgroup служб есть (x-ui и telemt работают; nginx — не прокси) — выход
#    сервера считает цепочка vk_count: из cgroup службы — out_fwd, прочее —
#    out_srv; return — назад в vk_output, к тем же reject.
sh_reset
CG="$SF/d/cg"; mkdir -p "$CG/system.slice/x-ui.service" "$CG/system.slice/telemt.service" "$CG/system.slice/nginx.service"
: > "$CG/cgroup.controllers"
out=$(sh_run 'shield_install; echo "rc=$?"')
check has "$out" 'rc=0'
check [ "$(sed -n 's/^stl=//p' "$SF/dir/status")" = 3 ]; check [ "$(sed -n 's/^prx=//p' "$SF/dir/status")" = 'x-ui,telemt' ]
check [ "$(sed -n '/chain vk_count {/,/^\t}/p' "$nf_" | tr -d '\t')" = "$(printf '%s\n' 'chain vk_count {' \
    'socket cgroupv2 level 2 "system.slice/x-ui.service" counter name "out_fwd" return' \
    'socket cgroupv2 level 2 "system.slice/telemt.service" counter name "out_fwd" return' 'counter name "out_srv"' '}')" ]
vko=$(sed -n '/chain vk_output {/,/^\t}/p' "$nf_" | tr -d '\t')
check [ "$(grep -c 'jump vk_count' <<<"$vko")" = 2 ]; check hasnt "$vko" 'counter name'
check [ "$(grep -n 'jump vk_count' <<<"$vko" | head -1 | cut -d: -f1)" -gt "$(grep -n 'daddr @allow6 accept' <<<"$vko" | cut -d: -f1)" ]
check [ "$(grep -n 'jump vk_count' <<<"$vko" | tail -1 | cut -d: -f1)" -lt "$(grep -n 'reject' <<<"$vko" | head -1 | cut -d: -f1)" ]
check [ "$(grep -n 'chain vk_count {' "$nf_" | cut -d: -f1)" -lt "$(grep -n 'chain vk_output {' "$nf_" | cut -d: -f1)" ]
check has "$(sed -n '/chain vk_forward {/,/^\t}/p' "$nf_")" 'ct state new ip daddr @vk4 counter name "out_fwd"'
check [ "$(sh_run '_shield_paths; shield_live_ok; echo "rc=$?"')" = 'rc=0' ]
sh_run 'shield_stats_snap' >/dev/null      # данные уровня 3: снимок после установки
out=$(sh_run 'shield_cli stats </dev/null')
check has "$out" 'выход  клиенты — VPN и прокси: x-ui, telemt'; check hasnt "$out" 'сервер и прокси на нём'
check has "$(sh_run 'LANG_CODE=en; shield_cli stats </dev/null')" 'out    clients — VPN and proxies: x-ui, telemt'
# Перезапуск службы — новый каталог cgroup с другим номером (старый ещё
#    занят при создании нового — номер точно другой): отпечаток сменился,
#    такт пересобирает правила. Без перезапуска — тихо.
n0=$(grep -c 'службы-прокси сменились' "$SF/dir/shield.log")
sh_run '_shield_paths; _shield_fp_sync' >/dev/null
check [ "$(grep -c 'службы-прокси сменились' "$SF/dir/shield.log")" = "$n0" ]
mv "$CG/system.slice/x-ui.service" "$CG/system.slice/x-ui.old"; mkdir "$CG/system.slice/x-ui.service"; rmdir "$CG/system.slice/x-ui.old"
sh_run '_shield_paths; _shield_fp_sync' >/dev/null
check [ "$(grep -c 'службы-прокси сменились' "$SF/dir/shield.log")" = "$(( n0 + 1 ))" ]
# Служба остановлена (каталога нет) — пересборка без неё.
rmdir "$CG/system.slice/telemt.service"
sh_run '_shield_paths; _shield_fp_sync' >/dev/null
check [ "$(sed -n 's/^prx=//p' "$SF/dir/status")" = 'x-ui' ]; check neg grep -q 'telemt' "$nf_"
# ВК выключен — выход не считается: службы не в отпечатке, перезапуск не пересобирает.
sh_run 'shield_toggle vk 0' >/dev/null
check grep -qx 'vk=0' "$SF/dir/settings"; check neg grep -q 'vk_count' "$nf_"; check [ -z "$(sed -n 's/^prx=//p' "$SF/dir/status")" ]
n0=$(grep -c 'службы-прокси сменились' "$SF/dir/shield.log")
mv "$CG/system.slice/x-ui.service" "$CG/system.slice/x-ui.old"; mkdir "$CG/system.slice/x-ui.service"; rmdir "$CG/system.slice/x-ui.old"
sh_run '_shield_paths; _shield_fp_sync' >/dev/null
check [ "$(grep -c 'службы-прокси сменились' "$SF/dir/shield.log")" = "$n0" ]
# nft или ядро не умеют socket cgroupv2 (Ubuntu 20.04, Debian 11) — тот же
#    уровень без служб, без ошибки; отчёт: «сервер и прокси на нём».
sh_reset
mkdir -p "$CG/system.slice/x-ui.service"; : > "$CG/cgroup.controllers"
out=$(NFT_NOCG=1 sh_run 'shield_install; echo "rc=$?"')
check has "$out" 'rc=0'; check hasnt "$out" 'cgroupv2'
check [ "$(sed -n 's/^stl=//p' "$SF/dir/status")" = 3 ]; check [ -z "$(sed -n 's/^prx=//p' "$SF/dir/status")" ]
check neg grep -q 'vk_count\|cgroupv2' "$nf_"; check grep -q 'counter name "out_srv"' "$nf_"
check [ "$(grep -c -- '^-c -f ' "$SF/d/nft.calls")" = 2 ]
check neg grep -qi 'cgroupv2\|не принял' "$SF/dir/shield.log"
NFT_NOCG=1 sh_run 'shield_stats_snap' >/dev/null
out=$(SC_ACTIVE='nginx x-ui' NFT_NOCG=1 sh_run 'shield_cli stats </dev/null')
check has "$out" 'выход  сервер — сервер и прокси на нём'; check hasnt "$out" 'VPN и прокси'
check has "$(SC_ACTIVE=telemt NFT_NOCG=1 sh_run 'LANG_CODE=en; shield_cli stats </dev/null')" 'out    server — the server and proxies on it'
# К5-17: служб-прокси нет (24.04 без goVLESS и goTelegram) — о прокси ни слова.
out=$(SC_ACTIVE=nginx NFT_NOCG=1 sh_run 'shield_cli stats </dev/null')
check has "$out" 'выход  сервер — сам сервер'; check hasnt "$out" 'прокси'
check has "$(NFT_NOCG=1 sh_run 'LANG_CODE=en; shield_cli stats </dev/null')" 'out    server — the server itself'
# Каталог исчез между перечнем и nft (служба остановилась) — то же, без ошибки.
sh_reset
mkdir -p "$CG/system.slice/x-ui.service"; : > "$CG/cgroup.controllers"
out=$(sh_run 'ls() { command ls "$@"; rmdir "$GOINST_SHIELD_CG/system.slice/x-ui.service" 2>/dev/null; }; shield_install; echo "rc=$?"')
check has "$out" 'rc=0'; check [ "$(sed -n 's/^stl=//p' "$SF/dir/status")" = 3 ]; check neg grep -q 'vk_count' "$nf_"
# nft -c принял, а загрузка со службами не прошла — тот же уровень без них.
sh_reset
mkdir -p "$CG/system.slice/x-ui.service"; : > "$CG/cgroup.controllers"
out=$(NFT_LOADNOCG=1 sh_run 'shield_install; echo "rc=$?"')
check has "$out" 'rc=0'; check [ "$(sed -n 's/^stl=//p' "$SF/dir/status")" = 3 ]; check [ -z "$(sed -n 's/^prx=//p' "$SF/dir/status")" ]
check neg grep -q 'vk_count' "$nf_"; check grep -q 'update @ports' "$nf_"; check [ "$(grep -c -- '^-f ' "$SF/d/nft.calls")" = 2 ]
# Без cgroup v2 (нет cgroup.controllers — смешанная иерархия) — службы не ищутся.
sh_reset
mkdir -p "$CG/system.slice/x-ui.service"
sh_run 'shield_install' >/dev/null
check neg grep -q 'vk_count' "$nf_"; check [ "$(grep -c -- '^-c -f ' "$SF/d/nft.calls")" = 1 ]
# Рендер: чужой путь не проходит; без счёта (уровень 0) служб нет.
G6="$SF/d/g6"; mkdir -p "$G6/lists"; printf '45.0.0.0/24\n' > "$G6/lists/vk4"; : > "$G6/addrs"
out=$(sh_run '_shield_py render "'"$G6"'" 0 1 22 "'"$G6"'/addrs" "'"$G6"'/o" 3 "system.slice/x-ui.service ../../etc system.slice/a\"b.service user.slice/x.service system.slice/x-ui.service"')
check has "$out" 'prx=1'; check [ "$(grep -c 'socket cgroupv2' "$G6/o")" = 1 ]
out=$(sh_run '_shield_py render "'"$G6"'" 0 1 22 "'"$G6"'/addrs" "'"$G6"'/o" 0 "system.slice/x-ui.service"')
check has "$out" 'prx=0'; check neg grep -q 'cgroupv2\|vk_count' "$G6/o"

# Сохранность: пересборка, перезагрузка, обновление списков, remove — stats/ на месте.
sh_reset
sh_run 'shield_install' >/dev/null
SST="$SF/dir/stats"
check [ -f "$SST/meta" ]
st0=$(sget started "$SST/meta")
printf '%s\n' "$((T0)) 77 3 1 2 0 0" > "$SST/days"
sh_run 'shield_apply' >/dev/null                                   # пересборка
check grep -q "^$T0 77 " "$SST/days"
GOINST_SHIELD_BOOTID=b9 sh_run 'rm -rf "$SHIELD_RUN"; shield_tick' >/dev/null   # перезагрузка
check grep -q "^$T0 77 " "$SST/days"
SHA=7777777777777777777777777777777777777777 sh_run 'shield_cli update </dev/null' >/dev/null
check grep -q "^$T0 77 " "$SST/days"
out=$(sh_run 'shield_cli remove --yes </dev/null; echo "rc=$?"')
check has "$out" 'rc=0'
check has "$out" "Статистика осталась: $SST"; check has "$out" 'goinstall --shield stats reset'
check grep -q "^$T0 77 " "$SST/days"; check [ ! -e "$SF/dir/lists" ]
check [ "$(sget started "$SST/meta")" = "$st0" ]
# Защиты нет, статистика есть — показать можно; поставить снова — та же статистика.
check has "$(sh_run 'shield_cli stats all </dev/null; echo "rc=$?"')" 'rc=0'
sh_run 'shield_install' >/dev/null
check grep -q "^$T0 77 " "$SST/days"; check [ "$(sget started "$SST/meta")" = "$st0" ]
# Каталог статистики — ссылка: не писать через неё.
mv "$SST" "$SF/d/real"; ln -s "$SF/d/real" "$SST"; rm -f "$SF/d/real/summary"
sh_run 'shield_stats_snap' >/dev/null
check [ ! -e "$SF/d/real/summary" ]; check [ -L "$SST" ]
# REVIEW-6 №7а: и строка в журнал — одна, пока ссылка на месте.
check [ "$(grep -c 'статистика не пишется: .* — ссылка, а не каталог' "$SF/dir/shield.log")" = 1 ]
sh_run 'shield_stats_snap' >/dev/null
check [ "$(grep -c 'ссылка, а не каталог' "$SF/dir/shield.log")" = 1 ]
# REVIEW-6 №7б: обнуление через ссылку — отказ с понятной причиной, не «stats».
out=$(sh_run 'shield_cli stats reset --yes </dev/null; echo "rc=$?"')
check has "$out" 'rc=1'; check has "$out" "Не обнулилось: $SST — ссылка, а не каталог"; check [ -f "$SF/d/real/meta" ]
rm -f "$SST"; mv "$SF/d/real" "$SST"
sh_run 'shield_stats_snap' >/dev/null
check [ -f "$SST/summary" ]; check [ -z "$(sed -n 's/^stlink=//p' "$SF/dir/status")" ]
# Обнуление: без терминала — только с --yes (иначе 64, ничего не тронуто).
out=$(sh_run 'shield_cli stats reset </dev/null; echo "rc=$?"')
check has "$out" 'rc=64'; check has "$out" 'goinstall --shield stats reset --yes'
check grep -q "^$T0 77 " "$SST/days"
sed -i.bak "s/^started=.*/started=$T0/" "$SST/meta"; rm -f "$SST/meta.bak"
out=$(sh_run 'shield_cli stats reset --yes </dev/null; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" 'Статистика обнулена'
check [ ! -e "$SST/days" ]
check [ "$(sget started "$SST/meta")" -gt "$T0" ]
check grep -q 'статистика обнулена' "$SF/dir/shield.log"
check [ -z "$(find "$SST" -type f ! -perm 600)" ]
check [ "$(stat -f %Lp "$SST" 2>/dev/null || stat -c %a "$SST")" = 700 ]
# Защиту сняли — «stats reset» (так подсказывает remove) удаляет каталог целиком.
sh_run 'shield_cli remove --yes </dev/null' >/dev/null; check [ -d "$SST" ]
out=$(sh_run 'shield_cli stats reset --yes </dev/null; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" "Статистика удалена: $SST"; check [ ! -e "$SST" ]
check [ ! -e "$SF/dir/shield.log" ]                              # журнал не воскрешён
check has "$(sh_run 'shield_cli stats </dev/null; echo "rc=$?"')" 'rc=3'
# REVIEW-6 №7е: внутри stats/ каталог (недописанный .tmp) — удаляется весь;
#    при стоящей защите — тоже.
sh_run 'shield_install' >/dev/null; mkdir -p "$SST/addrs.tmp/x"; : > "$SST/addrs.tmp/x/y"
check has "$(sh_run 'shield_cli stats reset --yes </dev/null; echo "rc=$?"')" 'rc=0'; check [ ! -e "$SST/addrs.tmp" ]
sh_run 'shield_cli remove --yes </dev/null' >/dev/null; mkdir -p "$SST/addrs.tmp/x"
out=$(sh_run 'shield_cli stats reset --yes </dev/null; echo "rc=$?"')
check has "$out" 'rc=0'; check has "$out" "Статистика удалена: $SST"; check [ ! -e "$SST" ]
# REVIEW-6 №7д: после remove вопрос не обещает «правила защиты останутся».
#    Настоящий терминал (pty): ответ «2» — каталог на месте.
mkdir -p "$SST"; printf 'started=1\n' > "$SST/meta"
cat > "$SF/d/ptyq.py" <<'PY'
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.execv(sys.argv[1], [sys.argv[1], '-c', '. "$1"; shield_cli stats reset; echo "rc=$?"', 'pty', sys.argv[2]])
buf, sent, end = b'', False, time.time() + 30
while time.time() < end:
    if not select.select([fd], [], [], 0.5)[0]:
        continue
    try:
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    buf += d
    if not sent and b'2)' in buf:
        time.sleep(0.3); os.write(fd, b'2\n'); sent = True
os.waitpid(pid, 0)
sys.stdout.write(buf.decode('utf-8', 'replace'))
PY
out=$(sh_run 'python3 -I "$SFD/ptyq.py" "$BASH" "$SCRIPT"')
check has "$out" "Защиты от сканеров уже нет. Удалить оставшуюся статистику ($SST)?"; check hasnt "$out" 'правила защиты останутся'
check has "$out" 'Оставил как есть'; check [ -f "$SST/meta" ]
rm -rf "$SST"
# REVIEW-6 №7и: список принят до 1.2.4 (подписей сетей lists/owners нет) —
#    первый такт скачивает его заново, не дожидаясь суток и нового хеша.
sh_reset
sh_run 'shield_install' >/dev/null; check [ -f "$SF/dir/lists/owners" ]
rm -f "$SF/dir/lists/owners"; n0=$(grep -c . "$SF/d/urls")
sh_run 'shield_tick' >/dev/null
check [ -f "$SF/dir/lists/owners" ]; check [ "$(grep -c . "$SF/d/urls")" -gt "$n0" ]
n0=$(grep -c . "$SF/d/urls"); sh_run 'shield_tick' >/dev/null
check [ "$(grep -c . "$SF/d/urls")" = "$n0" ]                       # дальше — как прежде, раз в сутки
# Удаление goInstaller — статистику тоже, и говорит об этом (стоит защита
# или осталась одна статистика).
un_seed; mkdir -p "$SF/d/unsh/stats"; printf 'started=1\n' > "$SF/d/unsh/stats/meta"
out=$(GOINST_SHIELD_DIR="$SF/d/unsh" GOINST_SHIELD_NFT="$SF/bin/nft" SFD="$SF/d" un --yes)
check has "$out" 'Статистика защиты от сканеров удалится вместе с ним'; check [ ! -e "$SF/d/unsh" ]
un_seed; mkdir -p "$SF/d/unsh/stats"; printf 'scan=1\nvk=1\n' > "$SF/d/unsh/settings"; : > "$SF/d/unsh/shield.nft"
out=$(GOINST_SHIELD_DIR="$SF/d/unsh" GOINST_SHIELD_NFT="$SF/bin/nft" SFD="$SF/d" un --yes)
check has "$out" 'правила nft, таймер, списки, статистика'; check [ ! -e "$SF/d/unsh" ]
# Сводка при входе (sh-a/sh-b/sh-c макета): строки защиты — те же, что в
# arcade_shield_*.json, клетка в клетку. Сводка читает только готовые
# числа stats/summary и отметку stats/seen; время и пояс заданы.
SHM="$SF/motd"; SHJ="$HERE/design/shield/handoff-stats/goinstaller-shield-stats/project/spec/screens"
TA=1793644800; TS=1793674800; TN=1793714400          # 02.11 18:40, 03.11 03:00, 03.11 14:00 (UTC)
# shm <сканеры> <ВК> <колонки> <язык> [тихо] — сводка без цвета; данные макета.
shm() {
    rm -rf "$SHM"; mkdir -p "$SHM/sh/lists" "$SHM/sh/stats"; chmod 700 "$SHM/sh/stats"
    printf 'scan=%s\nvk=%s\n' "$1" "$2" > "$SHM/sh/settings"
    printf 'date=%s\n' "$TN" > "$SHM/sh/lists/meta"
    printf 'nets=1172\nnx=0\nstl=3\n' > "$SHM/sh/status"
    printf '%s\n' "snap=$TN" lvl=${SHL:-3} "started=$(( TA - 3 * 86400 ))" tin=5000 tfw=100 tsr=20 naddr=4000 \
        d24_in=${SHD:-0} d24_fw=0 d24_sr=${SHD:-0} 't24_1=64500|EXAMPLE-NET (Example LLC)|820|24' 't24_2=64501|ANOTHER-AS|310|9' \
        't24_3=64502||205|6' "spike_h=${SHP:-0}" "spike_x10=${SHX:-0}" spike_n=212 "away_ref=$(( TN - 7200 ))" away_n=37 > "$SHM/sh/stats/summary"
    printf '%s\n' "at=${SHA:-$TA}" "upto=${SHU:-$(( TN - 7200 ))}" cin=3716 cfw=95 csr=16 > "$SHM/sh/stats/seen"
    printf 'sved=14:05\nninst=3\nhost=vpn-fin-1\n' > "$SHM/sum"
    [ -n "${5:-}" ] || printf 'news=↑|update|goTelegram pro|2.10.46 → 2.10.49|обновление в main\n' >> "$SHM/sum"
    ( export PATH="$SF/bin:$PATH" GOINST_SOURCE_ONLY=1 GOINST_LANG="$4" GOINST_TEST=1 TZ=UTC GOINST_SHIELD_DIR="$SHM/sh" \
        GOINST_SUM_FILE="$SHM/sum" GOINST_SHIELD_RUN="$SHM/run" GOINST_COLOR=none GOINST_UI_COLS="$3" GOINST_UI_LINES=24 \
        GOINST_UI_SYS="1 2 0.1" GOINST_SUMMARY_SHOWN="${SHN:-}" GOINST_SHIELD_NFT="$SF/bin/nft" GOINST_SHIELD_NOW="${SHNOW:-$(( TN + 600 ))}"
      . "$SCRIPT"; summary_print </dev/null ) 2>&1 | plain
}
# Строки защиты: от строки «Защита…» до низа рамки (в тихой форме — одна).
shcut() { awk '/Защит|Protection|protection|Shield:/ {f=1} /^╚/ {f=0} f' | sed -n '1,/^[^║]/p' | sed '/^$/d'; }
cat > "$T/shmock.py" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
for s in d:
    if s['id'] == sys.argv[2] and str(s['cols']) == sys.argv[3] and (s.get('state') or '') == sys.argv[4]:
        for r in s['rows']:
            print(''.join(x[0] for x in r).rstrip())
        break
PY
# en — одно имя защиты: «Shield:» макета (sh-b, 46) у нас «Protection:», рамка на месте.
shmock() { python3 -I "$T/shmock.py" "$SHJ/arcade_shield_$1.json" "$2" "$3" "$4" | shcut | sed 's/! Shield: \(.*\)    ║/! Protection: \1║/'; }
for lg in ru en; do
    for c in 80 46; do
        while read -r id st sc vk q; do
            want=$(shmock "$lg" "$id" "$c" "$st")
            got=$(SHX=$([ "$st" = on_spike ] && echo 28 || echo 0) SHP=$TS shm "$sc" "$vk" "$c" "$lg" $q | sed 's/[[:space:]]*$//' | shcut)
            if [ -n "$want" ] && [ "$want" = "$got" ]; then pass; else fail "сводка: $id $st $c $lg — строки защиты не как в макете"; diff <(echo "$want") <(echo "$got") | head -8; fi
        done <<'L'
sh-a on_spike 1 1
sh-a on 1 1
sh-a on_vk_off 1 0
sh-b off 0 1
sh-c quiet 1 1 q
L
    done
done
# «Пока вас не было» — с отметки прошлого показа: вход = tin − cin, адресов —
# away_n, пока отметка раньше снимка; показ отметку переносит.
o=$(shm 1 1 80 ru); check has "$o" '1 284 попытки · 37 адресов'; check has "$o" '9 соединений к сетям ВК'
check grep -qx "at=$TA" "$SHM/sh/stats/seen"                       # без входа по SSH отметка та же
o=$(SHN=1 shm 1 1 80 ru); check has "$o" '1 284 попытки'
check grep -qx "upto=$TN" "$SHM/sh/stats/seen"; check grep -qx 'cin=5000' "$SHM/sh/stats/seen"
check grep -qx 'cfw=100' "$SHM/sh/stats/seen"; check grep -qx 'csr=20' "$SHM/sh/stats/seen"
check [ "$(stat -c %a "$SHM/sh/stats/seen" 2>/dev/null || stat -f %Lp "$SHM/sh/stats/seen")" = 600 ]
# Второй показ подряд — уже ноль: считать с новой отметки.
o=$( ( export PATH="$SF/bin:$PATH" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 TZ=UTC GOINST_SHIELD_DIR="$SHM/sh" \
        GOINST_SUM_FILE="$SHM/sum" GOINST_SHIELD_RUN="$SHM/run" GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 \
        GOINST_UI_SYS="1 2 0.1" GOINST_SUMMARY_SHOWN=1 GOINST_SHIELD_NFT="$SF/bin/nft" GOINST_SHIELD_NOW=$(( TN + 600 ))
      . "$SCRIPT"; summary_print </dev/null ) 2>&1 | plain)
check has "$o" 'остановлены: 0 попыток · 0 адресов'; check has "$o" 'предотвращена: 0 соединений'
# Отметка от прежней статистики (обнулили) — не в счёт: с начала новой.
o=$(SHU=$(( TA - 4 * 86400 )) shm 1 1 80 ru); check has "$o" '5 000 попыток · 37 адресов'
check has "$o" "(с 30.10 18:40)"
# Отметка после снимка — адресов «пока не было» ноль, а не away_n.
o=$(SHU=$TN shm 1 1 80 ru); check has "$o" '1 284 попытки · 0 адресов'
# Уровень 1 (наборов нет) — без адресов и без топа; 0 — блока нет вовсе.
o=$(SHL=1 shm 1 1 80 ru); check has "$o" 'остановлены: 1 284 попытки'; check hasnt "$o" 'адрес'; check hasnt "$o" 'AS64500'
o=$(SHL=0 shm 1 1 80 ru); check hasnt "$o" 'Защита от сканеров'
# Тихая форма: числа за сутки; выкл — только в блоке «Б», тихой нет.
o=$(SHD=3 shm 1 1 80 ru q); check has "$o" '✓ Защита: вкл · за сутки: вход 3 попытки · выход 3 соединения к ВК'
o=$(SHD=3 shm 1 0 46 en q); check has "$o" '✓ Protection: on · 24 h: in 3 · out off'
# Снимки встали (последний — 4 ч назад): числа «на время снимка», без
# всплеска и топа «за сутки» (REVIEW-6 №4); 3 ч — ещё свежие.
SO=$(( TN + 4 * 3600 ))
o=$(SHNOW=$SO SHX=28 SHP=$TS shm 1 1 80 ru); check has "$o" '! Данные от 03.11 14:00 — статистика не обновляется'
check has "$o" '1 284 попытки · 37 адресов'; check hasnt "$o" 'за сутки'; check hasnt "$o" 'Всплеск'; check hasnt "$o" 'AS64500'
o=$(SHNOW=$(( TN + 10800 )) SHX=28 SHP=$TS shm 1 1 80 ru); check hasnt "$o" 'Данные от'; check has "$o" 'Всплеск'; check has "$o" 'Чаще всего за сутки'
o=$(SHNOW=$SO shm 1 1 46 en); check has "$o" '! data as of 3 Nov 14:00'; check hasnt "$o" 'AS64500'
o=$(SHNOW=$SO shm 0 1 80 ru); check has "$o" '! Данные от 03.11 14:00'; check has "$o" 'Рекомендуем включить'
o=$(SHNOW=$SO shm 0 1 46 ru); check has "$o" '! данные от 03.11 14:00'
o=$(SHD=3 SHNOW=$SO shm 1 1 80 ru q); check has "$o" '✓ Защита: вкл · статистика не обновлялась с 03.11 14:00'; check hasnt "$o" 'за сутки'
o=$(SHD=3 SHNOW=$SO shm 1 1 46 en q); check has "$o" '✓ Protection: on · data as of 3 Nov 14:00'
# «Сейчас» подменяется только в наборе.
check [ "$(GOINST_SHIELD_NOW=5 ml '_shield_now')" != 5 ]; check [ "$(GOINST_TEST=1 GOINST_SHIELD_NOW=5 ml '_shield_now')" = 5 ]
o=$(shm 0 1 80 ru q); check has "$o" 'Рекомендуем включить'; check hasnt "$o" 'Защита: вкл'
# Значок в приглашении: защита выкл — замечание.
check has "$(sh_run 'UD_NEWS=(); UD_PROB=(); UD_SHOFF=1; ui_badge; printf "%s\n" "$UI_BADGE"' | tr '\036\037' '\n\n')" ' !1'
check [ -z "$(sh_run 'UD_NEWS=(); UD_PROB=(); UD_SHOFF=""; ui_badge; printf "%s" "$UI_BADGE"')" ]
# Чужое в summary (не числа, длинные) — нули, а не арифметика bash.
printf '%s\n' 'snap=$(id)' 'lvl=3' 'tin=99999999999999999999' 'started=1' > "$SHM/sh/stats/summary"
o=$( ( export PATH="$SF/bin:$PATH" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1 TZ=UTC GOINST_SHIELD_DIR="$SHM/sh" \
        GOINST_SUM_FILE="$SHM/sum" GOINST_SHIELD_RUN="$SHM/run" GOINST_COLOR=none GOINST_UI_COLS=80 GOINST_UI_LINES=24 \
        GOINST_UI_SYS="1 2 0.1" GOINST_SHIELD_NFT="$SF/bin/nft" GOINST_SHIELD_NOW=$(( TN + 600 ))
      . "$SCRIPT"; summary_print </dev/null; echo "rc=$?" ) 2>&1 | plain)
check has "$o" 'rc=0'; check has "$o" ': 0 попыток · 0 адресов'
# Вывод без tty (sh-f макета): ключ раздела — первой колонкой, числа —
# вправо, подвал со ссылкой на источник. Данные — 30 часов снимков
# одной таблицы (час с всплеском), время и пояс заданы.
sh_reset; : > "$SF/d/own"
cat > "$SF/d/bwc" <<'TXT'
---
# Networks announced by AS64500
# AS-Name (ORG): EXAMPLE-NET (Example LLC)
45.0.4.0/24
---
# Networks announced by AS64501
# AS-Name (ORG): ANOTHER-AS
45.0.5.0/24
TXT
sh_run '_shield_spy owners "$SFD/bwc" "$SFD/own"' >/dev/null
i4=0; fw=0; sr=0; s4=""
for k in $(seq 0 29); do
    n=$(( 40 + (k * 7) % 23 )); [ "$k" = 26 ] && n=240
    i4=$(( i4 + n )); fw=$(( fw + k % 3 )); sr=$(( sr + (k % 5 == 0) ))
    s4="45.0.4.$((k % 9 + 1)):$((k + 1)):100,45.0.5.$((k % 4 + 1)):$((k / 2 + 1)):200,45.0.9.$((k % 3 + 1)):1:300"
    nfa h=23 in4=$i4 in6=0 out_fwd=$fw out_srv=$sr seen4="$s4" ports=tcp.22:$((k * 9)),tcp.443:$((k * 5)),tcp.3389:$((k * 2)) \
        pair4=45.0.4.$((k % 9 + 1)).tcp.443,45.0.5.$((k % 4 + 1)).tcp.22
    TZ=UTC snapx b1 $(( T0 + k * 3600 + 600 )) >/dev/null
    [ "$k" = 23 ] && { ci=$i4; cf=$fw; cs=$sr; }
done
printf '%s\n' scan=1 vk=1 "date=$((T0 + 20 * 3600))" nets=1172 nx=3 host=vpn-fin-1 'lab 22/tcp=SSH' 'lab 443/tcp=goVLESS pro' > "$SF/d/info"
printf '%s\n' "at=$((T0 + 24 * 3600))" "upto=$((T0 + 23 * 3600 + 600))" "cin=$ci" "cfw=$cf" "csr=$cs" > "$STD/seen"
shf() { TZ=UTC sh_run '_shield_spy report "$SFD/st" '"$1 $2 $3"' "$SFD/info" '"$(( T0 + 29 * 3600 + 900 ))"'; echo "rc=$?"'; }
# Каркас sh-f — как в макете: заголовки разделов («#»), подвал и порядок
# ключей первой колонки совпадают со всеми четырьмя вариантами макета.
cat > "$T/shfmock.py" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
for s in d:
    if s['id'] == 'sh-f' and str(s['cols']) == sys.argv[2]:
        for r in s['rows']:
            print(''.join(x[0] for x in r).rstrip())
PY
# Каркас: строки «#» без заголовка с сервером и временем, затем ключи по порядку.
shfskel() { awk '/^# (goInstaller|vpn-fin-1) · / {next} /^#/ {print; next} /^[^# ]/ {print "key " $1}' | uniq; }
for lg in ru en; do
    for c in 80 46; do
        want=$(python3 -I "$T/shfmock.py" "$SHJ/arcade_shield_$lg.json" "$c" | shfskel)
        got=$(shf full "$c" "$lg" | sed '$d' | shfskel)
        if [ -n "$want" ] && [ "$want" = "$got" ]; then pass; else fail "sh-f $c $lg: каркас не как в макете"; diff <(echo "$want") <(echo "$got") | head -8; fi
    done
done
# Числа sh-f на заданных данных (сверены вручную): «с …» — от отметки
# показа (вход = tin − cin), сутки — 24 часовые корзины, дни до начала
# счёта — «—», час всплеска и его кратность к медиане.
o=$(shf full 80 ru)
# В шапке — время последнего снимка (15:10), а не вызова (15:15): К5-7.
for l in '# goInstaller · защита от сканеров · vpn-fin-1 · 04.11.2026 15:10' \
         'список     AS_Network_List от 04.11.2026 · 1172 сетей · исключено 3' \
         'вход   с 04.11 10:00           497       13' 'вход   сутки                  1362       16' \
         'вход   всего                  1710       16' 'выход  с 04.11 10:00             7        6        1' \
         'день   02.11 пн              —        —' 'день   03.11 вт            752       18' \
         'час    11:00               209        2' 'пик        11:00–12:00 · 209' 'всплеск    ×4,2 к медиане часа' \
         'адреса     новые 3 · повторные 13' 'порт   443/tcp             115  goVLESS pro' 'порт   3389/tcp             46  свободен' \
         'топ24ч AS64500         213        9  EXAMPLE-NET (Example LLC)' 'топ24ч —                 0        3  без подписи в списке' \
         'rc=0'; do
    check grep -qxF -- "$l" <<<"$o"
done
check [ "$(grep -c '^час ' <<<"$o")" = 24 ]; check [ "$(grep -c '^день ' <<<"$o")" = 7 ]
o=$(shf full 46 en)
for l in '# goInstaller · scanner protection' '# vpn-fin-1 · 04.11.2026 15:10' 'list       AS_Network_List of 04.11.2026 · 11…' \
         'out    since 04.11 10:00         7        6  …' 'day    04.11 We            958       18' 'spike      ×4.2 vs hourly median' \
         'top24h AS64500         213        9' '   EXAMPLE-NET (Example LLC)' '# Thanks to C24Be for the data and the idea.'; do
    check grep -qxF -- "$l" <<<"$o"
done
check [ "$(python3 -I -c 'import sys; print(max(len(l.rstrip("\n")) for l in sys.stdin))' <<<"$o")" -le 46 ]
o=$(TZ=UTC sh_run '_shield_spy top "$SFD/st" 24h 80 ru "$SFD/info" '"$(( T0 + 29 * 3600 + 900 ))"'; echo "rc=$?"')
check grep -qxF '1   AS64500         213        9  04.11 15:08    443/tcp   EXAMPLE-NET (Example LLC)' <<<"$o"
check grep -qxF '# goInstaller · топ-30 сканеров · сутки · vpn-fin-1 · 04.11.2026 15:10' <<<"$o"
check grep -qxF '3   —                 0        3  04.11 15:05    —         без подписи в списке' <<<"$o"
# Свежий сервер: меньше 6 полных часов — всплеска нет, даже если час большой.
sh_reset; : > "$SF/d/own"
nfa h=1 in4=30 in6=0; TZ=UTC snapx b1 $(( T0 + 600 )) >/dev/null
nfa h=1 in4=330 in6=0; TZ=UTC snapx b1 $(( T0 + 3600 + 600 )) >/dev/null
printf '%s\n' scan=1 vk=1 host=h > "$SF/d/info"
o=$(TZ=UTC sh_run '_shield_spy report "$SFD/st" 24h 80 ru "$SFD/info" '"$(( T0 + 3600 + 900 ))")
check grep -qxF 'всплеск    нет' <<<"$o"; check grep -qxF 'час    09:00                25        0' <<<"$o"
check grep -qxF 'час    08:00                 —        —' <<<"$o"
check neg grep -q '^spike_' "$STD/summary"
# К5-7 (стенд 03.11): попыток не было — «пик —», а не первый час окна с 0;
#    в шапке — время снимка (10:10), а не вызова (10:30).
sh_reset; : > "$SF/d/own"
nfa h=1 in4=0 in6=0; TZ=UTC snapx b1 $(( T0 + 600 )) >/dev/null
printf '%s\n' scan=1 vk=1 host=h > "$SF/d/info"
o=$(TZ=UTC sh_run '_shield_spy report "$SFD/st" 24h 80 ru "$SFD/info" '"$(( T0 + 1800 ))")
check grep -qxF 'пик        —' <<<"$o"; check neg grep -q '^пик .*· 0' <<<"$o"
check grep -qxF '# goInstaller · защита от сканеров · h · 03.11.2026 10:10' <<<"$o"
check grep -qxF 'peak       —' <<<"$(TZ=UTC sh_run '_shield_spy report "$SFD/st" 24h 46 en "$SFD/info" '"$(( T0 + 1800 ))")"
# Попытки есть — пик как прежде (7 за 10:10–11:10: 6 в часе 10:00, 1 в 11:00).
nfa h=1 in4=7 in6=0; TZ=UTC snapx b1 $(( T0 + 4200 )) >/dev/null
o=$(TZ=UTC sh_run '_shield_spy report "$SFD/st" 24h 80 ru "$SFD/info" '"$(( T0 + 4500 ))")
check grep -qxF 'пик        10:00–11:00 · 6' <<<"$o"

echo "── защита от сканеров: статистика — нагрузка и сбои (REVIEW-6)"
# Снимок без защиты, прямо из извлечённого spy: память и время — его, а не bash.
awk '/^_shield_spy\(\) \{/ {f=1; next} f && /<<.SPY.$/ {g=1; next} g && /^SPY$/ {exit} g' "$SCRIPT" > "$T/spy.py"
# rss.py <команда…> → «rc пик-памяти-МБ ЦП-с»; на Linux ru_maxrss в КиБ, на macOS в байтах.
cat > "$T/rss.py" <<'PY'
import resource, subprocess, sys
try:
    r = subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60).returncode
except subprocess.TimeoutExpired:
    r = 124
u = resource.getrusage(resource.RUSAGE_CHILDREN)
m = u.ru_maxrss if sys.platform == 'darwin' else u.ru_maxrss * 1024
print(r, m >> 20, '%.2f' % (u.ru_utime + u.ru_stime))
PY
# №1: база на пределе (200 тыс.), все наборы полные и свежие — снимок и отчёт
# в 64 МБ (было ~400 и ~260). Числа замера — design/shield/bench/bench.sh.
BW="$T/bench"; rm -rf "$BW"; mkdir -p "$BW"
python3 -I "$HERE/design/shield/bench/gen.py" "$BW" 200000 1793714400
printf 'scan=1\nvk=1\nhost=h\n' > "$BW/info"
for x in 600 4200; do
    r=$(python3 -I "$T/rss.py" python3 -I "$T/spy.py" snap "$BW/st" "$BW/live" "$BW/own" b2 $((1793714400 + x)))
    check [ "${r%% *}" = 0 ]; read -r _ mb _ <<<"$r"; check [ "$mb" -le 64 ]
done
check [ "$(grep -c '' "$BW/st/addrs")" -le 200000 ]
na=$(sget naddr "$BW/st/meta"); check [ "$na" -gt 240000 ]
r=$(python3 -I "$T/rss.py" python3 -I "$T/spy.py" report "$BW/st" full 80 ru "$BW/info" $((1793714400 + 4300)))
check [ "${r%% *}" = 0 ]; read -r _ mb _ <<<"$r"; check [ "$mb" -le 64 ]
# Вытесненные по пределу и вернувшиеся (второй снимок видит их снова) — не новые.
r=$(python3 -I "$T/rss.py" python3 -I "$T/spy.py" snap "$BW/st" "$BW/live" "$BW/own" b2 $((1793714400 + 7800)))
check [ "${r%% *}" = 0 ]; check [ "$(sget naddr "$BW/st/meta")" = "$na" ]
rm -rf "$BW"
# №7ж: предел 3 — самый давний вытеснен; вернулся — «всего» не растёт, в часе
# он повторный, а не новый, первый раз — не позже вытеснения.
sh_reset; : > "$SF/d/own"
nfa h=23 in4=5 in6=0 seen4=45.0.4.1:1:3000,45.0.4.2:1:2000,45.0.4.3:1:1000,45.0.4.4:1:500
GOINST_SHIELD_STATS_MAX=3 snapx b1 $((T0+600)) >/dev/null
check [ "$(sget naddr "$STD/meta")" = 4 ]; check neg grep -q '^45.0.4.1 ' "$STD/addrs"
nfa h=23 in4=6 in6=0 seen4=45.0.4.1:2:100
GOINST_SHIELD_STATS_MAX=3 snapx b1 $((T0+4200)) >/dev/null
check [ "$(sget naddr "$STD/meta")" = 4 ]; check grep -q '^45.0.4.1 ' "$STD/addrs"
check [ "$(awk -v h=$((T0+3600)) '$1 == h {print $4, $5}' "$STD/hours")" = '0 1' ]
check [ "$(awk '$1 == "45.0.4.1" {print ($2 <= '$((T0+600-3000))')}' "$STD/addrs")" = 1 ]
check [ -z "$(find "$STD" -type f ! -perm 600)" ]
# Новый, которого не было, — новый.
nfa h=23 in4=7 in6=0 seen4=45.0.4.9:1:100
GOINST_SHIELD_STATS_MAX=3 snapx b1 $((T0+7800)) >/dev/null
check [ "$(sget naddr "$STD/meta")" = 5 ]
# №2: подпись сети на 8 МБ из «a-» (регулярка по ней — квадрат, часы) —
# список разбирается быстрее секунды, подпись — не длиннее 60.
python3 -I -c 'import sys; sys.stdout.write("---\n# NET-Name: 45.0.0.0/16 " + "a-" * 4000000 + "\n45.0.0.0/16\n")' > "$T/bwc8"
r=$(python3 -I -c 'import subprocess, sys, time
t = time.time()
try:
    subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, timeout=20)
except subprocess.TimeoutExpired:
    print("timeout"); sys.exit()
print("%.2f" % (time.time() - t))' python3 -I "$T/spy.py" owners "$T/bwc8" "$T/own8")
check python3 -I -c 'import sys; sys.exit(not float(sys.argv[1]) < 1)' "$r"
lab=$(awk -F'\t' '$1 == "45.0.0.0/16" {print $3}' "$T/own8")
check [ "$(printf '%s' "$lab" | python3 -I -c 'import sys; n = len(sys.stdin.read()); print(int(0 < n <= 60))')" = 1 ]
rm -f "$T/bwc8" "$T/own8"
# №3: сбой посреди записи (addrs.tmp — каталог) — снимок не встал, повтор
# считает дельту один раз: часы = дни = итог.
sh_reset
nfa h=23 in4=100 in6=0 seen4=45.0.4.1:1:100; snapx b1 $((T0+600)) >/dev/null
nfa h=23 in4=150 in6=0 seen4=45.0.4.1:2:100; mkdir "$STD/addrs.tmp"
check neg has "$(snapx b1 $((T0+4200)))" 'rc=0'
rmdir "$STD/addrs.tmp"; nfa h=23 in4=200 in6=0 seen4=45.0.4.1:3:100; snapx b1 $((T0+7800)) >/dev/null
check [ "$(sget tin "$STD/meta")" = 200 ]
check [ "$(awk '{s+=$2} END {print s}' "$STD/hours") $(awk '{s+=$2} END {print s}' "$STD/days")" = '200 200' ]
check [ "$(awk '$1 == "45.0.4.1" {print $4}' "$STD/addrs")" = 3 ]
# Убит посреди замен (часть файлов уже новая): следующий снимок доводит
# замены по журналу и считает только новое.
nfa h=23 in4=260 in6=0 seen4=45.0.4.1:5:100
out=$(GOINST_SHIELD_STATS_DIE=2 snapx b1 $((T0+11400)))
check has "$out" 'rc=9'; check [ -e "$STD/commit" ]
nfa h=23 in4=300 in6=0 seen4=45.0.4.1:6:100; snapx b1 $((T0+15000)) >/dev/null
check [ ! -e "$STD/commit" ]; check [ -z "$(find "$STD" -name '*.tmp' -o -name 'addrs.new')" ]
check [ "$(sget tin "$STD/meta")" = 300 ]
check [ "$(awk '{s+=$2} END {print s}' "$STD/hours") $(awk '{s+=$2} END {print s}' "$STD/days")" = '300 300' ]
check [ "$(awk '$1 == "45.0.4.1" {print $4}' "$STD/addrs")" = 6 ]
# Убит до журнала (только .tmp) — прежнее остаётся, .tmp выбрасываются.
printf 'junk\n' > "$STD/hours.tmp"; printf 'junk\n' > "$STD/meta.tmp"
nfa h=23 in4=310 in6=0; snapx b1 $((T0+18600)) >/dev/null
check [ "$(sget tin "$STD/meta")" = 310 ]; check neg grep -q junk "$STD/hours" "$STD/meta"
check [ -z "$(find "$STD" -name '*.tmp')" ]

echo "── защита от сканеров: экраны статистики в «Аркаде» (1.2.4)"
# Экраны sh-d, sh-e, sh-g, sh-h и главное меню (g1, g2, курсор на 1 и на s)
# сверяются клетка в клетку с макетом статистики (spec/screens пакета
# design/shield/handoff-stats). Данные — фикстура макета ui-model/<язык>.txt
# (её отдаёт ui_sh_model при GOINST_TEST), день — вт 03.11.2026.
# Подпись пункта x en у кода прежняя («Remove goInstaller»): в эталоне меню она
# подменяется; «2443/tcp12 872» макета у нас с пробелом; остальное — как в макете.
SHX="$T/shx"; mkdir -p "$SHX"
SHSPEC="$HERE/design/shield/handoff-stats/goinstaller-shield-stats/project/spec/screens"
cat > "$T/shgold.py" <<'PY'
import json, os, re, sys
sdir, lang, listf = sys.argv[1:4]
ALIAS = [("x Uninstall goInstaller", "x Remove goInstaller")]   # пункты списка, не заголовки
cache = {}
def find(spec, key):
    if spec not in cache:
        with open(os.path.join(sdir, f"arcade_{spec}_{lang}.json"), encoding="utf-8") as f:
            cache[spec] = json.load(f)
    c = dict(kv.split("=", 1) for kv in key.split(","))
    m = [x for x in cache[spec] if all(str(x.get(k)) == v for k, v in c.items())]
    return m[0] if len(m) == 1 else None
def spec_cells(row):
    return [[ch, tok] for txt, tok in row for ch in txt]
def dump_cells(line):
    if "\t" not in line: return [[c, "?"] for c in line]
    text, runs = line.split("\t", 1)
    toks = []
    for r in runs.split(","):
        if r:
            tok, n = r.rsplit(":", 1); toks += [tok] * int(n)
    return [[c, t] for c, t in zip(text, toks)]
def fix(exp, menu):
    for i, row in enumerate(exp):
        line = "".join(c for c, _ in row)
        for word in ("ЧТО НОВОГО", "WHAT'S NEW"):     # гасится, как в golden.py
            c = line.find(word)
            if c < 0: continue
            e = line.find("║", c); e = len(line) if e < 0 else e
            for rr in (i, i + 1):
                if rr < len(exp):
                    for k in range(c, min(e, len(exp[rr]))): exp[rr][k] = [" ", "text"]
        for a, b in (ALIAS if menu else []):
            c = "".join(x for x, _ in row).find(a)
            if c >= 0:
                for k, ch in enumerate(b.ljust(len(a))): row[c + k][0] = ch
        if not menu:   # «2443/tcp12 872» макета: у нас между портом и числом пробел (отступление)
            line = "".join(x for x, _ in row)
            for m in reversed(list(re.finditer(r"\d/(?:tcp|udp)(?=\d)", line))):
                row.insert(m.end(), [" ", "text"])
def norm(cells):
    out = [[c, ("SEL" if t.endswith("+sel") else "SP") if c == " " else t] for c, t in cells]
    while out and out[-1][0] == " " and out[-1][1] != "SEL": out.pop()
    return out
for line in open(listf, encoding="utf-8"):
    spec, key, dump = line.rstrip("\n").split("\t")
    s = find(spec, key)
    if s is None:
        print(f"BAD {spec} {key}: такого экрана в макете нет (или их несколько)"); continue
    exp = [spec_cells(r) for r in s["rows"]]; fix(exp, spec == "menu")
    got = [dump_cells(l) for l in open(dump, encoding="utf-8").read().split("\n")]
    while got and not got[-1]: got.pop()
    bad = []
    for i in range(max(len(exp), len(got))):
        a = norm(exp[i]) if i < len(exp) else []
        b = norm(got[i]) if i < len(got) else []
        if a != b: bad.append((i, a, b))
    if not bad:
        print(f"OK {spec} {key}"); continue
    i, a, b = bad[0]
    k = next((j for j in range(min(len(a), len(b))) if a[j] != b[j]), min(len(a), len(b)))
    print(f"BAD {spec} {key}: строк {len(bad)}, первая {i + 1}, клетка {k + 1}: "
          f"ждали {a[k] if k < len(a) else '∅'}, есть {b[k] if k < len(b) else '∅'}\n"
          f"      макет  |{''.join(c for c, _ in a)}|\n      у нас  |{''.join(c for c, _ in b)}|")
PY
cp "$HERE/design/shield/handoff-stats/ui-model/ru.txt" "$T/shfix-ru.txt"
cp "$HERE/design/shield/handoff-stats/ui-model/en.txt" "$T/shfix-en.txt"
# После обнуления: уровня ещё нет («-»), часовых чисел тоже.
printf 'g|-|03.11.2026|14:05|0|104858|0\n' > "$SHX/done.txt"
# макет|ключ экрана|ширины|модель|чем нарисовать; пустая модель — фикстура.
SHFS='ui_menu_items; for ((k = 0; k < ${#MI_KEY[@]}; k++)); do [ "${MI_KEY[k]}" = s ] && break; done'
cat > "$SHX/cases" <<C
shield|id=sh-d,state=on,chart=fly|80 46||ui_scr_shield 0
shield|id=sh-d,state=off|80 46||SHS_ST=off; SHS_SCAN=0; SHS_VK=0; ui_scr_shield 0
shield|id=sh-e,state=h24,chart=fly|80 46||UI_SHV=0; UI_SHR=-1; ui_scr_shstats
shield|id=sh-e,state=d7,chart=fly|80 46||UI_SHV=1; UI_SHR=-1; ui_scr_shstats
shield|id=sh-e,state=m30,chart=fly|80 46||UI_SHV=2; UI_SHR=-1; ui_scr_shstats
shield|id=sh-e,state=all,chart=fly|80 46||UI_SHV=3; UI_SHR=-1; ui_scr_shstats
shield|id=sh-g,state=h24|80 46||UI_SHV=0; UI_SHT=0; ui_scr_shtop
shield|id=sh-g,state=d7|80 46||UI_SHV=1; UI_SHT=0; ui_scr_shtop
shield|id=sh-g,state=m30|80 46||UI_SHV=2; UI_SHT=0; ui_scr_shtop
shield|id=sh-g,state=all|80 46||UI_SHV=3; UI_SHT=0; ui_scr_shtop
shield|id=sh-h,state=main|80 46||UI_SHH=main; UI_SHC=0; ui_scr_shset
shield|id=sh-h,state=confirm|80 46||UI_SHH=confirm; ui_scr_shset
shield|id=sh-h,state=done|80 46|$SHX/done.txt|UI_SHH=done; UI_SHC=0; ui_scr_shset
menu|id=g2,variant=A,cursor=1|80||ui_scr_menu 0
menu|id=g2,variant=A,cursor=s,chart=fly|80||$SHFS; ui_scr_menu \$k
menu|id=g1,variant=A,cursor=1|46||ui_scr_menu 0
menu|id=g1,variant=A,cursor=s|46||$SHFS; ui_scr_menu \$k
C
# Окружение экрана — как у сверки g1/g2 выше, версия — как в макете.
SHENV='GOINST_UI_COLS=$w; GOINST_UI_LINES=24; ui_detect
    ui_example; ui_example_more; ui_example_news; TOKEN=gold; UD_VER=1.2.3
    [ "$LANG_CODE" = en ] && UI_SPIN=⠇'
shx_draw() {  # shx_draw <язык> — экраны из $SHX/cases, один bash на язык
    T="$T" SHX="$SHX" SHENV="$SHENV" GOINST_SOURCE_ONLY=1 GOINST_LANG="$1" GOINST_COLOR=none GOINST_DIR=/opt/go-installer \
    bash -c 'unset GOINST_TOKEN_FILE GOINST_ASCII; . "$1"; . "$T/ui_example.sh"; n=0
        while IFS="|" read -r spec key widths mdl cmd; do
            for w in $widths; do
                n=$((n + 1)); f="$SHX/$LANG_CODE-$n"
                ( eval "$SHENV"; SHFIX="$mdl"; ui_example_shield; eval "$cmd"; ui_compose; ui_dump ) > "$f" 2>&1
                printf "%s\t%s\t%s\n" "$spec" "$key,cols=$w" "$f"
            done
        done < "$SHX/cases"' _ "$SCRIPT" > "$SHX/list-$1"
}
# shp <язык> <ширина> <модель|""> <команда> — один экран текстом (без ролей).
shp() {
    T="$T" SHENV="$SHENV" GOINST_SOURCE_ONLY=1 GOINST_LANG="$1" GOINST_COLOR=none GOINST_DIR=/opt/go-installer \
    bash -c 'unset GOINST_TOKEN_FILE GOINST_ASCII; . "$1"; . "$T/ui_example.sh"; w=$2
        eval "$SHENV"; SHFIX="$3"; ui_example_shield; eval "$4"; ui_compose; ui_dump | cut -f1' _ "$SCRIPT" "$2" "$3" "$4" 2>&1
}
if command -v python3 >/dev/null 2>&1; then
    for lg in ru en; do
        shx_draw "$lg"
        python3 -I "$T/shgold.py" "$SHSPEC" "$lg" "$SHX/list-$lg" > "$SHX/report-$lg" 2>&1
        while IFS= read -r l; do
            case "$l" in
                OK\ *) pass ;;
                BAD\ *) FAIL=$((FAIL+1)); echo "  ✗ макет статистики: $lg ${l#BAD }" ;;
                *) echo "$l" ;;
            esac
        done < "$SHX/report-$lg"
        # 13 экранов и 2 меню в двух ширинах: 30 сверок на язык.
        check [ "$(grep -c '^OK ' "$SHX/report-$lg")" -eq 30 ]
    done
else
    echo "  (нет python3 — сверка с макетом статистики пропущена)"
fi
# Состояния без макета — по смыслу. Модели: чисел нет; уровни 0–2 (nft
# не умеет счётчиков; без портов; без адресов).
: > "$SHX/none.txt"
for l in 0 1 2; do sed "1s/^g|3|/g|$l|/" "$T/shfix-ru.txt" > "$SHX/l$l.txt"; done
o=$(shp ru 80 "$SHX/none.txt" "$SHFS; ui_scr_menu \$k")
check has "$o" 'Статистики ещё нет: счётчики'
check has "$o" '✓ вход, попыток         —         —'
check has "$o" 'Enter — меню «Защита»'; check hasnt "$o" '←→ день'
check hasnt "$(shp ru 80 "$SHX/none.txt" 'ui_scr_menu 0')" '║ вход '
o=$(shp ru 46 "$SHX/none.txt" "$SHFS; ui_scr_menu \$k")
check hasnt "$o" 'сканеры остановлены'; check neg grep -q '^  вход ' <<<"$o"
check has "$(shp ru 46 "$SHX/none.txt" 'ui_scr_shield 0')" 'статистики ещё нет: раз в час'
check has "$(shp ru 80 "$SHX/none.txt" 'UI_SHV=0; UI_SHR=-1; ui_scr_shstats')" 'Статистики ещё нет: счётчики снимаются раз в час.'
check has "$(shp en 46 "$SHX/none.txt" 'UI_SHV=0; UI_SHT=0; ui_scr_shtop')" 'No statistics yet'
check has "$(shp ru 80 "$SHX/l0.txt" 'ui_scr_shield 0')" 'Статистики не будет: nft или ядро не'
o=$(shp ru 80 "$SHX/l2.txt" 'UI_SHV=0; UI_SHR=-1; ui_scr_shstats')
check has "$o" 'ПОРТЫ · чаще всего'; check grep -qE '┴0 +1 +2 +3 +нет данных$' <<<"$o"; check hasnt "$o" '22/tcp     704 SSH'
check has "$(shp ru 80 "$SHX/l2.txt" 'UI_SHV=0; UI_SHT=0; ui_scr_shtop')" 'EXAMPLE-NET (Example LL…        —        24  03.11 13:49'
check has "$(shp ru 80 "$SHX/l1.txt" 'UI_SHV=0; UI_SHT=0; ui_scr_shtop')" 'EXAMPLE-NET (Example LL…        —         —  03.11 13:49'
check grep -qE 'повторные +—$' <<<"$(shp ru 80 "$SHX/l1.txt" 'UI_SHV=0; UI_SHR=-1; ui_scr_shstats')"
check has "$(shp ru 80 "$SHX/l1.txt" 'ui_scr_shield 0')" '║   адресов               —         —   ║'
check has "$(shp ru 46 "$SHX/l1.txt" "$SHFS; ui_scr_menu \$k")" '✓ Вход · сканеры остановлены: 2 105 · —'
# К5-7: попыток не было — пик «—», а не «03:00–04:00 · 0»: на 80 — колонка
#    справа от пирамиды суток, на 46 — строка « пик» под пирамидой 7 дней.
sed -e 's/^pk|24h|212|28|1|03$/pk|24h|0|-1|0|03/' -e 's/^pk|7d|2310|14|0|02|11|1$/pk|7d|0|-1|0|02|11|1/' \
    "$T/shfix-ru.txt" > "$SHX/pk0.txt"
o=$(shp ru 80 "$SHX/pk0.txt" 'UI_SHV=0; UI_SHR=-1; ui_scr_shstats')
check grep -qE '│ 23–01  │.*┊ +—$' <<<"$o"; check hasnt "$o" '03:00–04:00'
check grep -qE '│ 23–01  │.*┊ +03:00–04:00 · 212$' <<<"$(shp ru 80 "" 'UI_SHV=0; UI_SHR=-1; ui_scr_shstats')"
check grep -qxF ' пик —' <<<"$(shp ru 46 "$SHX/pk0.txt" 'UI_SHV=1; UI_SHR=-1; ui_scr_shstats')"
check grep -qxF ' пик пн 02.11 · 2 310' <<<"$(shp ru 46 "" 'UI_SHV=1; UI_SHR=-1; ui_scr_shstats')"
# ВК выключен: выход не защищён — «!» в заголовке, счётчиках и спарклайне.
o=$(shp ru 80 "" "SHS_VK=0; $SHFS; ui_scr_menu \$k")
check has "$o" '═ ! выход выкл ═╗'; check has "$o" '║ ! выход выкл: утечка IP не защищена   ║'
check has "$(shp ru 80 "" 'SHS_VK=0; ui_scr_menu 0')" '║ вход ▂▂▃▁▃█▅ ✓  выход ! выкл      ║'
o=$(shp ru 46 "" "SHS_VK=0; $SHFS; ui_scr_menu \$k")
check has "$o" '  ! Выход: защита от утечки IP не работает'; check has "$o" '  вход ▂▂▃▁▃█▅ ✓  выход ! выкл'
check has "$(shp en 46 "" 'SHS_VK=0; ui_scr_menu 0')" '  in ▂▂▃▁▃█▅ ✓  out ! off'
# Вход выключен — считает, но не блокирует.
check has "$(shp ru 46 "" "SHS_ST=off; SHS_SCAN=0; $SHFS; ui_scr_menu \$k")" '  ! Вход · выкл · только считает: 2 105 · 52'
# Не работает: в карточке причина, а не график; «✓» у чисел в меню врал бы —
# ни счётчиков, ни спарклайна, о поломке говорят ✗ у пункта и тревога.
SHBAD="SHS_ST=bad; SHS_TEXT='не работает'; SHS_WHY='правил нет'"
o=$(shp ru 80 "" "$SHBAD; $SHFS; ui_scr_menu \$k")
check has "$o" '║ ✗ Не работает: правил нет             ║'; check hasnt "$o" 'шкала'; check hasnt "$o" '←→ день'
check hasnt "$(shp ru 80 "" "$SHBAD; ui_scr_menu 0")" '║ вход '
o=$(shp ru 46 "" "$SHBAD; $SHFS; ui_scr_menu \$k")
check has "$o" '  не работает: правил нет'; check hasnt "$o" 'сканеры остановлены'; check neg grep -q '^  вход ' <<<"$o"
# Токены in/out — из spec/tokens-shield.json макета: строка таблицы и цвет
# в каждом из четырёх режимов (без цвета — обычный текст, вход и выход
# различаются стороной и подписью).
check [ "$(python3 -I - "$SHSPEC/../tokens-shield.json" "$SCRIPT" <<'PY'
import json, re, sys
spec = json.load(open(sys.argv[1], encoding='utf-8'))['arcade']
src = open(sys.argv[2], encoding='utf-8').read()
bad = 0
for t in spec:
    m = re.search(r'^' + t['token'] + r"\|([^\n']*)", src, re.M)
    want = [t['truecolor_dark'], t['truecolor_light'], str(t['xterm256_dark']), str(t['xterm256_light']),
            t['ansi16'], '-', '1' if t['bold'] else '0', '-']
    if not m or m.group(1).split('|') != want:
        bad += 1
print('ok' if bad == 0 and len(spec) == 2 else 'bad')
PY
)" = ok ]
tk() { GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; UI_COLOR=$1; UI_BG=$2; ui_tokens; printf '%q %q' \"\${UI_SGR[in]}\" \"\${UI_SGR[out]}\""; }
check [ "$(tk true dark)" = "$'\E[0;38;2;31;182;255m' $'\E[0;38;2;159;227;255m'" ]
check [ "$(tk true light)" = "$'\E[0;38;2;0;104;168m' $'\E[0;38;2;74;151;201m'" ]
check [ "$(tk 256 dark)" = "$'\E[0;38;5;39m' $'\E[0;38;5;153m'" ]
check [ "$(tk 256 light)" = "$'\E[0;38;5;25m' $'\E[0;38;5;68m'" ]
check [ "$(tk 16 dark)" = "$'\E[0;36m' $'\E[0;96m'" ]
check [ "$(tk none dark)" = "$'\E[0m' $'\E[0m'" ]
# Большие числа (REVIEW-7 п.1): справа на sh-e и на 46 не режутся «…» и не
# слипаются с портом; от 100 000 — коротко («125 тыс.», «1,2 млн»; en «125k»,
# «1.2M»), до того — точно. Модель — фикстура с 5–7-значными числами.
for lg in ru en; do
    sed -e 's/^per|24h|2105|52|17|31|21$/per|24h|2105|52|17|125152|24985/' -e 's/^pt|24h|2443\/tcp|160|/pt|24h|3389\/tcp|36846|/' \
        -e 's/^per|30d|46210|640|388|410|230$/per|30d|46210|640|388|125152|24985/' -e 's/^pt|30d|2443\/tcp|3512|/pt|30d|3389\/tcp|36846|/' \
        -e 's/^per|all|169350|2140|/per|all|169350|1234567|/' -e 's/^pt|all|22\/tcp|56638|/pt|all|22\/tcp|1234567|/' \
        "$T/shfix-$lg.txt" > "$SHX/big-$lg.txt"
done
shb() { shp "$1" "$2" "$SHX/big-$1.txt" "UI_SHV=$3; UI_SHR=-1; ui_scr_shstats"; }
nocut() { ! grep -qE '[0-9]…|[0-9] …|/(tcp|udp)[0-9]' <<<"$1"; }
for v in 0 2; do
    o=$(shb ru 80 $v); check grep -qE 'новые +125 тыс\.' <<<"$o"; check grep -qE 'повторные +24 985' <<<"$o"
    check grep -qE '3389/tcp +36 846 MTProxy' <<<"$o"; check nocut "$o"
    o=$(shb en 80 $v); check grep -qE 'new +125k' <<<"$o"; check grep -qE 'repeat +24,985' <<<"$o"
    check grep -qE '3389/tcp +36,846 MTProxy' <<<"$o"; check nocut "$o"
done
o=$(shb ru 80 3); check grep -qE 'всего +1,2 млн' <<<"$o"; check grep -qE '22/tcp +1,2 млн SSH' <<<"$o"; check nocut "$o"
o=$(shb en 80 3); check grep -qE 'total +1.2M' <<<"$o"; check grep -qE '22/tcp +1.2M SSH' <<<"$o"; check nocut "$o"
o=$(shb ru 46 3); check grep -qE '^ 22/tcp +1,2 млн SSH' <<<"$o"; check grep -qE '^ 443/tcp +41 191 VLESS' <<<"$o"; check nocut "$o"
o=$(shb en 46 3); check grep -qE '^ 22/tcp +1.2M SSH' <<<"$o"; check nocut "$o"
# Строка графика на 80 (вход/выход выбранного дня): до 9 знаков — точно,
# длиннее — коротко; без «…».
o=$(shp ru 80 "" 'UI_SHV=1; UI_SHR=-1; SM_DI[29]=1234567; SM_DO[29]=1234567890; ui_scr_shstats')
check grep -qE 'вход +1 234 567 попыток' <<<"$o"; check grep -qE 'выход +1,2 млрд к ВК' <<<"$o"; check nocut "$o"
# ui_nfs и _sh_num: границы и «не обрезать».
out=$(GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c '. "$1"; for LANG_CODE in ru en; do
    for n in 99999 100000 999999 1000000 1234567 12345678 999999999 1234567890 98765432109; do ui_nfs $n; printf "%s|" "$UI_P"; done
    _sh_num 1 1234567890 5; printf "%s|" "$UI_P"; _sh_num 1 123456 7; printf "%s|" "$UI_P"; _sh_num 0 5 3; printf "%s\n" "$UI_P"; done' _ "$SCRIPT")
check [ "$out" = "$(printf '%s\n' '99 999|100 тыс.|999 тыс.|1,0 млн|1,2 млн|12 млн|999 млн|1,2 млрд|98 млрд|1,2 млрд|123 456|  —' \
    '99,999|100k|999k|1.0M|1.2M|12M|999M|1.2B|98B| 1.2B|123,456|  —')" ]
# Клавиши экранов: Home/End/PgUp/PgDn во всех видах, ←→ — Enter/Esc со
# стрелкой в UI_ARROW; Ctrl+стрелка — по-прежнему «other».
for s in '\033[H' '\033OH' '\033[1~' '\033[7~'; do check [ "$(rk "$s")" = home ]; done
for s in '\033[F' '\033OF' '\033[4~' '\033[8~'; do check [ "$(rk "$s")" = end ]; done
check [ "$(rk '\033[5~')" = pgup ]; check [ "$(rk '\033[6~')" = pgdn ]
check [ "$(rk '\033[1;5A')" = other ]; check [ "$(rk '\033[3~')" = other ]
rka() { printf '%b' "$1" | GOINST_SOURCE_ONLY=1 GOINST_LANG=ru bash -c ". '$SCRIPT'; ui_locale_fix; UI_INPUT=0; ui_read_key; printf '%s/%s' \"\$UI_KEY\" \"\$UI_ARROW\""; }
check [ "$(rka '\033[C')" = enter/right ]; check [ "$(rka '\033[D')" = esc/left ]; check [ "$(rka '\033[A')" = up/ ]
# Без UTF-8 (GOINST_ASCII) экраны защиты в английском — сплошь ASCII:
# полосы, сетка, «×» всплеска и «№» топа заменены.
for c in "$SHFS; ui_scr_menu \$k" 'ui_scr_shield 0' 'UI_SHV=0; UI_SHR=-1; ui_scr_shstats' 'UI_SHV=3; UI_SHR=-1; ui_scr_shstats' \
         'UI_SHV=0; UI_SHT=0; ui_scr_shtop' 'UI_SHH=confirm; ui_scr_shset'; do
    for w in 80 46; do
        o=$(T="$T" SHFIX="$T/shfix-en.txt" GOINST_SOURCE_ONLY=1 GOINST_LANG=en GOINST_ASCII=1 GOINST_COLOR=none GOINST_UI_COLS=$w GOINST_UI_LINES=24 \
            bash -c ". '$SCRIPT'; . '$T/ui_example.sh'; ui_detect; ui_example; ui_example_shield; $c; ui_compose; ui_emit" 2>&1)
        if [ -n "$o" ] && [ -z "$(printf '%s' "$o" | LC_ALL=C tr -d '\000-\177')" ]; then pass; else fail "ASCII $w: $c" 'только ASCII'; fi
    done
done
# Защита «стоит и работает» — заглушка поверх настоящего shield_state.
SHST='eval "$(declare -f shield_state | sed "1s/shield_state/_sh_state0/")"
    shield_state() { _sh_state0 "$@"; SHS_ST=ok; SHS_SCAN=1; SHS_VK=1; SHS_DATE=03.11; SHS_NEX=3; _shield_text; }'
# Нумерованное меню «Защиты» — те же пункты и тем же порядком, что в «Аркаде».
out=$(sh_run "$SHST"'
    menu_items_shield >/dev/null 2>&1
    for x in "${MENU_ITEMS[@]}"; do IFS="|" read -r k l _ <<<"$x"; [ "$k" = - ] || printf "%s %s\n" "$k" "$l"; done; echo ==
    shield_items; for i in "${!SHI_KEY[@]}"; do printf "%s %s\n" "${SHI_KEY[i]}" "${SHI_LABEL[i]}"; done')
check [ "$(sed '/^==$/,$d' <<<"$out")" = "$(sed '1,/^==$/d' <<<"$out")" ]
check grep -qx '6 Статистика' <<<"$out"; check grep -qx '8 Настройки статистики' <<<"$out"; check grep -qx '9 Удалить защиту' <<<"$out"
# Ходьба по экранам: защита стоит (заглушка состояния), модель — фикстура.
SHNAV="$SHST"'
    export GOINST_SHIELD_UIMODEL="$SHFIXNAV"
    shield_probs() { SHIELD_PROBS=(); }
    shield_stats_reset() { act STATSRESET; return 0; }'
export SHFIXNAV="$T/shfix-ru.txt"
# Период: 1–4 и ←→ на статистике, 1–4 на топе; строка ↑↓; топ листается
# PgDn (15 строк в 80 колонок), End, Home; 0 — назад по цепочке.
shtabs() { plain < "$NAV/out" | grep -E '^  ═ 1 (●|○) 24 часа ' | grep -oE '[1-4] ● ' | cut -c1 | uniq | tr -d '\n'; }
NAVSTUB="$SHNAV" nav s 6 2 '\033[C' '\033[C' '\033[D' '\033[A' 5 4 '\033[6~' '\033[F' '\033[H' 0 0 0 q
check [ "$(navtr0)" = "s menu|6 shield|2 shstats|right shstats|right shstats|left shstats|up shstats|5 shstats|4 shtop|pgdn shtop|end shtop|home shtop|0 shtop|0 shstats|0 shield|q menu" ]
check [ "$(shtabs)" = 123434 ]
check grep -q '^▸ 16 AS' <(plain < "$NAV/out"); check grep -q '^▸ 30 AS' <(plain < "$NAV/out")
check [ "$(plain < "$NAV/out" | grep -c '^▸  1 AS')" -ge 2 ]
check grep -qx 'EXIT 0' "$NAV/act"; check neg grep -q STATSRESET "$NAV/act"
# Обнуление — только «1 Да» на вопросе; Enter там — «Нет», как и 2, 0, Esc.
# Enter сразу после смены экрана глотается (0,4 с) — перед ним пауза.
NAVSTUB="$SHNAV" nav s 8 @0.5 '\n' @0.5 '\n' q
check [ "$(navtr0)" = "s menu|8 shield|enter shset|enter shset|q shset" ]
check grep -q 'Обнулить статистику? Счётчики входа и выхода' <(plain < "$NAV/out"); check neg grep -q STATSRESET "$NAV/act"
NAVSTUB="$SHNAV" nav s 8 1 2 1 0 1 '\033' q
check [ "$(navtr0)" = "s menu|8 shield|1 shset|2 shset|1 shset|0 shset|1 shset|esc shset|q shset" ]
check neg grep -q STATSRESET "$NAV/act"; check grep -q 'Не обнулено\.' <(plain < "$NAV/out")
# Две «1» подряд (REVIEW-7 п.2) не обнуляют: «1» в первые 0,4 с после вопроса
# глотается, как Enter. После паузы «1» — «Да».
NAVSTUB="$SHNAV" nav s 8 1 1 q
check [ "$(navtr0)" = "s menu|8 shield|1 shset|1 shset|q shset" ]
check neg grep -q STATSRESET "$NAV/act"; check neg grep -q 'Статистика обнулена' <(plain < "$NAV/out")
NAVSTUB="$SHNAV" nav s 8 1 @0.6 1 @0.5 q
check grep -qx STATSRESET "$NAV/act"; check grep -q '✓ Статистика обнулена. Собирается заново с' <(plain < "$NAV/out")
# Защита занята (REVIEW-7 п.3): не ждать, сказать словами, вопрос закрыть.
t0=$SECONDS
NAVSTUB="$SHNAV"'
    _shield_lock() { return 1; }' nav s 8 1 @0.6 1 @0.5 q
check [ $(( SECONDS - t0 )) -lt 8 ]; check neg grep -q STATSRESET "$NAV/act"
check grep -q 'Защита занята другой операцией — повторите через минуту' <(plain < "$NAV/out")
check [ "$(navtr0)" = "s menu|8 shield|1 shset|1 shset|q shset" ]
# «Назад» в настройках (↓ Enter) — в меню «Защита», без вопроса.
NAVSTUB="$SHNAV" nav s 8 '\033[B' @0.5 '\n' q
check [ "$(navtr0)" = "s menu|8 shield|down shset|enter shset|q shield" ]
# Главное меню, 80 колонок, курсор на s: ←→ листают день в карточке.
NAVSTUB="$SHNAV" nav s 0 '\033[D' '\033[D' '\033[C' q
check [ "$(navtr0)" = "s menu|0 shield|left menu|left menu|right menu|q menu" ]
check grep -q '▸ вс 01.11: вход' <(plain < "$NAV/out"); check grep -q '▸ пн 02.11: вход' <(plain < "$NAV/out")
# В 46 колонок графика нет: → — как прежде Enter (открыть «Защиту»).
NAVCOLS=46 NAVSTUB="$SHNAV" nav s 0 @0.5 '\033[C' 0 q
check [ "$(navtr0)" = "s menu|0 shield|enter menu|0 shield|q menu" ]
# Модель для экранов после обнуления: в meta нет lvl — уровень «-», а не 0
# («Статистики не будет» было бы неправдой: nft умеет, чисел ещё нет).
mkdir -p "$SF/d/str"; printf 'started=%s\nbase=1\n' "$(( T0 + 3600 ))" > "$SF/d/str/meta"
check grep -q '^g|-|03.11.2026|' <<<"$(TZ=UTC sh_run '_shield_spy ui "$SFD/str" "$SFD/info" '"$(( T0 + 4000 ))")"
printf 'lvl=0\n' >> "$SF/d/str/meta"
check grep -q '^g|0|03.11.2026|' <<<"$(TZ=UTC sh_run '_shield_spy ui "$SFD/str" "$SFD/info" '"$(( T0 + 4000 ))")"
# Модель экранов из настоящих снимков (REVIEW-7 п.6): числа `_shield_spy ui`
# сходятся со снимками, ui_sh_model раскладывает их по SM_*. Снимки — ровно
# на границе часа (суток): по 100 попыток, в пиковый час (день) ещё +97
# (×1,97 — всплеска нет, и × не округляется в 2,0) или +100 (×2,0 — всплеск).
# Адреса: три — весь срок (за сутки повторные), 45.0.9.1 — первые 3 часа,
# 45.0.7.k — с 20-го часа (за сутки новые, 10).
shu() {  # shu <каталог> <шаг, с> <снимков> <пиковый №> <добавка>
    local k i4=0 s4 b=$T0
    [ "$2" = 86400 ] && b=$(( T0 - 36000 ))                  # T0 — 10:00 UTC
    rm -rf "$SF/d/$1" "$SF/d/$1.n"; mkdir -p "$SF/d/$1.n"
    for ((k = 0; k < $3; k++)); do
        i4=$(( i4 + 100 + (k == $4 ? $5 : 0) ))
        s4="45.0.4.1:5:100,45.0.4.2:5:100,45.0.4.3:5:100"
        [ "$k" -le 2 ] && s4+=",45.0.9.1:2:100"; [ "$k" -ge 20 ] && s4+=",45.0.7.$k:3:100"
        python3 -I "$SF/nfta.py" h=23 in4=$i4 in6=0 out_fwd=0 out_srv=0 seen4="$s4" > "$SF/d/$1.n/$k"
    done
    TZ=UTC sh_run ': > "$SFD/'"$1"'.own"; for ((k = 0; k < '"$3"'; k++)); do
        _shield_spy snap "$SFD/'"$1"'" "$SFD/'"$1"'.n/$k" "$SFD/'"$1"'.own" b1 $(( '"$b"' + (k + 1) * '"$2"' )) || echo "rc=$?"; done'
}
shui() { TZ=UTC sh_run '_shield_spy ui "$SFD/'"$1"'" "$SFD/'"$1"'.own" '"$2"; }
shsum() { awk -F'|' -v k="$1" -v p="$2" -v c="$3" '$1 == k && (p == "" || $2 == p) { s += $c } END { print s + 0 }' <<<"$4"; }
check [ -z "$(shu stu 3600 30 26 97)" ]
o=$(shui stu $(( T0 + 30 * 3600 + 900 )))
check [ "$(grep -c '^h|' <<<"$o") $(grep -c '^d|' <<<"$o")" = "24 30" ]
check [ "$(shsum h '' 3 "$o")" = "$(shsum per 24h 3 "$o")" ]   # часы = сутки
check [ "$(shsum d '' 5 "$o")" = "$(shsum per 30d 3 "$o")" ]   # дни = 30 дней
check [ "$(shsum per all 3 "$o")" = "$(sget tin "$SF/d/stu/summary")" ]
check grep -qx 'per|24h|2397|13|0|10|3' <<<"$o"   # 23 часа по 100 + 97; новых 10, повторных 3
check grep -qx 'per|all|3097|14|0|-|-' <<<"$o"
check [ "$(TZ=UTC sh_run '_shield_spy report "$SFD/stu" 24h 80 ru "$SFD/stu.own" '"$(( T0 + 30 * 3600 + 900 ))" |
    awk '$1 == "вход" && $2 == "сутки" { print $3, $4 }')" = "2397 13" ]           # отчёт sh-f — те же числа
check grep -qx 'pk|24h|197|19|0|12' <<<"$o"
check [ -z "$(shu stv 3600 30 26 100)" ]
check grep -qx 'pk|24h|200|20|1|12' <<<"$(shui stv $(( T0 + 30 * 3600 + 900 )))"
check [ -z "$(shu stw 86400 8 4 97)" ]
o=$(shui stw $(( T0 - 36000 + 8 * 86400 + 900 )))
check grep -qx 'pk|7d|197|19|0|07|11|6' <<<"$o"; check grep -qx 'pk|30d|197|19|0|07|11|6' <<<"$o"
check [ -z "$(shu stx 86400 8 4 100)" ]
o=$(shui stx $(( T0 - 36000 + 8 * 86400 + 900 )))
check grep -qx 'pk|7d|200|20|1|07|11|6' <<<"$o"; check grep -qx 'pk|30d|200|20|1|07|11|6' <<<"$o"
# Связка cmd_ui → ui_sh_model (без фикстуры модели) и кеш (п.5): тот же
# час, язык и файлы stats/ — python не зовётся; файл изменился, час или
# язык сменились — зовётся снова.
SHU='_shield_has_stats() { SHIELD_STATS="$SFD/stu"; [ -f "$SHIELD_STATS/meta" ]; }
    _shield_stats_info() { : > "$1"; }; _shield_now() { echo "$NOW"; }
    eval "$(declare -f _shield_spy | sed "1s/_shield_spy/_spy0/")"
    _shield_spy() { echo >> "$SFD/spyn"; _spy0 "$@"; }; : > "$SFD/spyn"; NOW='"$(( T0 + 30 * 3600 + 900 ))"'
    spyn() { printf "%s " "$(wc -l < "$SFD/spyn" | tr -d " ")"; }'
o=$(TZ=UTC sh_run "$SHU"'
    ui_sh_model; echo "$SM_OK $SM_LV ${#SM_HH[@]} ${#SM_DD[@]} ${SM_IN[0]} ${SM_IN[3]} ${SM_NW[0]} ${SM_RP[0]} ${SM_PKV[0]} ${SM_PKX[0]} ${SM_PKS[0]} ${SM_HI[19]} ${SM_PKA[0]}"
    ui_sh_model; spyn; touch -t 200001010000 "$SHIELD_STATS/summary"; ui_sh_model; spyn
    NOW=$(( NOW + 3600 )); ui_sh_model; spyn; LANG_CODE=en; ui_sh_model; spyn; ui_sh_model; spyn; echo "$SM_OK"')
check [ "$o" = "$(printf '%s\n' '1 2 24 30 2397 3097 10 3 197 19 0 197 12' '1 2 3 4 4 1')" ]
# Временный файл ui_sh_model уходит и при Ctrl+C — той же ловушкой EXIT.
sh_run ': > "$SFD/shtmp"; UI_SHTMP="$SFD/shtmp"; ui_crash_exit' >/dev/null; check [ ! -e "$SF/d/shtmp" ]
echo "── самоустановка из канала: ветка этой версии"
SELFD="$SF/self"; rm -rf "$SELFD"; mkdir -p "$SELFD"
S1=1111111111111111111111111111111111111111; S2=2222222222222222222222222222222222222222
S3=3333333333333333333333333333333333333333; S4=4444444444444444444444444444444444444444
S5=5555555555555555555555555555555555555555; SD=dddddddddddddddddddddddddddddddddddddddd
sed -e "s/^GOINST_VERSION=\"$GIV\"\$/GOINST_VERSION=\"1.0.12\"/" -e 's/^shield_cli()/shield_cli_none()/' "$SCRIPT" > "$SELFD/raw.$S1"
sed "s/^GOINST_VERSION=\"$GIV\"\$/GOINST_VERSION=\"1.1.5\"/" "$SCRIPT" > "$SELFD/raw.$S2"
cp "$SCRIPT" "$SELFD/raw.$S3"; cp "$SCRIPT" "$SELFD/raw.$SD"
sed "s/^GOINST_VERSION=\"$GIV\"\$/GOINST_VERSION=\"1.1.9\"/" "$SCRIPT" > "$SELFD/raw.$S5"
check grep -qx 'GOINST_VERSION="1.0.12"' "$SELFD/raw.$S1"
br() { printf '[\n'; local n s c=""; while [ $# -gt 0 ]; do n="$1"; s="$2"; shift 2
    printf '%s  {\n    "name": "%s",\n    "commit": {\n      "sha": "%s",\n      "url": "https://api.github.com/repos/duboshin52/goInstaller/commits/%s"\n    },\n    "protected": false\n  }' "$c" "$n" "$s" "$s"; c=$',\n'; done; printf '\n]\n'; }
br 'bad;name' "$SD" dev "$S2" gh-pages "$S4" main "$S1" test-shield "$S3" > "$SELFD/branches.json"
br dev "$S2" main "$S1" test-shield "$S5" > "$SELFD/branches2.json"
printf '%s' "$S1" > "$SELFD/sha.main"; printf '%s' "$S2" > "$SELFD/sha.dev"
cat > "$SELFD/hook.sh" <<'HOOK'
_a=("$@"); _o="" _d="" _w="" _r="" _u="" _f=""
while [ $# -gt 0 ]; do
    case "$1" in -o) _o="$2"; shift ;; -D) _d="$2"; shift ;; -w) _w="$2"; shift ;; -r) _r="$2"; shift ;; -H|--max-time|--config|-K) shift ;; http*) _u="$1" ;; esac
    shift
done
set -- "${_a[@]}"
case "$_u" in https://api.github.com/repos/duboshin52/goInstaller/*|https://raw.githubusercontent.com/duboshin52/goInstaller/*) ;; *) return 0 ;; esac
[ -n "$_d" ] && : > "$_d"
echo "${_r:+range }$_u" >> "$SELFD/calls"
[ -n "${SELF_DOWN:-}" ] && { printf '%s' "${_w:+000}"; exit 7; }
case "${SELF_RAW_DOWN:-}$_u" in 1https://raw.*) printf '%s' "${_w:+000}"; exit 7 ;; esac
case "$_u" in https://raw.*/"${SELF_RAW_5XX:-none}"/*) printf '%s' "${_w:+503}"; exit 22 ;; esac
case "${SELF_LIST_401:-}$_u" in 1https://api.github.com/*/branches*) printf '%s' "${_w:+401}"; exit 22 ;; esac
case "$_u" in
    "https://api.github.com/repos/duboshin52/goInstaller/branches?per_page=100") _f="$SELFD/${SELF_LIST:-branches.json}" ;;
    https://api.github.com/repos/duboshin52/goInstaller/commits/*) _f="$SELFD/sha.${_u##*/}" ;;
    https://raw.githubusercontent.com/duboshin52/goInstaller/*/go-installer.sh)
        _f="${_u#https://raw.githubusercontent.com/duboshin52/goInstaller/}"; _f="$SELFD/raw.${_f%/go-installer.sh}" ;;
esac
if [ -n "$_f" ] && [ -f "$_f" ]; then
    if [ -n "$_r" ]; then head -c 16384 "$_f" > "$_o"; else cp "$_f" "$_o"; fi
    printf '%s' "${_w:+200}"; exit 0
fi
printf '%s' "${_w:+404}"; exit 22
HOOK
# si_run — как sh_run, но $0 не файл (как у `bash <(curl …)`; SI0=<файл> —
# запуск из файла) и goinstall — в $SF/d/bin.
si_run() {
    ( export PATH="$SF/bin:$PATH" SFD="$SF/d" SFS="${SFS:-$SF/src}" GOINST_SOURCE_ONLY=1 GOINST_LANG=ru GOINST_TEST=1
      export GOINST_GH_RETRY_DELAY=0 GOINST_SHIELD_DIR="$SF/dir" GOINST_SHIELD_RUN="$SF/d/boot" GOINST_SYSTEMD_DIR="$SF/units"
      export GOINST_SHIELD_CG="$SF/d/cg" GOINST_SHIELD_NFT="$SF/bin/nft" GOINST_SHIELD_ADDRS="45.0.5.7 2a00:1::5" GOINST_SS_FIXTURE="$SF/ss" GOINST_FS_ROOT="$SF/fs"
      export GOINST_BIN="$SF/d/bin/goinstall" GOINST_BIN_ALIAS="$SF/d/bin/go-installer" GOINST_DIR="$SF/gd" GH_TOKEN=ghp_shieldtesttoken0000
      export SELFD SCRIPT CURL_HOOK='. "$SELFD/hook.sh"'
      bash -c '. "$SCRIPT"; token_load; GOINST_SELF_PATH=$0; eval "$1"' "${SI0:-/dev/fd/63}" "$1" ) 2>&1 | sed $'s/\033\\[[0-9;]*m//g'
}
si_reset() { sh_reset; mkdir -p "$SF/d/bin"; rm -f "$SELFD/calls"; }
GI="$SF/d/bin/goinstall"
# Разбор списка веток: с отступами и в одну строку.
check [ "$(si_run '_self_branch_pairs < "$SELFD/branches2.json"')" = "$(printf 'dev %s\nmain %s\ntest-shield %s' "$S2" "$S1" "$S5")" ]
check [ "$(si_run 'x='"$S1"'; _self_branch_pairs <<<"[{\"name\":\"a\",\"commit\":{\"sha\":\"$x\",\"url\":\"u\"},\"protected\":false},{\"name\":\"b/c\",\"commit\":{\"sha\":\"$x\"}}]"')" = "$(printf 'a %s\nb/c %s' "$S1" "$S1")" ]
check [ "$(si_run 'for r in main test-shield b/c "bad;name" -x ../x a//b /a a/ "a b" ""; do _self_ref_ok "$r" && printf "%s," "$r"; done')" = 'main,test-shield,b/c,' ]
# 1) goinstall = main 1.0.12, запуск test-shield этой версии из канала →
#    goinstall становится этой версией из test-shield, ветка запомнена,
#    защита ставится.
si_reset; cp "$SELFD/raw.$S1" "$GI"; chmod 755 "$GI"
out=$(si_run 'self_install; echo "hit=$SELF_REF_HIT"; shield_install >/dev/null 2>&1; echo "shield=$?"; self_refs | tr "\n" " "')
check has "$out" "Команда goinstall установлена: версия ${GIV} из ветки test-shield."
check has "$out" 'hit=test-shield'; check has "$out" 'shield=0'
check cmp -s "$SCRIPT" "$GI"; check [ -x "$GI" ]; check [ -L "$SF/d/bin/go-installer" ]
check [ "$(cat "$SF/gd/.self-ref")" = test-shield ]
check has "$out" 'main test-shield'
check cmp -s "$SCRIPT" "$SF/dir/runner.sh"; check [ -e "$SF/units/goinstall-shield.timer" ]
# К API — один запрос (список веток); ветка с чужими знаками не опрошена,
# хеши — из списка, версии — по началу файла, целиком — только найденная.
check [ "$(grep -c '^https://api.github.com/' "$SELFD/calls")" = 1 ]
check [ -z "$(grep -n 'commits/' "$SELFD/calls")" ]
check [ -z "$(grep -n "$SD" "$SELFD/calls")" ]
check grep -qx "range https://raw.githubusercontent.com/duboshin52/goInstaller/$S1/go-installer.sh" "$SELFD/calls"
check [ "$(grep -c '^https://raw.githubusercontent.com/duboshin52/goInstaller/' "$SELFD/calls")" = 1 ]
check grep -qx "https://raw.githubusercontent.com/duboshin52/goInstaller/$S3/go-installer.sh" "$SELFD/calls"
check [ -z "$(ls "$SF/d/bin" | grep -vx 'goinstall\|go-installer')" ]  # временных goinstall.XXXXXX не осталось
# 1б) REVIEW-4 №1: на сервере прежняя тестовая ветка — goinstall = test-shield
#     1.2.0 (bdb1d52, другое содержимое). У нового скрипта обязана быть другая
#     версия: с той же self_install выходит («уже эта версия»), и таймер защиты
#     получает старый код. OLDV — версия origin/test-shield до этой правки.
OLDV=1.2.0
si_reset; { sed "s/^GOINST_VERSION=\"$GIV\"\$/GOINST_VERSION=\"$OLDV\"/" "$SCRIPT"; echo '# прежнее содержимое'; } > "$GI"; chmod 755 "$GI"
check grep -qx "GOINST_VERSION=\"$OLDV\"" "$GI"
out=$(si_run 'self_install; shield_install >/dev/null 2>&1; echo "shield=$?"')
check has "$out" "версия ${GIV} из ветки test-shield"; check has "$out" 'shield=0'
check cmp -s "$SCRIPT" "$GI"; check cmp -s "$SCRIPT" "$SF/dir/runner.sh"
# 2) goinstall уже этой версии — без изменений и без сети.
rm -f "$SELFD/calls"; touch -t 202601010000 "$GI"
out=$(si_run 'self_install; echo "rc=$?"')
check [ "$out" = 'rc=0' ]; check [ ! -e "$SELFD/calls" ]; check cmp -s "$SCRIPT" "$GI"
check [ -z "$(find "$GI" -newer "$SELFD/hook.sh")" ]
# 3) goinstall нет — ставится версия найденной ветки; хеши веток уже в кеше
#    «.sha» — по началу файла ничего не качается.
rm -f "$GI" "$SF/d/bin/go-installer" "$SELFD/calls"; rm -rf "$SF/dir" "$SF/units"
out=$(si_run 'self_install')
check has "$out" "версия ${GIV} из ветки test-shield"; check cmp -s "$SCRIPT" "$GI"
check [ -z "$(grep -n '^range ' "$SELFD/calls")" ]
check [ "$(wc -l < "$SELFD/calls" | tr -d ' ')" = 2 ]
# 4) Ветки этой версии нет, goinstall = main — не заменяем, говорим словами;
#    защита отказывает с советом «из файла».
si_reset; cp "$SELFD/raw.$S1" "$GI"; chmod 755 "$GI"
out=$(SELF_LIST=branches2.json si_run 'self_install; echo "rc=$? hit=$SELF_REF_HIT"; shield_install; echo "shield=$?"')
check has "$out" "Команда goinstall оставлена прежней (версия 1.0.12): ни в одной ветке duboshin52/goInstaller нет версии ${GIV}. Другой версией её не заменяю. Чтобы goinstall стал версией ${GIV}, запустите скрипт из файла — той ветки, из которой запускали: curl -fsSL -H \"Authorization: token <ключ>\" -o go-installer.sh https://raw.githubusercontent.com/duboshin52/goInstaller/<ветка>/go-installer.sh && bash go-installer.sh"
check has "$out" 'rc=0 hit='; check has "$out" 'shield=1'
check hasnt "$out" 'bash go-installer.sh.'
check has "$out" "Таймеру защиты нечего запускать: нет файла скрипта версии ${GIV} (скрипт запущен не из файла, а goinstall другой версии). Чтобы поставить защиту, запустите скрипт из файла — той ветки"
check hasnt "$out" 'ghp_shieldtesttoken0000'
check cmp -s "$SELFD/raw.$S1" "$GI"; check [ ! -e "$SF/gd/.self-ref" ]; check [ ! -e "$SF/dir/settings" ]
check [ -z "$(grep -n -v '^range \|branches' "$SELFD/calls")" ]
# … список не получить (сеть) — «не опросить», goinstall тот же.
si_reset; cp "$SELFD/raw.$S1" "$GI"; chmod 755 "$GI"
out=$(SELF_DOWN=1 si_run 'self_install')
check has "$out" 'Команда goinstall оставлена прежней (версия 1.0.12): ветки duboshin52/goInstaller не опросить: GitHub не ответил (сеть).'
check cmp -s "$SELFD/raw.$S1" "$GI"
# REVIEW-4 №3: на мёртвой сети — строка поиска до ответа, каждая попытка на
#    экране и один круг повторов: goinstall нет — запасной main не качаем
#    (второй круг ожидания), а говорим, как быть.
si_reset
out=$(SELF_DOWN=1 si_run 'self_install')
check has "$out" "Ищу ветку duboshin52/goInstaller с версией ${GIV}…"
check has "$out" 'Список веток duboshin52/goInstaller: попытка 1 из 4 не удалась'
check has "$out" 'Список веток duboshin52/goInstaller: попытка 3 из 4 не удалась'
check has "$out" 'Команда goinstall не установлена: ветки duboshin52/goInstaller не опросить: GitHub не ответил (сеть). Чтобы она появилась, запустите скрипт из файла'
check [ "$(wc -l < "$SELFD/calls" | tr -d ' ')" = 4 ]; check [ ! -e "$GI" ]
check [ "$(grep -n 'Ищу ветку' <<<"$out" | cut -d: -f1)" -lt "$(grep -n 'попытка 1 из 4' <<<"$out" | cut -d: -f1)" ]
# REVIEW-4 №6: ключ не принят (401) — так и сказано, а не «сеть или лимит»;
#    ветки по одной не опрашиваются.
si_reset; cp "$SELFD/raw.$S1" "$GI"
out=$(SELF_LIST_401=1 si_run 'self_install')
check has "$out" 'Команда goinstall оставлена прежней (версия 1.0.12): ветки duboshin52/goInstaller не опросить: GitHub не принял ключ (ответ 401).'
check [ "$(wc -l < "$SELFD/calls" | tr -d ' ')" = 1 ]; check cmp -s "$SELFD/raw.$S1" "$GI"
# … 5xx на пробе ветки — «опрошены не все», а не «версии нет»; сбой не кешируется.
S9=9999999999999999999999999999999999999999
br main "$S1" t9 "$S9" > "$SELFD/branches6.json"
si_reset; cp "$SELFD/raw.$S1" "$GI"
out=$(SELF_LIST=branches6.json SELF_RAW_5XX=$S9 si_run 'self_install; printf "sha=%s\n" "$(_ver_cache_file "$SELF_ID" t9).sha"')
check has "$out" 'Команда goinstall оставлена прежней (версия 1.0.12): ветки duboshin52/goInstaller опрошены не все: GitHub ответил ошибкой.'
check hasnt "$out" 'нет версии'
check [ ! -e "$(sed -n 's/^sha=//p' <<<"$out")" ]
check [ "$(grep -c "/$S9/" "$SELFD/calls")" = 4 ]; check cmp -s "$SELFD/raw.$S1" "$GI"
# … список есть, а файлы не скачать (сеть пропала) — тоже «не опросить».
si_reset; cp "$SELFD/raw.$S1" "$GI"
check has "$(SELF_RAW_DOWN=1 si_run 'self_install')" 'ветки duboshin52/goInstaller не опросить'
check cmp -s "$SELFD/raw.$S1" "$GI"; check [ -z "$(ls "$SF/gd/versions" | grep '\.sha$')" ]
# … не больше SELF_FIND_MAX веток (по порядку: main, dev, …).
si_reset; cp "$SELFD/raw.$S1" "$GI"
GOINST_SELF_FIND_MAX=2 si_run 'self_install' >/dev/null
check [ "$(grep -c '^range ' "$SELFD/calls")" = 2 ]; check cmp -s "$SELFD/raw.$S1" "$GI"
# … списка нет (404) — свои ветки по хешу ref_sha; goinstall нет — как
#    раньше: GOINST_SELF_REF.
#    REVIEW-4 №2: запись .self-ref от прежней установки — стёрта: goinstall
#    теперь из GOINST_SELF_REF, обновления без ветки не уйдут на test-shield.
si_reset; mkdir -p "$SF/gd"; echo test-shield > "$SF/gd/.self-ref"
out=$(SELF_LIST=none si_run 'self_install; echo "hit=$SELF_REF_HIT"')
check has "$out" 'Команда goinstall установлена.'; check has "$out" 'hit='
check cmp -s "$SELFD/raw.$S1" "$GI"; check [ ! -e "$SF/gd/.self-ref" ]
check grep -q 'commits/main$' "$SELFD/calls"; check grep -q 'commits/dev$' "$SELFD/calls"
# REVIEW-4 №2: запуск из файла, а запись .self-ref от прежней установки из
#    канала — запись стёрта, обновление без ветки — из main/dev, а не test-shield.
si_reset; cp "$SELFD/raw.$S1" "$GI"; mkdir -p "$SF/gd"; echo test-shield > "$SF/gd/.self-ref"
out=$(SI0="$SCRIPT" si_run 'self_install; ver_cache_get() { case "$2" in test-shield) printf 9.9.9 ;; main) printf 1.0.12 ;; *) return 1 ;; esac; }; echo "best=$(self_best)"')
check has "$out" 'Команда goinstall установлена.'; check has "$out" 'best=main 1.0.12'
check cmp -s "$SCRIPT" "$GI"; check [ ! -e "$SF/gd/.self-ref" ]
# REVIEW-4 №4: «скрипта нет» (404) — не навсегда: raw только что запушенного
#    коммита бывает 404. В пределах GOINST_SELF_NONE_TTL — из кеша, позже — снова.
S6=6666666666666666666666666666666666666666
br main "$S1" fresh "$S6" > "$SELFD/branches3.json"
si_reset; cp "$SELFD/raw.$S1" "$GI"
out=$(SELF_LIST=branches3.json si_run 'self_install; printf "sha=%s\n" "$(_ver_cache_file "$SELF_ID" fresh).sha"')
check has "$out" "ни в одной ветке duboshin52/goInstaller нет версии ${GIV}"
shaf=$(sed -n 's/^sha=//p' <<<"$out"); check [ "$(cat "$shaf")" = "$S6 " ]
cp "$SCRIPT" "$SELFD/raw.$S6"; rm -f "$SELFD/calls"
check has "$(SELF_LIST=branches3.json si_run 'self_install')" "нет версии ${GIV}"
check [ -z "$(grep -n "$S6" "$SELFD/calls")" ]; check cmp -s "$SELFD/raw.$S1" "$GI"
touch -t 202601010000 "$shaf"
check has "$(SELF_LIST=branches3.json si_run 'self_install')" "версия ${GIV} из ветки fresh."
check cmp -s "$SCRIPT" "$GI"; check [ "$(cat "$shaf")" = "$S6 $GIV" ]
rm -f "$SELFD/raw.$S6"
# REVIEW-4 №5: эта версия в нескольких ветках с разным содержимым — ни одну
#    не берём, называем все и как быть; goinstall нет — тоже не ставим (таймер
#    защиты получил бы чужой код). Содержимое то же — берётся первая.
S7=7777777777777777777777777777777777777777; S8=8888888888888888888888888888888888888888
{ cat "$SCRIPT"; echo '# другая сборка той же версии'; } > "$SELFD/raw.$S7"; cp "$SCRIPT" "$SELFD/raw.$S8"
br main "$S1" a1 "$S3" a2 "$S7" > "$SELFD/branches4.json"
br main "$S1" a1 "$S3" a3 "$S8" > "$SELFD/branches5.json"
si_reset; cp "$SELFD/raw.$S1" "$GI"
out=$(SELF_LIST=branches4.json si_run 'self_install; echo "hit=$SELF_REF_HIT many=$SELF_REF_MANY"; shield_install; echo "shield=$?"')
check has "$out" "Команда goinstall оставлена прежней (версия 1.0.12): версия ${GIV} есть в нескольких ветках duboshin52/goInstaller с разным содержимым (a1, a2) — из какой запускали, не узнать. Другой версией её не заменяю. Чтобы goinstall стал версией ${GIV}, обновите команду из нужной ветки (a1, a2) и запустите goinstall снова: goinstall --self-update <ветка>"
check has "$out" 'hit= many=a1 a2'; check has "$out" 'shield=1'
check has "$out" 'Чтобы поставить защиту, обновите команду из нужной ветки (a1, a2)'
check cmp -s "$SELFD/raw.$S1" "$GI"; check [ ! -e "$SF/gd/.self-ref" ]
rm -f "$GI" "$SF/d/bin/go-installer"
out=$(SELF_LIST=branches4.json si_run 'self_install')
check has "$out" "Команда goinstall не установлена: версия ${GIV} есть в нескольких ветках duboshin52/goInstaller с разным содержимым (a1, a2)"
check has "$out" 'Чтобы она появилась, запустите скрипт из файла'
check [ ! -e "$GI" ]
si_reset; cp "$SELFD/raw.$S1" "$GI"
check has "$(SELF_LIST=branches5.json si_run 'self_install')" "версия ${GIV} из ветки a1."
check cmp -s "$SCRIPT" "$GI"; check [ "$(cat "$SF/gd/.self-ref")" = a1 ]
# Ветка известна, а goinstall не той версии — точная команда.
si_reset; cp "$SELFD/raw.$S1" "$GI"
out=$(si_run 'SELF_REF_HIT=test-shield; shield_install; echo "rc=$?"; shield_runner_put; echo "$SHIELD_ERR"')
check has "$out" 'Чтобы поставить защиту, запустите goinstall снова, обновив команду: goinstall --self-update test-shield'
check hasnt "$out" 'goinstall --self-update test-shield.'
check has "$out" "нет файла скрипта версии ${GIV} для таймера: запустите goinstall снова, обновив команду: goinstall --self-update test-shield"
# goinstall уже этой версии (без защиты) — команда не поможет, совет «из файла».
cp "$SF/goinstall" "$GI"
check has "$(si_run 'SELF_REF_HIT=test-shield; shield_install')" 'запустите скрипт из файла'
# Запомненная ветка: main и dev стираются; ветки больше нет — забыта.
si_reset
si_run 'self_ref_remember test-shield' >/dev/null; check [ "$(cat "$SF/gd/.self-ref")" = test-shield ]
si_run 'self_ref_remember "bad;x"' >/dev/null; check [ "$(cat "$SF/gd/.self-ref")" = test-shield ]
si_run 'self_ref_remember main' >/dev/null; check [ ! -e "$SF/gd/.self-ref" ]
echo test-shield > "$SF/gd/.self-ref"
printf 'duboshin52/goInstaller=main dev test-shield\n' > "$SELFD/fx"
GOINST_BRANCHES_FIXTURE="$SELFD/fx" si_run 'self_fetch_versions' >/dev/null
check [ "$(cat "$SF/gd/.self-ref")" = test-shield ]
rm -rf "$SF/gd/versions"; printf 'duboshin52/goInstaller=main dev\n' > "$SELFD/fx"
GOINST_BRANCHES_FIXTURE="$SELFD/fx" si_run 'self_fetch_versions' >/dev/null
check [ ! -e "$SF/gd/.self-ref" ]
# self_update: ветка запоминается (и стирается на main) — делом, а не грепом
#    (REVIEW-4 №6).
si_reset; cp "$SELFD/raw.$S1" "$GI"; printf '%s' "$S3" > "$SELFD/sha.test-shield"
out=$(si_run 'ensure_token() { :; }; self_fetch_versions() { :; }
    self_update test-shield >/dev/null 2>&1; echo "rc=$? $(cat "$SELF_REF_FILE")"; cmp -s "$SCRIPT" "$GOINST_BIN" && echo same
    self_update main >/dev/null 2>&1; echo "rc=$?"; [ -e "$SELF_REF_FILE" ] || echo gone')
check [ "$out" = "$(printf 'rc=0 test-shield\nsame\nrc=0\ngone')" ]
check cmp -s "$SELFD/raw.$S1" "$GI"; rm -f "$SELFD/sha.test-shield"

selfref() { mkdir -p "$SF/gd"; echo "$1" > "$SF/gd/.self-ref"; }  # si_reset стирает gd
# К5-11 (стенд 03.11): две сборки с одним номером. Запуск из файла ставит файл
#    в goinstall, как другой номер; копия таймера идёт за goinstall — они не
#    расходятся, и «пинг-понга» копии нет.
si_reset; { cat "$SCRIPT"; echo '# прежняя сборка того же номера'; } > "$GI"; chmod 755 "$GI"
si_run 'shield_install' >/dev/null 2>&1
check cmp -s "$GI" "$SF/dir/runner.sh"; check neg cmp -s "$SCRIPT" "$SF/dir/runner.sh"
nlog() { grep -c 'копия скрипта для таймера' "$SF/dir/shield.log"; }
n0=$(nlog); selfref test-shield
out=$(SI0="$SCRIPT" si_run 'GOINST_SHIELD_TEST=1; self_install; shield_offer; echo "rc=$?"')
check has "$out" "Команда goinstall заменена запущенным файлом: та же версия ${GIV}, другая сборка."
check has "$out" 'rc=0'
# REVIEW-8 №2: тот же номер — та же ветка, запись .self-ref не стирается.
check [ "$(cat "$SF/gd/.self-ref")" = test-shield ]
check cmp -s "$SCRIPT" "$GI"; check cmp -s "$SCRIPT" "$SF/dir/runner.sh"; check [ -x "$GI" ]
check [ "$(readlink "$SF/d/bin/go-installer")" = "$GI" ]
check [ -z "$(ls "$SF/d/bin" | grep -vx 'goinstall\|go-installer')" ]  # временных goinstall.XXXXXX не осталось
check [ "$(nlog)" = $(( n0 + 1 )) ]; check grep -q "goinstall заменён другой сборкой версии ${GIV} (из файла)" "$SF/dir/shield.log"
# Повтор и запуск самого goinstall — ничего не меняют.
out=$(SI0="$SCRIPT" si_run 'GOINST_SHIELD_TEST=1; self_install; shield_offer')
check hasnt "$out" 'Команда goinstall'
out=$(SI0="$GI" si_run 'GOINST_SHIELD_TEST=1; self_install; shield_offer')
check hasnt "$out" 'Команда goinstall'
SI0="$SF/dir/runner.sh" si_run 'shield_sync' >/dev/null
check [ "$(nlog)" = $(( n0 + 1 )) ]; check cmp -s "$SCRIPT" "$GI"; check cmp -s "$SCRIPT" "$SF/dir/runner.sh"
# Команда --shield из файла другой сборки (self_install не зовётся) — копия
#    остаётся за goinstall, а не за файлом.
{ cat "$SCRIPT"; echo '# третья сборка того же номера'; } > "$SF/d/third.sh"
SI0="$SF/d/third.sh" si_run 'shield_sync' >/dev/null
check cmp -s "$SCRIPT" "$SF/dir/runner.sh"; check [ "$(nlog)" = $(( n0 + 1 )) ]
# Из канала тот же номер другой сборки — сверить не с чем: goinstall и копия
#    не трогаются, сети нет.
{ cat "$SCRIPT"; echo '# прежняя сборка того же номера'; } > "$GI"; rm -f "$SELFD/calls"
si_run 'GOINST_SHIELD_TEST=1; self_install; shield_offer' >/dev/null
check [ ! -e "$SELFD/calls" ]; check neg cmp -s "$SCRIPT" "$GI"; check cmp -s "$GI" "$SF/dir/runner.sh"
# goinstall не записать — копия таймера тоже не уходит к файлу.
{ cat "$SCRIPT"; echo '# прежняя сборка того же номера'; } > "$GI"; cp "$GI" "$SF/dir/runner.sh"; chmod 555 "$SF/d/bin"
SI0="$SCRIPT" si_run 'GOINST_SHIELD_TEST=1; self_install; shield_offer' >/dev/null
chmod 755 "$SF/d/bin"
check neg cmp -s "$SCRIPT" "$GI"; check cmp -s "$GI" "$SF/dir/runner.sh"

# Пути обновления между ветками (решение владельца 04.11: апрув → тест-ветка
# → main; обновления между ветками обязаны проходить).
pathrun() {  # pathrun <канал|файл> <выражение> — запуск этой версии
    if [ "$1" = файл ]; then SI0="$SCRIPT" si_run "$2"; else si_run "$2"; fi
}
for how in канал файл; do
    # main 1.0.12 (без защиты) → test-shield этой версии.
    si_reset; cp "$SELFD/raw.$S1" "$GI"; chmod 755 "$GI"
    out=$(pathrun $how 'GOINST_SHIELD_TEST=1; self_install; shield_install >/dev/null 2>&1; echo "shield=$?"')
    check has "$out" 'shield=0'; check cmp -s "$SCRIPT" "$GI"; check cmp -s "$SCRIPT" "$SF/dir/runner.sh"
    if [ "$how" = канал ]; then check [ "$(cat "$SF/gd/.self-ref")" = test-shield ]; else check [ ! -e "$SF/gd/.self-ref" ]; fi
    # test-shield 1.2.4 с защитой (копия таймера — 1.2.4) → эта версия.
    si_reset; sed "s/^GOINST_VERSION=\"$GIV\"\$/GOINST_VERSION=\"1.2.4\"/" "$SCRIPT" > "$GI"; chmod 755 "$GI"
    SI0="$SCRIPT" si_run 'shield_install' >/dev/null 2>&1; cp "$GI" "$SF/dir/runner.sh"
    selfref test-shield
    out=$(pathrun $how 'GOINST_SHIELD_TEST=1; self_install; shield_offer; echo "rc=$?"')
    check has "$out" 'rc=0'; check cmp -s "$SCRIPT" "$GI"; check cmp -s "$SCRIPT" "$SF/dir/runner.sh"
    check grep -q "копия скрипта для таймера: версия ${GIV}" "$SF/dir/shield.log"
    if [ "$how" = канал ]; then check [ "$(cat "$SF/gd/.self-ref")" = test-shield ]; else check [ ! -e "$SF/gd/.self-ref" ]; fi
done
# test-shield 1.2.4 → эта версия кнопкой обновления: запомненная ветка новее
#    main — self_best ведёт на неё; копию таймера приводит следующий запуск
#    goinstall.
si_reset; sed "s/^GOINST_VERSION=\"$GIV\"\$/GOINST_VERSION=\"1.2.4\"/" "$SCRIPT" > "$GI"; chmod 755 "$GI"
SI0="$SCRIPT" si_run 'shield_install' >/dev/null 2>&1; cp "$GI" "$SF/dir/runner.sh"; selfref test-shield
printf '%s' "$S3" > "$SELFD/sha.test-shield"
out=$(SI0="$GI" si_run 'self_fetch_versions; echo "best=$(self_best)"; [ -e "$SELF_REF_FILE" ] && echo kept
    ensure_token() { :; }; self_update >/dev/null 2>&1; echo "rc=$?"')
check has "$out" "best=test-shield ${GIV}"; check has "$out" kept; check has "$out" 'rc=0'
check cmp -s "$SCRIPT" "$GI"; check [ "$(cat "$SF/gd/.self-ref")" = test-shield ]
SI0="$GI" si_run 'GOINST_SHIELD_TEST=1; shield_offer' >/dev/null
check cmp -s "$SCRIPT" "$SF/dir/runner.sh"
# test-shield этой версии → main догнал: та же версия в main — запись забыта,
#    обновлять нечего (тот же номер — та же сборка, К5-11); новее в main —
#    обновление из main. Стоящая новее main — запись остаётся.
S10=a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0; S11=b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1
cp "$SCRIPT" "$SELFD/raw.$S10"
sed "s/^GOINST_VERSION=\"$GIV\"\$/GOINST_VERSION=\"9.9.9\"/" "$SCRIPT" > "$SELFD/raw.$S11"
for how in канал файл; do
    si_reset; cp "$SCRIPT" "$GI"; chmod 755 "$GI"; selfref test-shield
    out=$(pathrun $how 'self_install; self_fetch_versions; echo "best=$(self_best)"; [ -e "$SELF_REF_FILE" ] && echo kept')
    check has "$out" "best=test-shield ${GIV}"; check has "$out" kept
    printf '%s' "$S10" > "$SELFD/sha.main"; rm -rf "$SF/gd/versions"
    out=$(pathrun $how 'self_install; self_fetch_versions; echo "best=$(self_best)"; [ -e "$SELF_REF_FILE" ] || echo gone')
    check has "$out" "best=main ${GIV}"; check has "$out" gone; check cmp -s "$SCRIPT" "$GI"
    # Запись стирает и свежий кеш (без нового опроса).
    selfref test-shield
    check has "$(pathrun $how 'self_fetch_versions; [ -e "$SELF_REF_FILE" ] || echo gone')" gone
    # REVIEW-8 №1: main принял эту версию, а в ветке уже новее — запись
    #    остаётся, обновление — из ветки. Сбой пробы ветки (пустая версия) —
    #    тоже остаётся.
    printf '%s' "$S11" > "$SELFD/sha.test-shield"; rm -rf "$SF/gd/versions"; selfref test-shield
    out=$(pathrun $how 'self_fetch_versions; echo "best=$(self_best)"; [ -e "$SELF_REF_FILE" ] && echo kept')
    check has "$out" 'best=test-shield 9.9.9'; check has "$out" kept
    out=$(pathrun $how 'ver_cache_write "$SELF_ID" test-shield ""; _self_ref_caught; [ -e "$SELF_REF_FILE" ] && echo kept')
    check has "$out" kept
    printf '%s' "$S3" > "$SELFD/sha.test-shield"; rm -rf "$SF/gd/versions"
    printf '%s' "$S11" > "$SELFD/sha.main"; rm -rf "$SF/gd/versions"; selfref test-shield
    out=$(pathrun $how 'self_fetch_versions; echo "best=$(self_best)"; [ -e "$SELF_REF_FILE" ] || echo gone
        ensure_token() { :; }; self_update >/dev/null 2>&1; echo "rc=$?"')
    check has "$out" 'best=main 9.9.9'; check has "$out" gone; check has "$out" 'rc=0'
    check cmp -s "$SELFD/raw.$S11" "$GI"; check [ ! -e "$SF/gd/.self-ref" ]
    printf '%s' "$S1" > "$SELFD/sha.main"
done
# Из канала main новее: запущенный скрипт main 9.9.9 находит свою ветку (main),
#    запись test-shield стирается.
si_reset; cp "$SCRIPT" "$GI"; chmod 755 "$GI"; selfref test-shield
br dev "$S2" main "$S11" test-shield "$S3" > "$SELFD/branches7.json"
out=$(SCRIPT="$SELFD/raw.$S11" SELF_LIST=branches7.json si_run 'self_install')
check has "$out" 'Команда goinstall установлена: версия 9.9.9 из ветки main.'
check cmp -s "$SELFD/raw.$S11" "$GI"; check [ ! -e "$SF/gd/.self-ref" ]
rm -f "$SELFD/sha.test-shield" "$SELFD/raw.$S10" "$SELFD/raw.$S11"

echo "── набор не тронул рабочие файлы"
check [ "$(cksum < "$SCRIPT") $(cksum < "$HERE/test_goinstaller.sh")" = "$SELF_SUM" ]

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

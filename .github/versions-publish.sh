#!/bin/bash
# Публикация сводки версий в ветку versions (зовёт workflows/versions.yml).
#
# Ветка — один коммит без родителей: история сводки никому не нужна, а
# расти она не должна. Публикуем, когда сводка изменилась или прошлой
# больше двух часов: по сроку серверы отличают живую сборку от сломанной
# (goInstaller не верит сводке старше 12 часов). Расписание Actions на деле
# срабатывает раз в 3–9 часов, а не раз в час (gh run list, 10–14.10): при
# сроке 6 часов сводка доживала до 15 и серверы ей не верили. С двумя —
# худший случай 2 + 9,5 < 12.
#
# Вызов: versions-publish.sh <файл сводки>, из рабочей копии с remote origin.
set -euo pipefail

new="${1:?нужен файл сводки}"
branch="${GOINST_DIGEST_REF:-versions}"
heartbeat="${GOINST_DIGEST_HEARTBEAT:-7200}"

[ -s "$new" ] || { echo "Сводка пустая — не публикую" >&2; exit 1; }
grep -qx 'format=1' "$new" || { echo "В сводке нет format=1 — не публикую" >&2; exit 1; }
grep -q '^generated=[0-9][0-9]*$' "$new" || { echo "В сводке нет времени сборки — не публикую" >&2; exit 1; }

old=$(mktemp)
trap 'rm -f "$old"' EXIT
if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    git fetch --quiet --depth=1 origin "$branch"
    git show "FETCH_HEAD:versions.txt" > "$old" 2>/dev/null || : > "$old"
fi

# Сравниваем без строки времени: иначе «изменилась» была бы каждая сборка.
body() { grep -v '^generated=' "$1" || true; }
gen_old=$(grep -m1 '^generated=' "$old" || true)
gen_old="${gen_old#generated=}"
case "$gen_old" in ''|*[!0-9]*) gen_old=0 ;; esac
now=$(date +%s)
if [ "$(body "$old")" = "$(body "$new")" ] && [ $(( now - gen_old )) -lt "$heartbeat" ]; then
    echo "Сводка не изменилась — публиковать нечего"
    exit 0
fi

export GIT_AUTHOR_NAME="goInstaller versions"
export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
blob=$(git hash-object -w "$new")
tree=$(printf '100644 blob %s\tversions.txt\n' "$blob" | git mktree)
commit=$(git commit-tree "$tree" -m "versions: сводка на $(date -u +%Y-%m-%dT%H:%MZ)")
git push --force --quiet origin "$commit:refs/heads/$branch"
echo "Сводка опубликована: $commit"

#!/bin/sh
# anchor: при старте сессии — назвать вкладку по якорю и рассказать, где мы.
#
# Хук молчит и выходит с нулём везде, где чего-то не хватает: без herdr, без
# beads, вне git, на ветке без якоря. Хук, который ломает старт сессии, будет
# снесён в первый же плохой день — и правильно.
#
# Якорь определяется по имени ветки: feature/aio-ppku-jobs-queue → aio-ppku.
# Второго источника правды (файла-маркера в каталоге) нет намеренно: он
# однажды разойдётся с веткой, а ветка на worktree одна и незаметно не меняется.

set -u

command -v bd >/dev/null 2>&1 || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[ -n "$branch" ] && [ "$branch" != "HEAD" ] || exit 0

# База beads живёт в ОСНОВНОМ дереве репозитория: .beads не версионируется, и
# в worktree его нет вовсе — а работа идёт именно в worktree. Флаг --db здесь
# не поможет: beads работает через Dolt-сервер и ищет базу по рабочему
# каталогу, так что единственный верный способ — звать его из корня.
root=$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")
[ -d "$root/.beads" ] || exit 0
bd() { (cd "$root" && command bd "$@"); }

# Id якоря в имени ветки: <префикс>/<id>-<что-угодно> или <id>-<что-угодно>.
# Форма id задаётся beads: буквы проекта, дефис, короткий суффикс.
last=${branch##*/}
anchor=$(printf '%s' "$last" | sed -E -n 's/^([a-z][a-z0-9]+-[a-z0-9]{4})([-.].*)?$/\1/p')
[ -n "$anchor" ] || exit 0

# Заголовок берём из json, а не разбираем человекочитаемый вывод: он меняется
# со сменой версии bd, и разбор развалится молча.
title=$(bd show "$anchor" --json 2>/dev/null | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print((d[0] if isinstance(d, list) else d).get("title", ""))
except Exception:
    pass' 2>/dev/null)
[ -n "$title" ] || exit 0

# Имя вкладки — заголовок якоря, а не его id: имя читают глазами.
if [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ] && command -v herdr >/dev/null 2>&1; then
  tab=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["pane"].get("tab_id",""))
except Exception: pass' 2>/dev/null)
  [ -n "$tab" ] && herdr tab rename "$tab" "$title" >/dev/null 2>&1
fi

# Что сессия должна знать, не спрашивая: чем занят этот якорь и что в нём открыто.
printf '\n⚓ Якорь: %s — %s\n   ветка: %s\n' "$anchor" "$title" "$branch"
children=$(bd list --status=open --limit=0 2>/dev/null | grep -F "$anchor" | head -5)
[ -n "$children" ] && printf '   открыто в теме:\n%s\n' "$children"
exit 0

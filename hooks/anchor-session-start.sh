#!/bin/sh
# anchor: при старте сессии — дать смысловое ядро, назвать вкладку по якорю и
# рассказать, где мы.
#
# Хук молчит и выходит с нулём везде, где чего-то не хватает: без herdr, без
# beads, вне git, на ветке без якоря. Хук, который ломает старт сессии, будет
# снесён в первый же плохой день — и правильно.
#
# Якорь определяется по имени ветки: feature/aio-ppku-jobs-queue → aio-ppku.
# Если ветку диктует внешний трекер (AS-2103-doctype-provenance), якорь ищется
# по коду в заголовках задач, от самого частного к общему: ветка
# AS-1637-GXP-036-gxp-validator — это подтема GXP-036, а не эпик AS-1637.
# Второго источника правды ни то, ни другое не создаёт: правда — по-прежнему
# ветка. Файла-маркера в каталоге нет намеренно: он однажды разойдётся с
# веткой, а ветка на worktree одна и незаметно не меняется.

set -u

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Всё общее для темы живёт в ОСНОВНОМ дереве репозитория, а работа идёт в
# worktree. Отсюда root — он нужен и ядру, и beads.
# Путь абсолютный намеренно: в основном дереве git-common-dir отдаёт «.git», и
# dirname от него — «.». Относительный root молча ломал две вещи. В основном
# дереве here != root, поэтому хук считал его worktree и писал в его настройки
# BEADS_DIR=./.beads — путь, верный лишь пока cwd совпадает с корнем; а строка
# «beads: общая база основного дерева» печаталась там, где базу никуда не
# уводили.
root=$(cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")" 2>/dev/null && pwd)
here=$(git rev-parse --show-toplevel 2>/dev/null)

# --- Смысловое ядро -------------------------------------------------------
# Цель, язык, приоритеты и ограничения проекта — то, из чего следуют остальные
# решения. Печатается раньше якоря и не зависит от beads: воркер в изолированном
# worktree иначе не знает о продукте ничего, кроме текста присланной задачи, и
# ограничения приходится копипастить в каждый промпт оркестратора — где их
# однажды забудут или перефразируют.
#
# Ядро пишет человек. Хук его только подаёт и никогда не правит.
for candidate in "$root/CORE.md" "$root/docs/CORE.md" "$root/.anchor/core.md"; do
  [ -f "$candidate" ] || continue
  printf '\n📘 Смысловое ядро — %s\n\n' "${candidate#"$root"/}"
  # Большое ядро не печатаем целиком: оно перестаёт быть ядром, а контекст не
  # резиновый. Обрезанное честно показывает, где читать дальше.
  if [ "$(wc -c < "$candidate")" -le 6000 ]; then
    cat "$candidate"
  else
    head -n 40 "$candidate"
    printf '\n   … целиком: %s\n' "$candidate"
  fi
  break
done

command -v bd >/dev/null 2>&1 || exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[ -n "$branch" ] && [ "$branch" != "HEAD" ] || exit 0

# База beads живёт в основном дереве: .beads версионируется лишь частично, и в
# worktree git раскладывает огрызок — config.yaml, metadata.json, hooks. Этого
# хватает, чтобы bd счёл огрызок своим проектом, поднял над ним ПУСТОЙ
# Dolt-сервер и упал с «database not found»: воркер не может ни заявить якорь,
# ни закрыть его. Флаг --db не помогает — он не уводит поиск из рабочего
# каталога. Уводит переменная BEADS_DIR.
[ -d "$root/.beads" ] || exit 0
bd() { BEADS_DIR="$root/.beads" command bd "$@"; }

# Чтобы то же самое работало у самой сессии, а не только внутри хука, кладём
# переменную в настройки worktree. Файл дополняем, а не переписываем: там могут
# быть чужие настройки, и затирать их хуком — худший способ познакомиться.
if [ -n "$here" ] && [ "$here" != "$root" ] && command -v python3 >/dev/null 2>&1; then
  BEADS_DIR_VALUE="$root/.beads" SETTINGS_DIR="$here/.claude" python3 - <<'PY' 2>/dev/null
import json, os, pathlib
d = pathlib.Path(os.environ["SETTINGS_DIR"]); d.mkdir(exist_ok=True)
p = d / "settings.local.json"
try:
    cfg = json.loads(p.read_text())
    if not isinstance(cfg, dict):
        raise ValueError
except Exception:
    cfg = {}
env = cfg.setdefault("env", {})
if env.get("BEADS_DIR") != os.environ["BEADS_DIR_VALUE"]:
    env["BEADS_DIR"] = os.environ["BEADS_DIR_VALUE"]
    p.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n")
PY
fi

# Id якоря в имени ветки: <префикс>/<id>-<что-угодно> или <id>-<что-угодно>.
# Форма id задаётся beads: буквы проекта, дефис, короткий суффикс.
last=${branch##*/}
# Суффикс id у beads разной длины: aio-ppku — четыре знака, am-9ly — три.
# Жёсткая четвёрка молча не узнавала якорь в репозиториях с коротким
# суффиксом — хук выходил как будто ветка вообще не про якорь.
# Подзадача молекулы называется am-1ua.2 — точка входит в id, а не
# отделяет хвост. Без этого якорем становился родительский эпик, и сессия
# рассказывала про тему в целом вместо своей части.
anchor=$(printf '%s' "$last" | sed -E -n 's/^([a-z][a-z0-9]*-[a-z0-9]{3,8}(\.[0-9]+)?)(-.*)?$/\1/p')
# Ветка может нести код внешнего трекера вместо id beads:
# AS-2103-doctype-provenance. Так живут репозитории, где имена ветвей диктует
# трекер компании, а beads — личный слой поверх него: требовать id якоря в
# начале ветки там значит требовать сменить правило всей команды.
#
# Второго источника правды это не создаёт. Якорь по-прежнему один, просто
# найден не по имени ветки, а по коду, который и так стоит в его заголовке.
#
# Кодов в имени ветки бывает несколько, и они идут от общего к частному:
# AS-1637-GXP-036-gxp-validator — это подтема GXP-036 внутри эпика AS-1637.
# Поэтому разбор идёт с конца: иначе десять ветвей одного эпика опознаются как
# один и тот же якорь, и каждая сессия рассказывает про тему в целом вместо
# своей части. И только если ни один код не открывает чей-то заголовок,
# принимается совпадение в середине текста — там код чаще всего ссылка на
# соседнюю задачу, а не имя темы.
case "$last" in
  *[A-Z]-[0-9]*)
    if [ -z "$anchor" ] && command -v python3 >/dev/null 2>&1; then
      anchor=$(bd list --limit=0 --json 2>/dev/null \
        | ANCHOR_BRANCH_TAIL="$last" python3 -c 'import json, os, re, sys
tail = os.environ["ANCHOR_BRANCH_TAIL"]
try:
    items = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(items, list):
    items = items.get("issues", [])
rank = {"in_progress": 0, "open": 1, "blocked": 2}
codes = re.findall(r"[A-Z][A-Z0-9]*-[0-9]+", tail)
def pick(match):
    hits = [(rank.get(i.get("status"), 3), i.get("id") or "")
            for i in items if match(i.get("title") or "")]
    return sorted(hits)[0][1] if hits else ""
for leading in (True, False):
    for c in reversed(codes):
        if leading:
            rx = re.compile(r"^[^A-Za-z0-9]*(\[[^]]*\][^A-Za-z0-9]*)*"
                            + re.escape(c) + r"(?![A-Za-z0-9])")
            got = pick(rx.match)
        else:
            rx = re.compile(r"(?<![A-Za-z0-9])" + re.escape(c) + r"(?![A-Za-z0-9])")
            got = pick(rx.search)
        if got:
            print(got)
            sys.exit(0)
' 2>/dev/null)
    fi ;;
esac

# Якоря нет — значит это основное дерево (ветка main) либо ветка не по схеме.
# Основному дереву блок якоря не нужен, но нужна процедура: оркестратор —
# единственная роль, которой хук иначе не даёт НИ ИНСТРУМЕНТА, НИ КОМАНДЫ.
# Он получает ядро («темы живут в worktree») и заполняет пробел тем, чем
# заполнил бы любой — `git worktree add` и сообщением соседу. Дерево при этом
# появляется, а вкладка нет, и человек не видит, кто над чем работает.
if [ -z "$anchor" ]; then
  if [ "$here" = "$root" ] && command -v herdr >/dev/null 2>&1; then
    printf '\n🎛  Основное дерево — оркестрация. Процедура темы: навык `anchor` (/anchor)\n'
    printf '   Дерево и вкладку заводит herdr, а не git напрямую:\n'
    printf '     herdr worktree create --branch <ветка> --base main\n'
    printf '   Работу соседу отдают тоже через herdr — тогда её видно в списке:\n'
    printf '     herdr agent list · herdr agent prompt <id> "…"\n'
  fi
  exit 0
fi

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
#
# Переименовывается только вкладка worktree. Основное дерево — место оркестрации:
# оттуда заводят якоря, сводят в main и убирают за собой, и оно не является
# темой. Назвать его вкладку темой значит соврать дважды: сессия там не занята
# этой темой, а имя вдобавок меняется от того, на какой ветке основное дерево
# случайно осталось.
#
# Цена решения: кто работает в одном дереве без worktree, переименования не
# получит. Это следует из самой схемы — тема живёт в отдельном каталоге, — и
# лучше, чем вкладка-оркестратор с чужим именем.
if [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ] \
   && [ -n "$here" ] && [ "$here" != "$root" ] \
   && command -v herdr >/dev/null 2>&1; then
  tab=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["pane"].get("tab_id",""))
except Exception: pass' 2>/dev/null)
  [ -n "$tab" ] && herdr tab rename "$tab" "$title" >/dev/null 2>&1
fi

# Что сессия должна знать, не спрашивая: чем занят этот якорь и что в нём открыто.
printf '\n⚓ Якорь: %s — %s\n   ветка: %s\n' "$anchor" "$title" "$branch"
children=$(bd list --status=open --limit=0 2>/dev/null | grep -F "$anchor" | head -5)
[ -n "$children" ] && printf '   открыто в теме:\n%s\n' "$children"

# Своя база у темы не заводится: и хук, и сессия ходят в основное дерево.
[ -n "$here" ] && [ "$here" != "$root" ] && \
  printf '   beads: общая база основного дерева (BEADS_DIR=%s)\n' "$root/.beads"

# Чем кончилась прошлая сессия. Спрашиваем не трекер, а репозиторий: задача
# закрывается в конце, а обрывается работа посередине — и тогда единственный
# честный ответ «на чём остановились» лежит в последнем коммите и в том, что
# осталось незакоммиченным.
tip=$(git log -1 --format='%h %s (%cr)' 2>/dev/null)
[ -n "$tip" ] && printf '   последнее: %s\n' "$tip"

dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "${dirty:-0}" -gt 0 ]; then
  # Незакоммиченное — не беспорядок, а прерванная мысль: сказать о нём нужно
  # раньше, чем человек начнёт следующую правку поверх.
  printf '   не закоммичено файлов: %s\n' "$dirty"
fi
exit 0

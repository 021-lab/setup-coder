#!/usr/bin/env bash
#
# Раскладывает общие настройки агента по репозиторию проекта:
#
#   CLAUDE.md        — общие правила, вставляются блоком между маркерами, чтобы
#                      правила самого проекта, написанные рядом, не затирались;
#   .claude/skills/  — общие скиллы, каждый заменяется целиком, чужие не трогаются.
#
# Перезапуск безопасен: повторный запуск обновляет ровно то, что изменилось в
# источнике, и ничего не спрашивает.
#
#   ./setup-coder.sh [каталог-проекта]     по умолчанию — текущий каталог
#   ./setup-coder.sh --check [каталог]     показать, что изменится, и выйти
#
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEGIN_MARK='<!-- setup-coder: начало. Не править здесь — правки в 021-lab/setup-coder -->'
END_MARK='<!-- setup-coder: конец -->'

check_only=0
if [ "${1:-}" = "--check" ]; then check_only=1; shift; fi

target_arg="${1:-$PWD}"
if [ ! -d "$target_arg" ]; then
  echo "Нет такого каталога: $target_arg" >&2
  exit 1
fi
TARGET_DIR="$(cd "$target_arg" && pwd)"

if [ "$TARGET_DIR" = "$SOURCE_DIR" ]; then
  echo "Целевой каталог совпадает с источником — копировать некуда." >&2
  exit 1
fi

say() { printf '%s\n' "$*"; }
planned=0

# --- CLAUDE.md -------------------------------------------------------------
#
# Блок между маркерами — единственное, чем владеет этот скрипт. Файла нет —
# блок становится файлом; маркеры есть — содержимое между ними заменяется;
# файл есть, а маркеров нет — блок дописывается в конец, чужой текст остаётся.

rules_src="$SOURCE_DIR/CLAUDE.md"
rules_dst="$TARGET_DIR/CLAUDE.md"

if [ -f "$rules_src" ]; then
  block="$(mktemp)"; trap 'rm -f "$block" "${merged:-}"' EXIT
  { printf '%s\n' "$BEGIN_MARK"; cat "$rules_src"; printf '%s\n' "$END_MARK"; } > "$block"

  merged="$(mktemp)"
  if [ ! -f "$rules_dst" ]; then
    cat "$block" > "$merged"
  elif grep -qF "$BEGIN_MARK" "$rules_dst"; then
    awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v blockfile="$block" '
      $0 == begin { while ((getline line < blockfile) > 0) print line; close(blockfile); skipping = 1; next }
      skipping && $0 == end { skipping = 0; next }
      !skipping { print }
    ' "$rules_dst" > "$merged"
  else
    { cat "$rules_dst"; printf '\n'; cat "$block"; } > "$merged"
  fi

  if [ -f "$rules_dst" ] && cmp -s "$merged" "$rules_dst"; then
    say "CLAUDE.md — уже совпадает"
  else
    planned=1
    if [ "$check_only" = 1 ]; then
      say "CLAUDE.md — будет обновлён блок общих правил"
    else
      cat "$merged" > "$rules_dst"
      say "CLAUDE.md — записан блок общих правил"
    fi
  fi
fi

# --- скиллы ----------------------------------------------------------------
#
# Скилл — это каталог. Он заменяется целиком, иначе удалённый в источнике файл
# остался бы жить в проекте. Скиллы, которых в источнике нет, не трогаются.

skills_src="$SOURCE_DIR/skills"
skills_dst="$TARGET_DIR/.claude/skills"
copied_skills=0

if [ -d "$skills_src" ]; then
  for skill_dir in "$skills_src"/*/; do
    [ -d "$skill_dir" ] || continue
    name="$(basename "$skill_dir")"
    copied_skills=$((copied_skills + 1))
    if [ -d "$skills_dst/$name" ] && diff -rq "$skill_dir" "$skills_dst/$name" >/dev/null 2>&1; then
      say "skills/$name — уже совпадает"
      continue
    fi
    planned=1
    if [ "$check_only" = 1 ]; then
      say "skills/$name — будет обновлён"
    else
      mkdir -p "$skills_dst"
      rm -rf "${skills_dst:?}/$name"
      cp -R "$skill_dir" "$skills_dst/$name"
      say "skills/$name — скопирован"
    fi
  done
fi

if [ "$copied_skills" = 0 ]; then
  say "skills/ — в источнике пусто, копировать нечего"
fi

if [ "$check_only" = 1 ]; then
  [ "$planned" = 1 ] && say "" && say "Это проверка: ничего не записано."
  exit 0
fi

say ""
say "Готово: $TARGET_DIR"
say "Проверьте изменения (git status) и закоммитьте их в проект."

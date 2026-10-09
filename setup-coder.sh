#!/usr/bin/env bash
#
# Ставит стандартное окружение агента из этого репозитория.
#
#   setup-coder.sh --env             в окружение: $HOME/.claude — правила, скиллы,
#                                    MCP-серверы на пользовательский уровень.
#                                    Это то, что вызывается при старте контейнера.
#
#   setup-coder.sh --repo [КАТАЛОГ]  в репозиторий проекта (по умолчанию текущий):
#                                    CLAUDE.md блоком между маркерами, скиллы в
#                                    .claude/skills, MCP-серверы в .mcp.json.
#                                    Нужно, когда настройки должны достаться всем,
#                                    кто открыл проект, и быть воспроизводимыми.
#
#   любой режим + --check            показать, что изменится, и ничего не писать.
#
# Повторный запуск безопасен: что совпадает — то не переписывается.
#
set -eu

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEGIN_MARK='<!-- setup-coder: начало. Не править здесь — правки в 021-lab/setup-coder -->'
END_MARK='<!-- setup-coder: конец -->'

say() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die() { warn "✗ $*"; exit 1; }

# --- разбор аргументов -----------------------------------------------------

mode=''
check_only=0
target_arg=''
for arg in "$@"; do
  case "$arg" in
    --env)   mode='env' ;;
    --repo)  mode='repo' ;;
    --check) check_only=1 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)      die "Неизвестный ключ: $arg" ;;
    *)       target_arg="$arg" ;;
  esac
done
# Путь без ключа означает репозиторий: так короче и так звали скрипт раньше.
[ -z "$mode" ] && [ -n "$target_arg" ] && mode='repo'
[ -z "$mode" ] && die "Нужен режим: --env или --repo [КАТАЛОГ]. Подсказка: --help"

version() {
  git -C "$SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo 'без версии'
}
# Только версия, без времени: иначе файл менялся бы при каждом запуске и в проекте
# появлялся бы пустой диff. Когда ставили — пишется отдельно, в $HOME/.claude/.setup-coder.
STAMP="setup-coder $(version)"

python_bin=''
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then python_bin="$candidate"; break; fi
done

changed=0
note() {
  changed=1
  if [ "$check_only" = 1 ]; then say "$1 — будет $2"; else say "$1 — $3"; fi
}

# --- правила ---------------------------------------------------------------
#
# В окружении файл наш целиком, и он просто записывается. В репозитории проекта
# рядом живут правила самого проекта, поэтому общие вставляются блоком между
# маркерами: повторный запуск меняет только блок.

install_rules_into_home() {
  local src="$SOURCE_DIR/CLAUDE.md" dst="$HOME/.claude/CLAUDE.md" tmp
  [ -f "$src" ] || return 0
  tmp="$(mktemp)"
  { cat "$src"; printf '\n<!-- %s -->\n' "$STAMP"; } > "$tmp"
  if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then say 'CLAUDE.md — уже совпадает'
  else
    note 'CLAUDE.md' 'записан' 'записан'
    [ "$check_only" = 1 ] || { mkdir -p "$HOME/.claude"; cat "$tmp" > "$dst"; }
  fi
  rm -f "$tmp"
}

install_rules_into_repo() {
  local src="$SOURCE_DIR/CLAUDE.md" dst="$1/CLAUDE.md" block merged
  [ -f "$src" ] || return 0
  block="$(mktemp)"; merged="$(mktemp)"
  { printf '%s\n' "$BEGIN_MARK"; printf '<!-- %s -->\n' "$STAMP"; cat "$src"; printf '%s\n' "$END_MARK"; } > "$block"

  if [ ! -f "$dst" ]; then
    cat "$block" > "$merged"
  elif grep -qF "$BEGIN_MARK" "$dst"; then
    awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v blockfile="$block" '
      $0 == begin { while ((getline line < blockfile) > 0) print line; close(blockfile); skipping = 1; next }
      skipping && $0 == end { skipping = 0; next }
      !skipping { print }
    ' "$dst" > "$merged"
  else
    { cat "$dst"; printf '\n'; cat "$block"; } > "$merged"
  fi

  if [ -f "$dst" ] && cmp -s "$merged" "$dst"; then say 'CLAUDE.md — уже совпадает'
  else
    note 'CLAUDE.md' 'обновлён блок общих правил' 'записан блок общих правил'
    [ "$check_only" = 1 ] || cat "$merged" > "$dst"
  fi
  rm -f "$block" "$merged"
}

# --- скиллы ----------------------------------------------------------------
#
# Скилл — каталог, и он заменяется целиком: иначе файл, удалённый в источнике,
# остался бы жить на месте установки. Скиллы, которых в источнике нет, не трогаем.

install_skills() {
  local dst="$1" count=0 skill name
  [ -d "$SOURCE_DIR/skills" ] || return 0
  for skill in "$SOURCE_DIR"/skills/*/; do
    [ -d "$skill" ] || continue
    name="$(basename "$skill")"
    count=$((count + 1))
    if [ -d "$dst/$name" ] && diff -rq "$skill" "$dst/$name" >/dev/null 2>&1; then
      say "skills/$name — уже совпадает"; continue
    fi
    note "skills/$name" 'обновлён' 'скопирован'
    [ "$check_only" = 1 ] && continue
    mkdir -p "$dst"
    rm -rf "${dst:?}/$name"
    cp -R "$skill" "$dst/$name"
  done
  [ "$count" = 0 ] && say 'skills/ — в источнике пусто'
  return 0
}

# --- MCP-серверы -----------------------------------------------------------
#
# В окружении это пользовательский конфиг, и правильный способ его менять —
# сама команда claude: формат конфига её, а не наш. В репозитории проекта это
# .mcp.json, который сливается, чтобы не затереть серверы проекта.

install_mcp_into_home() {
  local src="$SOURCE_DIR/mcp.json" name command_line
  [ -f "$src" ] || return 0
  if [ -z "$python_bin" ]; then warn 'mcp.json — пропущен: нет python3, нечем разобрать'; return 0; fi
  if ! command -v claude >/dev/null 2>&1; then
    warn 'mcp.json — пропущен: claude не найден в PATH, пользовательский конфиг правит только он'
    return 0
  fi
  # Каждый сервер отдаётся claude одной строкой: имя, затем команда с аргументами.
  "$python_bin" -I - "$src" <<'PY' | while IFS= read -r name && IFS= read -r command_line; do
import json, sys, shlex
servers = json.load(open(sys.argv[1])).get('mcpServers', {})
for name, spec in servers.items():
    if spec.get('type', 'stdio') != 'stdio' or not spec.get('command'):
        print(name); print('')          # не stdio — пропустим ниже
        continue
    print(name)
    print(shlex.join([spec['command'], *spec.get('args', [])]))
PY
    if [ -z "$command_line" ]; then warn "mcp/$name — пропущен: поддерживается только stdio"; continue; fi
    if [ "$check_only" = 1 ]; then say "mcp/$name — будет добавлен"; changed=1; continue; fi
    # Уже настроенный сервер — это успех, а не отказ, но claude возвращает на него 1
    # (измерено), поэтому решение принимается по тексту, а не по коду возврата.
    local output
    if output="$(claude mcp add --scope user "$name" -- $command_line 2>&1)"; then
      say "mcp/$name — добавлен в пользовательский конфиг"; changed=1
    elif printf '%s' "$output" | grep -q 'already exists'; then
      say "mcp/$name — уже настроен"
    else
      warn "mcp/$name — claude не смог добавить сервер: $output"
    fi
  done
  return 0
}

install_mcp_into_repo() {
  local src="$SOURCE_DIR/mcp.json" dst="$1/.mcp.json"
  [ -f "$src" ] || return 0
  if [ -z "$python_bin" ]; then warn '.mcp.json — пропущен: нет python3, нечем слить JSON'; return 0; fi
  local merged; merged="$(mktemp)"
  "$python_bin" -I - "$src" "$dst" > "$merged" <<'PY'
import json, os, sys
source, target = sys.argv[1], sys.argv[2]
ours = json.load(open(source)).get('mcpServers', {})
existing = {}
if os.path.exists(target):
    try: existing = json.load(open(target))
    except ValueError: raise SystemExit('.mcp.json проекта — не JSON, слияние отменено')
servers = dict(existing.get('mcpServers', {}))
servers.update(ours)                      # наши серверы выигрывают, чужие остаются
existing['mcpServers'] = servers
print(json.dumps(existing, ensure_ascii=False, indent=2))
PY
  if [ -f "$dst" ] && cmp -s "$merged" "$dst"; then say '.mcp.json — уже совпадает'
  else
    note '.mcp.json' 'обновлён' 'записан'
    [ "$check_only" = 1 ] || cat "$merged" > "$dst"
  fi
  rm -f "$merged"
  return 0
}

# --- выполнение ------------------------------------------------------------

if [ "$mode" = 'env' ]; then
  [ -n "$target_arg" ] && die '--env не принимает каталог: ставится в $HOME'
  say "▸ Окружение: \$HOME/.claude  ($STAMP)"
  install_rules_into_home
  install_skills "$HOME/.claude/skills"
  install_mcp_into_home
  if [ "$check_only" != 1 ]; then
    printf '%s, установлено %s\n' "$STAMP" "$(date -u '+%Y-%m-%d %H:%M UTC')" > "$HOME/.claude/.setup-coder"
  fi
else
  [ -z "$target_arg" ] && target_arg="$PWD"
  [ -d "$target_arg" ] || die "Нет такого каталога: $target_arg"
  TARGET_DIR="$(cd "$target_arg" && pwd)"
  [ "$TARGET_DIR" = "$SOURCE_DIR" ] && die 'Целевой каталог совпадает с источником.'
  say "▸ Проект: $TARGET_DIR  ($STAMP)"
  install_rules_into_repo "$TARGET_DIR"
  install_skills "$TARGET_DIR/.claude/skills"
  install_mcp_into_repo "$TARGET_DIR"
fi

say ''
if [ "$check_only" = 1 ]; then
  [ "$changed" = 1 ] && say 'Это проверка: ничего не записано.' || say 'Менять нечего.'
elif [ "$mode" = 'repo' ]; then
  say 'Готово. Проверьте git status и закоммитьте изменения в проект.'
else
  say 'Готово.'
fi

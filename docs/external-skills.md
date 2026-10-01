# Внешние инструменты

Три вещи, которые не живут в этом репозитории: их ставят один раз в Claude Code,
а `CLAUDE.md` только говорит, когда их грузить. Держать их в контексте постоянно
не нужно и дорого.

## Superpowers

Плагин Джесси Винсента: брейншторм спеки → план → выполнение с TDD и ревью между
шагами. Оттуда же берётся `/verify` — скилл `verification-before-completion`,
который запрещает говорить «готово» без запущенной команды и её вывода.

```
/plugin install superpowers@claude-plugins-official
```

Если официального маркетплейса нет:

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

Проверить: `/plugins` — в списке должен быть `superpowers`.

Полное имя команды проверки, если короткого `/verify` нет:
`/superpowers:verification-before-completion`.

- Репозиторий: https://github.com/obra/superpowers-marketplace
- Как автор это задумывал: https://blog.fsck.com/2025/10/09/superpowers/

**Когда грузить:** задача многошаговая и её не стыдно назвать проектом. Для
правки в две строки это лишний вес.

## Context7

MCP-сервер Upstash: подтягивает официальную документацию нужной версии
библиотеки в момент запроса, вместо того чтобы модель вспоминала API по памяти.

```
claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp@latest
```

С ключом (выше лимиты):

```
claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key КЛЮЧ
```

Использование: дописать `use context7` в запрос, либо сразу назвать библиотеку.

- Пакет: https://www.npmjs.com/package/@upstash/context7-mcp
- Документация для Claude Code: https://context7.com/docs/clients/claude-code

**Когда грузить:** пишем код под внешнюю библиотеку или API — особенно если
версия свежее, чем обучающие данные модели.

## webapp-testing

Скилл Anthropic: управление настоящим браузером через Playwright. Клики,
авторизация, JS-рендер, инспекция DOM, скриншоты, логи консоли, запуск и
остановка локальных серверов.

Ставится как скилл Claude Code; исходник и описание:
https://github.com/anthropics/skills

**Когда грузить:** надо увидеть фронтенд живьём, а не поверить тестам. Для CI
это не предназначено — туда пишется обычный Playwright-тест.

## Чего здесь нет

Эти три инструмента не копируются `setup-coder.sh` в проекты: плагин и
MCP-сервер ставятся в Claude Code, а не в репозиторий. В `skills/` этого
репозитория лежат только собственные скиллы.

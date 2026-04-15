---
description: Node.js coding standards and best practices
globs:
  - "**/*.js"
  - "**/*.mjs"
  - "**/*.cjs"
---

## Async

- Use `async/await` exclusively — no raw `.then()` chains or callbacks
- Always handle promise rejections with try/catch or `.catch()`
- Never use `new Promise()` when a native async API exists

## Error Handling

- Throw typed error classes, not generic `new Error('message')`
- Propagate errors up — never swallow them with empty catch blocks
- Register `process.on('unhandledRejection')` in all entry points

## Configuration

- All config via environment variables — never hardcoded values
- Centralise `process.env` access in a single config module
- No secrets, tokens, or API keys in source files

## Modules

- Prefer ES modules (`import/export`) over CommonJS (`require`)
- One module, one concern — split files when responsibilities diverge

## Testing

- Unit test all pure functions and service modules
- Integration tests for external service interactions (DB, APIs)
- Mock external services in unit tests; use real connections in integration tests

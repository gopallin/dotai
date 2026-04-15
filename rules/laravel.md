---
description: Laravel coding standards and best practices
globs:
  - "**/*.php"
---

## Architecture

- Business logic in Service classes, not Controllers
- Validation in Form Request classes, never in Controllers
- Use Eloquent relationships; avoid raw SQL unless absolutely necessary
- Never call `env()` outside of `config/` files; use `config()` everywhere else

## Controllers

- Use Resource Controllers (`artisan make:controller --resource`)
- Return API responses using Laravel API Resources (`artisan make:resource`)
- Keep controllers thin — delegate to Services, not inline logic

## Models

- Define `$fillable` or `$guarded` explicitly on every model
- Type all Eloquent relationships with return types
- Use model scopes for reusable query constraints

## Error Handling

- Register custom exceptions in `app/Exceptions/Handler.php`
- Avoid try-catch in controllers for domain errors — let the Handler manage them
- Use `abort()` helpers for HTTP-level errors (404, 403, etc.)

## Testing

- Feature tests for all API endpoints
- Unit tests for Service classes
- Use `RefreshDatabase` trait; never share database state between tests
- Test both success and failure paths for every endpoint

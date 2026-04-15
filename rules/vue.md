---
description: Vue.js and TypeScript coding standards and best practices
globs:
  - "**/*.vue"
  - "**/*.ts"
  - "**/*.tsx"
---

## Component Style

- Always use Vue 3 Composition API with `<script setup>` syntax
- No Options API in new components
- Component filenames: PascalCase (`UserProfile.vue`)
- If a component exceeds 200 lines, split it

## TypeScript

- All props must have explicit types via `defineProps<{...}>()`
- All emits must be typed via `defineEmits<{...}>()`
- No `any` type — use `unknown` and narrow instead
- Return types required on all exported functions

## State & Logic

- Extract reusable logic into composables (`use*.ts` in `composables/`)
- No direct DOM manipulation — use template refs (`useTemplateRef`)
- Pinia stores for shared state; composables for local reuse

## Styling

- Scoped CSS or Tailwind utility classes only
- No inline `style` attributes
- No global CSS mutations from within a component's `<style>`

## Testing

- Unit test all composables
- Component tests for interactive UI logic
- No snapshot tests — assert behavior, not markup

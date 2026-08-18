# AGENTS.md

## Quality Gate

Before finishing any code, package metadata, fixture, or behavior-affecting
change, run:

```bash
pnpm run ok  # => build + typecheck + lint:fix + test
```

For native Swift changes, also run:

```bash
pnpm run native:test
```

For documentation-only changes, do not run the full gate by default.

## Package Overview

- `packages/core` - The typed Node.js API and native-helper protocol.
- `packages/cli` - The `photokit-node` command-line interface over
  `@photokit-node/core`.
- `native/photokit-helper` - The macOS Swift executable that owns PhotoKit
  access and communicates with Node over JSON.

## Architecture Guardrails

- Keep PhotoKit and macOS authorization details in `native/photokit-helper`.
- Keep process management and public TypeScript types in `packages/core`.
- Keep the CLI thin. It should validate options, call core, and format output.
- Treat the Swift/Node JSON protocol as an explicit versioned boundary.
- Keep modules small and explicit. Do not add speculative abstractions.
- Prefer additive linear commits; do not rebase or amend unless requested.

## Style

- TypeScript strict mode is authoritative.
- Follow the existing ESLint/style rules: Allman braces, sorted imports,
  4-space indent, double quotes, and semicolons.
- Prefer explicit, small functions over speculative abstractions.
- Add or update tests when behavior changes.
- Add one-line JSDoc to exported functions, types, and classes unless the name
  alone is unambiguous.
- Keep comments concise and focused on non-obvious intent.
- Do not leave dead code.
- Do not rewrite unrelated code for style.
- Do not remove TODO comments unless their task is implemented or fixed.

## Documentation

- Keep committed docs self-contained.
- Update the README when CLI flags, protocol behavior, or platform requirements
  change.

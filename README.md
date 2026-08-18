# photokit-node

A macOS PhotoKit bridge with a typed Node.js API and CLI.

## Repository layout

- `native/photokit-helper` contains the Swift executable that talks to PhotoKit.
- `packages/core` contains the typed Node.js wrapper and protocol definitions.
- `packages/cli` contains the thin `photokit-node` command-line interface.

The native helper and Node wrapper communicate through a versioned JSON
protocol. Photo library permission prompts and iCloud asset retrieval remain on
the native side of that boundary.

## Development

Requirements:

- macOS with Xcode Command Line Tools
- Node.js 22 or newer
- pnpm 10.33.3

```bash
pnpm install
pnpm run ok
pnpm run native:test
```

Run the TypeScript CLI directly during development:

```bash
pnpm dev -- protocol-version
```

## Status

The repository currently provides the monorepo skeleton and protocol-version
handshake. PhotoKit library access will be added behind the native helper.

## License

MIT

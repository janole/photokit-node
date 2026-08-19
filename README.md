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
pnpm run native:build
pnpm run native:run -- '{"protocolVersion":1,"operation":"authorization-status","parameters":{}}'
pnpm run native:run -- '{"protocolVersion":1,"operation":"list-assets","parameters":{"limit":20,"mediaType":"image"}}'
pnpm run native:test
```

`native:build` creates a lightweight app bundle containing the required Photos
privacy description and signs it with a stable local-development identity. See
`native/photokit-helper/README.md` for authorization behavior and distribution
signing.

Run the TypeScript CLI directly during development:

```bash
pnpm dev -- protocol-version
```

## Status

The native helper provides versioned JSON operations for protocol diagnostics,
explicit Photos authorization, and bounded recent image/video metadata listing.
The private Node process runner invokes that helper without a shell and enforces
bounded output and execution time. The public client will be added over the same
boundary.

## License

MIT

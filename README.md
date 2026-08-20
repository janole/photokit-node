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

- Apple Silicon Mac running macOS 13 or newer
- Xcode Command Line Tools
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

## Native npm package

The first packaged helper supports Apple Silicon (`darwin-arm64`) only. The npm
package declares that operating-system and CPU contract, and the Node runner
and packaged launcher also reject unsupported runtimes with an explicit
`helper-platform-unsupported` diagnostic. Windows, Linux, and Intel Macs are
not runtime targets for this release.

Build and stage the signed release app inside the CLI package with one command:

```bash
pnpm run native:package
```

The package places an executable launcher and `PhotoKit Node Helper.app` under
`packages/cli/native`. Installed code resolves that launcher relative to its
own package, so it does not depend on the current working directory or
`PHOTOKIT_NODE_HELPER_PATH`.

Verify the compiled architecture, signature, bundle/npm version match, and
`npm pack --dry-run` file list, or run that verification followed by a fresh
temporary-install smoke test:

```bash
pnpm run package:verify
pnpm run package:smoke
```

Local and CI packaging uses the stable ad-hoc development signature unless
`PHOTOKIT_CODE_SIGN_IDENTITY` is set. A published release should set that
variable to its Developer ID identity and complete the corresponding Apple
distribution/notarization process.

The macOS native CI workflow is intentionally opt-in. Run it manually from the
Actions tab, or add the `ci:native` label to a pull request. While that label is
present, each new pull-request commit reruns native tests and package smoke
coverage; superseded native runs are cancelled.

Run the TypeScript CLI directly from a source checkout. The root development
script points it at the source-tree launcher automatically:

```bash
pnpm dev authorization status
pnpm dev assets list --limit 20 --media-type image
```

Set `PHOTOKIT_NODE_HELPER_PATH` only when you need to override that development
default with another helper executable.

## CLI

The Commander-based CLI exposes the public client without adding PhotoKit logic
of its own:

```text
photokit-node authorization status [--json]
photokit-node authorization request [--json]
photokit-node assets list [--limit 20] [--media-type image|video] [--json]
photokit-node assets thumbnail <local-identifier> --output <path> --max-width <pixels> --max-height <pixels> [--format jpeg|png] [--content-mode aspect-fit|aspect-fill] [--allow-network] [--overwrite] [--json]
photokit-node assets export <local-identifier> --output-directory <path> --version current|original [--allow-network] [--overwrite] [--json]
photokit-node protocol-version
```

Output is human-readable by default. `--json` emits command-specific JSON and
never embeds thumbnail bytes. Network retrieval and overwriting are disabled
unless `--allow-network` or `--overwrite` is explicitly present. Stable exit
codes distinguish usage (64), unavailable assets/media (66), unavailable
helpers or network content (69), native failures (70), output failures (73),
timeouts/cancellation (75), Photos authorization (77), and protocol mismatch
(78). See `packages/cli/README.md` for the complete behavior.

## Node API

`@photokit-node/core` exposes a typed, read-only client:

```ts
import { PhotoKitClient } from "@photokit-node/core";

const photos = new PhotoKitClient();
await photos.requestAuthorization();

const [asset] = await photos.listAssets({ limit: 20, mediaType: "image" });
if (asset)
{
    const thumbnail = await photos.getThumbnail(asset.localIdentifier, {
        maxHeight: 512,
        maxWidth: 512,
    });

    const exported = await photos.exportPhoto(asset.localIdentifier, {
        destinationDirectory: "./exports",
        version: "original",
    });

    console.log(thumbnail.bytes, exported.path);
}
```

The client performs an explicit protocol-version handshake, validates native
responses and output files at runtime, and exposes stable error codes.
Thumbnail files live in independent Node-owned temporary directories and are
always removed after their bytes are read. Photo exports remain in the
caller-owned destination and are never buffered into Node memory.

During repository development, pass an absolute `helperPath` pointing to
`native/photokit-helper/scripts/run.sh`. Installed clients resolve the bundled
launcher relative to their own package. Metadata and content deadlines are
independently configurable through `operationTimeoutMs`, `contentTimeoutMs`, or
the per-content-operation `timeoutMs` option. iCloud retrieval and replacement
remain disabled unless explicitly requested.

## Status

The native helper provides versioned JSON operations for protocol diagnostics,
explicit Photos authorization, and bounded recent image/video metadata listing.
The private Node process runner invokes that helper without a shell and enforces
bounded output and execution time. The shared protocol now defines out-of-band
thumbnail and still-photo export contracts, and the native helper renders
bounded JPEG/PNG thumbnails for image and video assets and exports current or
original still-photo content. The typed public client validates that native
boundary and manages content ownership, and the CLI exposes authorization,
listing, thumbnail, and photo-export commands over that client. The npm package
bundles and self-discovers the signed arm64 helper. Final validation and
documentation is the remaining slice.

## License

MIT

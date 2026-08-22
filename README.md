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

## Photo library behavior

The signed helper owns the macOS Photos privacy prompt and reads the current
System Photo Library only. It never mutates or deletes Photos assets. Listing
returns bounded metadata without requesting image content or downloading
iCloud originals. Local identifiers are opaque handles scoped to that library;
they are not durable cross-library IDs.

Thumbnail requests render the current image or video representation within the
requested pixel bounds. Still-photo export supports `current`, which reflects
the rendered representation visible in Photos, and `original`, which copies
the primary still-photo resource without transcoding. Live Photos contribute
their still component only; video export and paired motion remain unsupported.

Content retrieval is local-only by default. `--allow-network` or
`allowNetworkAccess: true` explicitly permits an iCloud download and can extend
operation time. Thumbnail storage belongs to Node and is removed after the
bytes are read. Export destinations and completed exports belong to the caller;
existing files are preserved unless overwrite is explicitly enabled.

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

## Validation and troubleshooting

See [`docs/validation.md`](docs/validation.md) for the complete automated gate,
real-library smoke procedure, cleanup-coverage map, and recorded baseline.

Common diagnostics are actionable by design:

- `helper-not-found` means an explicit helper override is wrong or an installed
  package is incomplete. The root `pnpm dev` command needs no override.
- `photo-library-access-unavailable` reports the current privacy state. Use
  System Settings > Privacy & Security > Photos to recover from denial.
- `network-access-required` means content is stored in iCloud; retry with
  network access only when downloading it is acceptable.
- `output-file-exists` preserves caller data. Choose another destination or opt
  into overwrite explicitly.
- `helper-platform-unsupported` means the packaged helper is running outside
  its declared Apple Silicon macOS target.

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
bundles and self-discovers the signed arm64 helper. Automated gates and the
repeatable real-library validation procedure cover the complete first slice.

## License

MIT

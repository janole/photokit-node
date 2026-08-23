# photokit-node

Read the current macOS System Photo Library through a typed Node.js API or a
command-line interface. The package can inspect Photos authorization, list
bounded recent metadata, create bounded thumbnails, and export current or
original still-photo content. It never mutates or deletes Photos assets.

## Requirements and installation

The npm package supports:

- An Apple Silicon Mac running macOS 13 or newer.
- Node.js 22 or newer.

Windows, Linux, and Intel Macs are not runtime targets for this release. After
a release is published to npm, install it locally so the CLI and typed API use
the same version:

```bash
npm install photokit-node
```

The npm package includes `PhotoKit Node Helper.app` and discovers its launcher
relative to the installed package. Do not set `PHOTOKIT_NODE_HELPER_PATH` for a
normal installed-package workflow.

## CLI quick start

Read the current authorization state without prompting:

```bash
npx photokit-node authorization status
```

If the state is `not-determined`, request access. macOS presents the Photos
permission prompt for the helper application:

```bash
npx photokit-node authorization request
```

List five recent images as machine-readable metadata, then use one returned
`localIdentifier` to write a thumbnail no larger than 512 by 512 pixels:

```bash
npx photokit-node assets list --limit 5 --media-type image --json
npx photokit-node assets thumbnail "<local-identifier>" \
    --output ./thumbnail.jpg \
    --max-width 512 \
    --max-height 512
```

Human-readable output is the default. `--json` emits one command-specific JSON
value on standard output after success. With `--json`, failures are structured
JSON on standard error. Thumbnail JSON describes the caller-owned output file;
it never embeds image bytes.

## Typed Node quick start

The installed `photokit-node` package exports the typed client and its public
types:

```ts
import { PhotoKitClient } from "photokit-node";

const photos = new PhotoKitClient();
const authorization = await photos.requestAuthorization();

if (authorization.status !== "authorized" && authorization.status !== "limited")
{
    throw new Error(authorization.guidance);
}

const [asset] = await photos.listAssets({ limit: 5, mediaType: "image" });
if (asset)
{
    const thumbnail = await photos.getThumbnail(asset.localIdentifier, {
        maxHeight: 512,
        maxWidth: 512,
    });

    console.log(asset.localIdentifier, thumbnail.bytes.byteLength);
}
```

`requestAuthorization()` prompts only while access is `not-determined`; for a
resolved state it returns that state without prompting again. The client
performs a protocol-version handshake, validates native responses and files,
and throws `PhotoKitError` instances with stable `code`, `operation`, and
optional `details` fields for operational failures.

## Photos authorization and helper identity

macOS grants Photos permission to the native helper application, not to the
calling terminal or Node process. The helper appears as **PhotoKit Node Helper**
and uses the bundle identifier `com.janole.photokit-node.helper`. Launching the
inner executable directly can give macOS the wrong responsible process; use the
package CLI or `PhotoKitClient` instead.

Authorization states have these meanings:

- `authorized`: the helper can read the System Photo Library.
- `limited`: only assets selected for the helper are visible.
- `not-determined`: `authorization request` or `requestAuthorization()` can
  display the system prompt.
- `denied`: macOS will not prompt again. Open System Settings > Privacy &
  Security > Photos and enable **PhotoKit Node Helper**, then retry.
- `restricted`: a system policy prevents access and the helper cannot request
  it. Resolve the applicable device, account, or administrative restriction
  before retrying.

Listing and content operations return `photo-library-access-unavailable` with
exit code 77 unless the state is `authorized` or `limited`.

## Library scope and identifiers

The helper reads the current System Photo Library only. With limited access it
sees only the system-selected subset. Asset listing returns metadata without
requesting image content or downloading iCloud originals, defaults to 20
results, and accepts a maximum limit of 200.

Each `localIdentifier` is an opaque PhotoKit handle scoped to the current photo
library. Pass it back exactly as returned. Do not parse it or treat it as a
portable, permanent identifier across libraries, devices, or library resets.

## Thumbnails, exports, and file ownership

Thumbnail dimensions must be between 1 and 4096 pixels. The returned image fits
within the requested width and height bounds; `aspect-fit` preserves the whole
image while `aspect-fill` may crop to fill the bounds. JPEG is the default, and
PNG is also supported. Thumbnails can be created from image and video assets.

The CLI writes a thumbnail to the exact path supplied with `--output`; that file
belongs to the caller. It refuses an existing path unless `--overwrite` is
present. The Node client instead returns thumbnail bytes and metadata, then
always removes its private temporary file.

Still-photo export requires an existing caller-owned destination directory and
an explicit representation:

```bash
mkdir -p ./exports
npx photokit-node assets export "<local-identifier>" \
    --output-directory ./exports \
    --version current
```

- `current` exports the largest rendered representation, including edits shown
  in Photos.
- `original` copies the primary still-photo resource without transcoding.

Exports support image assets and the still component of Live Photos. Video and
Live Photo motion export are not supported. Completed exports belong to the
caller and remain in the destination directory. Existing files are preserved
unless `--overwrite` or `overwrite: true` is explicit.

## iCloud retrieval is opt-in

Content access is local-only by default. An iCloud-only thumbnail or export
fails with `network-access-required` rather than downloading silently. Retry
with `--allow-network` in the CLI or `allowNetworkAccess: true` in that one Node
operation only when network retrieval is acceptable:

```bash
npx photokit-node assets thumbnail "<local-identifier>" \
    --output ./thumbnail.jpg \
    --max-width 512 \
    --max-height 512 \
    --allow-network
```

Network-backed operations can take longer. `PhotoKitClient` defaults content
operations to 120 seconds; configure `contentTimeoutMs` on the client or
`timeoutMs` on an individual content operation when necessary.

## CLI reference

```text
photokit-node authorization status [--json]
photokit-node authorization request [--json]
photokit-node assets list [--limit 20] [--media-type image|video] [--json]
photokit-node assets thumbnail <local-identifier> --output <path> --max-width <pixels> --max-height <pixels> [--format jpeg|png] [--content-mode aspect-fit|aspect-fill] [--allow-network] [--overwrite] [--json]
photokit-node assets export <local-identifier> --output-directory <path> --version current|original [--allow-network] [--overwrite] [--json]
photokit-node protocol-version
```

Stable exit codes distinguish usage (64), missing assets or unsupported media
(66), unavailable helpers or network content (69), native or protocol failures
(70), output collisions or write failures (73), cancellation or timeout (75),
Photos authorization (77), and protocol mismatch (78).

## Node API

`PhotoKitClient` accepts optional construction settings:

- `operationTimeoutMs`: deadline for metadata and authorization operations.
- `contentTimeoutMs`: default deadline for thumbnails and exports.
- `maxOutputBytes`: maximum native JSON response size.
- `helperPath`: explicit helper executable used only for a source checkout or
  controlled testing.

Its read-only operations are:

- `authorizationStatus()` and `requestAuthorization()`.
- `listAssets({ limit, mediaType })`.
- `getThumbnail(localIdentifier, { maxWidth, maxHeight, format, contentMode,
  allowNetworkAccess, timeoutMs })`.
- `exportPhoto(localIdentifier, { destinationDirectory, version, overwrite,
  allowNetworkAccess, timeoutMs })`.

## Source checkout

Repository development is a separate helper-discovery flow. It additionally
requires Xcode Command Line Tools and pnpm 10.33.3:

```bash
git clone https://github.com/janole/photokit-node.git
cd photokit-node
pnpm install
pnpm run native:build
pnpm dev authorization status
pnpm dev assets list --limit 5 --media-type image --json
```

The root `pnpm dev` script supplies
`native/photokit-helper/scripts/run.sh` as the source helper. A Node program run
directly from the checkout must construct `PhotoKitClient` with an absolute
`helperPath` to that script. `PHOTOKIT_NODE_HELPER_PATH` is a development CLI
override; it is not part of normal installed-package discovery.

## Troubleshooting

- `helper-not-found`: an explicit development override is wrong, or an
  installed package is incomplete. Remove the override for installed use.
- `helper-platform-unsupported`: the runtime is not Apple Silicon macOS.
- `photo-library-access-unavailable`: follow the returned authorization
  guidance; denied access is changed in System Settings, while restricted
  access must be resolved at the policy level.
- `network-access-required`: the asset content is in iCloud. Opt into network
  access only if downloading it is acceptable.
- `output-file-exists`: choose another caller-owned destination or opt into
  overwrite explicitly.
- `unsupported-media`: the selected asset does not support that content
  operation.

For repository validation and real-library smoke procedures, see the
[validation guide](https://github.com/janole/photokit-node/blob/main/docs/validation.md).

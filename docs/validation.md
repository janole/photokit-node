# Validation

This checklist validates the read-only PhotoKit slice without modifying or
deleting Photos assets. The commands write only to an explicit temporary
directory outside the System Photo Library.

## Automated gates

Run every gate from the repository root:

```bash
pnpm run ok
pnpm run qa
pnpm run native:test
pnpm run package:smoke
```

The automatic Linux workflow runs `pnpm run qa` and exercises the Node protocol
fixtures without requiring PhotoKit. The opt-in macOS workflow runs the Swift
tests, builds and signs the helper, verifies the npm artifact, and launches an
installed package from an unrelated directory. Trigger it from the Actions tab
or add the `ci:native` label to a pull request.

Cleanup coverage is split at the ownership boundary:

- `packages/core/test/client.test.ts` proves Node-owned thumbnail directories
  are removed after success, native errors, malformed responses, invalid file
  descriptors, helper crashes, and timeouts.
- `native/photokit-helper/Tests/PhotoKitProtocolTests/ThumbnailTests.swift` and
  `PhotoExportTests.swift` prove cancellation is rejected before filesystem
  placement and that partial files are removed after write failures.
- Protocol fixtures cover denied authorization, empty asset lists,
  iCloud-required content, cancellation, and write failures without accessing a
  real Photos library.

## Real-library smoke

These commands use the source-tree helper automatically. Start with an
authorized, non-empty System Photo Library and copy an image `localIdentifier`
from the JSON listing:

```bash
pnpm dev authorization status
pnpm dev assets list --limit 5 --media-type image --json

VALIDATION_DIR=$(mktemp -d "${TMPDIR:-/tmp}/photokit-node-validation.XXXXXX")
ASSET_ID='<local-identifier>'
mkdir "$VALIDATION_DIR/current" "$VALIDATION_DIR/original"

pnpm dev assets thumbnail "$ASSET_ID" \
    --output "$VALIDATION_DIR/thumbnail.jpg" \
    --max-width 512 \
    --max-height 512
pnpm dev assets export "$ASSET_ID" \
    --output-directory "$VALIDATION_DIR/current" \
    --version current
pnpm dev assets export "$ASSET_ID" \
    --output-directory "$VALIDATION_DIR/original" \
    --version original
```

Inspect the three files before removing the temporary directory. The thumbnail
must stay within 512 by 512 pixels. `current` is the rendered representation
visible in Photos and can include edits; `original` is the primary still-photo
resource copied without transcoding.

Repeat one output command without `--overwrite`. It must preserve the existing
file, report `output-file-exists`, and exit with status 73. Adding `--overwrite`
must replace the output explicitly.

### Authorization states

`authorization request` prompts only from `not-determined`. Resetting or
revoking the helper's permission changes machine privacy state, so do this only
when that disruption is acceptable:

```bash
tccutil reset Photos com.janole.photokit-node.helper
pnpm dev authorization status
pnpm dev authorization request
```

The status must first be `not-determined`; the request must show the macOS
Photos dialog; and the selected result must persist in a subsequent status
command. To validate denial, disable the helper under System Settings > Privacy
& Security > Photos, then confirm that asset listing reports
`photo-library-access-unavailable` with exit status 77. Restore the intended
permission afterwards.

An authorized query with no matching accessible assets must succeed with an
empty `assets` array. A media-type filter absent from the accessible library is
enough to exercise this without changing the library.

### iCloud-only content

Use an asset whose original is not stored locally. A thumbnail or export
without `--allow-network` must return `network-access-required` with exit status
69 and must not leave output behind. Repeating with `--allow-network` opts into
an iCloud download and can take substantially longer:

```bash
pnpm dev assets export '<icloud-local-identifier>' \
    --output-directory "$VALIDATION_DIR/original" \
    --version original
pnpm dev assets export '<icloud-local-identifier>' \
    --output-directory "$VALIDATION_DIR/original" \
    --version original \
    --allow-network
```

If the library has no known offloaded asset, record that environmental limit;
do not infer iCloud behavior from a locally available export.

## Recorded baseline

The final source-tree validation ran on 2026-08-22 against a real System Photo
Library on Apple Silicon macOS:

- The stable helper identity reached the first macOS authorization prompt, and
  the final source and installed-package commands returned persisted
  `authorized` status.
- Listing returned non-empty image and video results; the selected image was
  4032 by 3024 pixels.
- The CLI produced a visually verified 512 by 384 JPEG thumbnail containing
  97,281 bytes.
- `current` and `original` each produced a visually valid 4032 by 3024 JPEG
  containing 3,285,048 bytes for the selected unedited image.
- Repeating the thumbnail command preserved the existing file, returned
  `output-file-exists`, and exited with status 73.
- A freshly packed npm CLI found and launched its bundled signed arm64 helper
  without a helper-path override or working-directory assumption.

Denied authorization, a real empty-library result, and a genuinely offloaded
iCloud asset remain environment-dependent checks. Record them when the local
library can represent those states; deterministic fixtures keep their protocol
and error semantics in the automatic gates.

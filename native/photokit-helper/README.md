# photokit-helper

The native macOS process that owns PhotoKit access for `photokit-node`. The
repository build wraps the executable in a lightweight app bundle so macOS can
track its Photos permission independently of the terminal or parent process.

It accepts exactly one JSON request argument, writes exactly one JSON response
to standard output, and reserves standard error for diagnostics. Every request
and response carries `protocolVersion` and `operation`, plus `parameters`,
success data, or a structured error as appropriate.

Build the permission-capable helper first, then launch it through macOS Launch
Services:

```bash
pnpm run native:build
pnpm run native:run -- '{"protocolVersion":1,"operation":"version","parameters":{}}'
pnpm run native:run -- '{"protocolVersion":1,"operation":"authorization-status","parameters":{}}'
pnpm run native:run -- '{"protocolVersion":1,"operation":"authorization-request","parameters":{}}'
pnpm run native:run -- '{"protocolVersion":1,"operation":"list-assets","parameters":{"limit":20,"mediaType":"image"}}'
pnpm run native:run -- '{"protocolVersion":1,"operation":"get-thumbnail","parameters":{"assetIdentifier":"<local-identifier>","maxWidth":512,"maxHeight":512,"outputPath":"/tmp/photokit-thumbnail.jpg"}}'
pnpm run native:run -- '{"protocolVersion":1,"operation":"export-photo","parameters":{"assetIdentifier":"<local-identifier>","destinationDirectory":"/tmp/photokit-exports","version":"current"}}'
pnpm run native:run -- '{"protocolVersion":1,"operation":"export-photo","parameters":{"assetIdentifier":"<local-identifier>","destinationDirectory":"/tmp/photokit-exports","version":"original","allowNetworkAccess":true}}'
```

Launch Services makes the helper the responsible application for macOS privacy
checks. Running the inner executable directly from a terminal can instead
report the terminal application's Photos permission.

The `authorization-status` operation reads the current Photos permission without
prompting. `authorization-request` prompts only when the status is
`not-determined`; for resolved states it returns the existing status. Denied and
restricted responses include guidance explaining why the helper cannot prompt
again.

## Recent asset metadata

The `list-assets` operation returns recent image and video metadata, newest
creation date first. Returned assets with equal dates are ordered by local
identifier. Its parameters are:

- `limit`: optional integer from 1 through 200; defaults to 20.
- `mediaType`: optional `"image"` or `"video"`; omitting it includes both.

The response includes the local identifier, media type and named subtype flags,
nullable ISO-8601 creation/modification dates, dimensions, video duration,
favorite state, and hidden state. Local identifiers are opaque handles scoped
to the current photo library; do not persist them as cross-library asset IDs.

The fetch uses `PHAsset` metadata only. It does not request thumbnails, image
bytes, asset resources, or content-editing input, so iCloud originals are not
downloaded. The helper asks PhotoKit to include hidden assets, but the system can
still withhold them according to the user's hidden-album privacy setting.

Listing succeeds for `authorized` and `limited` access (the latter returns only
assets available to the app). Other authorization states return
`photo-library-access-unavailable` with status details and exit code 77; the
operation never prompts. An accessible library with no matching assets instead
returns a successful response with an empty `assets` array.

## Asset content transfer contract

Protocol version 1 defines `get-thumbnail` and `export-photo` as out-of-band
file operations. Their JSON responses describe the completed file—path,
filename, byte length, content type, uniform type identifier, dimensions, and
representation—but never contain image bytes or base64 data.

Thumbnail requests accept absolute output paths, dimensions from 1 through
4096 pixels, aspect-fit or aspect-fill content mode, and JPEG or PNG encoding.
Photo exports accept an absolute destination directory and an explicit
`current` or `original` representation. Both operations disable iCloud network
access and output replacement by default; callers must opt in explicitly.

Stable content failures distinguish missing assets, unsupported media, required
network access, cancellation, existing output, and write failures. Process
timeouts remain a typed Node runner failure because a terminated helper cannot
write a final protocol response.

`get-thumbnail` is implemented for image and video assets. It requests the
current edited representation from PhotoKit with high-quality exact sizing,
ignores degraded callbacks, renders aspect-fit or aspect-fill output, and
encodes JPEG by default or PNG when requested. Dimensions are bounded by the
request, and output is placed atomically at the supplied path.

Local-only access and collision refusal are the defaults. Set
`allowNetworkAccess` to `true` to permit iCloud retrieval and `overwrite` to
`true` to replace an existing output. Failed, cancelled, or interrupted writes
remove partial files.

`export-photo` supports image assets and the still component of Live Photos;
video assets and Live Photo paired video are not exported. `current` requests
the largest rendered representation from PhotoKit, so edits made in Photos are
reflected. `original` copies the primary still-photo resource bytes without
transcoding. The destination directory must already exist. Original exports
preserve a safe original filename, while rendered exports append `-current`
and use the returned content type's preferred extension.

PhotoKit data is collected before filesystem placement begins. The completed
bytes are then written to a unique partial file in the destination directory
and atomically placed at the final path, so request cancellation, timeout, or
PhotoKit failure cannot expose a partial destination. Existing files remain
unchanged unless `overwrite` is explicitly enabled.

Successful responses use this envelope:

```json
{
  "data": {
    "protocolVersion": 1
  },
  "operation": "version",
  "protocolVersion": 1,
  "success": true
}
```

Malformed requests, unknown operations, and incompatible versions return
`success: false` with a stable `error.code`. Incompatible versions use exit code
78; authorization failures use exit code 77; other request errors use exit code
64. Unexpected native failures use exit code 70. The response envelope itself
always states the helper's protocol version so callers can diagnose mismatches
explicitly.

## Stable development identity

The repository build embeds the Photos privacy usage description, creates an
app bundle, and assigns it the stable identifier
`com.janole.photokit-node.helper`.

Local builds use an ad-hoc signature with a fixed designated requirement. This
keeps the helper's development identity stable across normal rebuilds, but it
does not establish publisher trust and should not be distributed. Set
`PHOTOKIT_CODE_SIGN_IDENTITY` to an Apple Development or Developer ID identity
for cryptographically stable development or distribution signing.

The first `authorization-request` for this identity shows the macOS Photos
prompt. The choice persists for subsequent status and request commands. To
change a denied choice, open System Settings > Privacy & Security > Photos.

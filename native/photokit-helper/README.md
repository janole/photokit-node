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
```

Launch Services makes the helper the responsible application for macOS privacy
checks. Running the inner executable directly from a terminal can instead
report the terminal application's Photos permission.

The `authorization-status` operation reads the current Photos permission without
prompting. `authorization-request` prompts only when the status is
`not-determined`; for resolved states it returns the existing status. Denied and
restricted responses include guidance explaining why the helper cannot prompt
again.

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
78; other request errors use exit code 64. Unexpected native failures use exit
code 70. The response envelope itself always states the helper's protocol
version so callers can diagnose mismatches explicitly.

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

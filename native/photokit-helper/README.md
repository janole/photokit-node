# photokit-helper

The native macOS process that owns PhotoKit access for `photokit-node`. The
repository build wraps the executable in a lightweight app bundle so macOS can
track its Photos permission independently of the terminal or parent process.

It writes one JSON response to standard output and diagnostics to standard
error. The initial commands are:

Build the permission-capable helper first, then launch it through macOS Launch
Services:

```bash
pnpm run native:build
pnpm run native:run -- version
pnpm run native:run -- authorization-status
pnpm run native:run -- authorization-request
```

Launch Services makes the helper the responsible application for macOS privacy
checks. Running the inner executable directly from a terminal can instead
report the terminal application's Photos permission.

`authorization-status` reads the current Photos permission without prompting.
`authorization-request` prompts only when the status is `not-determined`; for
resolved states it returns the existing status. Denied and restricted responses
include guidance explaining why the helper cannot prompt again.

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

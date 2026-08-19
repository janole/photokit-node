# photokit-node CLI

`photokit-node` is the thin Commander-based command-line interface over
`@photokit-node/core`. It can inspect/request Photos authorization, list recent
assets, write bounded thumbnails, and export current or original still-photo
content.

```text
photokit-node authorization status [--json]
photokit-node authorization request [--json]
photokit-node assets list [--limit 20] [--media-type image|video] [--json]
photokit-node assets thumbnail <local-identifier> --output <path> --max-width <pixels> --max-height <pixels> [--format jpeg|png] [--content-mode aspect-fit|aspect-fill] [--allow-network] [--overwrite] [--json]
photokit-node assets export <local-identifier> --output-directory <path> --version current|original [--allow-network] [--overwrite] [--json]
photokit-node protocol-version
```

Human-readable output is the default. `--json` prints only a command-specific
JSON value on success; thumbnail JSON contains the final path and metadata but
never embeds image bytes. Failures use JSON on stderr when `--json` is active.

Network retrieval and replacement are disabled by default. Thumbnail writes
refuse an existing output unless `--overwrite` is present. Photo exports pass
the same explicit collision policy to the native helper.

Until native npm packaging is complete, repository development can point the
CLI at its executable helper launcher:

```bash
export PHOTOKIT_NODE_HELPER_PATH="$PWD/native/photokit-helper/scripts/run.sh"
pnpm dev authorization status
pnpm dev assets list --limit 20 --media-type image
```

Exit codes follow the native helper's sysexits-style contract:

| Code | Meaning |
| ---: | --- |
| 64 | Invalid CLI or protocol usage |
| 66 | Asset not found or unsupported media |
| 69 | Helper/content unavailable or network access required |
| 70 | Native, protocol-response, or process failure |
| 73 | Output exists or cannot be written |
| 75 | Operation cancelled or timed out |
| 77 | Photos authorization unavailable |
| 78 | Incompatible protocol version |

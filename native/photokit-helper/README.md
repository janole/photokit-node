# photokit-helper

The native macOS process that owns PhotoKit access for `photokit-node`.

It writes one JSON response to standard output and diagnostics to standard
error. The initial commands are:

```bash
swift run --package-path native/photokit-helper photokit-helper version
swift run --package-path native/photokit-helper photokit-helper authorization-status
```

`authorization-status` reads the current Photos permission without prompting.

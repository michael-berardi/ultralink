# Contributing

Issues and focused pull requests are welcome.

## Checks

Run the standalone decoder unit tests (no dish or app launch required):

```sh
tests/unit.sh
```

For a compile-only release check on macOS (Xcode / Swift 5.9+):

```sh
swift build -j 4 -c release --arch arm64 --arch x86_64 -Xswiftc -Osize
```

Checks run locally; this repository does not use GitHub Actions workflows.

## Ground rules

- Keep dish communication strictly read-only; never send mutating or configuration requests to the dish.
- Reject malformed or overflowing protobuf frames explicitly rather than crashing or accepting truncated values.
- Keep history local and preserve privacy (no telemetry or cloud upload of dish readings).
- Do not commit signing identities, notarization credentials, or local build output.

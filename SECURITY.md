# Security Policy

## Scope

UltraLink is a read-only macOS menu bar monitor for Starlink dishes on the local network. It requires no account, uploads no dish readings, and never writes dish settings.

Security-relevant surfaces include:

- Protobuf / gRPC-web decoding of untrusted responses from the configured dish endpoint (`192.168.100.1:9201` by default).
- Local history persistence under Application Support (`UltraLink/history.json`).
- Sparkle update feed verification against GitHub Releases and optional macOS `networkQuality` speed tests.

## Reporting a Vulnerability

Please report security issues privately through GitHub's
[security advisories](https://github.com/michael-berardi/ultralink/security/advisories/new)
rather than opening a public issue. Include the version, macOS release, and reproduction steps.

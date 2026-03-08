# OpenClaw tvOS

This Apple TV app is the minimal tvOS chat surface for OpenClaw.

## Scope

- manual gateway connection only
- persisted reconnect
- chat history, send, stream, abort
- session switching

Not in scope for this MVP:

- discovery
- setup-code import
- node/device features
- talk, voice wake, canvas, onboarding

## Local Run

1. Install prerequisites:
   - Xcode 16+
   - `pnpm`
   - `xcodegen`
2. From repo root:

```bash
pnpm install
pnpm tvos:open
```

3. In Xcode:
   - Scheme: `OpenClawTV`
   - Destination: Apple TV simulator or device
   - Configuration: `Debug`
   - Run

If signing fails on a personal team, start from `apps/tvos/LocalSigning.xcconfig.example`.

# UntrashApp

The phone companion of UntrashOS: pair with your NAS by QR code, reach it
through its own WireGuard tunnel (UntrashMesh) and confirm Desk sign-ins and
admin actions on the phone (number matching).

The contract with the NAS is `docs/architecture/app-api.md` in the UntrashOS
repository (API version 1). This app implements it.

## Layout

| Path | What |
|---|---|
| `lib/protocol/` | the protocol, no Flutter: canonical JSON, keys, mesh addresses, join, roster/address book, sync, signed Desk requests |
| `lib/app/` | app state (`model.dart`), key store, tunnel interface |
| `lib/ui/` | screens (German/English) in the Untrash look |
| `android/.../MeshTunnel.kt` | the tunnel on the official WireGuard library (`com.wireguard.android:tunnel`, VpnService) |
| `tool/nas_fixture.py`, `tool/desk_fixture.py` | the real `untrash-mesh` / `untrash-desk` in their PC test modes, for the tests |

## Tests

```bash
flutter test
```

- `protocol_test.dart`: canonical JSON, HMAC, IPv6 text and mesh addresses
  against Python and `untrash-mesh` itself; RFC 8032/7748 key vectors;
  roster/record rules.
- `nas_mesh_test.dart`: join, roster/records both ways, gossip and removal
  against a running `untrash-mesh`.
- `nas_desk_test.dart`, `app_model_test.dart`: pairing through the Desk,
  signed requests as the linked user, sign-in without password and with two
  factors, wrong number denies, restart keeps the pairing.

The integration tests need the UntrashOS checkout (default
`~/Projects/UntrashOS-v1.1/untrashos`, or `UNTRASHOS_DIR`), `python3` and
`gcc`. Without it they are skipped.

## Development on the desktop (no tunnel)

```bash
python3 tool/desk_fixture.py          # prints invitation, desk and sync ports
UNTRASH_STORE=memory UNTRASH_PORTMAP='{"80":"127.0.0.1:DESK","7340":"127.0.0.1:SYNC"}' flutter run -d linux
```

Paste the invitation. The desktop build has no tunnel and no QR scanner.

## State of version 1

- Android: pairing (QR or paste), tunnel, sync, requests, confirmations,
  NAS overview for admins. Polls while the app is in the foreground (no
  push yet: `/v1/app-notify` needs a listener in the background).
- iOS: the code builds on the same protocol, but the tunnel needs a
  NetworkExtension (WireGuardKit) and a Mac to build. Not done.
- Not yet: HTTPS with a pinned certificate when the NAS forces HTTPS, file
  browsing, background notifications.

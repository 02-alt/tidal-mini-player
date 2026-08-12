# Local signing (so the Accessibility grant survives rebuilds)

Background TIDAL control (pressing TIDAL's Playback menu when it doesn't own the
Now Playing slot) needs the macOS **Accessibility** permission. macOS ties that
grant to the app's code signature. An **ad-hoc** signature gets a new hash on
every build, so macOS forgets the permission each time you rebuild.

The fix is to sign with a **stable local identity** (a self-signed code-signing
certificate). `build.sh` uses it automatically if it's installed, and falls back
to ad-hoc otherwise.

## Create the identity (one time)

```bash
CN="Tidal Mini Player Local Signing"
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 3650 -nodes -subj "/CN=$CN" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -inkey key.pem -in cert.pem -out identity.p12 -passout pass:tmp -name "$CN"
security import identity.p12 -k ~/Library/Keychains/login.keychain-db -P tmp -A -T /usr/bin/codesign
```

The certificate is **untrusted** (self-signed) — that's fine; signing doesn't
require trust, and the app's *designated requirement* becomes stable:

```
identifier "com.local.tidalminiplayer" and certificate leaf = H"…"
```

Because that requirement no longer depends on the code hash, the Accessibility
grant persists across rebuilds.

## Remove it

Delete the "Tidal Mini Player Local Signing" certificate in **Keychain Access**
(login keychain). `build.sh` then reverts to ad-hoc signing.

> Note: this is a *local development* convenience. Shipping to other people still
> needs a real Developer ID signature + notarization for Gatekeeper.

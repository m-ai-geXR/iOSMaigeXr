# Vendor Assets

Local copies of the web libraries the playgrounds can load without a network
round trip. They are served to `WKWebView` through the custom `app://` URL
scheme, handled by
[../BuildKit/WKAppURLSchemeHandler.swift](../BuildKit/WKAppURLSchemeHandler.swift),
which maps request paths onto filenames in this directory.

Both `app://vendor/<file>` and `app://<file>` resolve here.

---

## ⚠️ Current state: partially broken

**This directory does not currently hold a working set of libraries, and the
scheme handler maps several filenames that are not here at all.** Audit the
directory before relying on the local vendor path; anything routed through the
CDN or the CodeSandbox/Sandpack build path is unaffected.

### Real files

| File | Size | Notes |
|---|---|---|
| `three-r160.module.js` | 1.2 MB | Three.js r160 — genuine |
| `react-dom-18.2.0.min.js` | 129 KB | genuine |
| `react-18.2.0.min.js` | 10 KB | genuine |
| `jszip.min.js` | 95 KB | scene save/export |
| `playground-utils.js` | 18 KB | shared playground helpers |
| `react-three-fiber-esm.js` | 887 B | Skypack ESM shim, pinned to R3F 9.3.0 |
| `drei-esm.js` | 882 B | Skypack ESM shim, pinned to drei 10.7.6 |

### Failed downloads saved as `.js`

These are **not libraries**. Each is a CDN error or redirect message that got
written to disk with a `.js` extension, so loading one executes nothing useful:

| File | Actual contents |
|---|---|
| `babylonjs-6.0.0.js` | `Not found: /@babylonjs/core@6.0.0/lib/babylon.js` |
| `drei-9.88.13.js` | `Not found: /@react-three/drei@9.88.13/dist/index.umd.js` |
| `react-three-fiber-8.15.12.js` | `Not found: /@react-three/fiber@8.15.12/dist/index.umd.js` |
| `drei-latest.js` | `Redirecting to /@react-three/drei@10.7.6/dist/index.js` |
| `react-three-fiber-latest.js` | `Redirecting to /@react-three/fiber@9.3.0/dist/index.js` |
| `reactylon-1.0.0.js` | `Redirecting to /reactylon@3.1.5/dist/index.js` |

### Mapped but absent

`WKAppURLSchemeHandler` has entries pointing at these filenames, none of which
exist in this directory:

- `react-19.1.1.min.js`, `react-dom-19.1.1.min.js`
- `three-r171.module.js` — note `/vendor/three.module.js` maps here, so the
  generic Three.js path resolves to a missing file while `three-r160.module.js`
  sits unused
- `react-three-fiber-8.17.10.js`
- `drei-9.127.3.js`
- `babylonjs-8.22.3.js` — including the generic `/vendor/babylonjs.js`
- `aframe-1.7.0.min.js` — including the generic `/vendor/aframe.js`

---

## Repopulating

To fetch the versions the scheme handler expects, from this directory:

```bash
# React 19
curl -fL -o react-19.1.1.min.js       https://unpkg.com/react@19.1.1/umd/react.production.min.js
curl -fL -o react-dom-19.1.1.min.js   https://unpkg.com/react-dom@19.1.1/umd/react-dom.production.min.js

# Three.js r171
curl -fL -o three-r171.module.js      https://unpkg.com/three@0.171.0/build/three.module.js

# React Three Fiber + drei
curl -fL -o react-three-fiber-8.17.10.js https://unpkg.com/@react-three/fiber@8.17.10/dist/index.umd.js
curl -fL -o drei-9.127.3.js              https://unpkg.com/@react-three/drei@9.127.3/dist/index.umd.js

# Babylon.js 8
curl -fL -o babylonjs-8.22.3.js       https://unpkg.com/babylonjs@8.22.3/babylon.js

# A-Frame
curl -fL -o aframe-1.7.0.min.js       https://unpkg.com/aframe@1.7.0/dist/aframe-master.min.js
```

**Use `-f`.** The placeholder files above exist precisely because `curl` without
`-f` writes the server's 404 body to the output file and exits successfully. With
`-f` a missing artifact fails loudly instead.

Then sanity-check what you got — a real library is not 50 bytes:

```bash
ls -l *.js
```

Not every version above is guaranteed to be published at that exact path on
unpkg. If one 404s, pick the nearest published version and update the mapping
rather than leaving a stub behind.

---

## Updating a version

1. Download the new file with `-f` and confirm its size
2. Update `vendorMappings` in
   [../BuildKit/WKAppURLSchemeHandler.swift](../BuildKit/WKAppURLSchemeHandler.swift) —
   both the versioned path and the generic alias (e.g. `/vendor/babylonjs.js`)
3. Update the build configuration in `../BuildKit/WasmBuildService.swift`
4. Delete the superseded file so a stale version cannot be served
5. Re-test a React Three Fiber scene and a Reactylon scene

---

## Notes

- Responses are served with long-lived cache headers, so `WKWebView` caches
  these aggressively. Delete the app from the simulator after swapping a file,
  or you may keep getting the old one.
- The point of vendoring is that a generated scene resolves its imports locally
  instead of reaching the network. Every stub in this directory quietly defeats
  that for its library.

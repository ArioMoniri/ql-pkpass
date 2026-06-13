<div align="center">

![pkpass Quick Look](docs/assets/hero.svg)

# pkpass Quick Look

**Peek inside Apple Wallet passes from Finder — just hit the Space bar.**

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-111?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5%20%2F%206-f05138?logo=swift&logoColor=white)
![Quick Look](https://img.shields.io/badge/Quick%20Look-preview%20%2B%20thumbnail-1a82dc)
![No dependencies](https://img.shields.io/badge/dependencies-zero-2ea44f)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

</div>

A `.pkpass` file is just a zipped-up Apple Wallet pass — a boarding pass, a coffee loyalty card, a concert ticket. macOS has no idea how to show you one without opening Wallet or unzipping it by hand. This fixes that.

Select a pass in Finder, press <kbd>Space</kbd>, and you get a proper Wallet-style card: the right colours, the logo, the fields, a scannable barcode, and the small print on the back. Finder shows a card thumbnail for it too. Everything is rendered on your Mac — **no network calls, ever.**

> 🎬 **See it move:** the card below is a live animated SVG (it plays right here on GitHub). For the full thing — Lottie and Rive running in the browser — open the **[live demo page](https://ariomoniri.github.io/ql-pkpass/)**.

<div align="center">

<img src="docs/assets/pass-card.svg" alt="Animated boarding pass preview" width="320">

</div>

---

## ⚡ Install

You'll need macOS 12 or newer and Xcode installed (it ships the build tools). Then:

```bash
git clone https://github.com/ArioMoniri/ql-pkpass.git
cd ql-pkpass
make install
```

That builds the app, drops it in `/Applications`, and refreshes Quick Look. Now click any `.pkpass` in Finder and tap <kbd>Space</kbd>.

Want to try it immediately? There's a sample pass in the repo:

```bash
open examples/Skyline-BoardingPass.pkpass   # or just select it in Finder and press Space
```

<details>
<summary>🔧 Prefer to do it by hand (or no <code>make</code>)?</summary>

<br>

```bash
# 1. Build a Release copy of the app (ad-hoc signed, no Apple account needed)
xcodebuild build -scheme PkpassQuickLook -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-"

# 2. Move it into place
cp -R build/Build/Products/Release/PkpassQuickLook.app /Applications/

# 3. Tell macOS it exists and reset Quick Look
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/PkpassQuickLook.app
qlmanage -r && qlmanage -r cache
```

Or just open `PkpassQuickLook.xcodeproj` in Xcode and hit ▶︎ once — running the host app registers the extensions.

</details>

<details>
<summary>🧹 Uninstall</summary>

<br>

```bash
make uninstall      # removes the app and refreshes Quick Look
```

</details>

---

## 👀 What you'll see

The preview adapts to whatever style the pass declares — boarding pass, event ticket, coupon, store card, or generic.

| Part of the pass | What the plugin does with it |
| --- | --- |
| 🎨 Colours | Uses the pass's own `backgroundColor` / `foregroundColor` / `labelColor` |
| 🏷️ Logo & header | Shows the logo image (or `logoText`) plus gate/flight-style header fields |
| ✈️ Primary fields | Big origin → destination for boarding passes, with a transit icon |
| 🔖 Secondary / auxiliary | Passenger, seat, balance, expiry… laid out like the real card |
| 🔳 Barcode | Re-rendered crisply with Core Image — QR, PDF417, Aztec, Code 128 |
| 📋 Back of pass | The fine print, with real links made clickable |
| ℹ️ Pass info & raw JSON | Collapsible panels for serial number, IDs, signature status, and the raw `pass.json` |

<details>
<summary>📸 Boarding pass, store card, event ticket — they all just work</summary>

<br>

The renderer keys off the top-level style object in `pass.json` (`boardingPass`, `storeCard`, `eventTicket`, `coupon`, or `generic`) and arranges the fields the way Wallet would. Event tickets even use the `background.png` as a full-bleed backdrop behind the card. Try editing `examples/Skyline-BoardingPass.pkpass` (it's just a zip) and re-previewing.

</details>

---

## 🧠 How it actually works

<details>
<summary>The short version</summary>

<br>

Old-school `.qlgenerator` plugins are dead on modern macOS. So this is a **modern Quick Look App Extension** — actually two of them, bundled inside a tiny host app:

- **`PkpassPreviewExtension`** — a `QLPreviewProvider` that returns a self-contained HTML card (images and barcode inlined as base64, so nothing is fetched).
- **`PkpassThumbnailExtension`** — a `QLThumbnailProvider` that draws the Finder thumbnail.

Both talk to **`PkpassKit`**, a dependency-free Swift framework that does the real work.

</details>

<details>
<summary>The one gotcha that trips everyone up 🪤</summary>

<br>

A `.pkpass` file on disk is **not** the UTI you'd guess. `com.apple.pkpass` is the *package* type (an installed pass directory). An actual file is **`com.apple.pkpass-data`** (it conforms to `public.data`, not to `com.apple.pkpass`). If your extension only registers `com.apple.pkpass`, it builds and installs fine and then silently never fires.

So both extensions register **both** types. (Found this the hard way; saving you the afternoon.)

</details>

<details>
<summary>Why there's a hand-written zip reader 📦</summary>

<br>

A pass is a ZIP archive, but pulling in a third-party zip library for a sandboxed Quick Look extension felt heavy. macOS already ships the `Compression` framework, and its `COMPRESSION_ZLIB` mode decodes raw DEFLATE — which is exactly what ZIP method 8 uses. So `MiniZip.swift` reads the central directory itself and inflates entries with system frameworks only. Zero external dependencies, nothing to resolve, nothing to audit but our own ~180 lines.

</details>

---

## 🛠️ Build & develop

```bash
make test       # run the unit tests
make build      # build app + both extensions
make sample     # regenerate examples/Skyline-BoardingPass.pkpass
make project    # regenerate the .xcodeproj from project.yml (needs xcodegen)
```

The project is defined in [`project.yml`](project.yml) and generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), but the resulting `.xcodeproj` is committed so you can build without it.

<details>
<summary>🧪 Tests & TDD</summary>

<br>

`PkpassKit` was built test-first with Swift Testing. The suite spins up **real** `.pkpass` archives with `/usr/bin/zip` (covering both DEFLATE and stored entries) and checks the zip reader, the `pass.json` model (including the awkward "field values can be strings *or* numbers" cases), colour parsing, barcode generation, the HTML renderer (fields present, HTML escaped, URLs linkified), and the thumbnail drawing path.

```bash
xcodebuild test -scheme PkpassKit -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

</details>

<details>
<summary>🗂️ Project layout</summary>

<br>

```
Sources/
  PkpassKit/            # the engine: zip reader, model, renderers (no UI, no deps)
  App/                  # host app — explains the plugin, refreshes Quick Look
  PreviewExtension/     # QLPreviewProvider  → the Space-bar HTML preview
  ThumbnailExtension/   # QLThumbnailProvider → Finder thumbnails
Tests/PkpassKitTests/   # Swift Testing unit tests
scripts/                # install / uninstall / build / sample generator
docs/                   # GitHub Pages live demo (Lottie + Rive + animated SVG)
examples/               # a ready-to-try sample pass
project.yml             # XcodeGen project definition
```

</details>

---

## 🩹 Troubleshooting

<details>
<summary>Pressing Space does nothing / I still see a generic icon</summary>

<br>

1. Make sure the app is in `/Applications` and has been registered:
   ```bash
   pluginkit -m -p com.apple.quicklook.preview | grep -i pkpass
   ```
   You should see `com.ariomoniri.PkpassQuickLook.Preview`.
2. Reset Quick Look and relaunch Finder:
   ```bash
   qlmanage -r && qlmanage -r cache && killall Finder
   ```
3. Open `PkpassQuickLook.app` once — the host app has a **Refresh Quick Look** button.
4. Test rendering directly from the terminal:
   ```bash
   qlmanage -p examples/Skyline-BoardingPass.pkpass
   ```

</details>

<details>
<summary>"PkpassQuickLook can't be opened because Apple cannot check it"</summary>

<br>

That's Gatekeeper reacting to the ad-hoc signature on a locally-built app. Right-click the app → **Open**, or run `xattr -dr com.apple.quarantine /Applications/PkpassQuickLook.app`. Building it yourself (as you did) is the trusted path here.

</details>

<details>
<summary>Is my pass data safe? 🔒</summary>

<br>

Yes. The extensions are sandboxed, they only ever read the file you're previewing, and there is **no networking code anywhere** — images and barcodes are rendered locally and embedded directly in the preview. Nothing about your passes leaves the machine.

</details>

---

## 🤝 Contributing

Issues and PRs welcome. If you hit a pass that renders wrong, attach it (or a scrubbed version) — odd-shaped real-world passes are the best test cases.

## 📄 License

MIT — see [LICENSE](LICENSE). Built by [Ariorad Moniri](https://github.com/ArioMoniri).

<div align="center">
<sub>Apple, Wallet, and Quick Look are trademarks of Apple Inc. This project is not affiliated with Apple.</sub>
</div>

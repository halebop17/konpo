# Visualizer — third-party attribution

The optional visualizer window renders MilkDrop-style presets with **Butterchurn**,
a WebGL implementation of MilkDrop, running in a `WKWebView`. These bundled files
are MIT-licensed (© Jordan Berg and contributors):

- `web/butterchurn.min.js` — the Butterchurn renderer
- `web/butterchurnPresets.min.js` — the built-in preset pack (~100 presets)

Project: https://github.com/jberg/butterchurn — MIT License.

The offline conversion helper (`scripts/lib/milkdrop-preset-converter.min.js`,
also MIT) is **not** shipped inside the app; it is only used by
`scripts/convert-milkdrop-presets.js` to pre-convert `.milk` files.

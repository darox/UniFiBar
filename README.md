<div align="center">

<img src="docs/app-icon.png" width="128" alt="UniFiBar" />

# UniFiBar

Real-time UniFi WiFi metrics in your macOS menu bar.

<img src="docs/screenshot.png" width="420" alt="UniFiBar screenshot" />

</div>

---

## Requirements

- macOS 26 (Tahoe)
- Xcode 26+ command line tools
- UniFi Network Application 10.1.85+ (tested with UCG Fiber)
- A UniFi API key (Settings → Integrations → Generate API Key)

## Build & Install

```bash
git clone https://github.com/darox/UniFiBar.git
cd UniFiBar
Scripts/package_app.sh
cp -r .build/release/UniFiBar.app /Applications/
open /Applications/UniFiBar.app
```

For development:

```bash
Scripts/compile_and_run.sh
```

On first launch, enter your controller URL, API key, and enable self-signed certificates if needed.

## License

MIT

# Changelog

## [Unreleased]

### Added
- macOS 27 (Golden Gate) support: verified build, tests, release bundle and app launch on macOS 27.2 with Xcode 27.1 and the macOS 27.0 SDK. The deployment target stays macOS 26, so Tahoe users keep working.

### Fixed
- The release bundle carries only entitlements that an ad-hoc signature can use. `keychain-access-groups` with `$(AppIdentifierPrefix)` cannot resolve without a provisioning profile; macOS rejects the entitlement and launchd refuses to start the bundle. `package_app.sh` now fails loudly if a placeholder reappears.

### Changed
- Opening Setup/Preferences uses `NSApp.activate()`, the documented replacement for the soft-deprecated `activate(ignoringOtherApps:)`.
- Menu footer buttons carry help tags, and Quit uses a power symbol instead of a close symbol. (macOS 27 hides menu item symbol images by default; UniFiBar presents a window-style menu bar extra, so it is unaffected.)
- Requirements and checks now cover macOS 26 or 27 with Xcode 26 or 27. CI tests the macOS 26 image and, as a non-blocking preview, the `xcode-27` image with the macOS 27 SDK.

## [1.0.0] — 2026-05-09

### Added
- WiFi Experience Score with satisfaction percentage and trend indicators
- Signal monitoring (RSSI, noise floor, signal quality trends)
- Access point details (current AP, channel, WiFi standard, MIMO configuration)
- Link speeds (Rx/Tx rates, session data transfer totals)
- Roaming detection with alerts when switching between access points
- Internet health (WAN status, ISP name, latency, availability, packet drops)
- Gateway monitoring (CPU, memory, uptime, throughput)
- WAN throughput (real-time upload/download speeds)
- VPN tunnel status (site-to-site tunnels)
- Network overview (total clients, devices online/offline, firmware updates)
- Session history with daily roaming breakdown by access point
- Optional monitoring sections: Dynamic DNS, port forwards, nearby APs
- Launch at login via macOS login items
- Self-signed certificate support with trust-on-first-use pinning
- Wired Ethernet connection support
- Compact mode for reduced menu bar footprint
- Configurable poll interval (10s–300s)
- Section visibility toggles (show/hide feature sections)
- Diagnostics log with export support
- Update checker (GitHub releases)
- Preferences window (edit credentials, reset all)
- Setup flow for first-launch configuration

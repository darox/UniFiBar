# Security policy

## Scope

UniFiBar is a macOS menu bar app that talks to your own UniFi controller.
Your controller URL and API key stay in the macOS Keychain. The app sends
them only to the controller address you configured. Update checks contact
the GitHub API and carry no credentials.

## Supported versions

Only the latest release and the current `main` branch receive security
fixes. Older releases are not patched.

## Report a vulnerability

Do not open a public issue for a security report.

1. Open the **Security** tab of this repository.
2. Select **Report a vulnerability** to file a private report.

If private reporting is not available, open a public issue that says only
that a security report exists. Do not include technical details, proof of
concept code, or credentials. The maintainer will arrange a private
channel from there.

Do not include API keys, controller addresses, or certificate data in any
report. Redact them before you attach logs or diagnostics output.

## Response

Expect a first answer within 7 days. Confirmed vulnerabilities get a fix on
`main` and a new release. The release notes describe the fix after the
release is public.

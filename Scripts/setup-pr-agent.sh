#!/usr/bin/env bash
set -euo pipefail

# Stores AI API key and GitHub token in macOS Keychain for use by direnv/pr-agent.
# The API key is stored under the host service name so it can be shared across tools.

SERVICE="ai.k8s1bu.dacores.com"

echo "==> Setting up local AI tooling (pr-agent + direnv)"

# Install pr-agent
if ! command -v pr-agent &>/dev/null; then
    echo "Installing pr-agent..."
    pipx install git+https://github.com/qodo-ai/pr-agent --python python3.12
else
    echo "pr-agent already installed: $(pr-agent --version 2>/dev/null | tail -1 || echo 'unknown')"
fi

# Store API key in Keychain (shared across tools)
echo ""
echo "Enter your API key for $SERVICE:"
read -rs api_key
if [ -n "$api_key" ]; then
    security delete-generic-password -s "$SERVICE" -a "api-key" 2>/dev/null || true
    security add-generic-password -s "$SERVICE" -a "api-key" -w "$api_key"
    echo "API key stored in Keychain (service=$SERVICE, account=api-key)."
else
    echo "Skipped API key."
fi

# Store GitHub token in Keychain (optional)
echo ""
echo "Enter your GitHub personal access token (optional, for PR comments):"
read -rs github_token
if [ -n "$github_token" ]; then
    security delete-generic-password -s "com.unifbar.github" -a "token" 2>/dev/null || true
    security add-generic-password -s "com.unifbar.github" -a "token" -w "$github_token"
    echo "GitHub token stored in Keychain."
else
    echo "Skipped GITHUB_TOKEN."
fi

echo ""
echo "==> Done. Run 'direnv allow' to load the environment."
echo "    Then: pr-agent --pr_url <url> review"
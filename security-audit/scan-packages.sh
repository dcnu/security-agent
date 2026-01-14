#!/bin/bash
# scan-packages.sh - Scan project for package vulnerabilities
# Usage: ./scan-packages.sh <project-path>

set -euo pipefail

PROJECT_PATH="${1:-}"

if [[ -z "$PROJECT_PATH" ]]; then
	echo "Usage: $0 <project-path>" >&2
	exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
	echo "Error: Directory not found: $PROJECT_PATH" >&2
	exit 1
fi

cd "$PROJECT_PATH"

# Detect project type and run appropriate audit
if [[ -f "package.json" ]]; then
	echo "=== Node.js Project Detected ==="

	# Check for pnpm-lock.yaml
	if [[ -f "pnpm-lock.yaml" ]]; then
		echo "Running pnpm audit..."
		pnpm audit --json 2>/dev/null || true
	elif [[ -f "package-lock.json" ]]; then
		echo "Running npm audit..."
		npm audit --json 2>/dev/null || true
	elif [[ -f "yarn.lock" ]]; then
		echo "Running yarn audit..."
		yarn audit --json 2>/dev/null || true
	else
		echo "No lockfile found. Running pnpm install first..."
		pnpm install --frozen-lockfile 2>/dev/null || pnpm install
		pnpm audit --json 2>/dev/null || true
	fi
fi

if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
	echo "=== Python Project Detected ==="

	# Check if pip-audit is available
	if ! command -v pip-audit &>/dev/null; then
		echo "Installing pip-audit..."
		uv pip install pip-audit 2>/dev/null || pip install pip-audit
	fi

	echo "Running pip-audit..."
	if [[ -f "requirements.txt" ]]; then
		pip-audit -r requirements.txt --format=json 2>/dev/null || true
	elif [[ -f "pyproject.toml" ]]; then
		pip-audit --format=json 2>/dev/null || true
	fi
fi

# Check for outdated packages
echo ""
echo "=== Checking for Outdated Packages ==="

if [[ -f "package.json" ]]; then
	if [[ -f "pnpm-lock.yaml" ]]; then
		pnpm outdated --format=json 2>/dev/null || true
	elif [[ -f "package-lock.json" ]]; then
		npm outdated --json 2>/dev/null || true
	fi
fi

if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
	pip list --outdated --format=json 2>/dev/null || true
fi

echo ""
echo "=== Package Scan Complete ==="

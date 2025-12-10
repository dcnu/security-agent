#!/bin/bash
# query-osv.sh - Query OSV API for package vulnerabilities
# Usage: ./query-osv.sh <ecosystem> <package-name> [version]
# Ecosystems: npm, PyPI, Go, Maven, etc.

set -euo pipefail

ECOSYSTEM="${1:-}"
PACKAGE="${2:-}"
VERSION="${3:-}"

if [[ -z "$ECOSYSTEM" ]] || [[ -z "$PACKAGE" ]]; then
	echo "Usage: $0 <ecosystem> <package-name> [version]" >&2
	echo "Example: $0 npm lodash 4.17.20" >&2
	echo "Ecosystems: npm, PyPI, Go, Maven, crates.io, NuGet, Packagist" >&2
	exit 1
fi

OSV_API="https://api.osv.dev/v1/query"

# Build the query JSON
if [[ -n "$VERSION" ]]; then
	QUERY=$(cat <<EOF
{
	"package": {
		"name": "$PACKAGE",
		"ecosystem": "$ECOSYSTEM"
	},
	"version": "$VERSION"
}
EOF
)
else
	QUERY=$(cat <<EOF
{
	"package": {
		"name": "$PACKAGE",
		"ecosystem": "$ECOSYSTEM"
	}
}
EOF
)
fi

echo "=== OSV Query for $ECOSYSTEM/$PACKAGE ==="
echo ""

# Make the API request
RESPONSE=$(curl -s -X POST "$OSV_API" \
	-H "Content-Type: application/json" \
	-d "$QUERY")

# Check if any vulnerabilities found
if echo "$RESPONSE" | grep -q '"vulns"'; then
	echo "Vulnerabilities found:"
	echo "$RESPONSE" | jq -r '.vulns[] | "- \(.id): \(.summary // "No summary") [Severity: \(.database_specific.severity // "unknown")]"' 2>/dev/null || echo "$RESPONSE"
else
	echo "No known vulnerabilities found for $PACKAGE"
fi

echo ""
echo "Raw response:"
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"

#!/bin/bash
# check-logs.sh - Review logs for security indicators
# Usage: ./check-logs.sh [vercel-project] [supabase-project-ref]

set -euo pipefail

VERCEL_PROJECT="${1:-}"
SUPABASE_REF="${2:-}"

echo "=== Log Security Review ==="
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# Check Vercel logs if project specified
if [[ -n "$VERCEL_PROJECT" ]]; then
	echo "=== Vercel Logs (Last 24h) ==="
	if command -v vercel &>/dev/null; then
		# Get recent logs and look for security-relevant patterns
		vercel logs "$VERCEL_PROJECT" --limit=100 2>/dev/null | \
			grep -iE "(error|fail|unauthorized|forbidden|denied|invalid.*token|rate.?limit)" || \
			echo "No security-relevant log entries found"
	else
		echo "Warning: vercel CLI not installed"
	fi
	echo ""
fi

# Check Supabase logs if project ref specified
if [[ -n "$SUPABASE_REF" ]]; then
	echo "=== Supabase Function Logs ==="
	if command -v supabase &>/dev/null; then
		supabase functions logs --project-ref "$SUPABASE_REF" 2>/dev/null | \
			grep -iE "(error|fail|unauthorized|forbidden|denied)" || \
			echo "No security-relevant log entries found"
	else
		echo "Warning: supabase CLI not installed"
	fi
	echo ""
fi

# Check local system logs (macOS)
echo "=== Local System Logs ==="
if [[ -f "/var/log/system.log" ]]; then
	# Look for SSH attempts, auth failures, etc.
	sudo grep -iE "(ssh|auth|login|failed)" /var/log/system.log 2>/dev/null | \
		tail -50 || echo "No relevant entries or no access"
else
	# Use log command on newer macOS
	log show --predicate 'eventMessage CONTAINS[c] "ssh" OR eventMessage CONTAINS[c] "auth"' \
		--last 24h --style compact 2>/dev/null | \
		tail -50 || echo "Unable to query system logs"
fi

echo ""
echo "=== Log Review Complete ==="

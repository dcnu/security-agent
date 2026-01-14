# Security Audit

A Claude Code slash command that audits repositories for package vulnerabilities, checks for recent security advisories, reviews logs, and maintains a persistent record of findings and fixes. Automatically applies patch/minor updates for known CVEs.

## Setup

### Prerequisites

```bash
brew install gh jq
pnpm add -g vercel
uv pip install pip-audit
```

### Authentication

```bash
gh auth login
vercel login
supabase login  # optional, for log review
```

### Install

Copy the slash command and scripts to your Claude commands directory:

```bash
cp security-audit.md ~/.claude/commands/
cp -r security-audit/ ~/.claude/commands/
chmod +x ~/.claude/commands/security-audit/*.sh
```

## Usage

Run in any repository:

```bash
/security-audit
```

Results are stored in `.security-audit/` within the scanned repository (automatically added to `.gitignore`).

## Features

- **Package Vulnerability Scan** - `pnpm audit` / `pip-audit`
- **Dependabot Alerts** - GitHub API integration
- **OSV API Query** - Open Source Vulnerabilities database
- **Log Review** - Vercel/Supabase security patterns
- **Breach Indicators** - Exposed secrets, hardcoded credentials
- **Automatic Fixes** - Patch/minor updates applied automatically
- **Persistence** - Tracks issues over time per repository

## Automatic Fixes

Updates applied automatically when:
- Fix version specified in advisory
- Patch or minor version (not major)
- Direct dependency

After fix:
- Tests run if available
- Committed: `Fix: Update <package> to <version> (<CVE-ID>)`
- Issue moved to `fixed-issues.json`

Manual review for: major updates, transitive deps, no fix available, test failures.

## Output Structure

Each repository gets a `.security-audit/` directory:

```
.security-audit/
├── audit-logs/          # Historical audit results
│   └── YYYYMMDD-HHMMSS.json
├── known-issues.json    # Currently tracked vulnerabilities
└── fixed-issues.json    # Resolved issues with timestamps
```

## Directory Structure

```
security-audit/
├── security-audit.md        # Slash command (copy to ~/.claude/commands/)
├── security-audit/          # Scripts (copy to ~/.claude/commands/)
│   ├── scan-packages.sh
│   ├── query-osv.sh
│   └── check-logs.sh
├── README.md
└── LICENSE
```

## Phases

1. **Setup** - Initialize output directory, detect project type
2. **GitHub Alerts** - Fetch and fix Dependabot alerts
3. **Package Audit** - Run local vulnerability scans
4. **Version Updates** - Interactive minor/major update prompts
5. **Security Research** - Query OSV API, web search for advisories
6. **Breach Detection** - Git history secrets, hardcoded credentials
7. **Report** - Generate summary, persist results

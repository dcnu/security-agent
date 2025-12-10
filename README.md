# Security Agent

A Claude Code slash command that audits repositories for package vulnerabilities, checks for recent security advisories, reviews logs, and maintains a persistent record of findings and fixes. Automatically applies patch/minor updates for known CVEs.

Assumes this repo lives at `~/projects/agents/security-agent/` alongside sibling project directories.

## Setup

### Prerequisites

```bash
brew install gh supabase/tap/supabase jq
pnpm add -g vercel
uv pip install pip-audit
```

### Authentication

```bash
gh auth login
vercel login
supabase login
```

### Install

1. Copy the slash command:
```bash
cp .claude/commands/security-audit.md ~/.claude/commands/
```

2. Initialize local config:
```bash
cp -r .security-agent.example .security-agent
```

3. Edit `.security-agent/config.json`:
```json
{
  "scanRoot": "~/projects",
  "excludeDirs": ["node_modules", ".git", "archive", "agents", ".next", ".venv", "__pycache__"],
  "vercelTeam": "team_xxxxx",
  "githubOrg": "your-username",
  "supabase": {
    "extractFromEnv": true,
    "envFile": ".env.local",
    "envVar": "SUPABASE_URL"
  }
}
```

## Usage

```bash
/user:security-audit              # Scan current directory
/user:security-audit --all        # Scan all projects in scanRoot
/user:security-audit my-project   # Scan specific project
```

## Features

- **Package Vulnerability Scan** - `pnpm audit` / `pip-audit`
- **Dependabot Alerts** - GitHub API integration
- **OSV API Query** - Open Source Vulnerabilities database
- **Log Review** - Vercel/Supabase security patterns
- **Breach Indicators** - Exposed secrets, hardcoded credentials
- **Automatic Fixes** - Patch/minor updates applied automatically
- **Persistence** - Tracks issues over time

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

## Directory Structure

```
security-agent/
├── .claude/commands/
│   └── security-audit.md     # Slash command
├── .security-agent.example/  # Template (tracked)
├── .security-agent/          # Local data (gitignored)
│   ├── config.json
│   ├── known-issues.json
│   ├── fixed-issues.json
│   └── audit-logs/
├── scripts/
│   ├── scan-packages.sh
│   ├── check-logs.sh
│   └── query-osv.sh
└── README.md
```

## Scripts

```bash
./scripts/scan-packages.sh <project-path>    # Package audit
./scripts/check-logs.sh [vercel] [supabase]  # Log review
./scripts/query-osv.sh npm lodash 4.17.20    # OSV lookup
```

# Security Audit

Perform a comprehensive security audit with deterministic, phased execution.

**Argument:** $ARGUMENTS

**Default behavior:** Scan only the current working directory (`$CWD`).

**Modifiers:**
- `--all` or `-a`: Scan all projects in `scanRoot` instead of just current directory
- `<project-name>`: Scan a specific project by name (relative to `scanRoot`)

## Configuration

Load configuration from: `~/Projects/agents/security-agent/.security-agent/config.json`

The config contains:
- `scanRoot`: Root directory containing projects to scan
- `excludeDirs`: Directories to skip during scanning
- `vercelTeam`: Vercel team slug for log access
- `githubOrg`: GitHub org/username for API access
- `supabase.extractFromEnv`: If true, extract project refs from project env files
- `supabase.envFile`: Env file to read (e.g., `.env.local`)
- `supabase.envVar`: Variable containing Supabase URL (e.g., `SUPABASE_URL`)

---

## Execution Flow

Execute all 7 phases in strict order. Every phase runs regardless of findings (report "0 issues found" and continue).

```
Phase 1: Setup
    ↓
Phase 2: GitHub Alerts → Fix
    ↓
Phase 3: Package Audit → Fix
    ↓
Phase 4: Version Updates (Interactive)
    ↓
Phase 5: Security Research
    ↓
Phase 6: Breach Detection
    ↓
Phase 7: Report & Persist
```

---

## Phase 1: Setup

### 1.1 Load Configuration

Read config from `~/Projects/agents/security-agent/.security-agent/config.json`.

### 1.2 Load History

Read from `~/Projects/agents/security-agent/.security-agent/`:
- `known-issues.json` - Previously identified vulnerabilities
- `fixed-issues.json` - Resolved issues with fix timestamps

Review recent audit logs in `audit-logs/` to identify recurring issues.

### 1.3 Discover Projects

**Determine scan target based on `$ARGUMENTS`:**

1. If `$ARGUMENTS` is empty: scan current working directory (`$CWD`) only
2. If `$ARGUMENTS` is `--all` or `-a`: scan all projects in `scanRoot`
3. If `$ARGUMENTS` is a project name: scan `scanRoot/<project-name>`

**For `--all` mode**, discover subdirectories containing:
- `package.json` (Node.js/JavaScript)
- `pyproject.toml` or `requirements.txt` (Python)

Exclude directories matching `excludeDirs` config.

**Output:** "Phase 1 complete. Scanning X project(s)."

---

## Phase 2: GitHub Alerts

**Priority:** This phase runs FIRST after setup. Fix GitHub-reported vulnerabilities before any other checks.

### 2.1 Fetch Dependabot Alerts

For each project with a GitHub remote:

```bash
gh api /repos/{owner}/{repo}/dependabot/alerts --jq '.[] | select(.state == "open") | {number: .number, package: .security_vulnerability.package.name, severity: .security_advisory.severity, cve: .security_advisory.cve_id, fix_version: .security_vulnerability.first_patched_version.identifier}'
```

### 2.2 Fix Each Alert

For each open alert with an available fix version:

**Node.js:**
```bash
cd <project-path>
pnpm add <package>@<fix-version>
```

**Python:**
```bash
cd <project-path>
uv pip install <package>==<fix-version>
```

### 2.3 Test and Commit

After each fix:

1. Run tests:
   - Node.js: `pnpm test` (if test script exists)
   - Python: `pytest` (if tests/ exists)

2. If tests pass:
   - Commit: `Fix: Update <package> to <version> (<CVE-ID>)`
   - Dismiss alert via API if possible

3. If tests fail:
   - Revert: `git checkout -- package.json pnpm-lock.yaml` (or equivalent)
   - Flag for manual review
   - Keep in tracking list

### 2.4 Phase Summary

**Output:**
```
Phase 2 complete.
- Dependabot alerts checked: X
- Automatically fixed: Y
- Failed/manual review needed: Z
```

---

## Phase 3: Package Audit

### 3.1 Run Local Audit

**Node.js projects:**
```bash
~/Projects/agents/security-agent/scripts/scan-packages.sh <project-path>
```

This runs `pnpm audit --json` and parses output.

**Python projects:**
```bash
pip-audit -r requirements.txt --format=json
```

### 3.2 Fix Vulnerabilities

For each vulnerability NOT already fixed in Phase 2:

1. Check if fix version is available
2. Check if update is patch/minor (not major)
3. If both true: apply fix using same flow as Phase 2.3

### 3.3 Phase Summary

**Output:**
```
Phase 3 complete.
- Vulnerabilities found: X
- Automatically fixed: Y
- Requires manual review: Z
```

---

## Phase 4: Version Updates (Interactive)

### 4.1 Check Outdated Packages

**Node.js:**
```bash
pnpm outdated --format=json
```

**Python:**
```bash
pip list --outdated --format=json
```

### 4.2 Categorize Updates

Separate packages into:
- **Minor/Patch updates**: Same major version, newer minor or patch
- **Major updates**: Different major version

### 4.3 Prompt for Minor Updates

Use AskUserQuestion to present available minor/patch updates:

```
Header: "Updates"
Question: "Select minor/patch updates to apply:"
Options: [list each package as "package (current → latest)"]
multiSelect: true
```

For each selected package:
1. Apply update: `pnpm add <package>@<latest>`
2. Run tests
3. If pass: commit `Update: <package> to <version>`
4. If fail: revert, report failure

### 4.4 Prompt for Major Updates

For each major version update, use AskUserQuestion:

```
Header: "Major update"
Question: "<package> has a major update (<current> → <latest>). How would you like to proceed?"
Options:
  1. "Add to TODO/tasks.md" - Create migration task with checklist
  2. "Skip" - Track in known-issues.json for future
  3. "Update anyway" - Apply update (may cause breaking changes)
```

**If "Add to TODO/tasks.md" selected:**

Append to the project's `TODO/tasks.md`:

```markdown
## Migration: <package> v<current> → v<latest>

- [ ] Review changelog: https://github.com/<owner>/<repo>/releases
- [ ] Check for breaking changes
- [ ] Update code as needed
- [ ] Test thoroughly
- [ ] Apply update: `pnpm add <package>@<latest>`
```

**If "Skip" selected:**

Add to `known-issues.json` with:
- `type`: "major_update_available"
- `package`: package name
- `currentVersion`: current version
- `availableVersion`: latest version
- `skippedAt`: ISO timestamp

**If "Update anyway" selected:**

Apply update using same flow as 4.3, but warn user about potential breaking changes.

### 4.5 Phase Summary

**Output:**
```
Phase 4 complete.
- Minor updates applied: X
- Major updates planned: Y
- Major updates skipped: Z
```

---

## Phase 5: Security Research

### 5.1 Query OSV API

For each direct dependency, query Open Source Vulnerabilities database:

```bash
~/Projects/agents/security-agent/scripts/query-osv.sh npm <package-name> <version>
~/Projects/agents/security-agent/scripts/query-osv.sh PyPI <package-name> <version>
```

Record any vulnerabilities not already found in Phases 2-3.

### 5.2 Web Search for Recent Advisories

Use web search to check for recent security advisories affecting:
- Next.js
- Vercel
- Supabase
- React
- Any major dependencies found in projects

Search queries:
- `"<package> security vulnerability 2025"` (use current year)
- `"<package> CVE"` for specific packages

Record any relevant findings not already captured.

### 5.3 Phase Summary

**Output:**
```
Phase 5 complete.
- OSV queries: X packages checked
- New vulnerabilities found: Y
- Recent advisories: Z
```

---

## Phase 6: Breach Detection

### 6.1 Git History Secrets Check

For each project with a git repository:

```bash
git log -p --all | grep -iE "(api[_-]?key|secret|password|token|credential)" | head -50
```

Flag any potential exposed secrets.

### 6.2 Verify .gitignore

Check that sensitive files are excluded:

```bash
grep -E "\.env|credentials|secrets" .gitignore
```

Report if `.env*` files are NOT in .gitignore.

### 6.3 Hardcoded Credentials Scan

```bash
grep -rE "(api[_-]?key|password|secret)\s*[:=]\s*['\"][^'\"]+['\"]" --include="*.js" --include="*.ts" --include="*.py" .
```

Flag any matches for review.

### 6.4 Log Review (If Configured)

**Extract Supabase project ref (if `supabase.extractFromEnv` is true):**
```bash
grep "^SUPABASE_URL=" <project-path>/.env.local | sed 's/.*https:\/\/\([^.]*\)\.supabase\.co.*/\1/'
```

**Run log checks:**
```bash
~/Projects/agents/security-agent/scripts/check-logs.sh [vercel-project] [supabase-ref]
```

Look for patterns indicating:
- Unusual error spikes
- Authentication failures
- Rate limiting triggers
- Unauthorized access attempts

### 6.5 Phase Summary

**Output:**
```
Phase 6 complete.
- Secrets in git history: X findings
- .gitignore status: OK/WARNING
- Hardcoded credentials: X findings
- Log anomalies: X findings
```

---

## Phase 7: Report & Persist

### 7.1 Generate Summary

Summarize all findings by severity:
- **Critical**: Actively exploited CVEs, exposed secrets
- **High**: CVEs with public exploits, auth vulnerabilities
- **Medium**: Outdated dependencies with known issues
- **Low**: Informational, best practice recommendations

Compare against previous audits to highlight:
- New issues since last scan
- Resolved issues
- Recurring problems

### 7.2 Write Audit Log

Save results to `~/Projects/agents/security-agent/.security-agent/audit-logs/YYYYMMDD-HHMMSS.json`

Format:
```json
{
  "timestamp": "ISO-8601",
  "projectsScanned": [],
  "summary": {"critical": 0, "high": 0, "medium": 0, "low": 0},
  "phases": {
    "githubAlerts": {"checked": 0, "fixed": 0, "manual": 0},
    "packageAudit": {"found": 0, "fixed": 0, "manual": 0},
    "versionUpdates": {"minorApplied": 0, "majorPlanned": 0, "skipped": 0},
    "securityResearch": {"osvChecked": 0, "newVulns": 0},
    "breachDetection": {"secretsFound": 0, "gitignoreOk": true, "hardcodedCreds": 0}
  },
  "newIssues": [],
  "resolvedIssues": [],
  "packagesUpdated": [],
  "majorUpdatesPending": [],
  "recommendations": []
}
```

### 7.3 Update Tracking Files

**Update known-issues.json:**
Add new vulnerabilities with:
- `id`: CVE or advisory ID
- `package`: Affected package name
- `version`: Vulnerable version
- `severity`: critical/high/medium/low
- `project`: Project where found
- `discoveredAt`: ISO timestamp
- `source`: How it was found (dependabot, pnpm-audit, osv, etc.)
- `description`: Brief description

**Update fixed-issues.json:**
Move resolved issues with:
- Original fields plus `fixedAt` timestamp
- `fixedVersion`: Version that resolved the issue
- `fixMethod`: How it was fixed (auto/manual)

### 7.4 Display Final Report

```
## Security Audit Summary - YYYY-MM-DD

### Projects Scanned
- project-a (Node.js)
- project-b (Python)

### Phase Results
| Phase | Checked | Fixed | Manual |
|-------|---------|-------|--------|
| GitHub Alerts | X | Y | Z |
| Package Audit | X | Y | Z |
| Version Updates | X | Y | Z |

### Findings by Severity
- Critical: X
- High: X
- Medium: X
- Low: X

### Critical Issues
1. [CVE-XXXX] package@version in project-a
   - Description
   - Status: Fixed/Manual review needed

### Pending Major Updates
- package: current → latest (TODO created)

### Recommendations
1. Priority actions
2. ...

Results saved to: ~/Projects/agents/security-agent/.security-agent/audit-logs/YYYYMMDD-HHMMSS.json
```

---

## Notes

- Every phase runs regardless of findings
- Phases execute in strict order (no parallel execution)
- User prompts appear only in Phase 4 for version updates
- All fixes are tested before committing
- Failed fixes are reverted and flagged for manual review

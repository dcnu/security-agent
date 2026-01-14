# Security Audit

Perform a comprehensive security audit of the current repository.

**Argument:** $ARGUMENTS

**Default behavior:** Scan the current working directory (`$CWD`).

---

## Output Directory

All audit results are stored in `.security-audit/` within the scanned repository:

```
.security-audit/
├── audit-logs/          # Historical audit results
│   └── YYYYMMDD-HHMMSS.json
├── known-issues.json    # Currently tracked vulnerabilities
└── fixed-issues.json    # Resolved issues with timestamps
```

**Important:** Ensure `.security-audit/` is in the repository's `.gitignore`.

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

### 1.1 Verify Output Directory

Create `.security-audit/` and `audit-logs/` subdirectory if they don't exist.

Check if `.security-audit` is in `.gitignore`. If not, add it.

### 1.2 Load History

Read from `.security-audit/`:
- `known-issues.json` - Previously identified vulnerabilities
- `fixed-issues.json` - Resolved issues with fix timestamps

If files don't exist, initialize with empty arrays `[]`.

Review recent audit logs in `audit-logs/` to identify recurring issues.

### 1.3 Detect Project Type

Identify project type by checking for:
- `package.json` → Node.js/JavaScript
- `pyproject.toml` or `requirements.txt` → Python

**Output:** "Phase 1 complete. Project type: [Node.js|Python|Mixed]"

---

## Phase 2: GitHub Alerts

**Priority:** Fix GitHub-reported vulnerabilities before any other checks.

### 2.1 Fetch Dependabot Alerts

For projects with a GitHub remote:

```bash
gh api /repos/{owner}/{repo}/dependabot/alerts --jq '.[] | select(.state == "open") | {number: .number, package: .security_vulnerability.package.name, severity: .security_advisory.severity, cve: .security_advisory.cve_id, fix_version: .security_vulnerability.first_patched_version.identifier}'
```

### 2.2 Fix Each Alert

For each open alert with an available fix version:

**Node.js:**
```bash
pnpm add <package>@<fix-version>
```

**Python:**
```bash
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

Run the package scan script:

```bash
~/.claude/commands/security-audit/scan-packages.sh "$CWD"
```

This script:
- Detects package manager (pnpm, npm, yarn)
- Runs appropriate audit command
- Handles Python projects with pip-audit
- Checks for outdated packages

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

Add to `.security-audit/known-issues.json` with:
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

For each direct dependency, query the OSV database:

```bash
~/.claude/commands/security-audit/query-osv.sh npm <package-name> <version>
~/.claude/commands/security-audit/query-osv.sh PyPI <package-name> <version>
```

Record any vulnerabilities not already found in Phases 2-3.

### 5.2 Web Search for Recent Advisories

Use web search to check for recent security advisories affecting major dependencies found in the project.

Search queries:
- `"<package> security vulnerability"` (include current year)
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

### 6.4 Log Review

Run the log review script to check Vercel and Supabase logs:

```bash
~/.claude/commands/security-audit/check-logs.sh [vercel-project] [supabase-ref]
```

**Extract Supabase project ref from env:**
```bash
grep "^SUPABASE_URL=" .env.local | sed 's/.*https:\/\/\([^.]*\)\.supabase\.co.*/\1/'
```

The script checks for:
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

Save results to `.security-audit/audit-logs/YYYYMMDD-HHMMSS.json`

Format:
```json
{
  "timestamp": "ISO-8601",
  "projectType": "nodejs|python|mixed",
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

**Update `.security-audit/known-issues.json`:**
Add new vulnerabilities with:
- `id`: CVE or advisory ID
- `package`: Affected package name
- `version`: Vulnerable version
- `severity`: critical/high/medium/low
- `discoveredAt`: ISO timestamp
- `source`: How it was found (dependabot, pnpm-audit, osv, etc.)
- `description`: Brief description

**Update `.security-audit/fixed-issues.json`:**
Move resolved issues with:
- Original fields plus `fixedAt` timestamp
- `fixedVersion`: Version that resolved the issue
- `fixMethod`: How it was fixed (auto/manual)

### 7.4 Display Final Report

```
## Security Audit Summary - YYYY-MM-DD

### Project Type
Node.js / Python / Mixed

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
1. [CVE-XXXX] package@version
   - Description
   - Status: Fixed/Manual review needed

### Pending Major Updates
- package: current → latest (TODO created)

### Recommendations
1. Priority actions
2. ...

Results saved to: .security-audit/audit-logs/YYYYMMDD-HHMMSS.json
```

---

## Notes

- Every phase runs regardless of findings
- Phases execute in strict order (no parallel execution)
- User prompts appear only in Phase 4 for version updates
- All fixes are tested before committing
- Failed fixes are reverted and flagged for manual review

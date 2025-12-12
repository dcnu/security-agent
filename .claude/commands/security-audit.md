# Security Audit

Perform a comprehensive security audit.

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

## Execution Steps

### 1. Load History

Read these files from `~/Projects/agents/security-agent/.security-agent/`:
- `known-issues.json` - Previously identified vulnerabilities
- `fixed-issues.json` - Resolved issues with fix timestamps

Review previous audit logs in `audit-logs/` to avoid redundant checks.

### 2. Discover Projects

**Determine scan target based on `$ARGUMENTS`:**

1. If `$ARGUMENTS` is empty: scan current working directory (`$CWD`) only
2. If `$ARGUMENTS` is `--all` or `-a`: scan all projects in `scanRoot`
3. If `$ARGUMENTS` is a project name: scan `scanRoot/<project-name>`

**For `--all` mode**, discover subdirectories containing:
- `package.json` (Node.js/JavaScript)
- `pyproject.toml` or `requirements.txt` (Python)

Exclude directories matching `excludeDirs` config.

**For single project mode** (default or named), verify the directory contains `package.json`, `pyproject.toml`, or `requirements.txt` before proceeding.

### 3. Package Vulnerability Scan

For each discovered project, run the appropriate audit:

**Node.js projects:**
```bash
~/Projects/agents/security-agent/scripts/scan-packages.sh <project-path>
```

This runs `pnpm audit --json` or equivalent based on lockfile.

**Python projects:**
The script also handles `pip-audit` for Python dependencies.

Parse the JSON output and correlate with `known-issues.json`.

### 4. Dependency Version Check

For each project:
- Compare installed versions against latest available
- Check for outdated packages with known CVEs
- Query Dependabot alerts if GitHub repo exists:

```bash
gh api /repos/{owner}/{repo}/dependabot/alerts --jq '.[] | {package: .security_vulnerability.package.name, severity: .security_advisory.severity, cve: .security_advisory.cve_id}'
```

### 5. Recent Vulnerability Search

Query OSV API for critical dependencies:

```bash
~/Projects/agents/security-agent/scripts/query-osv.sh npm <package-name> <version>
~/Projects/agents/security-agent/scripts/query-osv.sh PyPI <package-name> <version>
```

Use web search to check for recent security advisories affecting:
- Next.js
- Vercel
- Supabase
- Any major dependencies found in projects

### 5a. Vercel Platform Security Check

**Check Vercel security advisories and recent CVEs:**

1. **Query for Vercel-specific vulnerabilities:**
   - Search web for: `"Vercel" CVE site:nvd.nist.gov OR site:cve.mitre.org` (last 6 months)
   - Search web for: `Vercel security advisory {current_year}`
   - Check: https://vercel.com/changelog (filter for security-related entries)

2. **Check @vercel/* package vulnerabilities:**
   ```bash
   # Query OSV for Vercel SDK packages found in projects
   ~/Projects/agents/security-agent/scripts/query-osv.sh npm @vercel/analytics <version>
   ~/Projects/agents/security-agent/scripts/query-osv.sh npm @vercel/og <version>
   ~/Projects/agents/security-agent/scripts/query-osv.sh npm @vercel/kv <version>
   ~/Projects/agents/security-agent/scripts/query-osv.sh npm @vercel/postgres <version>
   ~/Projects/agents/security-agent/scripts/query-osv.sh npm @vercel/blob <version>
   ~/Projects/agents/security-agent/scripts/query-osv.sh npm @vercel/edge <version>
   ```

3. **Check Next.js vulnerabilities** (Vercel-maintained):
   ```bash
   ~/Projects/agents/security-agent/scripts/query-osv.sh npm next <version>
   ```
   Also search: `Next.js CVE {current_year}` and `Next.js security vulnerability`

4. **Review Vercel-specific attack vectors:**
   - Edge function vulnerabilities
   - Serverless function timeout/memory exploits
   - Environment variable exposure risks
   - Preview deployment security (exposed secrets in PR previews)
   - Build log exposure

5. **Check project Vercel configuration for security issues:**
   ```bash
   # Look for vercel.json misconfigurations
   if [[ -f "<project-path>/vercel.json" ]]; then
     # Check for overly permissive headers, redirects, or rewrites
     cat <project-path>/vercel.json | jq '.headers, .redirects, .rewrites' 2>/dev/null
   fi

   # Check for exposed environment variables in next.config.js
   grep -E "NEXT_PUBLIC_.*SECRET|NEXT_PUBLIC_.*KEY|NEXT_PUBLIC_.*TOKEN" <project-path>/next.config.* 2>/dev/null
   ```

6. **Flag Vercel-specific findings:**
   - Add to report under "Platform Security" section
   - Cross-reference with project's deployed Vercel version (if detectable)
   - Note any mitigations already in place (WAF, rate limiting, etc.)

### 6. Log Review

If configured, check deployment and function logs.

**Extract Supabase project ref from each project (if `supabase.extractFromEnv` is true):**
```bash
# Read only SUPABASE_URL from the project's .env.local, extract project ref
grep "^SUPABASE_URL=" <project-path>/.env.local | sed 's/.*https:\/\/\([^.]*\)\.supabase\.co.*/\1/'
```

Security notes:
- Only parse the specific env var, ignore all other values
- Extract only the subdomain (project ref), discard the full URL
- Never log or persist the extracted ref beyond the current audit session

**Run log checks:**
```bash
~/Projects/agents/security-agent/scripts/check-logs.sh [vercel-project] [supabase-ref]
```

Look for patterns indicating:
- Unusual error spikes
- Authentication failures
- Rate limiting triggers
- Unauthorized access attempts

### 7. Breach Indicators

For each project with a git repository:

**Check for exposed secrets in history:**
```bash
git log -p --all | grep -iE "(api[_-]?key|secret|password|token|credential)" | head -50
```

**Verify .gitignore includes sensitive files:**
```bash
grep -E "\.env|credentials|secrets" .gitignore
```

**Check for hardcoded credentials:**
```bash
grep -rE "(api[_-]?key|password|secret)\s*[:=]\s*['\"][^'\"]+['\"]" --include="*.js" --include="*.ts" --include="*.py" .
```

### 8. Generate Report

Summarize all findings by severity:
- **Critical**: Actively exploited CVEs, exposed secrets
- **High**: CVEs with public exploits, auth vulnerabilities
- **Medium**: Outdated dependencies with known issues
- **Low**: Informational, best practice recommendations

Compare against previous audits to highlight:
- New issues since last scan
- Resolved issues
- Recurring problems

### 9. Persist Results

**Save audit log:**
Write results to `~/Projects/agents/security-agent/.security-agent/audit-logs/YYYYMMDD-HHMMSS.json`

Format:
```json
{
  "timestamp": "ISO-8601",
  "projectsScanned": [],
  "summary": {"critical": 0, "high": 0, "medium": 0, "low": 0},
  "newIssues": [],
  "resolvedIssues": [],
  "packagesUpdated": [],
  "logsReviewed": {},
  "breachIndicators": [],
  "exploitationAssessments": [
    {
      "issueId": "CVE-XXXX",
      "vulnerabilityType": "injection",
      "remoteExploitable": true,
      "publicExploitsAvailable": false,
      "exploitationIndicatorsFound": false,
      "evidence": [],
      "status": "no_indicators_detected"
    }
  ],
  "potentiallyExploitedIssues": [],
  "platformSecurity": {
    "vercel": {
      "advisoriesChecked": true,
      "cveSearchDate": "ISO-8601",
      "findings": [],
      "configIssues": [],
      "nextJsVersion": "x.x.x",
      "vercelPackages": [
        {"name": "@vercel/analytics", "version": "x.x.x", "vulnerable": false}
      ]
    },
    "supabase": {
      "advisoriesChecked": true,
      "findings": []
    }
  },
  "recommendations": []
}
```

**Update known-issues.json:**
Add new vulnerabilities with:
- `id`: CVE or advisory ID
- `package`: Affected package name
- `version`: Vulnerable version
- `severity`: critical/high/medium/low
- `project`: Project where found
- `discoveredAt`: ISO timestamp
- `source`: How it was found (pnpm-audit, osv, etc.)
- `description`: Brief description
- `exploitationAssessment`: Object with exploitation analysis results
  - `vulnerabilityType`: Type of vulnerability (injection, deserialization, auth_bypass, path_traversal, etc.)
  - `remoteExploitable`: Boolean
  - `publicExploitsAvailable`: Boolean
  - `exploitationIndicatorsFound`: Boolean
  - `evidence`: Array of evidence objects (file paths, commit hashes, log entries)
  - `assessedAt`: ISO timestamp of when assessment was performed

**Update fixed-issues.json:**
Move resolved issues with:
- Original fields plus `fixedAt` timestamp
- `fixedVersion`: Version that resolved the issue
- `fixMethod`: How it was fixed

### 10. Exploitation Assessment

Before applying fixes, evaluate whether identified vulnerabilities may have already been exploited. For each security issue being fixed in this session:

**a) Analyze vulnerability characteristics:**
- Determine if the vulnerability allows remote exploitation
- Check if authentication is required to exploit
- Assess if public exploit code exists (search GitHub, ExploitDB, Metasploit modules)

**b) Search codebase for exploitation indicators:**

For **injection vulnerabilities** (SQL injection, command injection, XSS):
```bash
# Check git history for suspicious commits around user-input handling code
git log --oneline --all --since="1 year ago" -p -- "*.js" "*.ts" "*.py" | \
  grep -iE "(eval|exec|system|shell|innerHTML|dangerouslySetInnerHTML)" | head -50

# Look for unexpected data patterns in configuration or database files
grep -rE "(\$\{|<%|<\?|;--|UNION\s+SELECT)" --include="*.json" --include="*.sql" . 2>/dev/null
```

For **prototype pollution / deserialization** vulnerabilities:
```bash
# Check for unexpected object properties in config files
grep -rE '("__proto__|constructor|prototype)' --include="*.json" . 2>/dev/null

# Search for serialized payloads in data files
grep -rE "(rO0AB|aced0005|gASV)" --include="*.json" --include="*.txt" . 2>/dev/null
```

For **authentication/authorization bypasses**:
```bash
# Review recent auth-related commits for suspicious patterns
git log --oneline --all --since="6 months ago" -p -- "*auth*" "*login*" "*session*" | head -100

# Check logs for auth anomalies (if available)
grep -iE "(admin|root|sudo|superuser)" ~/.security-agent/audit-logs/*.json 2>/dev/null
```

For **path traversal / file inclusion**:
```bash
# Search for traversal patterns in logs and data
grep -rE "(\.\.\/|\.\.\\\\|%2e%2e)" . 2>/dev/null | head -50
```

**c) Review git history around vulnerable code:**
```bash
# Get commits that touched the vulnerable file/function
git log --oneline -20 -- <vulnerable-file>

# Check for unusual commit patterns (odd hours, bulk changes, unfamiliar authors)
git log --format="%h %ai %an: %s" --since="6 months ago" -- <vulnerable-file>
```

**d) Check runtime artifacts:**
- Examine log files for error patterns associated with exploitation attempts
- Look for unexpected files in temp directories or upload locations
- Check for modified timestamps on sensitive files

**e) Document findings:**

If exploitation indicators are found:
- Flag issue as **POTENTIALLY EXPLOITED** in the audit report
- Record specific evidence (file paths, commit hashes, log entries)
- Add to `known-issues.json` with `exploitationIndicators` array
- Recommend incident response procedures before applying fix

If no indicators found:
- Note "No exploitation indicators detected" in report
- Proceed with fix application

**Severity escalation:**
- If exploitation is suspected, escalate severity to **Critical** regardless of original rating
- Recommend immediate response: rotate credentials, review access logs, notify stakeholders

### 11. Apply Automatic Fixes

For vulnerabilities with available fix versions, apply updates automatically when ALL of these conditions are met:
- Fix version is specified in the vulnerability advisory
- Update is patch or minor version (not major)
- Package is a direct dependency

**Node.js:**
```bash
cd <project-path>
pnpm add <package>@<fix-version>   # For specific fix versions
pnpm update <package>               # For minor/patch updates
```

**Python:**
```bash
cd <project-path>
uv pip install <package>==<fix-version>
```

**After each fix:**
1. Run tests if available:
   - Node.js: `pnpm test` (if test script exists in package.json)
   - Python: `pytest` (if tests/ directory exists)

2. If tests pass:
   - Commit changes: `Fix: Update <package> to <version> (<CVE-ID>)`
   - Update `fixed-issues.json` with resolution details
   - Remove from `known-issues.json`

3. If tests fail:
   - Revert: `git checkout -- package.json pnpm-lock.yaml` or `git checkout -- requirements.txt`
   - Flag issue for manual review in report
   - Keep in `known-issues.json` with note about failed auto-fix

**Skip automatic fixes (flag for manual review) when:**
- Major version update required
- Transitive dependency (requires upstream update)
- No fix version available
- Tests fail after update

## Output Format

Present findings in a clear summary:

```
## Security Audit Summary - YYYY-MM-DD

### Projects Scanned
- project-a (Node.js)
- project-b (Python)

### Findings by Severity
- Critical: X
- High: X
- Medium: X
- Low: X

### Critical Issues
1. [CVE-XXXX] package@version in project-a
   - Description
   - Recommended fix

### Exploitation Assessment
For each vulnerability being fixed:

1. [CVE-XXXX] package@version
   - Vulnerability type: [injection/deserialization/auth bypass/etc.]
   - Remote exploitable: Yes/No
   - Public exploits available: Yes/No
   - **Exploitation indicators found:** Yes/No
   - Evidence: [file paths, commit hashes, log entries if applicable]
   - Status: POTENTIALLY EXPLOITED / No indicators detected

⚠️ POTENTIALLY EXPLOITED ISSUES (if any):
- [CVE-XXXX] Evidence: [summary of findings]
  - Recommended immediate actions before fix

### Platform Security (Vercel/Supabase)

**Vercel:**
- Advisories checked: [date]
- Next.js version: [version] - [status: current/outdated/vulnerable]
- @vercel/* packages: [count] checked, [count] issues found
- Configuration issues: [list any vercel.json or env exposure issues]
- Recent CVEs affecting projects: [list or "None found"]

**Supabase:**
- Advisories checked: [date]
- Issues found: [list or "None found"]

### New Since Last Audit
- List of new findings

### Resolved Since Last Audit
- List of fixed issues

### Recommendations
1. Priority actions
2. ...

Results saved to: ~/Projects/agents/security-agent/.security-agent/audit-logs/YYYYMMDD-HHMMSS.json
```

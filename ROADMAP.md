# a2m8-toolkit — Roadmap

> "Visibility over Noize. Prove it with data."

---

## v0.1.0 — Digest & Fleet Reports (THIS SPRINT)

**Goal:** Stakeholder-facing reports that run automatically.

### Digest system
- [x] `Send-StakeholderDigest.ps1` — role-based email (CTO, CFO, Exec, Mgr)
- [x] `setup-digest-schedule.ps1` — Saturday 11:45pm schtask (captures Mon-Sat week, lands for Sun/Mon reading)
- [x] `Deploy-M365DigestAutomation.ps1` — Azure Automation deployment path
- [ ] Multi-recipient config (currently all → `CTO@phoenix-cpas.com`)
- [ ] CFO/Exec digest sections (cost + headcount focus)
- [ ] Monthly digest variant (1st of month, 8am)

### Fleet reports
- [x] `Get-DeviceLoginReport.ps1` — last-login per user, inactive flags
- [x] `Get-IntuneHealthReport.ps1` — sync staleness, compliance, storage
- [x] `Get-HardwareInventoryResults.ps1` — hardware spec pull from Intune

### Client: Phoenix CPAs
- [x] Weekly CTO digest registered (LW-StakeholderDigest schtask, 2026-05-19)
- [ ] First live send validated (email received by Alexis)
- [ ] Monthly digest registered (LW-StakeholderDigest-Monthly schtask)

---

## v0.2.0 — Alias Library

**Goal:** Device-side helpers from Bootstrap become discoverable, updatable, standalone.

Current state: device aliases (`push-status`, `update-toolkit`, `check-tools`) are baked into `Bootstrap-Chocolatey.ps1` as a here-string at lines 307-380. They work, but are invisible.

- [ ] Extract alias library from Bootstrap into `aliases/lw-aliases.ps1`
- [ ] `setup-aliases.ps1` — registers aliases to PS profile
- [ ] `update-toolkit` points to a2m8-toolkit GitHub (once repo exists)
- [ ] `push-status` still calls Gist (stable ID: `ed301fb8606329456a8e7f87a46fbbab`)
- [ ] Ship as `a2m8-toolkit v0.2.0` — new Bootstrap references this instead of inline here-string

---

## v0.3.0 — Own Repo

**Goal:** a2m8-toolkit leaves the monorepo.

- [ ] `github.com/a2m8-org/toolkit` created
- [ ] Scripts migrated from `Intune-Deployments/` (AS-IS copy, no filter-repo needed — 1-3 commits each)
- [ ] Bootstrap updated to clone this repo instead of inline aliases
- [ ] Monorepo retains symlinks → toolkit repo for backward compat

---

## v0.3.0 — Fleet CLI (promote from Intune-Deployments)

**Goal:** `fleet.ps1` lives in a2m8-toolkit, auto-loads via PS profile on any dev machine.

- [ ] Move `fleet.ps1` → `a2m8-toolkit/fleet.ps1`, update profile loader path
- [ ] `user <upn|alias>` command — detail card per user:
  - Last interactive sign-in (AuditLog.Read.All)
  - Password lockout state + last set (User.Read.All)
  - MFA methods registered (UserAuthenticationMethod.Read.All)
  - Assigned device(s) (DeviceManagementManagedDevices.Read.All, primaryUser filter)
  - JIT elevation: last request datetime + remaining TTL (Grant-JitAdmin.ps1 output log)
- [ ] Gist integration: `gist <device>` — pull Backtalk status.json + log excerpt inline
- [ ] `fleet` table: add LAST-LOGIN column (days since last sign-in)
- [ ] Short-name resolver extended: accept email prefix (`tiffany` → `tiffany@phoenix-cpas.com`)

---

## Deferred / Backlog

- AI-generated weekly narrative (summarize digest data into plain English paragraph)
- Slack/Teams webhook output as alternative to email
- Cost trend analysis (MgGraph licensing API, compare month-over-month)
- Self-hosted dashboard mode (serve digest as HTML on local port)

---

## TO-BE — Data Export for Self-Service Analysis

**Concept:** Alongside (or instead of) the email digest, publish raw data to a shared location  
so stakeholders can slice it in whatever tool they prefer.

**Target destinations:**
- SharePoint document library (drop weekly CSV/Excel snapshot to `IT Reports/Weekly/`)
- OneDrive shared folder (same, lighter-weight setup)
- Power BI dataset push (stream via Graph + Power BI REST API)
- Excel workbook refresh (Excel Online data connection to Graph-sourced CSV)
- OneNote page (auto-generate a formatted page per week in the client notebook)

**Why this matters:**  
The email is a push — forces one format on everyone. The data export is a pull — stakeholders analyze how and when they want. CTO wants the security table. CFO wants the license count trend. Mgr wants the inactive user list. All three formats live in the same export; each person opens what they need.

**Implementation sketch:**
- `Publish-WeeklySnapshot.ps1` — uploads `DATA-TIER/cache/reports/digests/YYYY-MM/` CSVs to SharePoint via Graph `DriveItem` API
- Runs after `Send-StakeholderDigest.ps1` (same schtask or chained)
- SharePoint site/library ID configurable per-client in digest config block
- Power BI push deferred until client has Power BI Pro licensing

---

## ART Pattern

a2m8-toolkit was born from Phoenix CPAs MSP work. The client need was "prove we're doing stuff" — the toolkit is the answer. Useful for any M365 client. Owns its own roadmap and version cadence now. See `PHILOSOPHY.md` → "Pattern: ART Tool Spawning" for full pattern.

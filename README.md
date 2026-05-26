# a2m8-toolkit

Device-side remediation + alias toolkit for LogicWizards-managed endpoints.

This repo is cloned to `C:\ProgramData\LogicWizards\toolkit\` on every
Phoenix-managed device by the `update-toolkit` alias (defined in
`Bootstrap-Chocolatey.ps1`).

## How devices consume this repo

```powershell
# One-time setup per device (run elevated):
Set-Content 'C:\ProgramData\LogicWizards\config\toolkit-repo.txt' `
            'https://github.com/LogicWizards/a2m8-toolkit.git'

# Then any time, in any elevated pwsh:
update-toolkit                                          # git pull + reload aliases
& "$env:ProgramData\LogicWizards\toolkit\<Script>.ps1"  # run a remediation
```

## Contents

| File | Purpose |
|---|---|
| `Fix-BitLockerDrift.ps1` | Re-enables BitLocker on C: with TPM + recovery password, escrows recovery key to Entra. Idempotent. |

> **Note:** `aliases.ps1` is intentionally absent. When/if it exists in this
> repo, `update-toolkit` will `Copy-Item -Force` it over the device's live
> alias file (`C:\ProgramData\LogicWizards\aliases.ps1`) — which would wipe
> the aliases Bootstrap currently renders inline (`push-status`,
> `update-toolkit` itself, etc.). The full alias extraction is a deliberate
> v0.2.0 migration; until then, leaving `aliases.ps1` out keeps the
> copy-step a no-op.

## Repo philosophy

- **Public, no PAT.** Scripts contain no secrets; recovery keys live on the device
  and escrow to Entra, never into source.
- **Idempotent.** Every script safe to re-run.
- **PS5.1-safe.** Bootstrap runs as SYSTEM in PS5.1; scripts must work there.
- **Header block required.** See `CLIENTS/Pheonix-CPAs/headerTemplate.txt` in the
  LogicWizards monorepo for the standard.

## Related

- Bootstrap that deploys the `update-toolkit` alias →
  `LogicWizards/SOLUTIONS/CloudOps/Intune-Deployments/Bootstrap-Chocolatey.ps1`
- Planning + roadmap →
  `LogicWizards/SOLUTIONS/DevOps/SIDE-PROJECTS/tools/a2m8-toolkit/ROADMAP.md`

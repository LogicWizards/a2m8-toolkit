#------------------------------------------------------------------------------
# SCRIPT: aliases.ps1  (a2m8-toolkit -- device alias pack)
#------------------------------------------------------------------------------
#  PURPOSE: Device-side diagnostic/utility functions delivered via update-toolkit
# ABSTRACT: `update-toolkit` git-pulls this repo and copies this file to
#           C:\ProgramData\LogicWizards\aliases.ps1, then dot-sources it -- so
#           new aliases reach the fleet without an Intune push cycle. This file
#           is the extraction target for the alias functions currently still
#           inline in Bootstrap-Chocolatey.ps1's here-string (known tech-debt;
#           the here-string remains the onboarding source until fully migrated).
# REQUIRES: PowerShell 5.1+; gist-pat.txt at C:\ProgramData\LogicWizards\config
#  CREATED: 260820 BY: SOLOMON(Opus4.8)::Copilot::ai-labs.WIZ-00.fleet
#  UPDATED: 260820 BY: SOLOMON(Opus4.8)::Copilot::ai-labs.WIZ-00.fleet
#  COMPANY: LogicWizards.NYC <LogicWizards.NYC>
#  VERSION: 0.1.0
#  LICENSE: MIT
#  USAGE:
#     update-toolkit      # on any managed device: pull + dot-source this file
#     check-webwatcher    # then run any function defined here
#------------------------------------------------------------------------------

function check-webwatcher {
    # Pushes the WebWatcher Win32 install log + relevant choco errors to the
    # Backtalk Gist as <device>-webwatcher-install.txt so an admin can read
    # (remotely) why a WebWatcher install/upgrade failed -- no Quick Assist
    # copy/paste needed.
    $patFile = 'C:\ProgramData\LogicWizards\config\gist-pat.txt'
    if (-not (Test-Path $patFile)) {
        Write-Host '[check-webwatcher] gist-pat.txt not found -- cannot push' -ForegroundColor Red
        return
    }
    $pat = (Get-Content $patFile -Raw).Trim()

    $o = @()
    $o += "=== $env:COMPUTERNAME WebWatcher-Win32Install.log (tail 60) ==="
    $wlog = 'C:\ProgramData\LogicWizards\Logs\WebWatcher-Win32Install.log'
    if (Test-Path $wlog) {
        $o += (Get-Content $wlog -Tail 60 | Out-String)
    } else {
        $o += '(install log not found -- install.ps1 may not have run on this device)'
    }

    $o += "=== choco.log (webwatcher + errors, last 40) ==="
    $clog = 'C:\ProgramData\chocolatey\logs\chocolatey.log'
    if (Test-Path $clog) {
        $o += ((Get-Content $clog | Where-Object {
                    $_ -match 'webwatcher|ERROR|FAIL|Exception|exit code'
                } | Select-Object -Last 40) -join "`n")
    } else {
        $o += '(choco.log not found)'
    }

    $fileName = "$env:COMPUTERNAME-webwatcher-install.txt"
    $body = @{ files = @{ $fileName = @{ content = (($o -join "`n")) } } } | ConvertTo-Json -Depth 6
    Invoke-RestMethod -Method PATCH -Uri 'https://api.github.com/gists/ed301fb8606329456a8e7f87a46fbbab' `
        -Headers @{ Authorization = "token $pat"; 'User-Agent' = 'LW'; Accept = 'application/vnd.github+json' } `
        -Body $body | Out-Null
    Write-Host "[check-webwatcher] pushed $fileName to gist" -ForegroundColor Green
}

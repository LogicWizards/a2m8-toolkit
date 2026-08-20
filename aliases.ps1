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

function global:check-webwatcher {
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

function global:bounce-ime {
    # Force Intune to deliver NOW instead of waiting for the IME poll cycle: restart the
    # IntuneManagementExtension service (makes it re-pull Win32 app/policy assignments on
    # startup), then trigger the MDM sync. Use ONCE then wait ~5-10 min -- restarting IME
    # resets its ~4-min workload start-up delay, so repeated bounces are counterproductive.
    Write-Host '[bounce-ime] Restarting IntuneManagementExtension service...' -ForegroundColor Cyan
    try {
        Restart-Service IntuneManagementExtension -Force -ErrorAction Stop
        Write-Host '[bounce-ime] IME restarted.' -ForegroundColor Green
    } catch {
        Write-Host "[bounce-ime] Could not restart IME (run elevated): $($_.Exception.Message)" -ForegroundColor Yellow
    }
    if (Get-Command sync-intune -ErrorAction SilentlyContinue) {
        sync-intune
    } else {
        # Fallback: kick the MDM PushLaunch sync task directly.
        Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -TaskName 'PushLaunch' -ErrorAction SilentlyContinue |
            Start-ScheduledTask -ErrorAction SilentlyContinue
        Write-Host '[bounce-ime] Triggered MDM PushLaunch sync.' -ForegroundColor Green
    }
    Write-Host '[bounce-ime] Now WAIT ~5-10 min -- do NOT bounce again (restart resets the workload delay).' -ForegroundColor Yellow
}

function global:set-watcher-debug {
    # All-in-one WebWatcher remote-debug + kick. On ANY device: `update-toolkit; set-watcher-debug`.
    # It (1) reprograms the collector task to fast cadence, (2) pulls the latest collector +
    # this device's device-auth and runs it (cert-auth upload), (3) pushes a full diagnostic
    # payload to the Gist, and (4) fires check-webwatcher -- so the admin never needs to ask
    # the operator to run anything else on the device.
    param([int]$IntervalMinutes = 5)
    $dir  = 'C:\ProgramData\LogicWizards\SaaS-Tracker'
    $base = 'https://gist.githubusercontent.com/wwwizards/ed301fb8606329456a8e7f87a46fbbab/raw'
    $patFile = 'C:\ProgramData\LogicWizards\config\gist-pat.txt'
    if (-not (Test-Path $patFile)) { Write-Host '[watcher-debug] gist-pat.txt not found' -ForegroundColor Red; return }
    $pat = (Get-Content $patFile -Raw).Trim()

    # 1. Fast cadence on the collector task (idempotent) + capture task posture.
    $taskInfo = $null
    try {
        Set-ScheduledTask -TaskName 'LW-SaaSTracker' -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)) -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName 'LW-SaaSTracker' -ErrorAction SilentlyContinue
        $t  = Get-ScheduledTask -TaskName 'LW-SaaSTracker' -ErrorAction Stop
        $ti = Get-ScheduledTaskInfo -TaskName 'LW-SaaSTracker' -ErrorAction SilentlyContinue
        $taskInfo = [ordered]@{
            runLevel   = "$($t.Principal.RunLevel)"
            userId     = "$($t.Principal.UserId)"
            state      = "$($t.State)"
            lastRun    = if ($ti) { "$($ti.LastRunTime)" } else { $null }
            lastResult = if ($ti) { ('0x{0:X}' -f $ti.LastTaskResult) } else { $null }
            nextRun    = if ($ti) { "$($ti.NextRunTime)" } else { $null }
        }
        Write-Host "[watcher-debug] task -> ${IntervalMinutes}m cadence (RunLevel=$($t.Principal.RunLevel))" -ForegroundColor Cyan
    } catch { Write-Host "[watcher-debug] task update failed: $($_.Exception.Message)" -ForegroundColor Yellow }

    # 2. Kick: pull latest collector + this device's device-auth (RAW), run collector.
    $kick = [ordered]@{ ran = $false; error = $null }
    try {
        (Invoke-WebRequest "$base/Get-SaaSActivityTelemetry.ps1" -UseBasicParsing).Content | Set-Content (Join-Path $dir 'Get-SaaSActivityTelemetry.ps1') -Encoding utf8
        (Invoke-WebRequest "$base/$env:COMPUTERNAME-device-auth.json" -UseBasicParsing).Content | Set-Content (Join-Path $dir 'device-auth.json') -Encoding utf8
        & (Join-Path $dir 'Get-SaaSActivityTelemetry.ps1') *>&1 | Out-Null
        $kick.ran = $true
        Write-Host '[watcher-debug] collector kicked (cert-auth run)' -ForegroundColor Green
    } catch { $kick.error = $_.Exception.Message; Write-Host "[watcher-debug] kick failed: $($_.Exception.Message)" -ForegroundColor Yellow }

    # 3. Gather everything the admin might need, so no follow-up asks are needed.
    $auth = $null; try { $auth = Get-Content (Join-Path $dir 'device-auth.json') -Raw | ConvertFrom-Json -ErrorAction Stop } catch {}
    $certInStore = $false
    if ($auth.certificateThumbprint) {
        $certInStore = [bool](Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $auth.certificateThumbprint })
    }
    $canWrite = $false
    try { $probe = Join-Path $dir (".probe-" + [guid]::NewGuid().ToString('N')); Set-Content $probe 'x' -ErrorAction Stop; Remove-Item $probe -ErrorAction SilentlyContinue; $canWrite = $true } catch {}
    $lastJsonl = Get-ChildItem (Join-Path $dir 'Output'), (Join-Path $dir 'SaaS-Telemetry-Output') -Filter *.jsonl -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    $collectorVer = ([regex]::Match((Get-Content (Join-Path $dir 'Get-SaaSActivityTelemetry.ps1') -Raw -ErrorAction SilentlyContinue), '#\s*VERSION:\s*([\d.]+)')).Groups[1].Value

    $payload = [ordered]@{
        device             = $env:COMPUTERNAME
        upn                = (& whoami /upn 2>$null)
        collectedAtUtc     = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        task               = $taskInfo
        kick               = $kick
        deviceAuthPresent  = [bool]$auth
        clientId           = $auth.clientId
        certThumbprint     = $auth.certificateThumbprint
        certInStore        = $certInStore
        sharePointFolderId = $auth.sharePointFolderId
        collectorVersion   = $collectorVer
        installDirWritable  = $canWrite
        lastLocalJsonl     = if ($lastJsonl) { [ordered]@{ name = $lastJsonl.Name; modifiedUtc = $lastJsonl.LastWriteTimeUtc.ToString('s') } } else { $null }
    }
    $fn = "$env:COMPUTERNAME-watcher-debug.json"
    $body = @{ files = @{ $fn = @{ content = ($payload | ConvertTo-Json -Depth 6) } } } | ConvertTo-Json -Depth 8
    Invoke-RestMethod -Method PATCH -Uri 'https://api.github.com/gists/ed301fb8606329456a8e7f87a46fbbab' -Headers @{ Authorization = "token $pat"; 'User-Agent' = 'LW'; Accept = 'application/vnd.github+json' } -Body $body | Out-Null
    Write-Host "[watcher-debug] pushed $fn to gist" -ForegroundColor Green

    # 4. Also push the raw install log for completeness.
    if (Get-Command check-webwatcher -ErrorAction SilentlyContinue) { check-webwatcher }
}

function global:set-gist-pat {
    # One-time per-device: write the Backtalk Gist PAT so push-status / cert-request /
    # WebWatcher / set-watcher-debug can reach the Gist. The PAT is a SECRET -- it is
    # NEVER stored in this repo; the operator supplies it at the prompt. update-toolkit
    # itself needs no PAT (public repo), so a bare device can pull this alias, then set
    # the PAT:  update-toolkit; set-gist-pat <the-PAT>
    param([Parameter(Mandatory)][string]$Pat)
    if ($Pat -notmatch '^(ghp_|github_pat_)') {
        Write-Host '[set-gist-pat] value does not look like a GitHub PAT (ghp_/github_pat_) -- nothing written.' -ForegroundColor Red
        return
    }
    $cfg = 'C:\ProgramData\LogicWizards\config'
    if (-not (Test-Path $cfg)) { New-Item -ItemType Directory -Path $cfg -Force | Out-Null }
    Set-Content -Path (Join-Path $cfg 'gist-pat.txt') -Value $Pat.Trim() -Encoding ascii -Force
    Write-Host "[set-gist-pat] wrote gist-pat.txt to $cfg" -ForegroundColor Green
}

function global:fix-watcher-task {
    # The LW-SaaSTracker task defaults to RunLevel=Limited, so the collector -- running as
    # the non-elevated user -- can't read the LocalMachine cert's PRIVATE KEY (only enumerate
    # it) and can't reliably write to ProgramData, so cert-auth uploads fail silently on the
    # schedule (only elevated manual runs work). Re-register with RunLevel=Highest so the task
    # runs elevated in the user's context: keeps UPN + user identity AND gets key + write
    # access. Run this once, elevated, on each device (or bake it into bootstrap-WebWatcher).
    $t = Get-ScheduledTask -TaskName 'LW-SaaSTracker' -ErrorAction SilentlyContinue
    if (-not $t) { Write-Host '[fix-watcher-task] LW-SaaSTracker not found -- run WebWatcher install first' -ForegroundColor Red; return }
    try {
        $prin = New-ScheduledTaskPrincipal -UserId $t.Principal.UserId -LogonType Interactive -RunLevel Highest
        Set-ScheduledTask -TaskName 'LW-SaaSTracker' -Principal $prin -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName 'LW-SaaSTracker' -ErrorAction SilentlyContinue
        $now = Get-ScheduledTask -TaskName 'LW-SaaSTracker'
        Write-Host "[fix-watcher-task] RunLevel now: $($now.Principal.RunLevel) (was Limited) -- task will upload on its own from here" -ForegroundColor Green
    } catch {
        Write-Host "[fix-watcher-task] failed (run elevated): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

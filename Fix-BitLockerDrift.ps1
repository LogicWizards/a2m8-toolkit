#------------------------------------------------------------------------------
# SCRIPT: Fix-BitLockerDrift.ps1
#------------------------------------------------------------------------------
#  PURPOSE: Re-enable BitLocker on C: and escrow the recovery key to Entra.
# ABSTRACT: Diagnoses + remediates the three common BitLocker drift states
#           (encrypted-but-protection-off, partially-encrypted, fully-off)
#           by enabling the TPM protector, adding a RecoveryPassword
#           protector, escrowing it to Azure AD, and triggering an MDM
#           sync so Intune compliance flips back to Compliant.
#           Idempotent — safe to re-run.
# REQUIRES: - Elevated pwsh / powershell (Administrator)
#           - Device joined or hybrid-joined to Entra
#           - TPM present and enabled in firmware
#           - BitLocker feature installed (default on Win10/11 Pro+)
#  CREATED: 2026-05-25 BY: Joe Negron <Joe@LogicWizards.NYC>
#  COMPANY: Phoenix CPAs <Phoenix-CPAs.com>
#  VERSION: 0.1.0
#  LICENSE: MIT
#  USAGE:
#     # Standard run (after update-toolkit pulled it):
#     & "$env:ProgramData\LogicWizards\toolkit\Fix-BitLockerDrift.ps1"
#
#     # Dry-run (report state, take no action):
#     & "$env:ProgramData\LogicWizards\toolkit\Fix-BitLockerDrift.ps1" -WhatIf
#------------------------------------------------------------------------------

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$MountPoint = 'C:',
    [switch]$SkipMdmSync   # set if you don't want to trigger the PushLaunch schtask at the end
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Msg, [ConsoleColor]$Color = 'Cyan')
    Write-Host "[Fix-BitLockerDrift] $Msg" -ForegroundColor $Color
}

# --- Pre-flight checks ---------------------------------------------------------
$me = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Must run elevated (Administrator). Aborting.'
}

if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
    throw 'BitLocker module not available. Is this a Pro/Enterprise SKU?'
}

# --- Diagnose current state ----------------------------------------------------
Write-Step "Inspecting $MountPoint ..."
$vol = Get-BitLockerVolume -MountPoint $MountPoint
Write-Host ("  VolumeStatus      : {0}" -f $vol.VolumeStatus)
Write-Host ("  ProtectionStatus  : {0}" -f $vol.ProtectionStatus)
Write-Host ("  EncryptionMethod  : {0}" -f $vol.EncryptionMethod)
Write-Host ("  EncryptionPercent : {0}%" -f $vol.EncryptionPercentage)
Write-Host ("  KeyProtector count: {0}" -f $vol.KeyProtector.Count)

$hasTpm        = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'Tpm' }
$hasRecovery   = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
$isEncrypted   = $vol.VolumeStatus -in @('FullyEncrypted','EncryptionInProgress')
$isProtected   = $vol.ProtectionStatus -eq 'On'

# --- Branch 1: Encrypted but protection OFF (most common drift) ----------------
if ($isEncrypted -and -not $isProtected) {
    Write-Step 'Volume is encrypted but protection is OFF. Resuming protection.' Yellow
    if ($PSCmdlet.ShouldProcess($MountPoint, 'Resume BitLocker protection')) {
        Resume-BitLocker -MountPoint $MountPoint | Out-Null
        Start-Sleep -Seconds 2
        $vol = Get-BitLockerVolume -MountPoint $MountPoint
        if ($vol.ProtectionStatus -ne 'On') {
            Write-Step 'Resume-BitLocker did not flip protection. Falling back to manage-bde.' Yellow
            & manage-bde.exe -protectors -enable $MountPoint
            Start-Sleep -Seconds 2
            $vol = Get-BitLockerVolume -MountPoint $MountPoint
        }
    }
}

# --- Branch 2: Not encrypted at all -- fresh enable ----------------------------
elseif (-not $isEncrypted) {
    Write-Step 'Volume not encrypted. Enabling BitLocker.' Yellow
    if (-not $hasTpm) {
        if ($PSCmdlet.ShouldProcess($MountPoint, 'Enable-BitLocker (TPM + UsedSpaceOnly + XtsAes256)')) {
            Enable-BitLocker -MountPoint $MountPoint `
                             -EncryptionMethod XtsAes256 `
                             -UsedSpaceOnly `
                             -TpmProtector | Out-Null
        }
    }
    # Refresh state
    $vol = Get-BitLockerVolume -MountPoint $MountPoint
    $hasRecovery = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
}

# --- Branch 3: Already fully protected -- nothing to do for encryption ---------
else {
    Write-Step 'Volume already encrypted AND protected. No state change needed.' Green
}

# --- Ensure a RecoveryPassword protector exists --------------------------------
if (-not $hasRecovery) {
    Write-Step 'No RecoveryPassword protector found. Adding one.' Yellow
    if ($PSCmdlet.ShouldProcess($MountPoint, 'Add-BitLockerKeyProtector -RecoveryPasswordProtector')) {
        Add-BitLockerKeyProtector -MountPoint $MountPoint -RecoveryPasswordProtector | Out-Null
    }
}

# --- Escrow recovery key to Entra ----------------------------------------------
$vol = Get-BitLockerVolume -MountPoint $MountPoint
$rp  = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -First 1
if ($rp) {
    Write-Step "Escrowing recovery key to Entra. KeyProtectorId: $($rp.KeyProtectorId)" Cyan
    if ($PSCmdlet.ShouldProcess($MountPoint, "BackupToAAD-BitLockerKeyProtector $($rp.KeyProtectorId)")) {
        try {
            BackupToAAD-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $rp.KeyProtectorId | Out-Null
            Write-Step 'Entra escrow OK.' Green
        } catch {
            Write-Step "Entra escrow FAILED: $($_.Exception.Message)" Red
            Write-Step '  (Device may not be Entra-joined, or no network. Key is still on the device.)' Yellow
        }
    }
} else {
    Write-Step 'No RecoveryPassword protector to escrow. Skipping.' Yellow
}

# --- Trigger an MDM sync so Intune sees the fix ASAP ---------------------------
if (-not $SkipMdmSync) {
    Write-Step 'Triggering MDM PushLaunch sync ...' Cyan
    if ($PSCmdlet.ShouldProcess('PushLaunch', 'Start-ScheduledTask')) {
        try {
            Get-ScheduledTask -TaskName 'PushLaunch' -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -ErrorAction Stop |
                Start-ScheduledTask
            Write-Step 'PushLaunch triggered. Compliance should refresh within 5-15 min.' Green
        } catch {
            Write-Step "Could not trigger PushLaunch: $($_.Exception.Message)" Yellow
            Write-Step '  Fall back: Intune portal -> Devices -> [device] -> Sync.' Yellow
        }
    }
}

# --- Final state summary -------------------------------------------------------
$vol = Get-BitLockerVolume -MountPoint $MountPoint
Write-Host ''
Write-Step '=== FINAL STATE ===' Green
Write-Host ("  VolumeStatus      : {0}" -f $vol.VolumeStatus)
Write-Host ("  ProtectionStatus  : {0}" -f $vol.ProtectionStatus)
Write-Host ("  EncryptionMethod  : {0}" -f $vol.EncryptionMethod)
Write-Host ("  EncryptionPercent : {0}%" -f $vol.EncryptionPercentage)
Write-Host ("  KeyProtectors     : {0}" -f (($vol.KeyProtector | ForEach-Object KeyProtectorType) -join ', '))
Write-Host ''
if ($vol.ProtectionStatus -eq 'On') {
    Write-Step 'BitLocker is ON. Drift remediated.' Green
} else {
    Write-Step 'BitLocker protection still OFF. Manual investigation required:' Red
    Write-Host '  1. Check TPM:  Get-Tpm'
    Write-Host '  2. Check policy conflicts: gpresult /h C:\Temp\gp.html'
    Write-Host '  3. Check event log: Get-WinEvent -LogName Microsoft-Windows-BitLocker/BitLocker* -MaxEvents 20'
}

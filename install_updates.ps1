#Requires -Modules ActiveDirectory
param(
    # Log file written on each TARGET machine by the update task
    [string]$LogPath = 'C:\PSWindowsUpdate.log'
)

Import-Module ActiveDirectory -ErrorAction Stop

# Only enabled computer accounts (skips stale/disabled objects)
$Computers = Get-ADComputer -Filter 'Enabled -eq $true' |
    Select-Object -ExpandProperty Name

if ($Computers.Count -eq 0) {
    Write-Warning "No computers found in Active Directory."
    exit 0
}

Write-Host "Found $($Computers.Count) computers. Starting update deployment..." -ForegroundColor Cyan

foreach ($Computer in $Computers) {

    Write-Host "Installing updates on $Computer ..." -ForegroundColor Yellow

    # Check WinRM instead of ping: Windows clients block ICMP echo by default,
    # and WinRM is what Invoke-Command actually needs anyway.
    try {
        Test-WSMan -ComputerName $Computer -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning "$Computer : WinRM not reachable (offline, firewall, or WinRM disabled). Skipping. ($($_.Exception.Message.Trim()))"
        continue
    }

    try {
        Invoke-Command -ComputerName $Computer -ArgumentList $LogPath -ErrorAction Stop -ScriptBlock {
            param($LogPath)

            if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
                Install-Module PSWindowsUpdate -Force -Confirm:$false -ErrorAction Stop
            }

            Import-Module PSWindowsUpdate -ErrorAction Stop

            # Runs as a SYSTEM scheduled task, which is allowed to use the Windows Update API
            $Command = "Import-Module PSWindowsUpdate; " +
                       "Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot *>&1 | " +
                       "Out-File -FilePath '$LogPath' -Append"

            Invoke-WUJob -ComputerName localhost -Script $Command -Confirm:$false -RunNow -ErrorAction Stop | Out-Null
        }

        Write-Host "$Computer : update task started (see $LogPath on the machine)." -ForegroundColor Green

    } catch {
        Write-Host "$Computer : FAILED - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Update deployment started on all reachable computers." -ForegroundColor Cyan

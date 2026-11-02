# Crash-recovery test: stop the Gunicorn master (PID 1 of the app container) from inside the
# container, then verify that Docker restarts the same container and the same URL serves again.
#
# Method: `kill -TERM 1` via docker exec. Gunicorn handles SIGTERM by exiting, so the container
# exits on its own and the restart policy (restart: always) brings it back.
#
# Not used, and why:
#   - kill -9 1 from inside the container: Linux ignores SIGKILL sent to PID 1 from its own PID
#     namespace, so the process never dies. (Observed: the container kept running.)
#   - docker kill --signal KILL from the host: the container exits with code 137, but Docker
#     treats an explicit `docker kill` as a deliberate stop and does NOT apply the restart policy.
#     (Observed: RestartCount stayed 0 and no restart happened.)
#
# Gunicorn workers are child processes. Killing a worker only makes the master respawn it, so
# Docker does not restart the container. This test targets the master.
#
# Usage (stack running):  powershell -ExecutionPolicy Bypass -File scripts\test_crash_recovery.ps1
. "$PSScriptRoot\common.ps1"

$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Check = $Name; Result = $(if ($Passed) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
}

function Get-AppState {
    param([string]$ContainerId)
    $format = '{{.State.Status}}|{{.State.StartedAt}}|{{.State.Health.Status}}|{{.RestartCount}}|{{.State.Pid}}'
    return (& docker inspect -f $format $ContainerId).Trim().Split('|')
}

Write-Step 'Step 1: confirm the application is healthy'
Wait-ForHealthy -Service $script:AppService -TimeoutSeconds 120 | Out-Null
$containerId = Get-ContainerId -Service $script:AppService
$before = Get-AppState -ContainerId $containerId
$masterCmd = ((& docker exec $containerId cat /proc/1/cmdline) -join ' ') -replace "`0", ' '
Write-Step "Container $($containerId.Substring(0,12)) status=$($before[0]) health=$($before[2]) restartCount=$($before[3]) mainPid=$($before[4])"
Write-Step "Container main process: $($masterCmd.Trim())"
Add-Result 'app healthy before crash' ($before[2] -eq 'healthy') "status=$($before[0]) health=$($before[2])"
Add-Result 'Gunicorn is the container main process' ($masterCmd -match 'gunicorn') $masterCmd.Trim()

Write-Step 'Step 2: record uptime, then stop the Gunicorn master from inside the container'
$startedAt = [datetime]::Parse($before[1]).ToUniversalTime()
Write-Step ("Container started at {0:u} (uptime {1:N0}s)" -f $startedAt, ((Get-Date).ToUniversalTime() - $startedAt).TotalSeconds)
$killTime = Get-Date
# PID 1 is the Gunicorn master. The signal runs as the container user (uid 10001), the same user as Gunicorn.
# `kill` is a shell builtin in this image (no /bin/kill), so it must run through sh.
& docker exec $containerId sh -c 'kill -TERM 1'
if ($LASTEXITCODE -ne 0) { throw "docker exec kill failed with exit code $LASTEXITCODE" }
Write-Step ("SIGTERM sent to PID 1 at {0:yyyy-MM-dd HH:mm:ss}" -f $killTime)

Write-Step 'Step 3: wait for Docker to restart the container'
$deadline = (Get-Date).AddSeconds(120)
$restarted = $false
$after = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    $state = Get-AppState -ContainerId $containerId
    if ($state[0] -eq 'running' -and $state[1] -ne $before[1]) {
        $restarted = $true
        $after = $state
        break
    }
}

# The Docker event log records each container exit with its exit code, even when the restart is fast.
$dieEvents = & docker events --filter "container=$containerId" --filter 'event=die' `
    --since $killTime.ToString('o') --until (Get-Date).ToString('o') --format '{{.Time}} exitCode={{.Actor.Attributes.exitCode}}'
$exitDetail = if ($dieEvents) { ($dieEvents | Select-Object -First 1) } else { 'no die event recorded' }
Write-Step "Docker event: $exitDetail"
Add-Result 'Gunicorn master terminated (container exited)' ([bool]$dieEvents) $exitDetail
Add-Result 'Docker restarted the container after the crash' $restarted `
    $(if ($restarted) { "restartCount $($before[3]) -> $($after[3])" } else { 'container did not restart within 120s' })
if (-not $restarted) {
    Write-Host ''
    $results | Format-Table -AutoSize | Out-String | Write-Host
    exit 1
}
$restartedAt = [datetime]::Parse($after[1]).ToUniversalTime()
Write-Step ("Container restarted at {0:u} (downtime about {1:N1}s)" -f $restartedAt, ((Get-Date) - $killTime).TotalSeconds)
Add-Result 'container ID unchanged (same container, restarted in place)' ((Get-ContainerId -Service $script:AppService) -eq $containerId) $containerId.Substring(0, 12)
Add-Result 'restart count incremented' ([int]$after[3] -gt [int]$before[3]) "restartCount=$($after[3])"

Write-Step 'Step 4: wait for the application to become healthy again'
$healthyAt = Wait-ForHealthy -Service $script:AppService -TimeoutSeconds 180
Write-Step ("Healthy at {0:yyyy-MM-dd HH:mm:ss} (total recovery {1:N1}s)" -f $healthyAt, ($healthyAt - $killTime).TotalSeconds)
Add-Result 'app healthy after recovery' $true ("recovery {0:N1}s after SIGKILL" -f ($healthyAt - $killTime).TotalSeconds)

Write-Step 'Step 5: confirm the same URL serves requests'
$health = Invoke-WebRequest -Uri "$script:BaseUrl/health" -UseBasicParsing
Add-Result '/health returns HTTP 200 at localhost:5000' ($health.StatusCode -eq 200) $health.Content
$homepage = Invoke-WebRequest -Uri "$script:BaseUrl/" -UseBasicParsing
Add-Result 'homepage returns HTTP 200 at localhost:5000' ($homepage.StatusCode -eq 200)

Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host
$failed = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
Write-Host ("Summary: {0} checks, {1} failed" -f $results.Count, $failed)
if ($failed -gt 0) { exit 1 }

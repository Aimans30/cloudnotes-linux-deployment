# End-to-end smoke test of the running stack: health, pages, CRUD over HTTP, database,
# process model and network exposure. Exits non-zero if any check fails.
#
# Usage (from the project root, with the stack running):
#   powershell -ExecutionPolicy Bypass -File scripts\verify_deployment.ps1
. "$PSScriptRoot\common.ps1"

$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Check = $Name; Result = $(if ($Passed) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
}

Write-Step 'Validating docker-compose.yml'
& docker compose config --quiet
Add-Result 'docker compose config is valid' ($LASTEXITCODE -eq 0)

Write-Step 'Waiting for app and database health'
$appHealthy = $true
try { Wait-ForHealthy -Service $script:DbService -TimeoutSeconds 90 | Out-Null } catch { $appHealthy = $false }
try { Wait-ForHealthy -Service $script:AppService -TimeoutSeconds 120 | Out-Null } catch { $appHealthy = $false }
Add-Result 'app and db containers report healthy' $appHealthy

$health = Invoke-WebRequest -Uri "$script:BaseUrl/health" -UseBasicParsing
Add-Result '/health returns HTTP 200' ($health.StatusCode -eq 200) $health.Content

$homepage = Invoke-WebRequest -Uri "$script:BaseUrl/" -UseBasicParsing
Add-Result 'homepage loads through localhost:5000' ($homepage.StatusCode -eq 200 -and $homepage.Content -match 'CloudNotes')

# Process model: Gunicorn must be PID 1 of the app container, running as a non-root user.
$appId = Get-ContainerId -Service $script:AppService
$pid1 = ((& docker exec $appId cat /proc/1/cmdline) -join ' ') -replace "`0", ' '
$pid1 = $pid1.Trim()
Add-Result 'Gunicorn is PID 1 in the app container' ($pid1 -match 'gunicorn') $pid1
$uid = (& docker exec $appId id -u).Trim()
Add-Result 'app container runs as non-root' ($uid -ne '0') "uid=$uid"

# CRUD through the real web interface.
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$title = "Verify-$stamp"
Write-Step "Creating note '$title'"
$id = New-CloudNote -Title $title -Content 'first body' -Session $session
$created = Get-CloudNoteApi -Id $id
Add-Result 'create note via form (id returned)' ($created.title -eq $title -and $created.content -eq 'first body') "id=$id"

Write-Step "Editing note $id"
$editPage = Invoke-WebRequest -Uri "$script:BaseUrl/notes/$id/edit" -WebSession $session -UseBasicParsing
$token = [regex]::Match($editPage.Content, 'name="csrf_token" value="([^"]+)"').Groups[1].Value
$null = Invoke-WebRequest -Uri "$script:BaseUrl/notes/$id/edit" -Method Post -WebSession $session -UseBasicParsing `
    -Body @{ title = "$title-edited"; content = 'second body'; csrf_token = $token }
$edited = Get-CloudNoteApi -Id $id
Add-Result 'edit note updates title and content' ($edited.title -eq "$title-edited" -and $edited.content -eq 'second body')
Add-Result 'updated_at is not earlier than created_at' ([datetime]$edited.updated_at -ge [datetime]$edited.created_at)

Write-Step 'Viewing the note list'
$list = Invoke-WebRequest -Uri "$script:BaseUrl/" -WebSession $session -UseBasicParsing
Add-Result 'note list shows the edited note' ($list.Content -match [regex]::Escape("$title-edited"))

Write-Step "Deleting note $id"
$indexPage = Invoke-WebRequest -Uri "$script:BaseUrl/" -WebSession $session -UseBasicParsing
$token = [regex]::Match($indexPage.Content, 'name="csrf_token" value="([^"]+)"').Groups[1].Value
$null = Invoke-WebRequest -Uri "$script:BaseUrl/notes/$id/delete" -Method Post -WebSession $session -UseBasicParsing `
    -Body @{ csrf_token = $token }
$deleted = $true
try { Get-CloudNoteApi -Id $id | Out-Null; $deleted = $false } catch { $deleted = ($_.Exception.Response.StatusCode.value__ -eq 404) }
Add-Result 'delete note removes it (API returns 404)' $deleted

# Database checks: the rows exist in PostgreSQL, and the app is not using SQLite.
$dbCount = Invoke-Psql -Sql "SELECT count(*) FROM notes WHERE id = $id"
Add-Result 'database row removed after delete' ($dbCount -eq '0') "rows=$dbCount"
$version = Invoke-Psql -Sql 'SHOW server_version'
Add-Result 'PostgreSQL is reachable from the app container' ($version -ne '') "server_version=$version"
$appDbUrl = (& docker exec $appId sh -c 'echo $DATABASE_URL') -replace ':[^:@/]+@', ':***@'
Add-Result 'DATABASE_URL points at PostgreSQL' ($appDbUrl -like 'postgresql://*') $appDbUrl

# Network exposure: the web app is published; PostgreSQL is not.
# `docker port` prints nothing when a container port has no host mapping.
$dbPorts = ((& docker port (Get-ContainerId -Service $script:DbService)) | Out-String).Trim()
Add-Result 'PostgreSQL is not published to the host' ($dbPorts -eq '') "published ports='$dbPorts'"

Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host
$failed = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
Write-Host ("Summary: {0} checks, {1} failed" -f $results.Count, $failed)
if ($failed -gt 0) { exit 1 }

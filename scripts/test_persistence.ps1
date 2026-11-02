# Persistence test: a note must survive an application restart and a PostgreSQL restart,
# with exactly the same content. Verified through the HTTP API and direct SQL queries.
#
# Usage (stack running):  powershell -ExecutionPolicy Bypass -File scripts\test_persistence.ps1
. "$PSScriptRoot\common.ps1"

$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$title = "PERSIST-$stamp"
$content = "Persistence check $stamp`nLine two with special chars: <&> ""quotes"" 'single' and tabs`tend"
$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Check = $Name; Result = $(if ($Passed) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
}

Write-Step 'Step 1: create a note with a recognisable title and content'
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$id = New-CloudNote -Title $title -Content $content -Session $session
$before = Get-CloudNoteApi -Id $id
Write-Step "Created note id=$id"
Add-Result 'note created with expected title and content' ($before.title -ceq $title -and $before.content -ceq $content) "id=$id"

$dbBefore = Invoke-Psql -Sql "SELECT content FROM notes WHERE id = $id"
Add-Result 'note row exists in PostgreSQL before restarts' ($dbBefore -ne '') "id=$id"

Write-Step 'Step 2: restart the application container'
$appStart = Get-Date
Invoke-Compose -Arguments @('restart', $script:AppService)
$appHealthy = Wait-ForHealthy -Service $script:AppService -TimeoutSeconds 120
Write-Step ("Application healthy again after {0:N1}s" -f ($appHealthy - $appStart).TotalSeconds)
$afterApp = Get-CloudNoteApi -Id $id
Add-Result 'note survives application restart (API)' ($afterApp.title -ceq $title -and $afterApp.content -ceq $content) `
    ("restart took {0:N1}s" -f ($appHealthy - $appStart).TotalSeconds)

Write-Step 'Step 3: restart the PostgreSQL container'
$dbStart = Get-Date
Invoke-Compose -Arguments @('restart', $script:DbService)
$dbHealthy = Wait-ForHealthy -Service $script:DbService -TimeoutSeconds 120
Write-Step ("PostgreSQL healthy again after {0:N1}s" -f ($dbHealthy - $dbStart).TotalSeconds)
Wait-ForHttpOk -Url "$script:BaseUrl/health" -TimeoutSeconds 120 | Out-Null

$afterDb = Get-CloudNoteApi -Id $id
Add-Result 'note survives PostgreSQL restart (API, exact match)' ($afterDb.title -ceq $title -and $afterDb.content -ceq $content)
$dbAfter = Invoke-Psql -Sql "SELECT content FROM notes WHERE id = $id"
Add-Result 'note row present in PostgreSQL after restart (SQL)' ($dbAfter -eq $dbBefore.Trim()) "rows content length=$($dbAfter.Length)"

Write-Step 'Cleanup: deleting the test note'
$page = Invoke-WebRequest -Uri "$script:BaseUrl/notes/$id" -WebSession $session -UseBasicParsing
$token = [regex]::Match($page.Content, 'name="csrf_token" value="([^"]+)"').Groups[1].Value
$null = Invoke-WebRequest -Uri "$script:BaseUrl/notes/$id/delete" -Method Post -WebSession $session -UseBasicParsing -Body @{ csrf_token = $token }

Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host
$failed = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
Write-Host ("Summary: {0} checks, {1} failed" -f $results.Count, $failed)
if ($failed -gt 0) { exit 1 }

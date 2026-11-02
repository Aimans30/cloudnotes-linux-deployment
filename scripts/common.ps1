# Shared helpers for the CloudNotes PowerShell test scripts. Dot-source this file.
$ErrorActionPreference = 'Stop'

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:BaseUrl = 'http://localhost:5000'
$script:AppService = 'app'
$script:DbService = 'db'

Set-Location $script:ProjectRoot

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Get-ContainerId {
    param([string]$Service)
    $id = (& docker compose ps -q $Service).Trim()
    if (-not $id) { throw "No container found for service '$Service'. Is the stack running?" }
    return $id
}

function Wait-ForHealthy {
    param([string]$Service, [int]$TimeoutSeconds = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $id = Get-ContainerId -Service $Service
        $status = (& docker inspect -f '{{.State.Health.Status}}' $id).Trim()
        if ($status -eq 'healthy') { return (Get-Date) }
        Start-Sleep -Seconds 2
    }
    throw "Service '$Service' did not become healthy within $TimeoutSeconds seconds."
}

function Wait-ForHttpOk {
    param([string]$Url, [int]$TimeoutSeconds = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq 200) { return (Get-Date) }
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    throw "$Url did not return HTTP 200 within $TimeoutSeconds seconds."
}

function Invoke-Psql {
    # Runs a SQL statement inside the database container. Returns trimmed stdout.
    param([string]$Sql)
    $output = & docker compose exec -T $script:DbService psql -U cloudnotes_admin -d cloudnotes -tA -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "psql failed for: $Sql" }
    return ($output | Out-String).Trim()
}

function New-CloudNote {
    # Creates a note through the real HTML form (including the CSRF token). Returns its ID.
    param([string]$Title, [string]$Content, [Microsoft.PowerShell.Commands.WebRequestSession]$Session)
    $form = Invoke-WebRequest -Uri "$script:BaseUrl/notes/new" -WebSession $Session -UseBasicParsing
    $token = [regex]::Match($form.Content, 'name="csrf_token" value="([^"]+)"').Groups[1].Value
    if (-not $token) { throw 'CSRF token not found on the create form.' }
    $body = @{ title = $Title; content = $Content; csrf_token = $token }
    $response = Invoke-WebRequest -Uri "$script:BaseUrl/notes" -Method Post -Body $body -WebSession $Session -UseBasicParsing
    $match = [regex]::Match($response.BaseResponse.ResponseUri.AbsoluteUri, '/notes/(\d+)$')
    if (-not $match.Success) { throw "Note creation did not redirect to a note page: $($response.BaseResponse.ResponseUri)" }
    return [int]$match.Groups[1].Value
}

function Get-CloudNoteApi {
    param([int]$Id)
    return Invoke-RestMethod -Uri "$script:BaseUrl/api/notes/$Id" -UseBasicParsing
}

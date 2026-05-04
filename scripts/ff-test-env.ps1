# FocusFlow disposable test environment: optional Postgres + migrations + automated tests.
# Run from repo root:  powershell -ExecutionPolicy Bypass -File scripts/ff-test-env.ps1
# Teardown runs in finally when the test compose stack was started.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $repoRoot "mobile/pubspec.yaml"))) {
  throw "Run this from the FocusFlow repo root (expected mobile/pubspec.yaml under $repoRoot)."
}

$composeFile = Join-Path $repoRoot "backend/docker-compose.test-env.yml"
$composeProject = "ff_test_env"
$databaseUrl = "postgresql://postgres:ff_test_env_pw@127.0.0.1:5434/focusflow_test?schema=public"
$composeStarted = $false
$results = @()

try {
  $dockerOk = $false
  if (Get-Command docker -ErrorAction SilentlyContinue) {
    $prevEa = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    & docker info *> $null
    $ErrorActionPreference = $prevEa
    if ($LASTEXITCODE -eq 0) { $dockerOk = $true }
  }
  if (-not $dockerOk) {
    $results += "Docker: not available - skipped isolated Postgres and migrate deploy."
  } else {
    try {
      & docker compose -p $composeProject -f $composeFile up -d
      if ($LASTEXITCODE -ne 0) { throw "compose up failed" }
      $ready = $false
      for ($i = 0; $i -lt 40; $i++) {
        & docker compose -p $composeProject -f $composeFile exec -T postgres_test pg_isready -U postgres -d focusflow_test 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 2
      }
      if (-not $ready) { throw "postgres not ready" }
      $env:DATABASE_URL = $databaseUrl
      Push-Location (Join-Path $repoRoot "backend")
      & npx prisma migrate deploy
      if ($LASTEXITCODE -ne 0) { throw "migrate deploy failed" }
      Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
      Pop-Location
      $composeStarted = $true
      $results += "Docker test Postgres: up on 127.0.0.1:5434, migrations applied."
    } catch {
      $results += "Docker: compose or migrate failed - $($_.Exception.Message). Continuing with unit tests only."
      try {
        & docker compose -p $composeProject -f $composeFile down -v 2>$null
      } catch { }
      $composeStarted = $false
    }
  }

  Push-Location (Join-Path $repoRoot "backend")
  & npm test
  if ($LASTEXITCODE -ne 0) { throw "backend npm test failed" }
  $results += "Backend unit tests (jest): PASS"
  & npm run test:e2e
  if ($LASTEXITCODE -ne 0) { throw "backend test:e2e failed" }
  $results += "Backend e2e (jest): PASS"
  Pop-Location

  Push-Location (Join-Path $repoRoot "mobile")
  & dart analyze .
  if ($LASTEXITCODE -ne 0) { throw "dart analyze failed" }
  $results += "Mobile dart analyze: PASS"
  & flutter test
  if ($LASTEXITCODE -ne 0) { throw "flutter test failed" }
  $results += "Mobile flutter test: PASS"
  Pop-Location
}
finally {
  if ($composeStarted -and (Get-Command docker -ErrorAction SilentlyContinue) -and (Test-Path $composeFile)) {
    & docker compose -p $composeProject -f $composeFile down -v 2>$null
    $results += "Docker test environment: torn down (down -v)."
  }
}

$results | ForEach-Object { Write-Output $_ }

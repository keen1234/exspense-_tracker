#Requires -Version 5.1

<#
.SYNOPSIS
    Builds an Android release of the Expense Tracker app.
.DESCRIPTION
    Prompts for a version, updates pubspec.yaml, and builds APK + AAB.
#>

$ErrorActionPreference = "Stop"

function Read-Value($prompt, $default) {
    $raw = Read-Host -Prompt "${prompt} (default: $default)"
    if ([string]::IsNullOrWhiteSpace($raw)) { return $default }
    return $raw.Trim()
}

function Write-Step($msg) {
    Write-Host "`n>>> $msg" -ForegroundColor Cyan
}

# --- 1. Version ---
$currentVersion = "1.4.1"
$pubspec = Join-Path $PSScriptRoot "pubspec.yaml"

if (Test-Path $pubspec) {
    $match = Select-String -Path $pubspec -Pattern '^version:\s*(.+)$'
    if ($match) { $currentVersion = $match.Matches.Groups[1].Value.Trim() }
}

Write-Host "Current version: $currentVersion" -ForegroundColor Yellow
$version = Read-Value "Enter new version (X.Y.Z[+build])" $currentVersion

# --- 2. Confirm ---
Write-Host "`nVersion to build: " -NoNewline
Write-Host $version -ForegroundColor Green
$confirmed = Read-Host "Continue? (Y/n)"
if ($confirmed -eq "n") { Write-Host "Aborted."; exit 0 }

# --- 3. Update pubspec.yaml ---
Write-Step "Updating pubspec.yaml to version $version"
$content = Get-Content $pubspec -Raw
$content = $content -replace '(?m)^version:.*$', "version: $version"
Set-Content $pubspec -Value $content -NoNewline

# --- 4. Flutter pub get ---
Write-Step "Running flutter pub get"
Push-Location $PSScriptRoot
try {
    flutter pub get
    if (-not $?) { throw "flutter pub get failed" }
} finally { Pop-Location }

# --- 5. Build APK ---
Write-Step "Building APK"
Push-Location $PSScriptRoot
try {
    flutter build apk -t lib\main.dart
    if (-not $?) { throw "APK build failed" }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} finally { Pop-Location }

# --- 6. Build App Bundle ---
Write-Step "Building App Bundle (AAB)"
Push-Location $PSScriptRoot
try {
    flutter build appbundle
    if (-not $?) { throw "App Bundle build failed" }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} finally { Pop-Location }

# --- 7. Git tag (optional) ---
$tag = Read-Host "`nCreate git tag v${version}? (y/N)"
if ($tag -eq "y") {
    git add $pubspec
    git commit -m "chore: bump version to $version"
    git tag -a "v$version" -m "Release v$version"
    Write-Host "Tag v$version created." -ForegroundColor Yellow

    $push = Read-Host "Push commit and tags to remote? (y/N)"
    if ($push -eq "y") {
        git push
        git push --tags
        Write-Host "Changes and tags pushed to remote." -ForegroundColor Green
    }
}

Write-Step "Done! Built version $version (APK + AAB)"

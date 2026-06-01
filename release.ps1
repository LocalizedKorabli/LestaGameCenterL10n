<#
.SYNOPSIS
    Upload lgc_l10n.7z artifact to GitHub Release.
.DESCRIPTION
    Reads version from metadata/l10n.json, constructs tag name
    as {supported_lgc_version}-{version}, creates Release and uploads 7z.
.EXAMPLE
    .\release-l10n.ps1
    .\release-l10n.ps1 -Draft
    .\release-l10n.ps1 -NotesFile RELEASE_NOTES.md
#>

param(
    [switch]$Draft,
    [string]$Notes,
    [string]$NotesFile
)

$ErrorActionPreference = "Stop"

# ─── 1. Check gh CLI ─────────────────────────────────────────────
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] GitHub CLI (gh) not found. Install: winget install GitHub.cli" -ForegroundColor Red
    exit 1
}

# ─── 2. Read metadata/l10n.json ──────────────────────────────────
$metaPath = "metadata/l10n.json"
if (-not (Test-Path $metaPath)) {
    Write-Host "[ERROR] Run this script from the project root directory" -ForegroundColor Red
    exit 1
}

$metaContent = Get-Content -Path $metaPath -Encoding UTF8 -Raw | ConvertFrom-Json
$lgcVersion = $metaContent.version
$supportedLgcVersion = $metaContent.supported_lgc_version

if (-not $lgcVersion -or -not $supportedLgcVersion) {
    Write-Host "[ERROR] Cannot read version or supported_lgc_version from $metaPath" -ForegroundColor Red
    exit 1
}

$tagName = "LGC-${supportedLgcVersion}-${lgcVersion}"

Write-Host "[INFO] Version: $lgcVersion" -ForegroundColor Cyan
Write-Host "[INFO] Supported LGC: $supportedLgcVersion" -ForegroundColor Cyan

# ─── 3. Check for 7z file ───────────────────────────────────────
$archivePath = "artifacts/lgc_l10n.7z"
if (-not (Test-Path $archivePath)) {
    Write-Host "[ERROR] Archive not found at: $archivePath" -ForegroundColor Red
    Write-Host "    Make sure the 7z file exists in the artifacts directory" -ForegroundColor Yellow
    exit 1
}

$fileSize = (Get-Item $archivePath).Length
$sizeStr = if ($fileSize -gt 1GB) { "{0:N2} GB" -f ($fileSize / 1GB) } else { "{0:N2} MB" -f ($fileSize / 1MB) }
Write-Host "[INFO] Archive: lgc_l10n.7z ($sizeStr)" -ForegroundColor Green

# ─── 4. Delete existing tag if present ───────────────────────────
$tagExists = git tag -l "$tagName" | Select-String -SimpleMatch "$tagName" -Quiet
if ($tagExists) {
    Write-Host "[WARN] Tag '$tagName' exists, deleting ..." -ForegroundColor Yellow
    git tag -d "$tagName"
    git push origin --delete "$tagName" 2>$null
}

# ─── 5. Create GitHub Release ────────────────────────────────────
Write-Host "[INFO] Creating GitHub Release $tagName ..." -ForegroundColor Cyan

$ghArgs = @(
    "release", "create", $tagName,
    $archivePath,
    "--title", $tagName
)

if ($Draft) {
    $ghArgs += "--draft"
} elseif ($NotesFile) {
    if (-not (Test-Path $NotesFile)) {
        Write-Host "[ERROR] Notes file not found: $NotesFile" -ForegroundColor Red
        exit 1
    }
    $ghArgs += "--notes-file", $NotesFile
} elseif ([string]::IsNullOrEmpty($Notes)) {
    $ghArgs += "--generate-notes"
} else {
    $ghArgs += "--notes", $Notes
}

$result = & gh $ghArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to create Release: $result" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[OK] Release created: $tagName" -ForegroundColor Green
Write-Host "    https://github.com/LocalizedKorabli/LestaGameCenterL10n/releases/tag/$tagName"
Write-Host ""
Write-Host "GitHub Actions will now run in the background:"
Write-Host "  1. Download lgc_l10n.7z from this Release"
Write-Host "  2. Upload to Cloudflare R2"
Write-Host "  3. Trigger Cloudflare Pages deploy"
Write-Host ""
Write-Host "Check progress at: https://github.com/LocalizedKorabli/LestaGameCenterL10n/actions" -ForegroundColor Cyan

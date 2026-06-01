<# 
.SYNOPSIS
    Build LK-Lateral NSIS installer and publish to GitHub Release.
.DESCRIPTION
    Auto-reads version from Cargo.toml, locates NSIS installer, creates GitHub Release.
    After this, GitHub Actions will handle R2 upload, metadata.json update, and Pages deploy.
.PARAMETER Notes
    Release notes text. Use double quotes for multi-word text.
    Example: -Notes "Bug fixes and improvements"
.PARAMETER NotesFile
    Path to a file containing release notes. Use this instead of -Notes for long text.
    Example: -NotesFile RELEASE_NOTES.md
.PARAMETER Draft
    Create a draft release (not published immediately).
.PARAMETER SkipBuild
    Skip tauri build, use existing NSIS installer.
.EXAMPLE
    .\release.ps1
    .\release.ps1 -Draft
    .\release.ps1 -SkipBuild
    .\release.ps1 -Notes "Bug fixes and improvements"
    .\release.ps1 -NotesFile RELEASE_NOTES.md
#>

param(
    [switch]$Draft,
    [switch]$SkipBuild,
    [string]$Notes,
    [string]$NotesFile
)

$ErrorActionPreference = "Stop"

# ─── 1. Check gh CLI ─────────────────────────────────────────────
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] GitHub CLI (gh) not found. Install: winget install GitHub.cli" -ForegroundColor Red
    exit 1
}

# ─── 2. Read version from Cargo.toml ─────────────────────────────
$cargoPath = "src-tauri\Cargo.toml"
if (-not (Test-Path $cargoPath)) {
    Write-Host "[ERROR] Run this script from the project root directory" -ForegroundColor Red
    exit 1
}

$cargoContent = Get-Content -Path $cargoPath -Encoding UTF8 -Raw
$versionMatch = [regex]::Match($cargoContent, 'version\s*=\s*"([^"]+)"')
if (-not $versionMatch.Success) {
    Write-Host "[ERROR] Cannot read version from Cargo.toml" -ForegroundColor Red
    exit 1
}
$appVersion = $versionMatch.Groups[1].Value
$tagName = "v$appVersion"

Write-Host "[INFO] Version: $appVersion" -ForegroundColor Cyan

if ($Notes -and $NotesFile) {
    Write-Host "[ERROR] Use either -Notes or -NotesFile, not both" -ForegroundColor Red
    exit 1
}

# ─── 3. Delete existing tag if present ───────────────────────────
$tagExists = git tag -l "$tagName" | Select-String -SimpleMatch "$tagName" -Quiet
if ($tagExists) {
    Write-Host "[WARN] Tag '$tagName' exists, deleting ..." -ForegroundColor Yellow
    git tag -d "$tagName"
    git push origin --delete "$tagName" 2>$null
}

# ─── 4. Build → locate NSIS installer ────────────────────────────
if (-not $SkipBuild) {
    Write-Host "[INFO] Building Tauri + NSIS installer ..." -ForegroundColor Cyan
    npm run tauri build -- --bundles nsis
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Build failed" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Build complete" -ForegroundColor Green
} else {
    Write-Host "[INFO] Skipping build, using existing installer" -ForegroundColor Yellow
}

$appName = "LK-Lateral"
$fileName = "${appName}_${appVersion}_x64-setup.exe"
$nsisPath = "src-tauri\target\release\bundle\nsis\$fileName"

if (-not (Test-Path $nsisPath)) {
    Write-Host "[ERROR] Installer not found at: $nsisPath" -ForegroundColor Red
    exit 1
}

$fileSize = (Get-Item $nsisPath).Length
$sizeStr = if ($fileSize -gt 1GB) { "{0:N2} GB" -f ($fileSize / 1GB) } else { "{0:N2} MB" -f ($fileSize / 1MB) }
Write-Host "[INFO] Installer: $fileName ($sizeStr)" -ForegroundColor Green

# ─── 5. Create GitHub Release ────────────────────────────────────
Write-Host "[INFO] Creating GitHub Release $tagName ..." -ForegroundColor Cyan

$ghArgs = @(
    "release", "create", $tagName,
    $nsisPath,
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
Write-Host "    https://github.com/LocalizedKorabli/LK-Lateral/releases/tag/$tagName"
Write-Host ""
Write-Host "GitHub Actions will now run in the background:"
Write-Host "  1. Upload installer to Cloudflare R2"
Write-Host "  2. Update metadata.json and commit to repo"
Write-Host "  3. Trigger Cloudflare Pages deploy"
Write-Host ""
Write-Host "Check progress at: https://github.com/LocalizedKorabli/LK-Lateral/actions" -ForegroundColor Cyan

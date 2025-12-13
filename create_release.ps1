param (
    [string]$Token
)

if ([string]::IsNullOrEmpty($Token)) {
    Write-Error "Please provide a GitHub Token using -Token argument."
    exit 1
}

$repoOwner = "Renewable-Energy-Systems"
$repoName = "wi-display"
$apiUrl = "https://api.github.com/repos/$repoOwner/$repoName"

# 1. Get Version from pubspec.yaml
$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -match "version: (\d+\.\d+\.\d+)") {
    $version = "v" + $matches[1]
    Write-Host "Detected Version: $version" -ForegroundColor Cyan
} else {
    Write-Error "Could not parse version from pubspec.yaml"
    exit 1
}

# 2. Build APK
Write-Host "Building Release APK..." -ForegroundColor Yellow
cmd /c "flutter build apk --release"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build Failed."
    exit 1
}

$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkPath)) {
    Write-Error "APK not found at $apkPath"
    exit 1
}

# 3. Create Release (this creates the tag too)
Write-Host "Creating Release $version on GitHub..." -ForegroundColor Yellow
$body = @{
    tag_name = $version
    target_commitish = "main"
    name = "$version Release"
    body = "Automated release via script."
    draft = $false
    prerelease = $false
} | ConvertTo-Json

$headers = @{
    "Authorization" = "Bearer $Token"
    "Accept" = "application/vnd.github+json"
    "Content-Type" = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri "$apiUrl/releases" -Method Post -Headers $headers -Body $body -ErrorAction Stop
    $uploadUrl = $response.upload_url -replace "{.*}", ""
    Write-Host "Release created successfully!" -ForegroundColor Green
} catch {
    Write-Host "Error creating release. It might already exist." -ForegroundColor Red
    Write-Host $_.Exception.Message
    # Try to get existing release to upload asset anyway? 
    # For now, just exit.
    exit 1
}

# 4. Upload Asset
Write-Host "Uploading APK Asset..." -ForegroundColor Yellow
$fileName = "app-release.apk"
$fileContent = [System.IO.File]::ReadAllBytes($apkPath)

$uploadHeaders = @{
    "Authorization" = "Bearer $Token"
    "Content-Type" = "application/vnd.android.package-archive"
}

try {
    Invoke-RestMethod -Uri "$uploadUrl?name=$fileName" -Method Post -Headers $uploadHeaders -Body $fileContent
    Write-Host "APK Uploaded Successfully!" -ForegroundColor Green
} catch {
    Write-Error "Failed to upload asset: $($_.Exception.Message)"
}

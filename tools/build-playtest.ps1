[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
$template = Join-Path $projectRoot '.tools/export-templates/windows_debug_x86_64.exe'
$required = @(
    $engine, $template,
    (Join-Path $projectRoot '.tools/export-templates/windows_release_x86_64.exe'),
    (Join-Path $projectRoot 'Playtest.cmd'),
    (Join-Path $projectRoot 'tools/playtest.ps1'),
    (Join-Path $projectRoot 'docs/playtest-participant.ko.md'),
    (Join-Path $projectRoot '.tools/GODOT-LICENSE.txt'),
    (Join-Path $projectRoot '.tools/GODOT-COPYRIGHT.txt')
)
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Missing build input: $file. See docs/windows-playtest-build.ko.md."
    }
}

$buildId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$buildRoot = Join-Path $projectRoot 'builds'
$packageName = 'SISYPHUS-v0.2-Windows-' + $buildId
$packagePath = Join-Path $buildRoot $packageName
[void](New-Item -ItemType Directory -Path (Join-Path $packagePath 'tools') -Force)
$exportLog = Join-Path $projectRoot ('.tools/export-' + $buildId + '.log')
$executable = Join-Path $packagePath 'SISYPHUS.exe'
& $engine --headless --path $projectRoot --log-file $exportLog --export-debug 'Windows Playtest' $executable
if ($LASTEXITCODE -ne 0) { throw "Godot export failed. See $exportLog" }
foreach ($file in @($executable, (Join-Path $packagePath 'SISYPHUS.pck'))) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Export did not produce $file" }
}

# Only explicitly listed files enter this fresh package; playtest records never do.
Copy-Item -LiteralPath (Join-Path $projectRoot 'Playtest.cmd') -Destination $packagePath
Copy-Item -LiteralPath (Join-Path $projectRoot 'tools/playtest.ps1') -Destination (Join-Path $packagePath 'tools')
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/playtest-participant.ko.md') -Destination (Join-Path $packagePath 'START-HERE.txt')
Copy-Item -LiteralPath (Join-Path $projectRoot '.tools/GODOT-LICENSE.txt') -Destination $packagePath
Copy-Item -LiteralPath (Join-Path $projectRoot '.tools/GODOT-COPYRIGHT.txt') -Destination $packagePath
$utf8 = New-Object System.Text.UTF8Encoding($true)
$metadata = [ordered]@{
    build_id = $buildId
    game_version = '0.2-playtest'
    engine_version = '4.5.1.stable'
    platform = 'Windows x86_64'
    export_type = 'debug'
    created_at = [DateTime]::UtcNow.ToString('o')
    signed = $false
}
[IO.File]::WriteAllText((Join-Path $packagePath 'build-info.json'), ($metadata | ConvertTo-Json), $utf8)
$zipPath = Join-Path $buildRoot ($packageName + '.zip')
Compress-Archive -LiteralPath $packagePath -DestinationPath $zipPath -CompressionLevel Optimal
$sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zipPath + '.sha256'), ($sha256 + '  ' + [IO.Path]::GetFileName($zipPath) + [Environment]::NewLine), $utf8)
[pscustomobject]@{ Package = $packagePath; Zip = $zipPath; SHA256 = $sha256; ExportLog = $exportLog }

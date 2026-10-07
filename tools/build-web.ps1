[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
$required = @(
    $engine,
    (Join-Path $projectRoot '.tools/export-templates/web_nothreads_debug.zip'),
    (Join-Path $projectRoot '.tools/export-templates/web_nothreads_release.zip'),
    (Join-Path $projectRoot 'web/shell.html'),
    (Join-Path $projectRoot 'third_party/godot/LICENSE.txt'),
    (Join-Path $projectRoot 'third_party/godot/COPYRIGHT.txt'),
    (Join-Path $projectRoot 'assets/fonts/OFL.txt')
)
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing Web build input: $file. See docs/web-play.ko.md." }
}
$output = Join-Path $projectRoot 'builds/web'
[void][IO.Directory]::CreateDirectory($output)
$logPath = Join-Path $projectRoot '.tools/export-web.log'
& $engine --headless --path $projectRoot --log-file $logPath --export-release 'Web' (Join-Path $output 'index.html')
if ($LASTEXITCODE -ne 0) { throw "Web export failed. See $logPath" }
foreach ($name in @('index.html', 'index.js', 'index.wasm', 'index.pck')) {
    $artifact = Join-Path $output $name
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf) -or (Get-Item -LiteralPath $artifact).Length -eq 0) { throw "Missing Web export artifact: $artifact" }
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'third_party/godot/LICENSE.txt') -Destination (Join-Path $output 'GODOT-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'third_party/godot/COPYRIGHT.txt') -Destination (Join-Path $output 'GODOT-COPYRIGHT.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/fonts/OFL.txt') -Destination (Join-Path $output 'FONT-LICENSE.txt') -Force
[IO.File]::WriteAllText((Join-Path $output '.nojekyll'), '', [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Output = $output; Entry = (Join-Path $output 'index.html'); Log = $logPath }

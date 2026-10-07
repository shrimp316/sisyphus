[CmdletBinding()]
param(
    [ValidatePattern('^(0[1-9]|10)?$')][string]$ParticipantId = '',
    [ValidateSet('', 'practice', 'normal')][string]$Course = '',
    [ValidateSet('new', 'resume')][string]$Mode = 'new',
    [ValidatePattern('^([0-9]{8}T[0-9]{6}Z-[a-f0-9]{8})?$')][string]$SessionId = '',
    [switch]$PlanOnly,
    [switch]$PrepareOnly,
    [switch]$SkipObservations,
    [ValidateSet('self_report', 'facilitator_observation')][string]$ObservationSource = 'self_report'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resultsRoot = Join-Path $projectRoot 'playtest-results'
$utf8 = New-Object Text.UTF8Encoding($false)
$buildId = 'development-unpackaged'
$gameVersion = '0.2-development'
$buildInfoPath = Join-Path $projectRoot 'build-info.json'
if (Test-Path -LiteralPath $buildInfoPath -PathType Leaf) {
    $buildInfo = [IO.File]::ReadAllText($buildInfoPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $buildInfo.build_id -or -not $buildInfo.game_version) { throw 'build-info.json에 빌드 정보가 없습니다.' }
    $buildId = [string]$buildInfo.build_id
    $gameVersion = [string]$buildInfo.game_version
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($Path, $json, $utf8)
}

function Read-JsonFile {
    param([string]$Path)
    return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Resolve-Game {
    $exported = Join-Path $projectRoot 'SISYPHUS.exe'
    if (Test-Path -LiteralPath $exported -PathType Leaf) {
        return [pscustomobject]@{ Path = $exported; Exported = $true }
    }
    $bundled = Join-Path $projectRoot '.tools/godot/Godot_v4.5.1-stable_win64.exe'
    if (Test-Path -LiteralPath $bundled -PathType Leaf) {
        return [pscustomobject]@{ Path = $bundled; Exported = $false }
    }
    foreach ($name in @('godot', 'godot4')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { return [pscustomobject]@{ Path = $command.Source; Exported = $false } }
    }
    return $null
}

function Assert-SafeSessionPath {
    param([string]$Path)
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($resultsRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw '세션 경로가 playtest-results 폴더 밖을 가리킵니다.'
    }
    # Refuse junctions/symlinks so an apparently local session cannot target another folder.
    $cursor = $resolved
    while ($cursor -and $cursor.StartsWith([IO.Path]::GetFullPath($resultsRoot), [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $cursor) {
            $entry = Get-Item -LiteralPath $cursor -Force
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw '결과 폴더 안의 바로 가기나 연결 폴더는 사용할 수 없습니다.'
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
}

if ($PlanOnly -and $PrepareOnly) { throw '-PlanOnly와 -PrepareOnly는 함께 사용할 수 없습니다.' }
$interactive = [string]::IsNullOrEmpty($ParticipantId) -or [string]::IsNullOrEmpty($Course)
if (($PlanOnly -or $PrepareOnly) -and $interactive) {
    throw '준비/계획 실행에는 -ParticipantId와 -Course를 지정하세요.'
}
if ($interactive) {
    Write-Host ''
    Write-Host '시지프스 플레이테스트 — 진행자용 실행 도구' -ForegroundColor Cyan
    Write-Host '실제 이름 대신 배정받은 참가자 번호를 사용하세요. 기존 게임 저장과 분리됩니다.'
}
while ($ParticipantId -notmatch '^(0[1-9]|10)$') {
    $ParticipantId = (Read-Host '참가자 번호 [01~10]').Trim()
}
while ($Course -notin @('practice', 'normal')) {
    $answer = (Read-Host '코스: 1 연습 / 2 본 테스트').Trim()
    if ($answer -eq '1') { $Course = 'practice' }
    elseif ($answer -eq '2') { $Course = 'normal' }
}
if ($interactive -and -not $PSBoundParameters.ContainsKey('Mode')) {
    do { $answer = (Read-Host '새 세션 [Enter/N] / 저장된 세션 이어서 [R]').Trim().ToLowerInvariant() }
    while ($answer -notin @('', 'n', 'r'))
    $Mode = if ($answer -eq 'r') { 'resume' } else { 'new' }
}
if ($Mode -eq 'new' -and $SessionId) { throw '-SessionId는 -Mode resume에서만 사용할 수 있습니다.' }

$courseRoot = Join-Path (Join-Path $resultsRoot ('participant-' + $ParticipantId)) $Course
Assert-SafeSessionPath $courseRoot
if ($Mode -eq 'new') {
    $SessionId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
} elseif (-not $SessionId) {
    if ($PlanOnly -or $PrepareOnly) { throw '이어서 준비할 때는 -SessionId를 지정하세요.' }
    $sessions = @()
    if (Test-Path -LiteralPath $courseRoot) {
        $sessions = @(Get-ChildItem -LiteralPath $courseRoot -Directory | Where-Object {
            $_.Name -match '^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$' -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'session.json')) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'save.json'))
        } | Sort-Object Name -Descending)
    }
    if ($sessions.Count -eq 0) { throw '이 참가자·코스에 저장된 세션이 없습니다. 새 세션을 선택하세요.' }
    for ($index = 0; $index -lt $sessions.Count; $index++) {
        Write-Host ('{0}. {1}' -f ($index + 1), $sessions[$index].Name)
    }
    $selection = 0
    do { $answer = Read-Host '이어서 할 세션 번호' }
    while (-not [int]::TryParse($answer, [ref]$selection) -or $selection -lt 1 -or $selection -gt $sessions.Count)
    $SessionId = $sessions[$selection - 1].Name
}
$sessionRoot = Join-Path $courseRoot $SessionId
Assert-SafeSessionPath $sessionRoot
$savePath = Join-Path $sessionRoot 'save.json'
$metadataPath = Join-Path $sessionRoot 'session.json'
$observationsPath = Join-Path $sessionRoot 'observations.json'
$launchId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 4)
$logPath = Join-Path $sessionRoot ('godot-' + $launchId + '.log')
$metadata = $null
if ($Mode -eq 'resume') {
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf) -or -not (Test-Path -LiteralPath $savePath -PathType Leaf)) {
        throw '이 참가자·코스의 세션 정보와 저장 파일이 모두 있어야 이어서 할 수 있습니다.'
    }
    Assert-SafeSessionPath $metadataPath
    Assert-SafeSessionPath $savePath
    $metadata = Read-JsonFile $metadataPath
    if ($metadata.schema_version -ne 1 -or $metadata.participant_id -cne $ParticipantId -or $metadata.course -cne $Course -or $metadata.session_id -cne $SessionId) {
        throw '세션 정보가 선택한 참가자·코스와 일치하지 않습니다.'
    }
    if (-not ($metadata.PSObject.Properties.Name -contains 'build_id') -or $metadata.build_id -cne $buildId) {
        throw '다른 빌드에서 저장한 세션입니다. 이전 배포본으로 이어서 하거나 현재 빌드에서 새 세션을 시작하세요.'
    }
} elseif (Test-Path -LiteralPath $sessionRoot) {
    throw '동일한 세션 폴더가 이미 있습니다. 다시 실행하여 새 세션을 만드세요.'
}
$game = Resolve-Game
$arguments = @('--log-file', ('"' + $logPath + '"'))
if ($null -ne $game -and -not $game.Exported) { $arguments += @('--path', ('"' + $projectRoot + '"')) }
$conditionSeed = if ($Course -eq 'normal') { 42 } else { 1 }
$arguments += @('--', ('"--save-path=' + $savePath + '"'), ('--seed=' + $conditionSeed), '--weather=clear')
if ($Course -eq 'practice') { $arguments += '--debug-course' }
$plan = [pscustomobject][ordered]@{
    participant_id = $ParticipantId; course = $Course; mode = $Mode; session_id = $SessionId
    build_id = $buildId; game_version = $gameVersion
    session_path = $sessionRoot; save_path = $savePath; metadata_path = $metadataPath
    observations_path = $observationsPath; log_path = $logPath
    executable = if ($null -ne $game) { $game.Path } else { $null }
    arguments = $arguments; condition = [pscustomobject]@{ seed = if ($Course -eq 'normal') { 42 } else { 1 }; weather = 'clear'; debug_course = ($Course -eq 'practice') }
}
if ($PlanOnly) { return $plan }
if (-not $PrepareOnly -and $null -eq $game) {
    throw 'SISYPHUS.exe 또는 Godot 4.5 이상 실행 파일을 찾지 못했습니다. 배포 폴더 전체를 압축 해제하세요.'
}
if ($Mode -eq 'new') {
    [IO.Directory]::CreateDirectory($sessionRoot) | Out-Null
    $metadata = [pscustomobject][ordered]@{
        schema_version = 1; participant_id = $ParticipantId; course = $Course; session_id = $SessionId
        build_id = $buildId; game_version = $gameVersion
        created_at = [DateTime]::UtcNow.ToString('o'); condition = $plan.condition
        status = 'prepared'; launches = @(); observation_source = $ObservationSource
    }
    $observations = [ordered]@{}
    foreach ($criterion in @('A', 'B', 'C', 'D', 'E')) {
        $observations[$criterion] = [ordered]@{ status = 'unknown'; evidence = '' }
    }
    Write-JsonFile $observationsPath ([ordered]@{
        schema_version = 1; participant_id = $ParticipantId; course = $Course; session_id = $SessionId
        build_id = $buildId; game_version = $gameVersion
        completed_at = $null; observations = $observations; notes = ''; observation_source = $ObservationSource
    })
    Write-JsonFile $metadataPath $metadata
}
if ($PrepareOnly) { return $plan }

Write-Host ''
Write-Host ('참가자 {0} · {1} · {2}' -f $ParticipantId, $Course, $SessionId) -ForegroundColor Cyan
Write-Host '게임이 끝나면 이 창으로 돌아오세요. Esc 메뉴에서 저장 후 종료할 수 있습니다.'
Write-Host ('결과 폴더: ' + $sessionRoot)
$launch = [pscustomobject]@{ started_at = [DateTime]::UtcNow.ToString('o'); ended_at = $null; exit_code = $null; log_file = [IO.Path]::GetFileName($logPath) }
$metadata.launches = @($metadata.launches) + $launch
$metadata.status = 'running'
Write-JsonFile $metadataPath $metadata
# The participant requested an interactive playtest; show the game window and wait.
$process = Start-Process -FilePath $game.Path -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru -Wait
$launch.ended_at = [DateTime]::UtcNow.ToString('o')
$launch.exit_code = $process.ExitCode
$metadata.status = 'closed'
Write-JsonFile $metadataPath $metadata

if (-not $SkipObservations -and $Course -eq 'practice') {
    Write-Host ''
    $notes = Read-Host '연습 중 실행·조작 문제나 추가 메모 (없으면 Enter)'
    if ($notes) {
        Assert-SafeSessionPath $observationsPath
        $record = Read-JsonFile $observationsPath
        $record.notes = if ($record.notes) { $record.notes + "`n" + $notes } else { $notes }
        Write-JsonFile $observationsPath $record
    }
} elseif (-not $SkipObservations) {
    Write-Host ''
    Write-Host $(if ($ObservationSource -eq 'self_report') { '플레이 후 자기보고 (정답은 없습니다)' } else { '진행자 관찰 기록 (참가자의 정답을 묻는 설문이 아닙니다)' }) -ForegroundColor Cyan
    Write-Host '기회가 없거나 근거가 부족하면 판단 불가로 남기세요. 기록을 건너뛰어도 게임 저장은 유지됩니다.'
    $answer = (Read-Host '지금 관찰을 기록하려면 Y, 건너뛰려면 Enter').Trim().ToLowerInvariant()
    if ($answer -eq 'y') {
        Assert-SafeSessionPath $observationsPath
        $record = Read-JsonFile $observationsPath
        $labels = [ordered]@{
            A = '계속 강하게 미는 위험을 스스로 알아차린 말이나 입력 변화'
            B = '돌이 밀린 뒤 조작으로 한 번 이상 복구한 장면'
            C = '다음 발판을 가까운 목표로 삼은 말이나 행동'
            D = '실패 뒤 한 번 더 시도하려는 자발적인 말이나 행동'
            E = '다른 사람의 추락 장면을 지켜보며 보인 관심이나 반응 (보지 않았다면 판단 불가)'
        }
        foreach ($criterion in @('A', 'B', 'C', 'D', 'E')) {
            $entry = $record.observations.$criterion
            Write-Host ("`n{0}. {1}" -f $criterion, $labels[$criterion])
            Write-Host ('기존 기록: ' + $entry.status)
            do { $answer = (Read-Host '1 관찰됨 / 2 관찰되지 않음 / 3 판단 불가 / Enter 기존 값 유지').Trim() }
            while ($answer -notin @('', '1', '2', '3'))
            if ($answer) {
                $entry.status = @{ '1' = 'observed'; '2' = 'not_observed'; '3' = 'unknown' }[$answer]
                $entry.evidence = Read-Host '짧은 근거 (실제 말·행동·상황, 없으면 Enter)'
            }
        }
        $notes = Read-Host '추가 메모 (Enter는 기존 메모 유지)'
        if ($notes) { $record.notes = $notes }
        $record.completed_at = [DateTime]::UtcNow.ToString('o')
        $record.observation_source = $ObservationSource
        Write-JsonFile $observationsPath $record
    }
}
Write-Host ''
Write-Host ('세션 파일 위치: ' + $sessionRoot) -ForegroundColor Green
Write-Host '관찰되지 않음과 판단 불가는 별도로 저장됩니다. 결과를 전달할 때 해당 세션 폴더를 사용하세요.'
return $plan

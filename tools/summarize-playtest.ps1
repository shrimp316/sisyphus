[CmdletBinding()]
param(
    [string]$InputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'playtest-results'),
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Read-Field($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Markdown-Cell($Value) {
    return ([string]$Value).Replace('\', '\\').Replace('|', '\|').Replace('<', '&lt;').Replace('>', '&gt;').Replace("`r", ' ').Replace("`n", ' ')
}

$inputRoot = [IO.Path]::GetFullPath($InputDirectory)
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $inputRoot 'summary.md' }
$reportPath = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($reportPath) -ne '.md') { throw 'OutputPath must be a Markdown (.md) file.' }
$records = New-Object 'System.Collections.Generic.List[object]'
$invalid = New-Object 'System.Collections.Generic.List[string]'
$practiceCount = 0
$unfinishedCount = 0
$codes = @('A', 'B', 'C', 'D', 'E')
$files = @()
if (Test-Path -LiteralPath $inputRoot -PathType Container) {
    $files = @(Get-ChildItem -LiteralPath $inputRoot -Filter 'observations.json' -Recurse -File)
}

foreach ($file in $files) {
    try {
        $data = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ((Read-Field $data 'schema_version' 0) -ne 1) { throw 'Unsupported schema_version.' }
        $course = [string](Read-Field $data 'course' '')
        if ($course -eq 'practice') { $practiceCount++; continue }
        if ($course -ne 'normal') { throw 'Unknown course.' }
        $completed = [string](Read-Field $data 'completed_at' '')
        if ([string]::IsNullOrWhiteSpace($completed)) { $unfinishedCount++; continue }
        $completedAt = [DateTimeOffset]::Parse($completed, [Globalization.CultureInfo]::InvariantCulture)
        $participant = [string](Read-Field $data 'participant_id' '')
        if ($participant -notmatch '^\d{1,2}$' -or [int]$participant -lt 1 -or [int]$participant -gt 10) { throw 'participant_id must be 01 through 10.' }
        $participant = '{0:D2}' -f [int]$participant
        $session = [string](Read-Field $data 'session_id' '')
        if ([string]::IsNullOrWhiteSpace($session)) { throw 'Missing session_id.' }
        $answers = @{}
        $observations = Read-Field $data 'observations'
        foreach ($code in $codes) {
            $answer = Read-Field $observations $code
            $status = [string](Read-Field $answer 'status' 'unknown')
            if ($status -notin @('observed', 'not_observed', 'unknown')) { throw "Invalid status for $code." }
            $answers[$code] = [pscustomobject]@{ Status = $status; Evidence = [string](Read-Field $answer 'evidence' '') }
        }
        $source = [string](Read-Field $data 'observation_source' 'self_report')
        if ($source -notin @('self_report', 'facilitator_observation', 'mixed')) { $source = 'unspecified' }
        $buildId = [string](Read-Field $data 'build_id' '')
        $gameVersion = [string](Read-Field $data 'game_version' '')
        if ([string]::IsNullOrWhiteSpace($buildId)) { $buildId = 'unspecified' }
        if ([string]::IsNullOrWhiteSpace($gameVersion)) { $gameVersion = 'unspecified' }
        $records.Add([pscustomobject]@{
            Participant = $participant; Session = $session; CompletedAt = $completedAt
            Answers = $answers; Source = $source; Notes = [string](Read-Field $data 'notes' ''); Path = $file.FullName
            BuildId = $buildId; GameVersion = $gameVersion
        })
    } catch {
        $invalid.Add($file.FullName + ' — ' + $_.Exception.Message)
    }
}

# Use one entire latest completed observation per participant, including unknowns.
# Never cherry-pick older positive answers into the latest session.
$selected = @($records | Group-Object Participant | ForEach-Object {
    $_.Group | Sort-Object @{ Expression = { $_.CompletedAt.UtcTicks } }, Path | Select-Object -Last 1
} | Sort-Object Participant)
$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('# 시지프스 v0.2 플레이 테스트 집계')
$lines.Add('')
$lines.Add(('집계된 참가자: **{0}명 / 목표 10명**' -f $selected.Count))
$selfReportCount = @($selected | Where-Object { $_.Source -eq 'self_report' }).Count
$facilitatorCount = @($selected | Where-Object { $_.Source -eq 'facilitator_observation' }).Count
$lines.Add(('기록 출처: 자기보고 {0}명 · 진행자 직접 관찰 {1}명 · 혼합/미지정 {2}명' -f $selfReportCount, $facilitatorCount, ($selected.Count - $selfReportCount - $facilitatorCount)))
$lines.Add(('완료된 일반 기록 {0}개 · 중복 제외 {1}개 · 연습 제외 {2}개 · 미완료 제외 {3}개 · 형식 오류 {4}개' -f $records.Count, ($records.Count - $selected.Count), $practiceCount, $unfinishedCount, $invalid.Count))
$lines.Add('')
$lines.Add('참가자별 가장 최근에 완료된 일반 세션 전체를 사용했다. 동시각이면 파일 경로 정렬의 마지막 파일을 선택했다. 최신 unknown을 과거 답으로 대체하지 않았다.')
$lines.Add('자기보고는 연구자의 직접 관찰과 구분한다. 출처 필드가 없는 기록은 자기보고로 취급했다. 이 보고서는 파일의 내용을 집계하며 실제 사람의 참여 여부를 자동 인증하지 않는다.')
$lines.Add('')
$lines.Add('**판정 보류:** 명세의 항목별 성공 비율이 정해지지 않아 자동 통과 판정을 내리지 않는다. 관찰 인원수와 근거를 사람이 검토해야 한다.')
if ($selected.Count -eq 0) { $lines.Add('완료된 일반 참가자 기록이 없다. 실제 플레이 테스트 결과는 아직 집계되지 않았다.') }
$lines.Add('')
$buildGroups = @($selected | Group-Object BuildId | Sort-Object Name)
if ($buildGroups.Count -gt 1) {
    $lines.Add('**서로 다른 빌드가 섞여 있다. 아래 항목별 집계는 빌드별로 분리했으며 하나의 실험 결과로 합산하지 않는다.**')
}
foreach ($buildGroup in $buildGroups) {
    $lines.Add('')
    $lines.Add(('## 빌드 {0} · {1}명' -f (Markdown-Cell $buildGroup.Name), $buildGroup.Count))
    if ($buildGroup.Name -eq 'unspecified') { $lines.Add('빌드가 미기재되어 동일한 실행 파일을 사용했는지 확인이 필요하다.') }
    $lines.Add('')
    $lines.Add('| 항목 | observed · 관찰됨 | not_observed · 관찰 안 됨 | unknown · 판단 보류 |')
    $lines.Add('|---|---:|---:|---:|')
    foreach ($code in $codes) {
        $positive = @($buildGroup.Group | Where-Object { $_.Answers[$code].Status -eq 'observed' }).Count
        $negative = @($buildGroup.Group | Where-Object { $_.Answers[$code].Status -eq 'not_observed' }).Count
        $unknown = @($buildGroup.Group | Where-Object { $_.Answers[$code].Status -eq 'unknown' }).Count
        $lines.Add(('| {0} | {1} | {2} | {3} |' -f $code, $positive, $negative, $unknown))
    }
}
$lines.Add('')
$lines.Add('## 선택된 기록과 근거')
foreach ($record in $selected) {
    $lines.Add('')
    $lines.Add(('### 참가자 {0}' -f $record.Participant))
    $lines.Add('')
    $lines.Add(('세션: {0} · 완료: {1} · 출처: {2}' -f (Markdown-Cell $record.Session), $record.CompletedAt.ToUniversalTime().ToString('o'), (Markdown-Cell $record.Source)))
    $lines.Add(('빌드: {0} · 게임 버전: {1}' -f (Markdown-Cell $record.BuildId), (Markdown-Cell $record.GameVersion)))
    $lines.Add(('원본: {0}' -f (Markdown-Cell $record.Path)))
    $lines.Add('')
    $lines.Add('| 항목 | 상태 | 근거 |')
    $lines.Add('|---|---|---|')
    foreach ($code in $codes) {
        $answer = $record.Answers[$code]
        $evidence = $answer.Evidence
        if ([string]::IsNullOrWhiteSpace($evidence)) { $evidence = '근거 미기재 · 추가 확인 필요' }
        $lines.Add(('| {0} | {1} | {2} |' -f $code, $answer.Status, (Markdown-Cell $evidence)))
    }
    if (-not [string]::IsNullOrWhiteSpace($record.Notes)) { $lines.Add('자유 의견: ' + (Markdown-Cell $record.Notes)) }
}
if ($invalid.Count -gt 0) {
    $lines.Add('')
    $lines.Add('## 집계하지 못한 파일')
    $lines.Add('')
    foreach ($problem in $invalid) { $lines.Add('- ' + (Markdown-Cell $problem)) }
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($reportPath))
[IO.File]::WriteAllLines($reportPath, $lines, [Text.UTF8Encoding]::new($true))
Write-Output ('Summary: {0}' -f $reportPath)
Write-Output ('Participants={0}; completed={1}; duplicates={2}; invalid={3}' -f $selected.Count, $records.Count, ($records.Count - $selected.Count), $invalid.Count)

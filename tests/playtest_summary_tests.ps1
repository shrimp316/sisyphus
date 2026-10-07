# Synthetic QA only. Never writes participant records to playtest-results.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path $PSScriptRoot -Parent
$fixtureRoot = Join-Path $projectRoot ('.tools/summary-tests-' + [Guid]::NewGuid().ToString('N'))
$summarizer = Join-Path $projectRoot 'tools/summarize-playtest.ps1'
$encoding = New-Object Text.UTF8Encoding($true)
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$checks = 0

function Check([bool]$Condition, [string]$Label) {
    if (-not $Condition) { throw ('FAIL: ' + $Label) }
    $script:checks++
    Write-Output ('PASS: ' + $Label)
}

function Write-Fixture([string]$Name, [string]$Participant, [string]$Course, $Completed, [string]$Status, [string]$Build, [string]$Source = 'self_report') {
    $folder = Join-Path $fixtureRoot $Name
    [void][IO.Directory]::CreateDirectory($folder)
    $record = @{
        schema_version = 1; participant_id = $Participant; course = $Course
        session_id = $Name; completed_at = $Completed; build_id = $Build; game_version = 'QA-only'
        observation_source = $Source; notes = 'SYNTHETIC QA ONLY - no human participant'
        observations = @{ A = @{ status = $Status; evidence = 'SYNTHETIC | evidence' } }
    }
    [IO.File]::WriteAllText((Join-Path $folder 'observations.json'), ($record | ConvertTo-Json -Depth 8), $encoding)
}

Write-Fixture 'old-positive' '01' 'normal' '2026-10-07T01:00:00Z' 'observed' 'qa-build-A'
Write-Fixture 'latest-unknown' '01' 'normal' '2026-10-07T02:00:00Z' 'unknown' 'qa-build-A' 'facilitator_observation'
Write-Fixture 'other-build' '02' 'normal' '2026-10-07T03:00:00Z' 'not_observed' 'qa-build-B'
Write-Fixture 'practice-excluded' '03' 'practice' '2026-10-07T04:00:00Z' 'observed' 'qa-build-A'
Write-Fixture 'unfinished-excluded' '04' 'normal' $null 'observed' 'qa-build-A'
$malformed = Join-Path $fixtureRoot 'malformed'
[void][IO.Directory]::CreateDirectory($malformed)
[IO.File]::WriteAllText((Join-Path $malformed 'observations.json'), '{ not JSON', $encoding)

$reportPath = Join-Path $fixtureRoot 'summary.md'
$output = (& $summarizer -InputDirectory $fixtureRoot -OutputPath $reportPath) -join "`n"
$report = [IO.File]::ReadAllText($reportPath, [Text.Encoding]::UTF8)
Check ($output -match 'Participants=2; completed=3; duplicates=1; invalid=1') 'counts use two synthetic participants and exclude duplicate/malformed data'
Check ($report -match 'latest-unknown' -and $report -notmatch '세션: old-positive') 'latest whole observation replaces older positive answers'
Check ($report -match '\| A \| 0 \| 0 \| 1 \|') 'latest unknown remains unknown'
Check ($report -match '\| B \| 0 \| 0 \| 1 \|') 'missing answers default to unknown'
Check ($report -match '## 빌드 qa-build-A' -and $report -match '## 빌드 qa-build-B') 'different builds have separate criterion tables'
Check ($report -match '서로 다른 빌드가 섞여 있다') 'mixed builds are not presented as one experiment'
Check ($report -match '자기보고 1명' -and $report -match '진행자 직접 관찰 1명') 'self report is distinct from direct observation'
Check ($report -match '연습 제외 1개' -and $report -match '미완료 제외 1개') 'practice and unfinished observations are excluded'
Check ($report -match 'SYNTHETIC \\\| evidence') 'evidence is escaped for Markdown tables'
Check ($report -match '판정 보류' -and $report -match '자동 통과 판정을 내리지 않는다') 'no automatic pass is invented'

$emptyRoot = Join-Path $fixtureRoot 'empty'
$emptyPath = Join-Path $emptyRoot 'summary.md'
$emptyOutput = (& $summarizer -InputDirectory $emptyRoot -OutputPath $emptyPath) -join "`n"
Check ($emptyOutput -match 'Participants=0; completed=0') 'empty collection reports zero participants'
Write-Output ('SUMMARY QA: {0} checks passed. Synthetic fixtures only: {1}' -f $checks, $fixtureRoot)

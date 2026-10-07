$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureRoot = Join-Path $projectRoot ('.tools/launcher fixtures ' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'tools')) | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'tools/playtest.ps1') -Destination (Join-Path $fixtureRoot 'tools/playtest.ps1')
# This is a non-executable path-resolution fixture, never launched.
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'SISYPHUS.exe'), 'TEST FIXTURE - NEVER EXECUTE')
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'build-info.json'), '{"build_id":"launcher-fixture-a","game_version":"test-only"}')
$launcher = Join-Path $fixtureRoot 'tools/playtest.ps1'
$script:checks = 0
function Check([bool]$condition, [string]$label) {
    $script:checks++
    if (-not $condition) { throw ('FAIL: ' + $label) }
    Write-Host ('PASS: ' + $label)
}
function Rejects([scriptblock]$operation, [string]$label) {
    $rejected = $false
    try { & $operation | Out-Null } catch { $rejected = $true }
    Check $rejected $label
}

$plan = & $launcher -ParticipantId 01 -Course normal -PlanOnly
Check (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'playtest-results'))) 'PlanOnly performs no filesystem mutations'
Check ($plan.condition.seed -eq 42 -and $plan.condition.weather -eq 'clear') 'Normal condition is seed42 clear'
Check ($plan.executable -eq (Join-Path $fixtureRoot 'SISYPHUS.exe')) 'Packaged executable is preferred'
Check ($plan.arguments -contains ('"--save-path=' + $plan.save_path + '"')) 'Save argument is quoted for spaces and Unicode paths'
Check ($plan.arguments -notcontains '--path') 'Packaged executable needs no source project path'
$another = & $launcher -ParticipantId 01 -Course normal -PlanOnly
Check ($another.session_path -ne $plan.session_path) 'New sessions use distinct IDs'
$otherParticipant = & $launcher -ParticipantId 02 -Course normal -PlanOnly
$practice = & $launcher -ParticipantId 01 -Course practice -PlanOnly
Check ($otherParticipant.session_path -ne $plan.session_path -and $practice.session_path -ne $plan.session_path) 'Participant and course save paths are isolated'
Check ($practice.arguments -contains '--debug-course' -and $practice.condition.seed -eq 1) 'Practice uses the debug course and its real fixed seed'
Rejects { & $launcher -ParticipantId '../01' -Course normal -PlanOnly } 'Participant traversal rejected'
Rejects { & $launcher -ParticipantId 11 -Course normal -PlanOnly } 'Out-of-range participant rejected'
Rejects { & $launcher -ParticipantId 01 -Course '../normal' -PlanOnly } 'Course traversal rejected'
Rejects { & $launcher -ParticipantId 01 -Course normal -Mode resume -SessionId '../save' -PlanOnly } 'Session traversal rejected'
Rejects { & $launcher -ParticipantId 01 -Course normal -PlanOnly -PrepareOnly } 'Contradictory nonlaunch modes rejected'
$prepared = & $launcher -ParticipantId 01 -Course normal -PrepareOnly
$record = Get-Content -LiteralPath $prepared.observations_path -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($null -eq $record.completed_at -and $record.observation_source -eq 'self_report') 'Prepared forms contain no reported outcomes and identify source'
foreach ($criterion in @('A', 'B', 'C', 'D', 'E')) {
    Check ($record.observations.$criterion.status -eq 'unknown' -and $record.observations.$criterion.evidence -eq '') ('Initial criterion ' + $criterion + ' is unknown')
}
Rejects { & $launcher -ParticipantId 01 -Course normal -Mode resume -SessionId $prepared.session_id -PlanOnly } 'Resume requires an actual save file'
[IO.File]::WriteAllText($prepared.save_path, '{"test_fixture":true}')
$resumed = & $launcher -ParticipantId 01 -Course normal -Mode resume -SessionId $prepared.session_id -PlanOnly
Check ($resumed.save_path -eq $prepared.save_path) 'Explicit same participant/course resume uses the same save'
Rejects { & $launcher -ParticipantId 02 -Course normal -Mode resume -SessionId $prepared.session_id -PlanOnly } 'Cannot resume another participant session'
Rejects { & $launcher -ParticipantId 01 -Course practice -Mode resume -SessionId $prepared.session_id -PlanOnly } 'Cannot resume another course session'
Rejects { & $launcher -ParticipantId 01 -Course normal -SessionId $prepared.session_id -PlanOnly } 'A supplied session ID never silently implies resume'
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'build-info.json'), '{"build_id":"launcher-fixture-b","game_version":"test-only"}')
Rejects { & $launcher -ParticipantId 01 -Course normal -Mode resume -SessionId $prepared.session_id -PlanOnly } 'Different build cannot silently continue an older session'
Write-Host ('PLAYTEST LAUNCHER TESTS: {0} checks passed; fixtures only at {1}' -f $script:checks, $fixtureRoot)

# PowerShell script to run SCD tests for sf_user pipeline
# This script provides Windows-compatible test execution
# Requirements: 4.1, 4.2, 5.1, 7.1 - SCD testing execution on Windows

param(
    [string]$Target = "dev",
    [string]$ProfilesDir = ".",
    [switch]$PerformanceOnly,
    [switch]$NoPerformance,
    [switch]$Verbose
)

# Set error action preference
$ErrorActionPreference = "Continue"

# Function to run dbt commands
function Invoke-DbtCommand {
    param(
        [string]$Command,
        [string]$ProfilesDir = ".",
        [string]$Target = "dev"
    )
    
    $fullCommand = "dbt $Command --profiles-dir $ProfilesDir --target $Target"
    
    if ($Verbose) {
        Write-Host "Executing: $fullCommand" -ForegroundColor Cyan
    }
    
    try {
        $result = Invoke-Expression $fullCommand
        return @{
            Success = $LASTEXITCODE -eq 0
            Output = $result
            ExitCode = $LASTEXITCODE
        }
    }
    catch {
        return @{
            Success = $false
            Output = $_.Exception.Message
            ExitCode = -1
        }
    }
}

# Function to run a group of tests
function Invoke-TestGroup {
    param(
        [string]$GroupName,
        [array]$Tests,
        [string]$Severity = "warn"
    )
    
    Write-Host "`n$('='*60)" -ForegroundColor Yellow
    Write-Host "Running test group: $GroupName" -ForegroundColor Yellow
    Write-Host "$('='*60)" -ForegroundColor Yellow
    
    $groupResults = @()
    
    foreach ($test in $Tests) {
        $testCommand = "test --select $test"
        $result = Invoke-DbtCommand -Command $testCommand -ProfilesDir $ProfilesDir -Target $Target
        
        $testResult = @{
            TestName = $test
            Group = $GroupName
            Severity = $Severity
            Success = $result.Success
            Output = $result.Output
            ExitCode = $result.ExitCode
        }
        
        $groupResults += $testResult
        
        # Print immediate feedback
        if ($result.Success) {
            Write-Host "✅ PASS $test" -ForegroundColor Green
        } else {
            Write-Host "❌ FAIL $test" -ForegroundColor Red
            if ($Verbose) {
                Write-Host "Error: $($result.Output)" -ForegroundColor Red
            }
        }
    }
    
    return $groupResults
}

# Main execution
Write-Host "Starting SCD Test Suite for sf_user Pipeline" -ForegroundColor Cyan
Write-Host "Target: $Target" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

# Define test groups
$testGroups = @{
    'data_quality' = @{
        'tests' = @('test_sf_user_data_quality_comprehensive')
        'severity' = 'error'
    }
    'scd_integrity' = @{
        'tests' = @(
            'test_scd_integrity_sf_user',
            'test_scd_integrity_comprehensive', 
            'test_scd_is_current_flag_logic'
        )
        'severity' = 'error'
    }
    'scd_logic' = @{
        'tests' = @(
            'test_scd_type2_logic_correctness',
            'test_scd_currency_management_sf_user',
            'test_scd_tracked_fields_sf_user'
        )
        'severity' = 'error'
    }
    'scd_continuity' = @{
        'tests' = @('test_scd_no_gaps_overlaps')
        'severity' = 'error'
    }
}

# Performance-only execution
if ($PerformanceOnly) {
    Write-Host "`nRunning SCD Performance Tests..." -ForegroundColor Cyan
    $result = Invoke-DbtCommand -Command "run-operation test_scd_comprehensive" -ProfilesDir $ProfilesDir -Target $Target
    
    if ($result.Success) {
        Write-Host "✅ SCD Performance Tests completed successfully" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "❌ SCD Performance Tests failed" -ForegroundColor Red
        Write-Host $result.Output -ForegroundColor Red
        exit 1
    }
}

# Execute test groups
$allResults = @()
$failedGroups = @()

foreach ($groupName in $testGroups.Keys) {
    $groupConfig = $testGroups[$groupName]
    $tests = $groupConfig.tests
    $severity = $groupConfig.severity
    
    $groupResults = Invoke-TestGroup -GroupName $groupName -Tests $tests -Severity $severity
    $allResults += $groupResults
    
    # Check for critical failures
    $groupFailed = $groupResults | Where-Object { -not $_.Success }
    if ($severity -eq 'error' -and $groupFailed.Count -gt 0) {
        $failedGroups += $groupName
        Write-Host "`n❌ Critical test group '$groupName' failed!" -ForegroundColor Red
        
        # Stop on critical failures
        if ($groupName -in @('data_quality', 'scd_integrity')) {
            Write-Host "Stopping execution due to critical test failures." -ForegroundColor Red
            break
        }
    }
}

# Generate summary report
$totalTests = $allResults.Count
$passedTests = ($allResults | Where-Object { $_.Success }).Count
$failedTests = $totalTests - $passedTests
$successRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests * 100), 2) } else { 0 }

Write-Host "`n$('='*60)" -ForegroundColor Yellow
Write-Host "SCD TEST SUITE SUMMARY" -ForegroundColor Yellow
Write-Host "$('='*60)" -ForegroundColor Yellow
Write-Host "Total Tests: $totalTests" -ForegroundColor Cyan
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { 'Red' } else { 'Green' })
Write-Host "Success Rate: $successRate%" -ForegroundColor Cyan

if ($failedTests -gt 0) {
    Write-Host "`n❌ FAILED TESTS:" -ForegroundColor Red
    $allResults | Where-Object { -not $_.Success } | ForEach-Object {
        Write-Host "  - $($_.TestName) ($($_.Group))" -ForegroundColor Red
    }
} else {
    Write-Host "`n✅ ALL TESTS PASSED!" -ForegroundColor Green
}

# Save report
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportFile = "test_results_$($Target)_$timestamp.json"

$report = @{
    timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
    target = $Target
    summary = @{
        total_tests = $totalTests
        passed = $passedTests
        failed = $failedTests
        success_rate = $successRate
    }
    test_results = $allResults
} | ConvertTo-Json -Depth 10

$report | Out-File -FilePath $reportFile -Encoding UTF8
Write-Host "`nDetailed report saved to: $reportFile" -ForegroundColor Cyan

# Run performance tests unless skipped
if (-not $NoPerformance) {
    Write-Host "`nRunning SCD Performance Tests..." -ForegroundColor Cyan
    $perfResult = Invoke-DbtCommand -Command "run-operation test_scd_comprehensive" -ProfilesDir $ProfilesDir -Target $Target
    
    if ($perfResult.Success) {
        Write-Host "✅ SCD Performance Tests completed successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ SCD Performance Tests failed" -ForegroundColor Red
        if ($Verbose) {
            Write-Host $perfResult.Output -ForegroundColor Red
        }
    }
}

# Exit with appropriate code
exit $(if ($failedTests -eq 0) { 0 } else { 1 })
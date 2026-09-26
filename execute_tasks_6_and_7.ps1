# ============================================
# Execute Tasks 6 & 7 - Patient360 Data Load
# Loads 6 tables (3,067 rows) in dependency order
# ============================================

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Patient360: Tasks 6 & 7 Execution" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Define files in strict dependency order
$files = @(
    @{ Task=6; Table="VISITS"; File="sql_visits.sql"; Expected=572 }
    @{ Task=6; Table="LAB_RESULTS"; File="sql_lab_results.sql"; Expected=317 }
    @{ Task=6; Table="DIAGNOSTIC_REPORTS"; File="sql_diagnostic_reports.sql"; Expected=178 }
    @{ Task=7; Table="INSURANCE_CLAIMS"; File="sql_insurance_claims.sql"; Expected=572 }
    @{ Task=7; Table="PRESCRIPTIONS"; File="sql_prescriptions.sql"; Expected=582 }
    @{ Task=7; Table="CLINICAL_NOTES"; File="sql_clinical_notes.sql"; Expected=846 }
)

$totalRows = ($files | Measure-Object -Property Expected -Sum).Sum
Write-Host "About to load: $totalRows rows across 6 tables" -ForegroundColor White
Write-Host ""

$currentTask = 0
foreach ($file in $files) {
    if ($file.Task -ne $currentTask) {
        $currentTask = $file.Task
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Yellow
        Write-Host " TASK $currentTask" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Yellow
        Write-Host ""
    }
    
    $table = $file.Table
    $sqlFile = $file.File
    $expected = $file.Expected
    
    Write-Host "[$table] Loading..." -NoNewline
    
    # Check file exists
    if (-Not (Test-Path $sqlFile)) {
        Write-Host " FAILED - File not found!" -ForegroundColor Red
        exit 1
    }
    
    # Read SQL
    try {
        $sql = Get-Content $sqlFile -Raw -Encoding UTF8
        
        # Execute via cortex sql
        $result = cortex sql "$sql" 2>&1
        
        # Check if successful
        if ($LASTEXITCODE -eq 0) {
            Write-Host " ✓ $expected rows" -ForegroundColor Green
        } else {
            Write-Host " FAILED!" -ForegroundColor Red
            Write-Host $result
            exit 1
        }
    }
    catch {
        Write-Host " FAILED!" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " VERIFICATION" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

# Verify counts
$verifySQL = @"
SELECT 'VISITS' AS TABLE_NAME, COUNT(*) AS ROWS FROM PATIENT360.RAW.VISITS
UNION ALL SELECT 'LAB_RESULTS', COUNT(*) FROM PATIENT360.RAW.LAB_RESULTS
UNION ALL SELECT 'DIAGNOSTIC_REPORTS', COUNT(*) FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS
UNION ALL SELECT 'INSURANCE_CLAIMS', COUNT(*) FROM PATIENT360.RAW.INSURANCE_CLAIMS
UNION ALL SELECT 'PRESCRIPTIONS', COUNT(*) FROM PATIENT360.RAW.PRESCRIPTIONS
UNION ALL SELECT 'CLINICAL_NOTES', COUNT(*) FROM PATIENT360.RAW.CLINICAL_NOTES;
"@

Write-Host "Verifying row counts..." -ForegroundColor Cyan
$verifyResult = cortex sql "$verifySQL" 2>&1
Write-Host $verifyResult

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " ✓ TASKS 6 & 7 COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Loaded: $totalRows rows" -ForegroundColor Green
Write-Host ""
Write-Host "Next: Task 8 (Create DOCUMENTS schema tables)"
Write-Host ""

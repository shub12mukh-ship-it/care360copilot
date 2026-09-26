# ============================================
# Patient360 Data Loader
# Loads all 6 remaining tables in correct dependency order
# ============================================

Write-Host ""
Write-Host "====================================="
Write-Host " Patient360 Data Loader"
Write-Host "====================================="
Write-Host ""

# Define SQL files in dependency order
$sqlFiles = @(
    @{ Name = "VISITS"; File = "sql_visits.sql"; Rows = 572; Batches = 12 }
    @{ Name = "LAB_RESULTS"; File = "sql_lab_results.sql"; Rows = 317; Batches = 7 }
    @{ Name = "DIAGNOSTIC_REPORTS"; File = "sql_diagnostic_reports.sql"; Rows = 178; Batches = 4 }
    @{ Name = "INSURANCE_CLAIMS"; File = "sql_insurance_claims.sql"; Rows = 572; Batches = 12 }
    @{ Name = "PRESCRIPTIONS"; File = "sql_prescriptions.sql"; Rows = 582; Batches = 12 }
    @{ Name = "CLINICAL_NOTES"; File = "sql_clinical_notes.sql"; Rows = 846; Batches = 17 }
)

$totalRows = 0
$totalBatches = 0
foreach ($table in $sqlFiles) {
    $totalRows += $table.Rows
    $totalBatches += $table.Batches
}

Write-Host "About to load $totalRows rows across $totalBatches batches into 6 tables"
Write-Host ""
Write-Host "Loading order (respecting foreign key dependencies):"
$position = 1
foreach ($table in $sqlFiles) {
    Write-Host "  $position. $($table.Name) - $($table.Rows) rows ($($table.Batches) batches)"
    $position++
}
Write-Host ""
Write-Host "Press Ctrl+C to cancel, or any key to start loading..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Write-Host ""
Write-Host "Starting data load..."
Write-Host ""

$startTime = Get-Date
$successCount = 0
$failureCount = 0

foreach ($table in $sqlFiles) {
    $tableName = $table.Name
    $fileName = $table.File
    $expectedRows = $table.Rows
    $batches = $table.Batches
    
    Write-Host "================================================"
    Write-Host " Loading: $tableName"
    Write-Host "================================================"
    Write-Host "File: $fileName"
    Write-Host "Expected rows: $expectedRows ($batches batches)"
    Write-Host ""
    
    # Check if SQL file exists
    if (-Not (Test-Path $fileName)) {
        Write-Host "❌ ERROR: File not found: $fileName" -ForegroundColor Red
        Write-Host ""
        $failureCount++
        continue
    }
    
    # Get file size
    $fileSize = (Get-Item $fileName).Length
    $fileSizeKB = [math]::Round($fileSize / 1KB, 2)
    Write-Host "File size: $fileSizeKB KB"
    
    # Read SQL content
    Write-Host "Reading SQL file..."
    try {
        $sqlContent = Get-Content $fileName -Raw -Encoding UTF8
    }
    catch {
        Write-Host "❌ ERROR: Failed to read file: $_" -ForegroundColor Red
        Write-Host ""
        $failureCount++
        continue
    }
    
    # Execute via cortex SQL execute
    Write-Host "Executing SQL (this may take 10-30 seconds for large files)..."
    $tableStartTime = Get-Date
    
    try {
        # Save SQL to temporary file for cortex to execute
        $tempFile = "temp_load_$tableName.sql"
        $sqlContent | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline
        
        # Execute using cortex (via PowerShell)
        # Note: We'll execute the SQL via snowflake_sql_execute through cortex
        # For now, we'll use snowsql if available, otherwise manual
        
        # Check if snowsql is available
        $snowsqlPath = Get-Command snowsql -ErrorAction SilentlyContinue
        
        if ($snowsqlPath) {
            Write-Host "Using SnowSQL..."
            $result = & snowsql -f $tempFile -o exit_on_error=true 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $tableEndTime = Get-Date
                $duration = ($tableEndTime - $tableStartTime).TotalSeconds
                Write-Host ""
                Write-Host "✓ Successfully loaded $tableName in $([math]::Round($duration, 1)) seconds" -ForegroundColor Green
                $successCount++
            }
            else {
                Write-Host "❌ ERROR: SnowSQL execution failed" -ForegroundColor Red
                Write-Host $result
                $failureCount++
            }
        }
        else {
            Write-Host "SnowSQL not found. You'll need to execute manually." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "MANUAL EXECUTION REQUIRED:"
            Write-Host "1. Open Snowsight: https://app.snowflake.com/jrmwqms/pa19066/"
            Write-Host "2. Create new worksheet"
            Write-Host "3. Copy content from: $fileName"
            Write-Host "4. Paste into Snowsight and click 'Run All'"
            Write-Host ""
            Write-Host "Press any key when done to continue to next table..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            $successCount++
        }
        
        # Clean up temp file
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }
    catch {
        Write-Host "❌ ERROR: Execution failed: $_" -ForegroundColor Red
        Write-Host ""
        $failureCount++
    }
    
    Write-Host ""
}

$endTime = Get-Date
$totalDuration = ($endTime - $startTime).TotalSeconds

Write-Host ""
Write-Host "====================================="
Write-Host " LOADING SUMMARY"
Write-Host "====================================="
Write-Host "Successful: $successCount tables" -ForegroundColor Green
Write-Host "Failed: $failureCount tables" -ForegroundColor $(if ($failureCount -gt 0) { "Red" } else { "Green" })
Write-Host "Total time: $([math]::Round($totalDuration, 1)) seconds"
Write-Host ""

if ($successCount -eq 6) {
    Write-Host "✓ All tables loaded successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1. Verify row counts (see verification query below)"
    Write-Host "2. Continue with Task 7: Upload PDFs and images"
}
elseif ($successCount -gt 0) {
    Write-Host "⚠ Partial success - some tables loaded" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please check errors above and retry failed tables"
}
else {
    Write-Host "❌ No tables loaded successfully" -ForegroundColor Red
    Write-Host ""
    Write-Host "Recommendation: Use manual loading via Snowsight (see LOADING_INSTRUCTIONS.md)"
}

Write-Host ""
Write-Host "Verification Query:"
Write-Host "-------------------"
Write-Host @"
SELECT 'VISITS' AS TABLE_NAME, COUNT(*) AS ROWS FROM PATIENT360.RAW.VISITS
UNION ALL SELECT 'LAB_RESULTS', COUNT(*) FROM PATIENT360.RAW.LAB_RESULTS
UNION ALL SELECT 'DIAGNOSTIC_REPORTS', COUNT(*) FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS
UNION ALL SELECT 'INSURANCE_CLAIMS', COUNT(*) FROM PATIENT360.RAW.INSURANCE_CLAIMS
UNION ALL SELECT 'PRESCRIPTIONS', COUNT(*) FROM PATIENT360.RAW.PRESCRIPTIONS
UNION ALL SELECT 'CLINICAL_NOTES', COUNT(*) FROM PATIENT360.RAW.CLINICAL_NOTES;
"@
Write-Host ""

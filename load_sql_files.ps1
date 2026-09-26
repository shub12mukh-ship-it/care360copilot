# PowerShell script to execute SQL files through Snowflake
# This script reads each generated SQL file and helps track loading progress

param(
    [string]$OutputSummary = "load_summary.txt"
)

$sqlFiles = @(
    "sql_patients.sql",           # 100 rows - needed before visits
    "sql_visits.sql",             # 572 rows - needed before dependent tables
    "sql_lab_results.sql",        # 317 rows
    "sql_diagnostic_reports.sql", # 178 rows
    "sql_insurance_claims.sql",   # 572 rows
    "sql_prescriptions.sql",      # 582 rows
    "sql_clinical_notes.sql"      # 846 rows
)

Write-Host ""
Write-Host "SQL FILES READY FOR LOADING"
Write-Host "=============================="
Write-Host ""
Write-Host "The following SQL files have been generated and are ready to execute in Snowflake:"
Write-Host ""

$totalRows = 0
foreach ($file in $sqlFiles) {
    if (Test-Path $file) {
        $size = (Get-Item $file).Length
        $sizeKB = [math]::Round($size / 1KB, 2)
        
        # Count rows by looking at INSERT statements
        $content = Get-Content $file -Raw
        $matches = [regex]::Matches($content, "\('P\d+|'V\d+|'LR\d+|'DR\d+|'IC\d+|'RX\d+|'CN\d+")
        $rowCount = $matches.Count
        $totalRows += $rowCount
        
        Write-Host "  $file"
        Write-Host "    Size: $sizeKB KB"
        Write-Host "    Estimated rows: $rowCount"
        Write-Host ""
    }
}

Write-Host "Total estimated rows to load: $totalRows"
Write-Host ""
Write-Host "TO EXECUTE THESE FILES:"
Write-Host "----------------------"
Write-Host "Option 1: Use Snowsight UI"
Write-Host "  1. Open Snowsight (https://app.snowflake.com/)"
Write-Host "  2. Navigate to Worksheets"
Write-Host "  3. Copy/paste each SQL file content"
Write-Host "  4. Execute"
Write-Host ""
Write-Host "Option 2: Use SnowSQL CLI (if installed)"
Write-Host "  snowsql -c <connection> -f sql_patients.sql"
Write-Host ""
Write-Host "Option 3: Manual execution through Cortex Code"
Write-Host "  Copy the INSERT statements from each file and execute via Snowflake SQL tool"
Write-Host ""

# Write summary to file
$summary = @"
SQL Loading Summary
===================
Generated: $(Get-Date)

Files ready for loading:
$($sqlFiles | ForEach-Object { "- $_" } | Out-String)

Total rows: $totalRows

Load order (respects foreign key dependencies):
1. sql_patients.sql (must load before visits)
2. sql_visits.sql (must load before dependent tables)
3. sql_lab_results.sql, sql_diagnostic_reports.sql, sql_insurance_claims.sql, sql_prescriptions.sql, sql_clinical_notes.sql

Status:
- DOCTORS: 50 rows ✓
- DIAGNOSTIC_CENTERS: 10 rows ✓
- PATIENTS: Pending
- VISITS: Pending
- LAB_RESULTS: Pending
- DIAGNOSTIC_REPORTS: Pending
- INSURANCE_CLAIMS: Pending
- PRESCRIPTIONS: Pending
- CLINICAL_NOTES: Pending
"@

$summary | Out-File -FilePath $OutputSummary -Encoding UTF8
Write-Host "Summary written to: $OutputSummary"

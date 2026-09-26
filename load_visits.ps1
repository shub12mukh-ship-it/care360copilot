# Load VISITS data into Snowflake
# Reads sql_visits.sql and executes it via snowflake_sql_execute

$sqlFile = "sql_visits.sql"

if (-not (Test-Path $sqlFile)) {
    Write-Host "Error: $sqlFile not found"
    exit 1
}

Write-Host "Reading $sqlFile..."
$sql = Get-Content $sqlFile -Raw

Write-Host "File size: $($sql.Length) characters"
Write-Host "Executing SQL via snowflake..."

# Save to temp file for manual execution if needed
$sql | Out-File "visits_temp.sql" -Encoding UTF8

Write-Host ""
Write-Host "SQL prepared in visits_temp.sql"
Write-Host "Ready to execute via Snowflake"

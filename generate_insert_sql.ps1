# PowerShell script to generate INSERT statements from CSV files
# Usage: .\generate_insert_sql.ps1

function Escape-SqlString {
    param([string]$value)
    if ([string]::IsNullOrWhiteSpace($value) -or $value -eq 'NULL') {
        return 'NULL'
    }
    # Escape single quotes
    $escaped = $value.Replace("'", "''")
    return "'$escaped'"
}

function Convert-CsvToInsert {
    param(
        [string]$csvPath,
        [string]$tableName,
        [string[]]$columns,
        [int]$batchSize = 50
    )
    
    Write-Host "Processing $tableName from $csvPath..."
    
    $data = Import-Csv -Path $csvPath
    $totalRows = $data.Count
    Write-Host "  Found $totalRows rows"
    
    $sqlFile = "sql_$($tableName.ToLower()).sql"
    $batches = [Math]::Ceiling($totalRows / $batchSize)
    
    # Clear file if exists
    "" | Out-File -FilePath $sqlFile -Encoding UTF8
    
    # Write DELETE statement
    "DELETE FROM PATIENT360.RAW.$tableName;" | Out-File -FilePath $sqlFile -Append -Encoding UTF8
    "" | Out-File -FilePath $sqlFile -Append -Encoding UTF8
    
    # Process in batches
    for ($b = 0; $b -lt $batches; $b++) {
        $start = $b * $batchSize
        $end = [Math]::Min(($b + 1) * $batchSize, $totalRows)
        $batch = $data[$start..($end-1)]
        
        $values = @()
        foreach ($row in $batch) {
            $vals = @()
            foreach ($col in $columns) {
                $csvCol = $col.ToLower()
                $val = $row.$csvCol
                
                # Handle boolean
                if ($val -eq 'True' -or $val -eq 'TRUE') {
                    $vals += 'TRUE'
                }
                elseif ($val -eq 'False' -or $val -eq 'FALSE') {
                    $vals += 'FALSE'
                }
                # Handle numbers
                elseif ($val -match '^\d+$' -and $col -match 'EXPERIENCE|AGE|REFILLS') {
                    $vals += $val
                }
                # Handle decimals
                elseif ($val -match '^\d+\.\d+$' -and $col -match 'AMOUNT|RESPONSIBILITY|PAID') {
                    $vals += $val
                }
                # Handle NULL/empty
                elseif ([string]::IsNullOrWhiteSpace($val)) {
                    $vals += 'NULL'
                }
                # Handle strings
                else {
                    $vals += Escape-SqlString $val
                }
            }
            $values += "(" + ($vals -join ',') + ")"
        }
        
        # Write INSERT statement
        $colList = $columns -join ','
        "INSERT INTO PATIENT360.RAW.$tableName ($colList) VALUES" | Out-File -FilePath $sqlFile -Append -Encoding UTF8
        ($values -join ",`n") + ";" | Out-File -FilePath $sqlFile -Append -Encoding UTF8
        "" | Out-File -FilePath $sqlFile -Append -Encoding UTF8
    }
    
    Write-Host "  Generated $sqlFile with $batches batches"
    return $sqlFile
}

# Generate SQL for all tables
$basePath = "synthetic-healthcare-data\csv"

$tables = @(
    @{csv="doctors.csv"; table="DOCTORS"; columns=@("DOCTOR_ID","FIRST_NAME","LAST_NAME","SPECIALTY","SUB_SPECIALTY","YEARS_EXPERIENCE","MEDICAL_SCHOOL","BOARD_CERTIFIED","PHONE","EMAIL","LICENSE_NUMBER")},
    @{csv="diagnostic_centers.csv"; table="DIAGNOSTIC_CENTERS"; columns=@("CENTER_ID","CENTER_NAME","ADDRESS","CITY","STATE","ZIP_CODE","PHONE","SERVICES_OFFERED","ACCREDITATION","OPERATING_HOURS")},
    @{csv="patients.csv"; table="PATIENTS"; columns=@("PATIENT_ID","FIRST_NAME","LAST_NAME","DATE_OF_BIRTH","AGE","GENDER","ETHNICITY","BLOOD_TYPE","ADDRESS","CITY","STATE","ZIP_CODE","PHONE","EMAIL","EMERGENCY_CONTACT_NAME","EMERGENCY_CONTACT_PHONE","INSURANCE_PROVIDER","INSURANCE_POLICY_NUMBER")},
    @{csv="visits.csv"; table="VISITS"; columns=@("VISIT_ID","PATIENT_ID","DOCTOR_ID","VISIT_DATE","VISIT_TIME","VISIT_TYPE","CHIEF_COMPLAINT","DIAGNOSIS_CODE","DIAGNOSIS_DESCRIPTION","TREATMENT_PLAN","FOLLOW_UP_REQUIRED","FOLLOW_UP_DATE","NOTES")},
    @{csv="lab_results.csv"; table="LAB_RESULTS"; columns=@("LAB_RESULT_ID","PATIENT_ID","VISIT_ID","CENTER_ID","TEST_DATE","TEST_TYPE","TEST_CODE","PDF_FILENAME","ORDERED_BY_DOCTOR_ID","STATUS","CRITICAL_FLAG")},
    @{csv="diagnostic_reports.csv"; table="DIAGNOSTIC_REPORTS"; columns=@("REPORT_ID","PATIENT_ID","VISIT_ID","CENTER_ID","EXAM_DATE","EXAM_TYPE","MODALITY","BODY_PART","IMAGE_FILENAME","FINDINGS","IMPRESSION","RADIOLOGIST_NAME","CRITICAL_FINDING")},
    @{csv="insurance_claims.csv"; table="INSURANCE_CLAIMS"; columns=@("CLAIM_ID","PATIENT_ID","VISIT_ID","CLAIM_DATE","INSURANCE_PROVIDER","POLICY_NUMBER","PROCEDURE_CODE","PROCEDURE_DESCRIPTION","DIAGNOSIS_CODE","BILLED_AMOUNT","ALLOWED_AMOUNT","PATIENT_RESPONSIBILITY","INSURANCE_PAID","CLAIM_STATUS","CLAIM_STATUS_DATE","DENIAL_REASON")},
    @{csv="prescriptions.csv"; table="PRESCRIPTIONS"; columns=@("PRESCRIPTION_ID","PATIENT_ID","VISIT_ID","DOCTOR_ID","PRESCRIPTION_DATE","MEDICATION_NAME","NDC_CODE","DOSAGE","FREQUENCY","DURATION","REFILLS","PDF_FILENAME")},
    @{csv="clinical_notes.csv"; table="CLINICAL_NOTES"; columns=@("NOTE_ID","PATIENT_ID","VISIT_ID","DOCTOR_ID","NOTE_DATE","NOTE_TYPE","PDF_FILENAME","SUMMARY")}
)

$sqlFiles = @()
foreach ($table in $tables) {
    $csvPath = Join-Path $basePath $table.csv
    if (Test-Path $csvPath) {
        $sqlFile = Convert-CsvToInsert -csvPath $csvPath -tableName $table.table -columns $table.columns
        $sqlFiles += $sqlFile
    } else {
        Write-Host "WARNING: $csvPath not found"
    }
}

Write-Host ""
Write-Host "Generated $($sqlFiles.Count) SQL files"
Write-Host ""
Write-Host "SQL files created:"
$sqlFiles | ForEach-Object { Write-Host "  $_" }

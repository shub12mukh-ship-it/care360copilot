#!/usr/bin/env python3
"""
Upload files to Snowflake stages using snowflake-connector-python
This script uploads images and PDFs to the respective stages in PATIENT360.RAW schema
"""

import os
import glob
from pathlib import Path

try:
    import snowflake.connector
    from snowflake.connector import DictCursor
except ImportError:
    print("ERROR: snowflake-connector-python is not installed.")
    print("\nTo install, run:")
    print("  pip install snowflake-connector-python")
    print("\nOr use SnowSQL CLI with these commands:")
    print("\n  PUT file://synthetic-healthcare-data/images/*.png @PATIENT360.RAW.DIAGNOSTIC_IMAGES AUTO_COMPRESS=FALSE;")
    print("  PUT file://synthetic-healthcare-data/pdfs/lab_results/*.pdf @PATIENT360.RAW.LAB_RESULT_PDFS AUTO_COMPRESS=FALSE;")
    print("  PUT file://synthetic-healthcare-data/pdfs/prescriptions/*.pdf @PATIENT360.RAW.PRESCRIPTION_PDFS AUTO_COMPRESS=FALSE;")
    print("  PUT file://synthetic-healthcare-data/pdfs/clinical_notes/*.pdf @PATIENT360.RAW.CLINICAL_NOTE_PDFS AUTO_COMPRESS=FALSE;")
    exit(1)

def get_connection():
    """Create Snowflake connection using externalbrowser authentication"""
    return snowflake.connector.connect(
        account='JRMWQMS-PA19066',
        user='sreejaprabakar',
        authenticator='externalbrowser',
        warehouse='CARE360_WH',
        database='PATIENT360',
        schema='RAW'
    )

def upload_files(cursor, local_path_pattern, stage_name):
    """Upload files matching pattern to specified stage"""
    files = glob.glob(local_path_pattern)
    if not files:
        print(f"  No files found matching: {local_path_pattern}")
        return 0
    
    print(f"  Found {len(files)} files to upload to {stage_name}")
    
    # Convert Windows path to forward slashes for PUT command
    local_path_pattern_forward = local_path_pattern.replace('\\', '/')
    
    put_command = f"PUT file://{local_path_pattern_forward} @{stage_name} AUTO_COMPRESS=FALSE"
    print(f"  Executing: {put_command}")
    
    try:
        cursor.execute(put_command)
        results = cursor.fetchall()
        
        success_count = sum(1 for r in results if r[6] == 'UPLOADED')
        print(f"  Successfully uploaded {success_count}/{len(results)} files")
        return success_count
    except Exception as e:
        print(f"  ERROR: {e}")
        return 0

def main():
    print("=" * 80)
    print("Uploading files to Snowflake stages")
    print("=" * 80)
    
    try:
        conn = get_connection()
        cursor = conn.cursor()
        
        total_uploaded = 0
        
        # Upload diagnostic images
        print("\n1. Uploading diagnostic images...")
        total_uploaded += upload_files(
            cursor,
            "synthetic-healthcare-data/images/*.png",
            "DIAGNOSTIC_IMAGES"
        )
        total_uploaded += upload_files(
            cursor,
            "synthetic-healthcare-data/images/*.jpg",
            "DIAGNOSTIC_IMAGES"
        )
        
        # Upload lab result PDFs
        print("\n2. Uploading lab result PDFs...")
        total_uploaded += upload_files(
            cursor,
            "synthetic-healthcare-data/pdfs/lab_results/*.pdf",
            "LAB_RESULT_PDFS"
        )
        
        # Upload prescription PDFs
        print("\n3. Uploading prescription PDFs...")
        total_uploaded += upload_files(
            cursor,
            "synthetic-healthcare-data/pdfs/prescriptions/*.pdf",
            "PRESCRIPTION_PDFS"
        )
        
        # Upload clinical note PDFs
        print("\n4. Uploading clinical note PDFs...")
        total_uploaded += upload_files(
            cursor,
            "synthetic-healthcare-data/pdfs/clinical_notes/*.pdf",
            "CLINICAL_NOTE_PDFS"
        )
        
        print("\n" + "=" * 80)
        print(f"Upload complete! Total files uploaded: {total_uploaded}")
        print("=" * 80)
        
        # Verify uploads
        print("\nVerifying uploads...")
        for stage in ['DIAGNOSTIC_IMAGES', 'LAB_RESULT_PDFS', 'PRESCRIPTION_PDFS', 'CLINICAL_NOTE_PDFS']:
            cursor.execute(f"LIST @{stage}")
            results = cursor.fetchall()
            print(f"  {stage}: {len(results)} files")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"\nERROR: {e}")
        print("\nIf authentication fails, make sure you have access to the Snowflake account.")
        exit(1)

if __name__ == "__main__":
    main()

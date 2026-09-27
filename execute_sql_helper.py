"""
Execute the generated SQL files in Snowflake using CoCo's SQL execute tool
This script reads SQL files and executes them statement by statement
"""

import re
from pathlib import Path

def read_sql_file(filename):
    """Read SQL file and split into individual statements"""
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Split on semicolons but be careful about semicolons in strings
    # Simple approach: split on ";\n" which should work for our generated SQL
    statements = content.split(';\n')
    
    # Filter out empty statements and comments-only
    statements = [s.strip() for s in statements if s.strip() and not s.strip().startswith('--')]
    
    return statements

def main():
    print("=" * 80)
    print("SQL EXECUTION HELPER")
    print("=" * 80)
    print("\nThis script will help execute the generated SQL files.")
    print("You'll need to execute the statements manually using CoCo's SQL tool.\n")
    
    # Read the load_csv_data.sql file
    csv_file = 'load_csv_data.sql'
    if Path(csv_file).exists():
        statements = read_sql_file(csv_file)
        print(f"✓ Read {csv_file}: {len(statements)} statements")
        
        # Group statements by table
        current_table = None
        grouped = {}
        
        for stmt in statements:
            if 'USE DATABASE' in stmt or 'USE SCHEMA' in stmt:
                continue
            elif '-- Load' in stmt:
                current_table = stmt.replace('--', '').strip()
                grouped[current_table] = []
            elif current_table:
                grouped[current_table].append(stmt)
        
        print(f"\nStatements grouped by {len(grouped)} tables:")
        for table, stmts in grouped.items():
            print(f"  {table}: {len(stmts)} statements")
    
    # Read the load_files.sql file  
    files_file = 'load_files.sql'
    if Path(files_file).exists():
        with open(files_file, 'r', encoding='utf-8') as f:
            content = f.read()
        print(f"\n✓ Read {files_file}")
    
    print("\n" + "=" * 80)
    print("NEXT STEPS")
    print("=" * 80)
    print("\n1. I will now execute the CSV load SQL statements using CoCo")
    print("2. After CSV data is loaded, we'll create stages and upload files")
    print("3. File uploads (PUT commands) must be done via Snowflake CLI")

if __name__ == '__main__':
    main()

"""
Script to reduce synthetic healthcare dataset to specified limits.
"""
import os
import csv
from pathlib import Path

def reduce_csv_files():
    """Reduce CSV files to specified record counts."""
    csv_dir = Path("synthetic-healthcare-data/csv")
    
    # Define limits for each category
    csv_limits = {
        'clinical_notes.csv': 150,
        'diagnostic_reports.csv': 150,
        'insurance_claims.csv': 150,
        'lab_results.csv': 150,
        'prescriptions.csv': 150,
        'visits.csv': 150,
        # These are already at or below limits
        'patients.csv': 100,
        'doctors.csv': 50,
        'diagnostic_centers.csv': 10,
    }
    
    for csv_file, limit in csv_limits.items():
        csv_path = csv_dir / csv_file
        if csv_path.exists():
            # Read the CSV
            with open(csv_path, 'r', encoding='utf-8', newline='') as f:
                reader = csv.reader(f)
                header = next(reader)
                rows = list(reader)
            
            current_count = len(rows)
            
            if current_count > limit:
                print(f"Reducing {csv_file}: {current_count} → {limit}")
                # Write back with limited rows
                with open(csv_path, 'w', encoding='utf-8', newline='') as f:
                    writer = csv.writer(f)
                    writer.writerow(header)
                    writer.writerows(rows[:limit])
            else:
                print(f"Keeping {csv_file}: {current_count} (already at or below limit)")

def reduce_images():
    """Reduce images to 150 total."""
    images_dir = Path("synthetic-healthcare-data/images")
    all_images = list(images_dir.rglob("*.png")) + list(images_dir.rglob("*.jpg"))
    
    current_count = len(all_images)
    limit = 150
    
    if current_count > limit:
        print(f"\nReducing images: {current_count} → {limit}")
        # Sort by name for consistent results
        all_images.sort()
        # Remove excess images
        removed_count = 0
        for img_path in all_images[limit:]:
            img_path.unlink()
            removed_count += 1
        print(f"  Removed {removed_count} images")
    else:
        print(f"\nKeeping images: {current_count} (already at or below limit)")

def reduce_pdfs():
    """Reduce PDFs to 150 per category."""
    pdfs_dir = Path("synthetic-healthcare-data/pdfs")
    
    categories = ['clinical_notes', 'lab_results', 'prescriptions']
    limit = 150
    
    for category in categories:
        category_dir = pdfs_dir / category
        if category_dir.exists():
            pdf_files = list(category_dir.glob("*.pdf"))
            current_count = len(pdf_files)
            
            if current_count > limit:
                print(f"\nReducing {category} PDFs: {current_count} → {limit}")
                # Sort by name for consistent results
                pdf_files.sort()
                # Remove excess PDFs
                removed_count = 0
                for pdf_path in pdf_files[limit:]:
                    pdf_path.unlink()
                    removed_count += 1
                print(f"  Removed {removed_count} PDFs")
            else:
                print(f"\nKeeping {category} PDFs: {current_count} (already at or below limit)")

def main():
    print("=" * 60)
    print("Reducing Synthetic Healthcare Dataset")
    print("=" * 60)
    
    print("\n--- Reducing CSV Files ---")
    reduce_csv_files()
    
    print("\n--- Reducing Images ---")
    reduce_images()
    
    print("\n--- Reducing PDFs ---")
    reduce_pdfs()
    
    print("\n" + "=" * 60)
    print("Dataset reduction complete!")
    print("=" * 60)

if __name__ == "__main__":
    main()

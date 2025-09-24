#!/usr/bin/env python3
"""
Script to copy comprehensive implementation from lumata-datalake to lumata-lakehouse

This script copies all the comprehensive testing framework, dbt models, monitoring,
and orchestration components from the lumata-datalake directory to lumata-lakehouse.
"""

import os
import shutil
import sys
from pathlib import Path

def copy_comprehensive_implementation():
    """Copy all comprehensive components from lumata-datalake to lumata-lakehouse"""
    
    # Define source and destination paths
    source_base = Path("../../lumata-datalake/sf_user_pipeline")
    dest_base = Path(".")
    
    print("🔄 Copying comprehensive implementation from lumata-datalake to lumata-lakehouse...")
    
    # Components to copy
    components_to_copy = [
        # dbt comprehensive implementation
        {
            'source': source_base / 'dbt',
            'dest': dest_base / 'transformations',
            'description': 'Complete dbt project with SCD macros and tests'
        },
        # Comprehensive testing framework
        {
            'source': source_base / 'tests',
            'dest': dest_base / 'tests',
            'description': 'Comprehensive testing framework',
            'merge': True  # Merge with existing tests
        },
        # Monitoring infrastructure
        {
            'source': source_base / 'monitoring',
            'dest': dest_base / 'monitoring',
            'description': 'CloudWatch monitoring and alerting'
        },
        # Orchestration infrastructure
        {
            'source': source_base / 'orchestration',
            'dest': dest_base / 'orchestration',
            'description': 'Step Functions orchestration'
        },
        # Additional configuration files
        {
            'source': source_base / 'dbthub',
            'dest': dest_base / 'ingestion' / 'dbthub',
            'description': 'dbtHub configuration'
        },
        # Project documentation
        {
            'source': source_base / 'PROJECT_STRUCTURE.md',
            'dest': dest_base / 'PROJECT_STRUCTURE.md',
            'description': 'Project structure documentation'
        }
    ]
    
    # Copy each component
    for component in components_to_copy:
        source_path = component['source']
        dest_path = component['dest']
        description = component['description']
        merge = component.get('merge', False)
        
        print(f"\n📁 Copying {description}...")
        print(f"   From: {source_path}")
        print(f"   To: {dest_path}")
        
        try:
            if source_path.is_file():
                # Copy single file
                dest_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source_path, dest_path)
                print(f"   ✓ Copied file: {source_path.name}")
                
            elif source_path.is_dir():
                # Copy directory
                if merge and dest_path.exists():
                    # Merge directories
                    print(f"   🔄 Merging with existing directory...")
                    _copy_directory_contents(source_path, dest_path)
                else:
                    # Replace directory
                    if dest_path.exists():
                        shutil.rmtree(dest_path)
                    dest_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copytree(source_path, dest_path)
                
                print(f"   ✓ Copied directory: {source_path.name}")
            else:
                print(f"   ⚠️ Source not found: {source_path}")
                
        except Exception as e:
            print(f"   ✗ Failed to copy {description}: {str(e)}")
    
    print("\n✅ Comprehensive implementation copy completed!")
    print("\nNext steps:")
    print("1. Review the copied files in lumata-lakehouse/sf_user_pipeline/")
    print("2. Update any path references if needed")
    print("3. Test the deployment: python deploy.py --environment development")

def _copy_directory_contents(source_dir, dest_dir):
    """Copy contents of source directory to destination directory"""
    dest_dir.mkdir(parents=True, exist_ok=True)
    
    for item in source_dir.iterdir():
        dest_item = dest_dir / item.name
        
        if item.is_file():
            shutil.copy2(item, dest_item)
        elif item.is_dir():
            if dest_item.exists():
                _copy_directory_contents(item, dest_item)
            else:
                shutil.copytree(item, dest_item)

if __name__ == "__main__":
    # Change to the script directory
    script_dir = Path(__file__).parent
    os.chdir(script_dir)
    
    copy_comprehensive_implementation()
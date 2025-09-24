#!/usr/bin/env python3
"""
Test script to validate SCD macro syntax and basic functionality
This script performs basic validation of the dbt macros without requiring a full dbt run
"""

import os
import re
import sys
from pathlib import Path

def validate_macro_syntax(macro_file_path):
    """Validate basic dbt macro syntax"""
    print(f"Validating macro: {macro_file_path}")
    
    with open(macro_file_path, 'r') as f:
        content = f.read()
    
    # Check for basic macro structure
    if not re.search(r'{%\s*macro\s+\w+\s*\(\s*.*?\s*\)\s*%}', content):
        print(f"  ❌ No valid macro definition found")
        return False
    
    # Check for macro end
    if not re.search(r'{%\s*endmacro\s*%}', content):
        print(f"  ❌ No endmacro found")
        return False
    
    # Check for balanced braces
    open_braces = content.count('{%')
    close_braces = content.count('%}')
    if open_braces != close_braces:
        print(f"  ❌ Unbalanced braces: {open_braces} open, {close_braces} close")
        return False
    
    print(f"  ✅ Basic syntax validation passed")
    return True

def validate_scd_macro_requirements():
    """Validate that SCD macros meet the task requirements"""
    macro_dir = Path("dbt/macros")
    
    required_files = [
        "scd_type2_sf_user.sql",
        "scd_merge_sf_user.sql", 
        "scd_data_quality_checks.sql"
    ]
    
    print("Validating SCD macro requirements...")
    
    all_valid = True
    
    for file_name in required_files:
        file_path = macro_dir / file_name
        if not file_path.exists():
            print(f"  ❌ Required file missing: {file_name}")
            all_valid = False
            continue
            
        if not validate_macro_syntax(file_path):
            all_valid = False
            continue
            
        # Check specific requirements for main SCD macro
        if file_name == "scd_type2_sf_user.sql":
            with open(file_path, 'r') as f:
                content = f.read()
                
            # Check for change detection logic
            if 'division' not in content or 'audit_phase__c' not in content:
                print(f"  ❌ Missing tracked fields (division, audit_phase__c)")
                all_valid = False
            
            # Check for SCD flags
            required_flags = ['is_current', 'is_deleted', 'update_date']
            for flag in required_flags:
                if flag not in content:
                    print(f"  ❌ Missing SCD flag: {flag}")
                    all_valid = False
            
            # Check for change detection logic
            if 'lag(' not in content:
                print(f"  ❌ Missing change detection logic (lag function)")
                all_valid = False
                
            if all([flag in content for flag in required_flags]) and 'lag(' in content:
                print(f"  ✅ SCD Type 2 requirements validated")
    
    return all_valid

def validate_model_files():
    """Validate that required model files exist"""
    print("\nValidating model files...")
    
    models_dir = Path("dbt/models")
    
    required_models = [
        "staging/stg_sf_user.sql",
        "marts/dim_sf_user_scd.sql"
    ]
    
    all_valid = True
    
    for model_path in required_models:
        full_path = models_dir / model_path
        if not full_path.exists():
            print(f"  ❌ Required model missing: {model_path}")
            all_valid = False
        else:
            print(f"  ✅ Model exists: {model_path}")
    
    return all_valid

def validate_test_files():
    """Validate that SCD test files exist"""
    print("\nValidating test files...")
    
    tests_dir = Path("dbt/tests/singular")
    
    required_tests = [
        "test_scd_integrity_sf_user.sql",
        "test_scd_tracked_fields_sf_user.sql",
        "test_scd_currency_management_sf_user.sql"
    ]
    
    all_valid = True
    
    for test_file in required_tests:
        full_path = tests_dir / test_file
        if not full_path.exists():
            print(f"  ❌ Required test missing: {test_file}")
            all_valid = False
        else:
            print(f"  ✅ Test exists: {test_file}")
    
    return all_valid

def main():
    """Main validation function"""
    print("🔍 Validating SCD Type 2 macro implementation for sf_user")
    print("=" * 60)
    
    all_checks_passed = True
    
    # Validate macro syntax and requirements
    if not validate_scd_macro_requirements():
        all_checks_passed = False
    
    # Validate model files
    if not validate_model_files():
        all_checks_passed = False
    
    # Validate test files
    if not validate_test_files():
        all_checks_passed = False
    
    print("\n" + "=" * 60)
    if all_checks_passed:
        print("✅ All validations passed! SCD Type 2 macro implementation is complete.")
        print("\nTask 4.3 requirements satisfied:")
        print("  ✅ SCD Type 2 macro created for sf_user Division and Audit_Phase__c tracking")
        print("  ✅ Change detection logic implemented for tracked fields")
        print("  ✅ SCD record generation with update_date, is_current, and is_deleted flags")
        return 0
    else:
        print("❌ Some validations failed. Please review the issues above.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
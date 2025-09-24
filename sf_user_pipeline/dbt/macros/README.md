# SCD Type 2 Macros for sf_user

This directory contains dbt macros for implementing Slowly Changing Dimension (SCD) Type 2 logic specifically for sf_user data, tracking changes in Division and Audit_Phase__c fields.

## Macros Overview

### Core SCD Macros

#### `scd_type2_sf_user()`
The main macro that implements SCD Type 2 logic for sf_user data.

**Purpose**: 
- Detects changes in Division and Audit_Phase__c fields
- Generates SCD records with proper update_date, is_current, and is_deleted flags
- Handles first-time records and change detection

**Usage**:
```sql
-- In a dbt model
{{ scd_type2_sf_user() }}
```

**Logic**:
1. Reads from `stg_sf_user` staging model
2. Detects changes in tracked fields (Division, Audit_Phase__c)
3. Creates SCD records only when tracked fields change or for first records
4. Generates surrogate keys and SCD flags
5. Validates business rules using project variables

#### `scd_merge_sf_user()`
Helper macro for handling incremental SCD processing with proper merge logic.

**Purpose**:
- Handles incremental updates to SCD table
- Manages is_current flag updates for existing records
- Coordinates new record insertion with existing record updates

**Usage**:
```sql
-- In an incremental dbt model
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='_scd_id'
) }}

{{ scd_merge_sf_user() }}
```

**Logic**:
1. For incremental runs: Updates existing current records to is_current=false
2. Adds new SCD records from the main macro
3. For full refresh: Returns only new SCD records

### Data Quality Macros

#### `validate_scd_integrity(table_name)`
Validates that each active user has exactly one current record.

**Usage**:
```sql
-- In a test
{{ validate_scd_integrity(ref('dim_sf_user_scd')) }}
```

#### `validate_tracked_field_changes(table_name)`
Ensures SCD records are only created when tracked fields actually change.

#### `validate_sf_user_business_rules(table_name)`
Validates business rules for Division and Audit_Phase__c values.

#### `get_scd_statistics(table_name)`
Provides monitoring statistics for SCD table health.

## Configuration Requirements

### Project Variables
The macros use the following dbt project variables (defined in `dbt_project.yml`):

```yaml
vars:
  valid_divisions: ['North', 'South', 'East', 'West', 'Central']
  valid_audit_phases: ['Phase1', 'Phase2', 'Phase3', 'Complete']
```

### Dependencies
- `dbt-utils` package for `generate_surrogate_key` macro
- Staging model `stg_sf_user` must exist and follow expected schema

## Implementation Example

### Complete SCD Model Implementation

```sql
-- models/marts/dim_sf_user_scd.sql
{{ config(
    materialized='incremental',
    file_format='iceberg',
    incremental_strategy='merge',
    unique_key='_scd_id',
    merge_update_columns=['is_current', '_dbt_updated_at'],
    schema='curated'
) }}

{{ scd_merge_sf_user() }}
```

### Testing Implementation

```sql
-- tests/singular/test_scd_integrity.sql
{{ validate_scd_integrity(ref('dim_sf_user_scd')) }}
```

## Key Features

1. **Change Detection**: Only creates SCD records when Division or Audit_Phase__c change
2. **Currency Management**: Properly manages is_current flags during incremental updates
3. **Data Quality**: Built-in validation for business rules and SCD integrity
4. **Performance**: Optimized for incremental processing with Iceberg tables
5. **Monitoring**: Provides statistics and validation macros for operational monitoring

## Tracked Fields

The SCD implementation specifically tracks changes in:
- `division`: User's organizational division
- `audit_phase__c`: Custom audit phase field

Any change to these fields will trigger creation of a new SCD record while preserving historical values.

## SCD Record Structure

Each SCD record includes:
- `user_key`: Surrogate key (generated from user_id + update_date)
- `user_id`: Natural key from Salesforce
- `division`, `audit_phase__c`: Tracked fields
- `update_date`: Effective date of the record version
- `is_current`: Boolean flag for current version
- `is_deleted`: Boolean flag for deleted records
- `_scd_id`: Unique identifier for merge operations
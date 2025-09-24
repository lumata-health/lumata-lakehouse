-- Comprehensive data quality test for sf_user
-- This test validates all data quality requirements for sf_user records
-- Requirements: 5.1 - Comprehensive data quality validation for sf_user records

{{ config(severity = 'warn') }}

with data_quality_checks as (
    
    -- Check 1: Required fields validation
    select 
        'missing_required_fields' as check_type,
        user_id,
        name,
        division,
        audit_phase__c,
        'Required fields (Id, Name, Division, Audit_Phase__c) must not be null' as description
    from {{ ref('dim_sf_user_scd') }}
    where user_id is null 
       or name is null 
       or trim(name) = ''
       or division is null
       or audit_phase__c is null
    
    union all
    
    -- Check 2: Division value validation
    select 
        'invalid_division_values' as check_type,
        user_id,
        name,
        division,
        audit_phase__c,
        'Division must be one of: North, South, East, West, Central' as description
    from {{ ref('dim_sf_user_scd') }}
    where division not in {{ var('valid_divisions') | list }}
      and coalesce(is_deleted, false) = false
    
    union all
    
    -- Check 3: Audit Phase value validation
    select 
        'invalid_audit_phase_values' as check_type,
        user_id,
        name,
        division,
        audit_phase__c,
        'Audit_Phase__c must be one of: Phase1, Phase2, Phase3, Complete' as description
    from {{ ref('dim_sf_user_scd') }}
    where audit_phase__c not in {{ var('valid_audit_phases') | list }}
      and coalesce(is_deleted, false) = false
    
    union all
    
    -- Check 4: User ID format validation (Salesforce ID format)
    select 
        'invalid_user_id_format' as check_type,
        user_id,
        name,
        division,
        audit_phase__c,
        'User ID must be valid Salesforce ID format (15 or 18 characters)' as description
    from {{ ref('dim_sf_user_scd') }}
    where not (user_id ~ '^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$')
      and coalesce(is_deleted, false) = false
    
    union all
    
    -- Check 5: Name length and format validation
    select 
        'invalid_name_format' as check_type,
        user_id,
        name,
        division,
        audit_phase__c,
        'Name must be between 1 and 255 characters and not contain only whitespace' as description
    from {{ ref('dim_sf_user_scd') }}
    where length(trim(name)) < 1 
       or length(name) > 255
       or trim(name) = ''
      and coalesce(is_deleted, false) = false
    
    union all
    
    -- Check 6: Date field validation
    select 
        'invalid_date_fields' as check_type,
        user_id,
        name,
        division,
        audit_phase__c,
        'Date fields must be valid timestamps after 1900-01-01' as description
    from {{ ref('dim_sf_user_scd') }}
    where (update_date is null or update_date < '1900-01-01'::timestamp)
       or (_dbt_updated_at is null or _dbt_updated_at < '1900-01-01'::timestamp)
       or (_extracted_at is null or _extracted_at < '1900-01-01'::timestamp)
    
    union all
    
    -- Check 7: Boolean field validation
    select 
        'invalid_boolean_fields' as check_type,
        user_id,
        name,
        division,
        audit_phase__c,
        'Boolean fields must be true or false' as description
    from {{ ref('dim_sf_user_scd') }}
    where is_current not in (true, false)
       or is_deleted not in (true, false)
       or is_active not in (true, false)
)

-- Return all data quality violations
select *
from data_quality_checks
order by check_type, user_id
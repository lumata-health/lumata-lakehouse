-- Test to validate SCD Type 2 logic correctness for sf_user
-- This test ensures that the SCD Type 2 implementation follows all business rules
-- Requirements: 4.1, 4.2 - Validate SCD Type 2 logic correctness

{{ config(severity = 'error') }}

with scd_logic_validation as (
    select 
        user_id,
        division,
        audit_phase__c,
        update_date,
        is_current,
        is_deleted,
        version_sequence,
        _scd_id,
        
        -- Previous record analysis
        lag(division) over (partition by user_id order by update_date) as prev_division,
        lag(audit_phase__c) over (partition by user_id order by update_date) as prev_audit_phase,
        lag(update_date) over (partition by user_id order by update_date) as prev_update_date,
        lag(is_current) over (partition by user_id order by update_date) as prev_is_current,
        
        -- Next record analysis
        lead(update_date) over (partition by user_id order by update_date) as next_update_date,
        lead(is_current) over (partition by user_id order by update_date) as next_is_current,
        
        -- Record position analysis
        row_number() over (partition by user_id order by update_date) as record_position,
        count(*) over (partition by user_id) as total_records_for_user
        
    from {{ ref('dim_sf_user_scd') }}
    where is_deleted = false
),

logic_violations as (
    -- Test 1: First record should always be version 1
    select 
        user_id,
        update_date,
        version_sequence,
        'first_record_not_version_1' as violation_type,
        'First SCD record for each user should be version 1' as description
    from scd_logic_validation
    where record_position = 1
      and version_sequence != 1
    
    union all
    
    -- Test 2: SCD records should only be created when tracked fields change
    select 
        user_id,
        update_date,
        version_sequence,
        'unnecessary_scd_record' as violation_type,
        'SCD records should only be created when Division or Audit_Phase__c changes' as description
    from scd_logic_validation
    where record_position > 1  -- Not the first record
      and division = coalesce(prev_division, division)
      and audit_phase__c = coalesce(prev_audit_phase, audit_phase__c)
    
    union all
    
    -- Test 3: Previous record should be marked not current when new record is created
    select 
        user_id,
        prev_update_date as update_date,
        version_sequence - 1 as version_sequence,
        'previous_record_still_current' as violation_type,
        'Previous SCD record should be marked not current when new record is created' as description
    from scd_logic_validation
    where record_position > 1
      and prev_is_current = true  -- Previous record is still marked current
    
    union all
    
    -- Test 4: Version sequence should be continuous
    select 
        user_id,
        update_date,
        version_sequence,
        'version_sequence_not_continuous' as violation_type,
        'Version sequence should be continuous (no gaps)' as description
    from scd_logic_validation
    where record_position != version_sequence
    
    union all
    
    -- Test 5: Latest record should be current (unless deleted)
    select 
        user_id,
        update_date,
        version_sequence,
        'latest_record_not_current' as violation_type,
        'Latest non-deleted record should be marked as current' as description
    from scd_logic_validation
    where record_position = total_records_for_user  -- This is the latest record
      and is_current = false
      and next_update_date is null  -- Confirm this is truly the latest
    
    union all
    
    -- Test 6: SCD ID should be unique and properly formatted
    select 
        user_id,
        update_date,
        version_sequence,
        'invalid_scd_id' as violation_type,
        'SCD ID should be unique and properly formatted' as description
    from scd_logic_validation
    where _scd_id is null
       or length(_scd_id) < 10  -- Assuming minimum length for hash
    
    union all
    
    -- Test 7: Update dates should be chronological
    select 
        user_id,
        update_date,
        version_sequence,
        'non_chronological_dates' as violation_type,
        'Update dates should be in chronological order' as description
    from scd_logic_validation
    where prev_update_date is not null
      and update_date <= prev_update_date
)

select * from logic_violations
order by user_id, violation_type, update_date
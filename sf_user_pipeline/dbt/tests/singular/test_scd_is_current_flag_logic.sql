-- Test to validate proper is_current flag management in SCD Type 2
-- This test ensures that is_current flags are properly managed across all SCD operations
-- Requirements: 4.1, 4.2 - Proper is_current flag management and SCD integrity

{{ config(severity = 'error') }}

with current_flag_analysis as (
    select 
        user_id,
        update_date,
        is_current,
        is_deleted,
        version_sequence,
        -- Check if this is the latest non-deleted record for the user
        case 
            when update_date = max(update_date) over (partition by user_id) and is_deleted = false
            then true 
            else false 
        end as should_be_current,
        -- Count current records per user
        sum(case when is_current = true and is_deleted = false then 1 else 0 end) 
            over (partition by user_id) as current_record_count
    from {{ ref('dim_sf_user_scd') }}
),

flag_violations as (
    -- Test 1: Records that should be current but aren't
    select 
        user_id,
        update_date,
        version_sequence,
        'should_be_current_but_not' as violation_type,
        'Latest non-deleted record should be marked as current' as description
    from current_flag_analysis
    where should_be_current = true
      and is_current = false
      and is_deleted = false
    
    union all
    
    -- Test 2: Records that shouldn't be current but are
    select 
        user_id,
        update_date,
        version_sequence,
        'should_not_be_current_but_is' as violation_type,
        'Non-latest records should not be marked as current' as description
    from current_flag_analysis
    where should_be_current = false
      and is_current = true
      and is_deleted = false
    
    union all
    
    -- Test 3: Users with multiple current records
    select 
        user_id,
        update_date,
        version_sequence,
        'multiple_current_records' as violation_type,
        'Each user should have exactly one current record' as description
    from current_flag_analysis
    where current_record_count > 1
      and is_current = true
      and is_deleted = false
    
    union all
    
    -- Test 4: Deleted records marked as current
    select 
        user_id,
        update_date,
        version_sequence,
        'deleted_record_marked_current' as violation_type,
        'Deleted records should never be marked as current' as description
    from current_flag_analysis
    where is_deleted = true
      and is_current = true
    
    union all
    
    -- Test 5: Users with no current records (but have non-deleted records)
    select 
        user_id,
        max(update_date) as update_date,
        max(version_sequence) as version_sequence,
        'no_current_record' as violation_type,
        'Users with non-deleted records should have one current record' as description
    from current_flag_analysis
    where is_deleted = false
    group by user_id
    having sum(case when is_current = true then 1 else 0 end) = 0
)

select * from flag_violations
order by user_id, violation_type, update_date
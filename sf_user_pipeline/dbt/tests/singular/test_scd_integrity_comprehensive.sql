-- Comprehensive SCD Type 2 Integrity Test for sf_user
-- This test validates all aspects of SCD integrity and currency management
-- 
-- Requirements tested:
-- - 4.1: Proper handling of deleted sf_user records with is_deleted flag
-- - 4.2: Create unique SCD identifiers for tracking record versions  
-- - 4.2: Logic to mark previous versions as is_current=false when new versions are created

with scd_integrity_violations as (
    
    -- Test 1: Each user should have exactly one current record (excluding deleted)
    select 
        'multiple_current_records' as violation_type,
        user_id,
        count(*) as current_record_count,
        'Each user should have exactly one current record' as description
    from {{ ref('dim_sf_user_scd') }}
    where is_current = true 
      and is_deleted = false
    group by user_id
    having count(*) > 1
    
    union all
    
    -- Test 2: No user should have zero current records (unless all are deleted)
    select 
        'no_current_records' as violation_type,
        user_id,
        0 as current_record_count,
        'Active users should have at least one current record' as description
    from (
        select user_id
        from {{ ref('dim_sf_user_scd') }}
        group by user_id
        having sum(case when is_current = true and is_deleted = false then 1 else 0 end) = 0
           and sum(case when is_deleted = false then 1 else 0 end) > 0  -- Has non-deleted records
    ) users_without_current
    
    union all
    
    -- Test 3: Deleted records should never be marked as current
    select 
        'deleted_record_marked_current' as violation_type,
        user_id,
        count(*) as violation_count,
        'Deleted records should never be marked as current' as description
    from {{ ref('dim_sf_user_scd') }}
    where is_deleted = true 
      and is_current = true
    group by user_id
    
    union all
    
    -- Test 4: SCD identifiers should be unique
    select 
        'duplicate_scd_id' as violation_type,
        _scd_id as user_id,  -- Using _scd_id in user_id field for consistency
        count(*) as violation_count,
        'SCD identifiers should be unique across all records' as description
    from {{ ref('dim_sf_user_scd') }}
    group by _scd_id
    having count(*) > 1
    
    union all
    
    -- Test 5: Version sequence should be continuous for each user
    select 
        'version_sequence_gap' as violation_type,
        user_id,
        count(*) as gap_count,
        'Version sequences should be continuous without gaps' as description
    from (
        select 
            user_id,
            version_sequence,
            lag(version_sequence) over (partition by user_id order by version_sequence) as prev_sequence
        from {{ ref('dim_sf_user_scd') }}
    ) version_check
    where version_sequence - coalesce(prev_sequence, 0) > 1
    group by user_id
    
    union all
    
    -- Test 6: Current record should be the latest version for each user
    select 
        'current_not_latest' as violation_type,
        user_id,
        1 as violation_count,
        'Current record should be the latest version for each user' as description
    from (
        select 
            user_id,
            update_date,
            is_current,
            max(update_date) over (partition by user_id) as max_update_date
        from {{ ref('dim_sf_user_scd') }}
        where is_deleted = false
    ) currency_check
    where is_current = true 
      and update_date < max_update_date
    
    union all
    
    -- Test 7: Validate proper handling of Division and Audit_Phase__c changes
    select 
        'invalid_scd_trigger' as violation_type,
        user_id,
        count(*) as violation_count,
        'SCD records should only be created when tracked fields change' as description
    from (
        select 
            user_id,
            division,
            audit_phase__c,
            lag(division) over (partition by user_id order by update_date) as prev_division,
            lag(audit_phase__c) over (partition by user_id order by update_date) as prev_audit_phase,
            version_sequence
        from {{ ref('dim_sf_user_scd') }}
    ) change_check
    where version_sequence > 1  -- Not the first record
      and division = coalesce(prev_division, '')
      and audit_phase__c = coalesce(prev_audit_phase, '')
    group by user_id
)

-- Return all integrity violations
select *
from scd_integrity_violations
order by violation_type, user_id
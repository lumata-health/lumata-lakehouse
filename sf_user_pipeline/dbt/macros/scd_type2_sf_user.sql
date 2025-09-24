-- SCD Type 2 macro for sf_user
-- This macro implements Slowly Changing Dimension Type 2 logic specifically for sf_user
-- tracking changes in Division and Audit_Phase__c fields

{% macro scd_type2_sf_user() %}
    
    -- Get source data from staging model
    with source_data as (
        select 
            id as user_id,
            name,
            division,
            audit_phase__c,
            isactive as is_active,
            lastmodifieddate as update_date,
            isdeleted as is_deleted,
            _extracted_at,
            _extraction_run_id
        from {{ ref('stg_sf_user') }}
        where lastmodifieddate is not null
    ),
    
    -- Add row numbers for processing order
    source_with_row_num as (
        select *,
            row_number() over (partition by user_id order by update_date) as rn
        from source_data
    ),
    
    -- Detect changes in tracked fields (Division and Audit_Phase__c)
    changes_detected as (
        select *,
            lag(division) over (partition by user_id order by update_date) as prev_division,
            lag(audit_phase__c) over (partition by user_id order by update_date) as prev_audit_phase,
            lag(update_date) over (partition by user_id order by update_date) as prev_update_date
        from source_with_row_num
    ),
    
    -- Identify records that need SCD processing
    -- Include first record for each user and records where tracked fields changed
    scd_candidates as (
        select *,
            case 
                when rn = 1 then true  -- First record for user
                when division != coalesce(prev_division, '') then true  -- Division changed
                when audit_phase__c != coalesce(prev_audit_phase, '') then true  -- Audit phase changed
                else false
            end as needs_scd_record
        from changes_detected
    ),
    
    -- Filter to only records that need SCD processing
    scd_records_base as (
        select *
        from scd_candidates
        where needs_scd_record = true
    ),
    
    -- Generate SCD records with proper flags and integrity management
    scd_records as (
        select 
            -- Generate surrogate key for SCD record (unique across all versions)
            {{ dbt_utils.generate_surrogate_key(['user_id', 'update_date']) }} as user_key,
            
            -- Core user fields
            user_id,
            name,
            division,
            audit_phase__c,
            is_active,
            update_date,
            
            -- SCD Type 2 currency management
            case 
                when lead(update_date) over (partition by user_id order by update_date) is null 
                     and is_deleted = false
                then true 
                else false 
            end as is_current,
            
            -- Proper handling of deleted sf_user records with is_deleted flag
            case
                when is_deleted = true then true
                else false
            end as is_deleted,
            
            -- Audit fields
            current_timestamp() as _dbt_updated_at,
            _extracted_at,
            _extraction_run_id,
            
            -- Create unique SCD identifiers for tracking record versions
            -- This ensures each version has a unique identifier for merge operations
            {{ dbt_utils.generate_surrogate_key(['user_id', 'update_date', 'division', 'audit_phase__c', 'is_deleted']) }} as _scd_id
            
        from scd_records_base
    ),
    
    -- Additional integrity checks for SCD currency management
    scd_with_integrity_checks as (
        select *,
            -- Ensure only one current record per user (excluding deleted)
            count(*) filter (where is_current = true and is_deleted = false) 
                over (partition by user_id) as current_record_count,
            
            -- Track version sequence for each user
            row_number() over (partition by user_id order by update_date) as version_sequence,
            
            -- Identify if this is the latest version for the user
            case 
                when update_date = max(update_date) over (partition by user_id) 
                then true 
                else false 
            end as is_latest_version
            
        from scd_records
    ),
    
    -- Final SCD records with validation and integrity enforcement
    final_scd_records as (
        select 
            user_key,
            user_id,
            name,
            division,
            audit_phase__c,
            is_active,
            update_date,
            
            -- Enforce SCD integrity: mark previous versions as is_current=false when new versions are created
            case
                when is_deleted = true then false  -- Deleted records are never current
                when is_latest_version = true and is_deleted = false then true  -- Latest non-deleted version is current
                else false  -- All other versions are not current
            end as is_current,
            
            is_deleted,
            _dbt_updated_at,
            _extracted_at,
            _extraction_run_id,
            _scd_id,
            version_sequence
            
        from scd_with_integrity_checks
        where user_id is not null
          and name is not null
          and update_date is not null
          and division in {{ var('valid_divisions') | list }}
          and audit_phase__c in {{ var('valid_audit_phases') | list }}
          -- Ensure SCD integrity: only one current record per user
          and (is_deleted = true or current_record_count <= 1)
    )
    
    select * from final_scd_records

{% endmacro %}
{% doc scd_merge_sf_user %}
This macro implements the merge logic for the a Type 2 Slowly Changing Dimension (SCD) for the `sf_user` table. It is designed to be used in an incremental dbt model.

**Arguments:**
- None

**Behavior:**
- **Incremental Load:**
    1. **Identifies Updates:** It first identifies the `user_id`s that have been updated in the staging table since the last run.
    2. **Generates New Records:** It then calls the `scd_type2_sf_user` macro to generate the new SCD records for the updated users.
    3. **Updates Existing Records:** It identifies the existing `is_current` records for the updated users and marks them as `is_current = false`.
    4. **Combines Records:** It combines the new SCD records with the updated existing records.
- **Full Refresh:**
    - In a full refresh, it calls the `scd_type2_sf_user` macro to generate the SCD records for all users from scratch.

**Returns:**
A CTE that contains the merged SCD records.
{% enddoc %}

-- SCD Type 2 merge helper macro for sf_user
-- This macro handles the merge logic for updating existing SCD records
-- when new versions are created (setting is_current = false for previous versions)
-- 
-- Implements incremental merge strategy to handle:
-- 1. New records and updates to Division/Audit_Phase__c
-- 2. Currency management (is_current flag updates)
-- 3. Proper SCD identifier generation for merge operations

{% macro scd_merge_sf_user() %}
    
    {% if is_incremental() %}
        
        -- Step 1: Identify users with updates in this incremental run
        with users_with_updates as (
            select distinct user_id 
            from {{ ref('stg_sf_user') }}
            where lastmodifieddate > (
                select coalesce(max(update_date), '1900-01-01'::timestamp) 
                from {{ this }}
            )
        ),
        
        -- Step 2: Generate new SCD records for updated users
        new_scd_records as (
            {{ scd_type2_sf_user() }}
        ),
        
        -- Step 3: Get existing records that need currency flag updates
        -- These are current records for users who have new versions
        existing_records_to_update as (
            select 
                user_key,
                user_id,
                name,
                division,
                audit_phase__c,
                is_active,
                update_date,
                false as is_current,  -- Mark previous versions as not current
                is_deleted,
                current_timestamp() as _dbt_updated_at,  -- Update timestamp
                _extracted_at,
                _extraction_run_id,
                _scd_id
            from {{ this }}
            where user_id in (select user_id from users_with_updates)
              and is_current = true
              and _scd_id not in (select _scd_id from new_scd_records)  -- Avoid duplicates
        ),
        
        -- Step 4: Combine updated existing records with new SCD records
        all_records as (
            -- Updated existing records (marked as not current)
            select * from existing_records_to_update
            
            union all
            
            -- New SCD records (marked as current)
            select * from new_scd_records
        ),
        
        -- Step 5: Final validation and cleanup
        final_records as (
            select *
            from all_records
            where user_id is not null
              and name is not null
              and update_date is not null
              and _scd_id is not null
        )
        
        select * from final_records
        
    {% else %}
        
        -- For full refresh, generate all SCD records from scratch
        with full_refresh_records as (
            {{ scd_type2_sf_user() }}
        )
        
        select * from full_refresh_records
        
    {% endif %}

{% endmacro %}
-- Staging model for sf_user data
-- This model provides cleaned and standardized sf_user data for downstream processing

{{ config(
    materialized='view',
    schema='staging'
) }}

with source_data as (
    select * from {{ source('sf_raw', 'sf_user') }}
),

cleaned_data as (
    select 
        -- Core user identifiers
        id,
        trim(name) as name,
        
        -- SCD tracked fields (cleaned and standardized)
        case 
            when trim(upper(division)) in ('NORTH', 'SOUTH', 'EAST', 'WEST', 'CENTRAL') 
            then initcap(trim(division))
            else division
        end as division,
        
        case 
            when trim(upper(audit_phase__c)) in ('PHASE1', 'PHASE2', 'PHASE3', 'COMPLETE')
            then initcap(trim(audit_phase__c))
            else audit_phase__c
        end as audit_phase__c,
        
        -- Status fields
        coalesce(isactive, false) as isactive,
        coalesce(isdeleted, false) as isdeleted,
        
        -- Timestamp fields
        lastmodifieddate,
        createddate,
        
        -- Extraction metadata
        _extracted_at,
        _extraction_run_id
        
    from source_data
    where id is not null  -- Ensure we have valid user IDs
),

-- Apply data quality filters
final as (
    select *
    from cleaned_data
    where name is not null
      and trim(name) != ''
      and lastmodifieddate is not null
)

select * from final
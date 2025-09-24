-- Dimension model for sf_user with SCD Type 2
-- This model tracks changes in key attributes of sf_user over time

{{ config(
    materialized='incremental',
    schema='marts',
    unique_key='id',
    incremental_strategy='merge',
    merge_update_columns=['division', 'audit_phase__c', 'isactive', 'lastmodifieddate'],
    opts={ 'location': 's3://lumata-salesforce-lakehouse-iceberg-dev/iceberg/salesforce_curated/sf_user' }
) }}

with source_data as (
    select * from {{ ref('stg_sf_user') }}
),

-- Identify new and changed records
-- We use the is_incremental() macro to only process new or changed data
{% if is_incremental() %}

latest_records as (
    select * from source_data where lastmodifieddate > (select max(lastmodifieddate) from {{ this }})
),

-- Records to be updated (closed out)
updates as (
    select
        t.id,
        t.lastmodifieddate as dwh_end_ts,
        false as dwh_active_flag
    from {{ this }} t
    join latest_records s on t.id = s.id
    where t.dwh_active_flag = true
      and (t.division != s.division or t.audit_phase__c != s.audit_phase__c)
),

-- New records to be inserted
inserts as (
    select
        id,
        name,
        division,
        audit_phase__c,
        isactive,
        isdeleted,
        createddate,
        lastmodifieddate,
        _extracted_at,
        _extraction_run_id,
        lastmodifieddate as dwh_start_ts,
        null as dwh_end_ts,
        true as dwh_active_flag
    from latest_records
)

select * from updates
union all
select * from inserts

{% else %}

-- Full load for the initial run
select
    id,
    name,
    division,
    audit_phase__c,
    isactive,
    isdeleted,
    createddate,
    lastmodifieddate,
    _extracted_at,
    _extraction_run_id,
    lastmodifieddate as dwh_start_ts,
    null as dwh_end_ts,
    true as dwh_active_flag
from source_data

{% endif %}

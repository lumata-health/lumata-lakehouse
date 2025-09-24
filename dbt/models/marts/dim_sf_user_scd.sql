-- SCD Type 2 dimension model for sf_user
-- This model implements Slowly Changing Dimension Type 2 for sf_user data
-- tracking historical changes in Division and Audit_Phase__c fields
-- 
-- Requirements satisfied:
-- - 4.1: SCD Type 2 implementation for Division and Audit_Phase__c tracking
-- - 4.2: Change detection and historical preservation

{{ config(
    materialized='incremental',
    file_format='iceberg',
    incremental_strategy='merge',
    unique_key='_scd_id',
    merge_update_columns=['is_current', '_dbt_updated_at'],
    schema='curated',
    
    -- Iceberg table properties for optimal query performance
    partition_by=['is_current', 'bucket(8, user_id)'],
    table_properties={
        'write.format.default': 'parquet',
        'write.parquet.compression-codec': 'snappy',
        'write.metadata.compression-codec': 'gzip',
        'write.target-file-size-bytes': '134217728',  -- 128MB target file size
        'format-version': '2',  -- Use Iceberg v2 for better performance
        'write.delete.mode': 'merge-on-read',
        'write.update.mode': 'merge-on-read',
        'write.merge.mode': 'merge-on-read'
    },
    
    -- Performance optimizations
    pre_hook="OPTIMIZE {{ this }} REWRITE DATA USING BIN_PACK WHERE _dbt_updated_at < current_date - interval '7' day",
    post_hook=[
        "ANALYZE TABLE {{ this }} COMPUTE STATISTICS",
        "ANALYZE TABLE {{ this }} COMPUTE STATISTICS FOR ALL COLUMNS"
    ],
    
    -- Incremental processing predicates for performance
    incremental_predicates=[
        "lastmodifieddate > (select coalesce(max(update_date), '1900-01-01'::timestamp) from {{ this }})"
    ]
) }}

-- Use the SCD Type 2 merge macro to handle incremental processing
-- This macro manages both new SCD records and currency flag updates
{{ scd_merge_sf_user() }}
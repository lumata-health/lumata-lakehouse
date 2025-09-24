{{
  config(
    materialized='incremental',
    unique_key='_scd_id',
    file_format='iceberg',
    table_type='iceberg',
    incremental_strategy='merge',
    partition_by=['is_current', 'division'],
    clustered_by=['user_id', 'update_date']
  )
}}

-- SCD Type 2 implementation for sf_user dimension
-- Tracks changes in Division and Audit_Phase__c fields over time

WITH source_data AS (
  SELECT 
    id as user_id,
    name,
    username,
    email,
    division,
    audit_phase__c,
    isactive as is_active,
    lastmodifieddate as update_date,
    false as is_deleted,
    _extracted_at,
    _extraction_run_id
  FROM {{ source('salesforce_raw', 'sf_user') }}
  
  {% if is_incremental() %}
    -- Only process records that have been updated since last run
    WHERE _extracted_at > (SELECT MAX(_dbt_updated_at) FROM {{ this }})
  {% endif %}
),

-- Get existing SCD records for comparison
{% if is_incremental() %}
existing_records AS (
  SELECT 
    user_key,
    user_id,
    name,
    username,
    email,
    division,
    audit_phase__c,
    is_active,
    update_date,
    is_current,
    is_deleted,
    effective_from,
    effective_to,
    _scd_id
  FROM {{ this }}
  WHERE is_current = true
),
{% endif %}

-- Identify changes in tracked fields (Division and Audit_Phase__c)
changes_detected AS (
  SELECT 
    s.*,
    {% if is_incremental() %}
    CASE 
      WHEN e.user_id IS NULL THEN 'INSERT'  -- New user
      WHEN s.division != e.division OR s.audit_phase__c != e.audit_phase__c THEN 'UPDATE'  -- SCD fields changed
      ELSE 'NO_CHANGE'  -- No SCD field changes
    END as change_type,
    e.user_key as existing_user_key,
    e._scd_id as existing_scd_id
    {% else %}
    'INSERT' as change_type,
    NULL as existing_user_key,
    NULL as existing_scd_id
    {% endif %}
  FROM source_data s
  {% if is_incremental() %}
  LEFT JOIN existing_records e ON s.user_id = e.user_id
  {% endif %}
),

-- Generate new SCD records
new_scd_records AS (
  SELECT 
    -- Generate surrogate key
    {% if is_incremental() %}
    COALESCE(existing_user_key, 
      (SELECT COALESCE(MAX(user_key), 0) FROM {{ this }}) + 
      ROW_NUMBER() OVER (ORDER BY user_id)
    ) as user_key,
    {% else %}
    ROW_NUMBER() OVER (ORDER BY user_id) as user_key,
    {% endif %}
    
    user_id,
    name,
    username,
    email,
    division,
    audit_phase__c,
    is_active,
    update_date,
    
    -- SCD Type 2 fields
    true as is_current,
    is_deleted,
    update_date as effective_from,
    NULL as effective_to,
    
    -- Metadata
    CURRENT_TIMESTAMP as _dbt_updated_at,
    
    -- Generate unique SCD identifier
    CONCAT('scd_', user_id, '_', division, '_', audit_phase__c, '_', 
           DATE_FORMAT(update_date, 'yyyyMMdd_HHmmss')) as _scd_id
    
  FROM changes_detected
  WHERE change_type IN ('INSERT', 'UPDATE')
),

-- Handle historical record updates (mark as not current)
{% if is_incremental() %}
historical_updates AS (
  SELECT 
    user_key,
    user_id,
    name,
    username,
    email,
    division,
    audit_phase__c,
    is_active,
    update_date,
    false as is_current,  -- Mark as historical
    is_deleted,
    effective_from,
    c.update_date as effective_to,  -- Set end date
    _dbt_updated_at,
    _scd_id
  FROM existing_records e
  INNER JOIN changes_detected c ON e.user_id = c.user_id
  WHERE c.change_type = 'UPDATE'
),
{% endif %}

-- Union all records
final_records AS (
  -- New/updated current records
  SELECT * FROM new_scd_records
  
  {% if is_incremental() %}
  UNION ALL
  
  -- Historical records (updated to not current)
  SELECT * FROM historical_updates
  
  UNION ALL
  
  -- Existing records with no changes
  SELECT 
    user_key,
    user_id,
    name,
    username,
    email,
    division,
    audit_phase__c,
    is_active,
    update_date,
    is_current,
    is_deleted,
    effective_from,
    effective_to,
    CURRENT_TIMESTAMP as _dbt_updated_at,
    _scd_id
  FROM existing_records e
  WHERE NOT EXISTS (
    SELECT 1 FROM changes_detected c 
    WHERE c.user_id = e.user_id AND c.change_type IN ('UPDATE', 'INSERT')
  )
  {% endif %}
)

SELECT * FROM final_records
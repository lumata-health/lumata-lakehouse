{% doc ensure_scd_currency_integrity %}
This macro ensures the currency integrity of a Type 2 Slowly Changing Dimension (SCD) table. It sets the `is_current` flag to true for the latest non-deleted version of each user.

**Arguments:**
- `user_id_field` (str): The name of the user ID field.
- `update_date_field` (str): The name of the update date field.
- `is_current_field` (str): The name of the `is_current` flag field.
- `is_deleted_field` (str): The name of the `is_deleted` flag field.

**Returns:**
A CTE that contains the `is_current` flag.
{% enddoc %}

{% doc generate_scd_unique_identifier %}
This macro generates a unique identifier for each SCD record.

**Arguments:**
- `user_id_field` (str): The name of the user ID field.
- `update_date_field` (str): The name of the update date field.
- `tracked_fields` (list): A list of the tracked fields.
- `include_deleted` (bool): A boolean to indicate whether to include the `is_deleted` flag in the identifier.

**Returns:**
A unique identifier for the SCD record.
{% enddoc %}

{% doc validate_scd_integrity %}
This macro validates the integrity of a Type 2 Slowly Changing Dimension (SCD) table. It checks for users with more than one current record.

**Returns:**
A CTE that contains the `user_id` and the number of current records for each user with more than one current record.
{% enddoc %}

{% doc mark_previous_versions_not_current %}
This macro marks the previous versions of a user's records as not current when a new version is created.

**Arguments:**
- `user_ids_with_updates` (str): A string containing the user IDs that have updates.

**Returns:**
A CTE that contains the updated records.
{% enddoc %}

{% doc handle_deleted_sf_user_records %}
This macro handles the deleted records from the `sf_user` table. It creates a final SCD record for each deleted user, marking it as deleted and not current.

**Returns:**
A struct that contains the `is_deleted`, `is_current`, `update_date`, and `record_status` fields.
{% enddoc %}

{% doc scd_version_tracking %}
This macro adds version tracking fields to the SCD records.

**Returns:**
The `version_sequence`, `previous_version_date`, `next_version_date`, and `is_latest_version` fields.
{% enddoc %}

{% doc scd_audit_fields %}
This macro adds standard audit fields to the SCD records.

**Returns:**
The `_dbt_updated_at`, `_dbt_invocation_id`, `_dbt_run_started_at`, `_extracted_at`, and `_extraction_run_id` fields.
{% enddoc %}

-- SCD Integrity and Currency Management Macros for sf_user
-- These macros ensure proper SCD Type 2 integrity and currency flag management
-- 
-- Requirements satisfied:
-- - 4.1: Proper handling of deleted sf_user records with is_deleted flag
-- - 4.2: Create unique SCD identifiers for tracking record versions
-- - 4.2: Add logic to mark previous versions as is_current=false when new versions are created

{% macro ensure_scd_currency_integrity(user_id_field='user_id', update_date_field='update_date', is_current_field='is_current', is_deleted_field='is_deleted') %}
    -- Macro to ensure SCD currency integrity
    -- Only one current record per user (excluding deleted records)
    
    case
        when {{ is_deleted_field }} = true then false  -- Deleted records are never current
        when {{ update_date_field }} = max({{ update_date_field }}) over (
            partition by {{ user_id_field }} 
            order by {{ update_date_field }} 
            rows between unbounded preceding and unbounded following
        ) and {{ is_deleted_field }} = false then true  -- Latest non-deleted version is current
        else false  -- All other versions are not current
    end as {{ is_current_field }}

{% endmacro %}

{% macro generate_scd_unique_identifier(user_id_field, update_date_field, tracked_fields=[], include_deleted=true) %}
    -- Generate unique SCD identifier for tracking record versions
    -- Includes all tracked fields to ensure uniqueness across versions
    
    {% set id_fields = [user_id_field, update_date_field] + tracked_fields %}
    {% if include_deleted %}
        {% set id_fields = id_fields + ['is_deleted'] %}
    {% endif %}
    
    {{ dbt_utils.generate_surrogate_key(id_fields) }}

{% endmacro %}

{% macro validate_scd_integrity() %}
    -- Validation macro to check SCD Type 2 integrity
    -- Returns records that violate SCD integrity rules
    
    with integrity_check as (
        select 
            user_id,
            count(*) filter (where is_current = true and is_deleted = false) as current_record_count,
            count(*) as total_versions,
            max(update_date) as latest_update_date,
            sum(case when is_current = true and is_deleted = false then 1 else 0 end) as active_current_count
        from {{ this }}
        group by user_id
    )
    
    select *
    from integrity_check
    where current_record_count != 1  -- Should have exactly one current record per user
       or active_current_count > 1   -- Should not have multiple active current records

{% endmacro %}

{% macro mark_previous_versions_not_current(user_ids_with_updates) %}
    -- Macro to mark previous versions as not current when new versions are created
    -- Used in incremental processing to maintain SCD currency
    
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
        current_timestamp() as _dbt_updated_at,
        _extracted_at,
        _extraction_run_id,
        _scd_id
    from {{ this }}
    where user_id in ({{ user_ids_with_updates }})
      and is_current = true

{% endmacro %}

{% macro handle_deleted_sf_user_records() %}
    -- Proper handling of deleted sf_user records
    -- Ensures deleted records are marked appropriately and not considered current
    
    case
        when isdeleted = true then
            -- For deleted records, create a final SCD record marking deletion
            struct(
                true as is_deleted,
                false as is_current,  -- Deleted records are never current
                lastmodifieddate as update_date,
                'DELETED' as record_status
            )
        else
            -- For active records, normal SCD processing
            struct(
                false as is_deleted,
                null as is_current,  -- Will be determined by currency logic
                lastmodifieddate as update_date,
                'ACTIVE' as record_status
            )
    end

{% endmacro %}

{% macro scd_version_tracking() %}
    -- Add version tracking fields for SCD records
    -- Helps with debugging and monitoring SCD processing
    
    row_number() over (partition by user_id order by update_date) as version_sequence,
    lag(update_date) over (partition by user_id order by update_date) as previous_version_date,
    lead(update_date) over (partition by user_id order by update_date) as next_version_date,
    case 
        when update_date = max(update_date) over (partition by user_id) 
        then true 
        else false 
    end as is_latest_version

{% endmacro %}

{% macro scd_audit_fields() %}
    -- Standard audit fields for SCD records
    -- Provides tracking and debugging information
    
    current_timestamp() as _dbt_updated_at,
    '{{ invocation_id }}' as _dbt_invocation_id,
    '{{ run_started_at }}' as _dbt_run_started_at,
    _extracted_at,
    _extraction_run_id

{% endmacro %}
{% doc validate_scd_integrity %}
This macro validates the integrity of a Type 2 Slowly Changing Dimension (SCD) table. It checks for users with more than one current record.

**Arguments:**
- `table_name` (str): The name of the SCD table to validate.

**Returns:**
A CTE that contains the `user_id` and the number of current records for each user with more than one current record.
{% enddoc %}

{% doc validate_scd_history_completeness %}
This macro validates the completeness of the history in a Type 2 Slowly Changing Dimension (SCD) table. It checks for gaps in the history of each user.

**Arguments:**
- `table_name` (str): The name of the SCD table to validate.

**Returns:**
A CTE that contains the `user_id`, the current and previous `update_date`, and the gap in days for each gap found in the history.
{% enddoc %}

{% doc validate_tracked_field_changes %}
This macro validates that new SCD records are only created when the tracked fields have changed.

**Arguments:**
- `table_name` (str): The name of the SCD table to validate.

**Returns:**
A CTE that contains the records that have a new version but no change in the tracked fields.
{% enddoc %}

{% doc get_scd_statistics %}
This macro calculates statistics for a Type 2 Slowly Changing Dimension (SCD) table.

**Arguments:**
- `table_name` (str): The name of the SCD table.

**Returns:**
A CTE that contains the total number of records, the number of unique users, the number of current and historical records, the number of deleted records, and the earliest and latest record dates.
{% enddoc %}

{% doc validate_sf_user_business_rules %}
This macro validates the business rules for the `sf_user` table.

**Arguments:**
- `table_name` (str): The name of the table to validate.

**Returns:**
A CTE that contains the records that violate the business rules.
{% enddoc %}

-- SCD Type 2 data quality check macros for sf_user
-- These macros provide reusable data quality validation for SCD implementation

-- Macro to validate SCD integrity (no overlapping current records)
{% macro validate_scd_integrity(table_name) %}
    
    select 
        user_id,
        count(*) as current_record_count
    from {{ table_name }}
    where is_current = true
      and is_deleted = false
    group by user_id
    having count(*) > 1

{% endmacro %}

-- Macro to validate SCD history completeness (no gaps in history)
{% macro validate_scd_history_completeness(table_name) %}
    
    with user_history as (
        select 
            user_id,
            update_date,
            lag(update_date) over (partition by user_id order by update_date) as prev_update_date,
            is_current,
            is_deleted
        from {{ table_name }}
        where is_deleted = false
        order by user_id, update_date
    ),
    
    potential_gaps as (
        select 
            user_id,
            update_date,
            prev_update_date,
            extract(day from (update_date - prev_update_date)) as days_gap
        from user_history
        where prev_update_date is not null
          and extract(day from (update_date - prev_update_date)) > 1  -- More than 1 day gap
    )
    
    select * from potential_gaps

{% endmacro %}

-- Macro to validate tracked field changes
{% macro validate_tracked_field_changes(table_name) %}
    
    with field_changes as (
        select 
            user_id,
            update_date,
            division,
            audit_phase__c,
            lag(division) over (partition by user_id order by update_date) as prev_division,
            lag(audit_phase__c) over (partition by user_id order by update_date) as prev_audit_phase,
            row_number() over (partition by user_id order by update_date) as rn
        from {{ table_name }}
        where is_deleted = false
        order by user_id, update_date
    ),
    
    -- Records that should have triggered SCD but didn't change tracked fields
    invalid_scd_records as (
        select *
        from field_changes
        where rn > 1  -- Not the first record
          and division = coalesce(prev_division, division)  -- Division didn't change
          and audit_phase__c = coalesce(prev_audit_phase, audit_phase__c)  -- Audit phase didn't change
    )
    
    select * from invalid_scd_records

{% endmacro %}

-- Macro to get SCD statistics for monitoring
{% macro get_scd_statistics(table_name) %}
    
    select 
        'sf_user_scd' as table_name,
        count(*) as total_records,
        count(distinct user_id) as unique_users,
        sum(case when is_current = true and is_deleted = false then 1 else 0 end) as current_active_records,
        sum(case when is_current = false and is_deleted = false then 1 else 0 end) as historical_records,
        sum(case when is_deleted = true then 1 else 0 end) as deleted_records,
        min(update_date) as earliest_record_date,
        max(update_date) as latest_record_date,
        max(_dbt_updated_at) as last_dbt_run
    from {{ table_name }}

{% endmacro %}

-- Macro to validate business rules for sf_user
{% macro validate_sf_user_business_rules(table_name) %}
    
    with business_rule_violations as (
        select 
            user_id,
            name,
            division,
            audit_phase__c,
            update_date,
            case 
                when division not in {{ var('valid_divisions') | list }} then 'Invalid Division'
                when audit_phase__c not in {{ var('valid_audit_phases') | list }} then 'Invalid Audit Phase'
                when name is null or trim(name) = '' then 'Missing Name'
                else null
            end as violation_type
        from {{ table_name }}
        where is_deleted = false
    )
    
    select * 
    from business_rule_violations
    where violation_type is not null

{% endmacro %}
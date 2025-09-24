-- Test to ensure proper SCD currency management for sf_user
-- This test validates that when a new SCD record is created,
-- the previous record is properly marked as not current (is_current = false)

{{ config(severity = 'error') }}

with user_versions as (
    select 
        user_id,
        update_date,
        is_current,
        is_deleted,
        lead(update_date) over (partition by user_id order by update_date) as next_update_date
    from {{ ref('dim_sf_user_scd') }}
    where is_deleted = false
    order by user_id, update_date
),

-- Find records that should be marked as not current but aren't
currency_violations as (
    select *
    from user_versions
    where next_update_date is not null  -- There is a newer version
      and is_current = true  -- But this record is still marked as current
)

select * from currency_violations
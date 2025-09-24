-- Test to ensure SCD Type 2 integrity for sf_user
-- This test validates that each user has exactly one current record (is_current = true)
-- when the user is not deleted

{{ config(severity = 'error') }}

with current_record_counts as (
    select 
        user_id,
        count(*) as current_record_count
    from {{ ref('dim_sf_user_scd') }}
    where is_current = true
      and is_deleted = false
    group by user_id
),

integrity_violations as (
    select *
    from current_record_counts
    where current_record_count != 1
)

select * from integrity_violations
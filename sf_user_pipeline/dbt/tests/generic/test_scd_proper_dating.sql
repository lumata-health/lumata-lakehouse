-- Generic test for SCD Type 2 proper dating
-- This test validates that SCD records have proper chronological ordering
-- Requirements: 4.1, 4.2 - SCD Type 2 proper dating and historical tracking

{% test scd_proper_dating(model, user_id_column='user_id', date_column='update_date') %}

with date_validation as (
    select 
        {{ user_id_column }},
        {{ date_column }},
        lag({{ date_column }}) over (partition by {{ user_id_column }} order by {{ date_column }}) as prev_date,
        is_current,
        is_deleted
    from {{ model }}
    where coalesce(is_deleted, false) = false
),

dating_violations as (
    select *
    from date_validation
    where prev_date is not null
      and {{ date_column }} <= prev_date  -- Current date should be after previous date
)

select * from dating_violations

{% endtest %}
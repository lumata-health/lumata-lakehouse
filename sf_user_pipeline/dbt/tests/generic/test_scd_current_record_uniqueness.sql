-- Generic test for SCD Type 2 current record uniqueness
-- This test ensures each user has exactly one current record
-- Requirements: 4.1, 4.2 - SCD Type 2 integrity and current record management

{% test scd_current_record_uniqueness(model, user_id_column='user_id') %}

with current_record_counts as (
    select 
        {{ user_id_column }},
        count(*) as current_record_count
    from {{ model }}
    where is_current = true
      and coalesce(is_deleted, false) = false
    group by {{ user_id_column }}
),

uniqueness_violations as (
    select *
    from current_record_counts
    where current_record_count != 1
)

select * from uniqueness_violations

{% endtest %}
-- Test to ensure no gaps or overlaps in SCD record history
-- This test validates that SCD Type 2 records have proper temporal continuity
-- Requirements: 4.1, 5.1 - Ensure no gaps or overlaps in SCD record history

{{ config(severity = 'error') }}

with user_timeline as (
    select 
        user_id,
        update_date,
        lead(update_date) over (partition by user_id order by update_date) as next_update_date,
        is_current,
        is_deleted,
        version_sequence
    from {{ ref('dim_sf_user_scd') }}
    where is_deleted = false
    order by user_id, update_date
),

-- Check for gaps in version sequences
version_gaps as (
    select 
        user_id,
        version_sequence,
        lag(version_sequence) over (partition by user_id order by version_sequence) as prev_version,
        'version_sequence_gap' as violation_type
    from {{ ref('dim_sf_user_scd') }}
    where is_deleted = false
),

gap_violations as (
    select 
        user_id,
        version_sequence,
        prev_version,
        violation_type
    from version_gaps
    where prev_version is not null
      and version_sequence - prev_version > 1  -- Gap in sequence
),

-- Check for temporal overlaps (should not exist in SCD Type 2)
temporal_overlaps as (
    select 
        user_id,
        update_date,
        next_update_date,
        'temporal_overlap' as violation_type
    from user_timeline
    where next_update_date is not null
      and update_date >= next_update_date  -- Current date is not before next date
),

-- Check for missing current records
missing_current as (
    select 
        user_id,
        max(update_date) as latest_date,
        'missing_current_record' as violation_type
    from {{ ref('dim_sf_user_scd') }}
    where is_deleted = false
    group by user_id
    having sum(case when is_current = true then 1 else 0 end) = 0  -- No current record
),

-- Combine all violations
all_violations as (
    select user_id, version_sequence as detail, violation_type from gap_violations
    union all
    select user_id, extract(epoch from update_date)::bigint as detail, violation_type from temporal_overlaps
    union all
    select user_id, extract(epoch from latest_date)::bigint as detail, violation_type from missing_current
)

select * from all_violations
order by user_id, violation_type
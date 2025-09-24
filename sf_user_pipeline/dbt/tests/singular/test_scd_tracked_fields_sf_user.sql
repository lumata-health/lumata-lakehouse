-- Test to ensure SCD records are only created when tracked fields change
-- This test validates that consecutive SCD records for the same user
-- have different values in Division or Audit_Phase__c fields

{{ config(severity = 'warn') }}

with user_history as (
    select 
        user_id,
        division,
        audit_phase__c,
        update_date,
        lag(division) over (partition by user_id order by update_date) as prev_division,
        lag(audit_phase__c) over (partition by user_id order by update_date) as prev_audit_phase,
        row_number() over (partition by user_id order by update_date) as rn
    from {{ ref('dim_sf_user_scd') }}
    where is_deleted = false
    order by user_id, update_date
),

-- Find records where tracked fields didn't change (except first record)
unnecessary_scd_records as (
    select *
    from user_history
    where rn > 1  -- Not the first record for the user
      and division = coalesce(prev_division, division)  -- Division didn't change
      and audit_phase__c = coalesce(prev_audit_phase, audit_phase__c)  -- Audit phase didn't change
)

select * from unnecessary_scd_records
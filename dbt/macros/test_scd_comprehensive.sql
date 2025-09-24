{% doc test_scd_comprehensive %}
This macro runs a comprehensive set of tests for a Type 2 Slowly Changing Dimension (SCD) table.

**Arguments:**
- `table_name` (str): The name of the SCD table to test.

**Returns:**
A CTE that contains the results of the tests.
{% enddoc %}

{% doc generate_scd_test_report %}
This macro generates a test report for the SCD table.

**Returns:**
A CTE that contains the test report.
{% enddoc %}

{% doc validate_scd_performance_metrics %}
This macro validates the performance metrics of an SCD table.

**Arguments:**
- `table_name` (str): The name of the SCD table to validate.

**Returns:**
A CTE that contains the performance metrics.
{% enddoc %}

-- Comprehensive SCD testing macro for sf_user
-- This macro runs all SCD-related tests and provides a summary report
-- Requirements: 4.1, 4.2, 5.1 - Comprehensive SCD testing and validation

{% macro test_scd_comprehensive(table_name='dim_sf_user_scd') %}

    {% set test_results = [] %}
    
    -- Test 1: SCD Integrity (Current Record Uniqueness)
    {% set integrity_test %}
        select 
            'scd_integrity' as test_name,
            count(*) as violation_count,
            'Each user should have exactly one current record' as description
        from (
            {{ validate_scd_integrity(ref(table_name)) }}
        ) integrity_violations
    {% endset %}
    
    -- Test 2: SCD History Completeness
    {% set history_test %}
        select 
            'scd_history_completeness' as test_name,
            count(*) as violation_count,
            'SCD history should be complete without gaps' as description
        from (
            {{ validate_scd_history_completeness(ref(table_name)) }}
        ) history_violations
    {% endset %}
    
    -- Test 3: Tracked Field Changes
    {% set changes_test %}
        select 
            'tracked_field_changes' as test_name,
            count(*) as violation_count,
            'SCD records should only be created when tracked fields change' as description
        from (
            {{ validate_tracked_field_changes(ref(table_name)) }}
        ) change_violations
    {% endset %}
    
    -- Test 4: Business Rules Validation
    {% set business_rules_test %}
        select 
            'business_rules' as test_name,
            count(*) as violation_count,
            'All business rules should be satisfied' as description
        from (
            {{ validate_sf_user_business_rules(ref(table_name)) }}
        ) business_violations
    {% endset %}
    
    -- Combine all test results
    with test_summary as (
        {{ integrity_test }}
        union all
        {{ history_test }}
        union all
        {{ changes_test }}
        union all
        {{ business_rules_test }}
    ),
    
    -- Add overall statistics
    overall_stats as (
        select 
            'overall_statistics' as test_name,
            0 as violation_count,
            concat(
                'Total records: ', count(*), 
                ', Unique users: ', count(distinct user_id),
                ', Current records: ', sum(case when is_current = true and is_deleted = false then 1 else 0 end),
                ', Historical records: ', sum(case when is_current = false and is_deleted = false then 1 else 0 end),
                ', Deleted records: ', sum(case when is_deleted = true then 1 else 0 end)
            ) as description
        from {{ ref(table_name) }}
    )
    
    select * from test_summary
    union all
    select * from overall_stats
    order by 
        case 
            when test_name = 'overall_statistics' then 1
            else 2
        end,
        test_name

{% endmacro %}

-- Macro to generate SCD test report
{% macro generate_scd_test_report() %}
    
    select 
        current_timestamp() as report_generated_at,
        'sf_user_scd_test_report' as report_type,
        test_name,
        violation_count,
        case 
            when violation_count = 0 then 'PASS'
            when violation_count > 0 and test_name != 'overall_statistics' then 'FAIL'
            else 'INFO'
        end as test_status,
        description
    from (
        {{ test_scd_comprehensive() }}
    ) test_results
    
{% endmacro %}

-- Macro to validate SCD performance metrics
{% macro validate_scd_performance_metrics(table_name='dim_sf_user_scd') %}
    
    with performance_metrics as (
        select 
            count(*) as total_records,
            count(distinct user_id) as unique_users,
            avg(version_sequence) as avg_versions_per_user,
            max(version_sequence) as max_versions_per_user,
            min(update_date) as earliest_record,
            max(update_date) as latest_record,
            extract(day from (max(update_date) - min(update_date))) as date_range_days,
            
            -- Calculate SCD efficiency metrics
            count(*) / count(distinct user_id) as avg_scd_records_per_user,
            sum(case when is_current = true then 1 else 0 end) / count(distinct user_id) as current_records_ratio,
            
            -- Data quality metrics
            sum(case when division in {{ var('valid_divisions') | list }} then 1 else 0 end) / count(*) as valid_division_ratio,
            sum(case when audit_phase__c in {{ var('valid_audit_phases') | list }} then 1 else 0 end) / count(*) as valid_audit_phase_ratio
            
        from {{ ref(table_name) }}
        where is_deleted = false
    )
    
    select 
        'performance_metrics' as metric_category,
        json_build_object(
            'total_records', total_records,
            'unique_users', unique_users,
            'avg_versions_per_user', round(avg_versions_per_user, 2),
            'max_versions_per_user', max_versions_per_user,
            'date_range_days', date_range_days,
            'avg_scd_records_per_user', round(avg_scd_records_per_user, 2),
            'current_records_ratio', round(current_records_ratio, 4),
            'valid_division_ratio', round(valid_division_ratio, 4),
            'valid_audit_phase_ratio', round(valid_audit_phase_ratio, 4)
        ) as metrics
    from performance_metrics
    
{% endmacro %}
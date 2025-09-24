-- Generic test for sf_user data type validation
-- This test validates that all fields have the expected data types and formats
-- Requirements: 5.1 - Data quality validation for sf_user records

{% test sf_user_data_types(model, column_name) %}

with data_type_validation as (
    select 
        {{ column_name }},
        case 
            when '{{ column_name }}' = 'id' then 
                case when {{ column_name }} ~ '^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$' then 'valid' else 'invalid' end
            when '{{ column_name }}' = 'name' then 
                case when length(trim({{ column_name }})) >= 1 and length(trim({{ column_name }})) <= 255 then 'valid' else 'invalid' end
            when '{{ column_name }}' = 'division' then 
                case when {{ column_name }} in {{ var('valid_divisions') | list }} then 'valid' else 'invalid' end
            when '{{ column_name }}' = 'audit_phase__c' then 
                case when {{ column_name }} in {{ var('valid_audit_phases') | list }} then 'valid' else 'invalid' end
            when '{{ column_name }}' in ('isactive', 'isdeleted', 'is_current', 'is_deleted') then 
                case when {{ column_name }} in (true, false) then 'valid' else 'invalid' end
            when '{{ column_name }}' in ('lastmodifieddate', 'createddate', 'update_date', '_dbt_updated_at', '_extracted_at') then 
                case when {{ column_name }} is not null and {{ column_name }} >= '1900-01-01'::timestamp then 'valid' else 'invalid' end
            else 'valid'  -- Default to valid for other fields
        end as validation_result
    from {{ model }}
    where {{ column_name }} is not null
),

validation_failures as (
    select *
    from data_type_validation
    where validation_result = 'invalid'
)

select * from validation_failures

{% endtest %}
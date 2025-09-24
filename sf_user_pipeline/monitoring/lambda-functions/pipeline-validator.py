"""
sf_user Pipeline Validator Lambda Function

Validates pipeline execution results, data quality, and SCD integrity.
Provides comprehensive validation for different stages of the pipeline.
"""

import json
import boto3
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Tuple
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
athena = boto3.client('athena')
s3 = boto3.client('s3')

# Configuration
ATHENA_DATABASE = os.environ.get('ATHENA_DATABASE', 'salesforce_curated')
ATHENA_WORKGROUP = os.environ.get('ATHENA_WORKGROUP', 'primary')
S3_RESULTS_BUCKET = os.environ.get('S3_RESULTS_BUCKET', 'lumata-salesforce-lakehouse-config-dev')
S3_RESULTS_PREFIX = 'athena-results/'
DEFAULT_ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for pipeline validation.
    
    Args:
        event: Event data containing validation request
        context: Lambda context object
        
    Returns:
        Dict containing validation results
    """
    try:
        logger.info(f"Processing validation request: {json.dumps(event, default=str)}")
        
        # Extract validation details
        validation_type = event.get('validation_type', 'unknown')
        execution_id = event.get('execution_id', 'unknown')
        environment = event.get('environment', DEFAULT_ENVIRONMENT)
        
        # Route to appropriate validator
        if validation_type == 'glue_job_results':
            result = validate_glue_job_results(event, environment)
        elif validation_type == 'scd_integrity':
            result = validate_scd_integrity(event, environment)
        else:
            result = {
                'validation_passed': False,
                'error': f'Unknown validation type: {validation_type}'
            }
        
        # Add common fields
        result.update({
            'validation_type': validation_type,
            'execution_id': execution_id,
            'environment': environment,
            'validated_at': datetime.now(timezone.utc).isoformat()
        })
        
        logger.info(f"Validation completed: {validation_type} - Passed: {result.get('validation_passed', False)}")
        
        return result
        
    except Exception as e:
        logger.error(f"Error in pipeline validator: {str(e)}", exc_info=True)
        return {
            'validation_passed': False,
            'error': str(e),
            'execution_id': event.get('execution_id', 'unknown'),
            'validation_type': event.get('validation_type', 'unknown')
        }

def validate_glue_job_results(event: Dict[str, Any], environment: str) -> Dict[str, Any]:
    """Validate Glue job execution results and data quality."""
    glue_job_result = event.get('glue_job_result', {})
    
    validation_results = {
        'validation_passed': True,
        'data_quality_passed': True,
        'validations_performed': [],
        'failed_validations': [],
        'data_quality_score': 100,
        'records_processed': 0,
        'validation_details': {}
    }
    
    try:
        # Validate Glue job execution status
        job_run_state = glue_job_result.get('JobRunState', 'UNKNOWN')
        validation_results['validations_performed'].append('glue_job_status')
        
        if job_run_state != 'SUCCEEDED':
            validation_results['validation_passed'] = False
            validation_results['data_quality_passed'] = False
            validation_results['failed_validations'].append(f'Glue job failed with state: {job_run_state}')
            return validation_results
        
        # Extract records processed
        arguments = glue_job_result.get('Arguments', {})
        records_processed = int(arguments.get('--records-processed', 0))
        validation_results['records_processed'] = records_processed
        
        # Validate minimum record count
        validation_results['validations_performed'].append('minimum_record_count')
        min_expected_records = 100  # Configurable threshold
        
        if records_processed < min_expected_records:
            validation_results['failed_validations'].append(
                f'Records processed ({records_processed}) below minimum threshold ({min_expected_records})'
            )
            validation_results['data_quality_passed'] = False
        
        # Validate data freshness in raw table
        freshness_validation = validate_data_freshness(environment)
        validation_results['validations_performed'].append('data_freshness')
        validation_results['validation_details']['data_freshness'] = freshness_validation
        
        if not freshness_validation['passed']:
            validation_results['failed_validations'].extend(freshness_validation['errors'])
            validation_results['data_quality_passed'] = False
        
        # Validate required fields presence
        required_fields_validation = validate_required_fields(environment)
        validation_results['validations_performed'].append('required_fields')
        validation_results['validation_details']['required_fields'] = required_fields_validation
        
        if not required_fields_validation['passed']:
            validation_results['failed_validations'].extend(required_fields_validation['errors'])
            validation_results['data_quality_passed'] = False
        
        # Calculate overall data quality score
        total_validations = len(validation_results['validations_performed'])
        failed_validations = len(validation_results['failed_validations'])
        
        if total_validations > 0:
            validation_results['data_quality_score'] = ((total_validations - failed_validations) / total_validations) * 100
        
        # Overall validation passes if data quality is above threshold
        quality_threshold = 95  # 95% threshold
        validation_results['validation_passed'] = validation_results['data_quality_score'] >= quality_threshold
        
    except Exception as e:
        logger.error(f"Error validating Glue job results: {e}")
        validation_results['validation_passed'] = False
        validation_results['data_quality_passed'] = False
        validation_results['failed_validations'].append(f'Validation error: {str(e)}')
    
    return validation_results

def validate_scd_integrity(event: Dict[str, Any], environment: str) -> Dict[str, Any]:
    """Validate SCD Type 2 integrity and historical tracking."""
    dbt_test_result = event.get('dbt_test_result', {})
    
    validation_results = {
        'validation_passed': True,
        'integrity_score': 100,
        'validations_performed': [],
        'validation_errors': 0,
        'scd_records_created': 0,
        'scd_records_updated': 0,
        'scd_records_deleted': 0,
        'validation_details': {}
    }
    
    try:
        # Validate dbt test results first
        if dbt_test_result and 'Payload' in dbt_test_result:
            payload = dbt_test_result['Payload']
            tests_failed = payload.get('tests_failed', 0)
            
            if tests_failed > 0:
                validation_results['validation_passed'] = False
                validation_results['validation_errors'] += tests_failed
        
        # Validate SCD current record uniqueness
        current_uniqueness_validation = validate_scd_current_uniqueness(environment)
        validation_results['validations_performed'].append('scd_current_uniqueness')
        validation_results['validation_details']['current_uniqueness'] = current_uniqueness_validation
        
        if not current_uniqueness_validation['passed']:
            validation_results['validation_passed'] = False
            validation_results['validation_errors'] += current_uniqueness_validation['error_count']
        
        # Validate SCD historical integrity
        historical_integrity_validation = validate_scd_historical_integrity(environment)
        validation_results['validations_performed'].append('scd_historical_integrity')
        validation_results['validation_details']['historical_integrity'] = historical_integrity_validation
        
        if not historical_integrity_validation['passed']:
            validation_results['validation_passed'] = False
            validation_results['validation_errors'] += historical_integrity_validation['error_count']
        
        # Get SCD processing statistics
        scd_stats = get_scd_processing_stats(environment)
        validation_results.update({
            'scd_records_created': scd_stats.get('records_created', 0),
            'scd_records_updated': scd_stats.get('records_updated', 0),
            'scd_records_deleted': scd_stats.get('records_deleted', 0)
        })
        
        # Calculate integrity score
        total_validations = len(validation_results['validations_performed'])
        if total_validations > 0:
            passed_validations = sum(1 for v in validation_results['validation_details'].values() if v['passed'])
            validation_results['integrity_score'] = (passed_validations / total_validations) * 100
        
    except Exception as e:
        logger.error(f"Error validating SCD integrity: {e}")
        validation_results['validation_passed'] = False
        validation_results['validation_errors'] += 1
        validation_results['integrity_score'] = 0
    
    return validation_results

def validate_data_freshness(environment: str) -> Dict[str, Any]:
    """Validate that data in raw table is fresh (recent extraction)."""
    query = f"""
    SELECT 
        MAX(_extracted_at) as latest_extraction,
        COUNT(*) as total_records,
        COUNT(DISTINCT DATE(_extracted_at)) as extraction_days
    FROM salesforce_raw.sf_user
    WHERE _extracted_at >= current_timestamp - interval '1' day
    """
    
    try:
        result = execute_athena_query(query)
        
        if result and len(result) > 0:
            row = result[0]
            latest_extraction = row.get('latest_extraction')
            total_records = int(row.get('total_records', 0))
            
            # Check if data is within last 6 hours (pipeline frequency)
            if latest_extraction:
                extraction_time = datetime.fromisoformat(latest_extraction.replace('Z', '+00:00'))
                hours_since_extraction = (datetime.now(timezone.utc) - extraction_time).total_seconds() / 3600
                
                if hours_since_extraction <= 6 and total_records > 0:
                    return {
                        'passed': True,
                        'latest_extraction': latest_extraction,
                        'total_records': total_records,
                        'hours_since_extraction': hours_since_extraction,
                        'errors': []
                    }
                else:
                    return {
                        'passed': False,
                        'latest_extraction': latest_extraction,
                        'total_records': total_records,
                        'hours_since_extraction': hours_since_extraction,
                        'errors': [f'Data not fresh - {hours_since_extraction:.1f} hours since last extraction']
                    }
            else:
                return {
                    'passed': False,
                    'errors': ['No recent extraction timestamp found']
                }
        else:
            return {
                'passed': False,
                'errors': ['No data found in raw table']
            }
            
    except Exception as e:
        logger.error(f"Error validating data freshness: {e}")
        return {
            'passed': False,
            'errors': [f'Freshness validation error: {str(e)}']
        }

def validate_required_fields(environment: str) -> Dict[str, Any]:
    """Validate that required fields are present and not null."""
    query = f"""
    SELECT 
        COUNT(*) as total_records,
        COUNT(id) as id_count,
        COUNT(name) as name_count,
        COUNT(division) as division_count,
        COUNT(audit_phase__c) as audit_phase_count
    FROM salesforce_raw.sf_user
    WHERE _extracted_at >= current_timestamp - interval '1' day
    """
    
    try:
        result = execute_athena_query(query)
        
        if result and len(result) > 0:
            row = result[0]
            total_records = int(row.get('total_records', 0))
            id_count = int(row.get('id_count', 0))
            name_count = int(row.get('name_count', 0))
            division_count = int(row.get('division_count', 0))
            audit_phase_count = int(row.get('audit_phase_count', 0))
            
            errors = []
            
            if total_records == 0:
                errors.append('No records found')
            else:
                if id_count != total_records:
                    errors.append(f'Missing ID values: {total_records - id_count} records')
                if name_count != total_records:
                    errors.append(f'Missing Name values: {total_records - name_count} records')
                # Division and Audit_Phase__c can be null, so we don't enforce 100% coverage
            
            return {
                'passed': len(errors) == 0,
                'total_records': total_records,
                'field_coverage': {
                    'id': id_count / total_records * 100 if total_records > 0 else 0,
                    'name': name_count / total_records * 100 if total_records > 0 else 0,
                    'division': division_count / total_records * 100 if total_records > 0 else 0,
                    'audit_phase__c': audit_phase_count / total_records * 100 if total_records > 0 else 0
                },
                'errors': errors
            }
        else:
            return {
                'passed': False,
                'errors': ['Could not retrieve field validation data']
            }
            
    except Exception as e:
        logger.error(f"Error validating required fields: {e}")
        return {
            'passed': False,
            'errors': [f'Required fields validation error: {str(e)}']
        }

def validate_scd_current_uniqueness(environment: str) -> Dict[str, Any]:
    """Validate that each user has only one current record."""
    query = f"""
    SELECT 
        user_id,
        COUNT(*) as current_record_count
    FROM salesforce_curated.dim_sf_user_scd
    WHERE is_current = true AND is_deleted = false
    GROUP BY user_id
    HAVING COUNT(*) > 1
    """
    
    try:
        result = execute_athena_query(query)
        
        duplicate_users = len(result) if result else 0
        
        return {
            'passed': duplicate_users == 0,
            'duplicate_current_records': duplicate_users,
            'error_count': duplicate_users,
            'details': result[:10] if result else []  # First 10 duplicates for debugging
        }
        
    except Exception as e:
        logger.error(f"Error validating SCD current uniqueness: {e}")
        return {
            'passed': False,
            'error_count': 1,
            'error_message': str(e)
        }

def validate_scd_historical_integrity(environment: str) -> Dict[str, Any]:
    """Validate SCD historical integrity (no gaps or overlaps)."""
    query = f"""
    WITH scd_ordered AS (
        SELECT 
            user_id,
            update_date,
            is_current,
            LAG(update_date) OVER (PARTITION BY user_id ORDER BY update_date) as prev_update_date,
            LEAD(update_date) OVER (PARTITION BY user_id ORDER BY update_date) as next_update_date
        FROM salesforce_curated.dim_sf_user_scd
        WHERE is_deleted = false
    ),
    integrity_issues AS (
        SELECT 
            user_id,
            'gap_in_history' as issue_type,
            update_date,
            prev_update_date
        FROM scd_ordered
        WHERE prev_update_date IS NOT NULL 
        AND update_date != prev_update_date
        AND is_current = false
        
        UNION ALL
        
        SELECT 
            user_id,
            'current_flag_issue' as issue_type,
            update_date,
            next_update_date
        FROM scd_ordered
        WHERE is_current = true AND next_update_date IS NOT NULL
    )
    SELECT 
        issue_type,
        COUNT(*) as issue_count
    FROM integrity_issues
    GROUP BY issue_type
    """
    
    try:
        result = execute_athena_query(query)
        
        total_issues = sum(int(row.get('issue_count', 0)) for row in result) if result else 0
        
        return {
            'passed': total_issues == 0,
            'error_count': total_issues,
            'integrity_issues': result if result else [],
            'details': 'SCD historical integrity validation completed'
        }
        
    except Exception as e:
        logger.error(f"Error validating SCD historical integrity: {e}")
        return {
            'passed': False,
            'error_count': 1,
            'error_message': str(e)
        }

def get_scd_processing_stats(environment: str) -> Dict[str, Any]:
    """Get statistics about SCD processing from the latest run."""
    query = f"""
    SELECT 
        COUNT(*) as total_scd_records,
        COUNT(CASE WHEN is_current = true THEN 1 END) as current_records,
        COUNT(CASE WHEN is_deleted = true THEN 1 END) as deleted_records,
        COUNT(CASE WHEN _dbt_updated_at >= current_timestamp - interval '1' day THEN 1 END) as recently_updated
    FROM salesforce_curated.dim_sf_user_scd
    """
    
    try:
        result = execute_athena_query(query)
        
        if result and len(result) > 0:
            row = result[0]
            return {
                'total_scd_records': int(row.get('total_scd_records', 0)),
                'current_records': int(row.get('current_records', 0)),
                'deleted_records': int(row.get('deleted_records', 0)),
                'records_created': int(row.get('recently_updated', 0)),  # Approximation
                'records_updated': 0,  # Would need more complex logic to determine
                'records_deleted': int(row.get('deleted_records', 0))
            }
        else:
            return {
                'total_scd_records': 0,
                'current_records': 0,
                'deleted_records': 0,
                'records_created': 0,
                'records_updated': 0,
                'records_deleted': 0
            }
            
    except Exception as e:
        logger.error(f"Error getting SCD processing stats: {e}")
        return {
            'total_scd_records': 0,
            'current_records': 0,
            'deleted_records': 0,
            'records_created': 0,
            'records_updated': 0,
            'records_deleted': 0
        }

def execute_athena_query(query: str) -> List[Dict[str, Any]]:
    """Execute Athena query and return results."""
    try:
        # Start query execution
        response = athena.start_query_execution(
            QueryString=query,
            QueryExecutionContext={'Database': ATHENA_DATABASE},
            WorkGroup=ATHENA_WORKGROUP,
            ResultConfiguration={
                'OutputLocation': f's3://{S3_RESULTS_BUCKET}/{S3_RESULTS_PREFIX}'
            }
        )
        
        query_execution_id = response['QueryExecutionId']
        
        # Wait for query completion
        while True:
            response = athena.get_query_execution(QueryExecutionId=query_execution_id)
            status = response['QueryExecution']['Status']['State']
            
            if status in ['SUCCEEDED', 'FAILED', 'CANCELLED']:
                break
        
        if status != 'SUCCEEDED':
            raise Exception(f"Query failed with status: {status}")
        
        # Get query results
        results = athena.get_query_results(QueryExecutionId=query_execution_id)
        
        # Parse results
        columns = [col['Label'] for col in results['ResultSet']['ResultSetMetadata']['ColumnInfo']]
        rows = []
        
        for row in results['ResultSet']['Rows'][1:]:  # Skip header row
            row_data = {}
            for i, col in enumerate(columns):
                row_data[col] = row['Data'][i].get('VarCharValue', '')
            rows.append(row_data)
        
        return rows
        
    except Exception as e:
        logger.error(f"Error executing Athena query: {e}")
        raise
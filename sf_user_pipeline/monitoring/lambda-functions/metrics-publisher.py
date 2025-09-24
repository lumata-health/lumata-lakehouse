"""
sf_user Pipeline Metrics Publisher Lambda Function

Publishes custom CloudWatch metrics for pipeline execution monitoring.
Processes execution results from Step Functions and publishes detailed metrics.
"""

import json
import boto3
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
cloudwatch = boto3.client('cloudwatch')

# Configuration
METRICS_NAMESPACE = 'SfUserPipeline'
DEFAULT_ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for publishing pipeline metrics.
    
    Args:
        event: Event data containing pipeline execution results
        context: Lambda context object
        
    Returns:
        Dict containing execution results and metrics published
    """
    try:
        logger.info(f"Processing metrics publishing request: {json.dumps(event, default=str)}")
        
        # Extract execution details
        execution_id = event.get('execution_id', 'unknown')
        environment = event.get('environment', DEFAULT_ENVIRONMENT)
        start_time = event.get('start_time')
        
        # Calculate execution duration
        execution_duration = calculate_execution_duration(start_time)
        
        # Prepare metrics to publish
        metrics_data = []
        
        # Add execution duration metric
        if execution_duration is not None:
            metrics_data.append({
                'MetricName': 'ExecutionDuration',
                'Value': execution_duration,
                'Unit': 'Seconds',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': environment},
                    {'Name': 'ExecutionId', 'Value': execution_id}
                ]
            })
        
        # Process Glue job metrics
        glue_metrics = process_glue_job_metrics(event.get('glue_job_result', {}), environment)
        metrics_data.extend(glue_metrics)
        
        # Process dbt run metrics
        dbt_run_metrics = process_dbt_run_metrics(event.get('dbt_run_result', {}), environment)
        metrics_data.extend(dbt_run_metrics)
        
        # Process dbt test metrics
        dbt_test_metrics = process_dbt_test_metrics(event.get('dbt_test_result', {}), environment)
        metrics_data.extend(dbt_test_metrics)
        
        # Process SCD validation metrics
        scd_metrics = process_scd_validation_metrics(event.get('scd_validation_result', {}), environment)
        metrics_data.extend(scd_metrics)
        
        # Publish metrics in batches (CloudWatch limit is 20 metrics per call)
        metrics_published = publish_metrics_batch(metrics_data)
        
        # Log success
        logger.info(f"Successfully published {metrics_published} metrics for execution {execution_id}")
        
        return {
            'statusCode': 200,
            'execution_id': execution_id,
            'metrics_published': metrics_published,
            'execution_duration_minutes': execution_duration / 60 if execution_duration else None,
            'environment': environment
        }
        
    except Exception as e:
        logger.error(f"Error publishing metrics: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'error': str(e),
            'execution_id': event.get('execution_id', 'unknown')
        }

def calculate_execution_duration(start_time: str) -> float:
    """Calculate execution duration in seconds."""
    if not start_time:
        return None
        
    try:
        start_dt = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
        end_dt = datetime.now(timezone.utc)
        duration = (end_dt - start_dt).total_seconds()
        return duration
    except Exception as e:
        logger.warning(f"Could not calculate execution duration: {e}")
        return None

def process_glue_job_metrics(glue_result: Dict[str, Any], environment: str) -> List[Dict[str, Any]]:
    """Process Glue job execution results and create metrics."""
    metrics = []
    
    if not glue_result:
        return metrics
    
    try:
        # Extract Glue job metrics from arguments or job run details
        job_run_id = glue_result.get('JobRunId', 'unknown')
        job_run_state = glue_result.get('JobRunState', 'UNKNOWN')
        
        # Records processed metric (from job arguments if available)
        arguments = glue_result.get('Arguments', {})
        records_processed = arguments.get('--records-processed')
        if records_processed:
            metrics.append({
                'MetricName': 'RecordsProcessed',
                'Value': float(records_processed),
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': environment},
                    {'Name': 'JobType', 'Value': 'Ingestion'},
                    {'Name': 'JobRunId', 'Value': job_run_id}
                ]
            })
        
        # Job success/failure metric
        job_success = 1 if job_run_state == 'SUCCEEDED' else 0
        metrics.append({
            'MetricName': 'JobSuccess',
            'Value': job_success,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment},
                {'Name': 'JobType', 'Value': 'Ingestion'},
                {'Name': 'JobRunId', 'Value': job_run_id}
            ]
        })
        
        # Execution time metric (if available)
        execution_time = glue_result.get('ExecutionTime')
        if execution_time:
            metrics.append({
                'MetricName': 'GlueJobDuration',
                'Value': float(execution_time),
                'Unit': 'Seconds',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': environment},
                    {'Name': 'JobRunId', 'Value': job_run_id}
                ]
            })
            
    except Exception as e:
        logger.warning(f"Error processing Glue job metrics: {e}")
    
    return metrics

def process_dbt_run_metrics(dbt_result: Dict[str, Any], environment: str) -> List[Dict[str, Any]]:
    """Process dbt run results and create metrics."""
    metrics = []
    
    if not dbt_result or 'Payload' not in dbt_result:
        return metrics
    
    try:
        payload = dbt_result['Payload']
        
        # Models run successfully
        models_run = payload.get('models_run', 0)
        metrics.append({
            'MetricName': 'DbtModelsRun',
            'Value': float(models_run),
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment},
                {'Name': 'JobType', 'Value': 'Transformation'}
            ]
        })
        
        # Models failed
        models_failed = payload.get('models_failed', 0)
        metrics.append({
            'MetricName': 'DbtModelsFailed',
            'Value': float(models_failed),
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment},
                {'Name': 'JobType', 'Value': 'Transformation'}
            ]
        })
        
        # dbt run duration
        run_duration = payload.get('run_duration_seconds')
        if run_duration:
            metrics.append({
                'MetricName': 'DbtRunDuration',
                'Value': float(run_duration),
                'Unit': 'Seconds',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': environment}
                ]
            })
            
    except Exception as e:
        logger.warning(f"Error processing dbt run metrics: {e}")
    
    return metrics

def process_dbt_test_metrics(dbt_test_result: Dict[str, Any], environment: str) -> List[Dict[str, Any]]:
    """Process dbt test results and create metrics."""
    metrics = []
    
    if not dbt_test_result or 'Payload' not in dbt_test_result:
        return metrics
    
    try:
        payload = dbt_test_result['Payload']
        
        # Tests passed
        tests_passed = payload.get('tests_passed', 0)
        metrics.append({
            'MetricName': 'DbtTestsPassed',
            'Value': float(tests_passed),
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment},
                {'Name': 'TestType', 'Value': 'DataQuality'}
            ]
        })
        
        # Tests failed
        tests_failed = payload.get('tests_failed', 0)
        metrics.append({
            'MetricName': 'DbtTestsFailed',
            'Value': float(tests_failed),
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment},
                {'Name': 'TestType', 'Value': 'DataQuality'}
            ]
        })
        
        # Data quality score (percentage of tests passed)
        total_tests = tests_passed + tests_failed
        if total_tests > 0:
            quality_score = (tests_passed / total_tests) * 100
            metrics.append({
                'MetricName': 'DataQualityScore',
                'Value': quality_score,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': environment}
                ]
            })
            
    except Exception as e:
        logger.warning(f"Error processing dbt test metrics: {e}")
    
    return metrics

def process_scd_validation_metrics(scd_result: Dict[str, Any], environment: str) -> List[Dict[str, Any]]:
    """Process SCD validation results and create metrics."""
    metrics = []
    
    if not scd_result or 'Payload' not in scd_result:
        return metrics
    
    try:
        payload = scd_result['Payload']
        
        # SCD records created
        scd_records_created = payload.get('scd_records_created', 0)
        metrics.append({
            'MetricName': 'RecordsCreated',
            'Value': float(scd_records_created),
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment},
                {'Name': 'JobType', 'Value': 'SCD'}
            ]
        })
        
        # SCD records updated
        scd_records_updated = payload.get('scd_records_updated', 0)
        metrics.append({
            'MetricName': 'RecordsUpdated',
            'Value': float(scd_records_updated),
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment},
                {'Name': 'JobType', 'Value': 'SCD'}
            ]
        })
        
        # SCD records deleted
        scd_records_deleted = payload.get('scd_records_deleted', 0)
        metrics.append({
            'MetricName': 'RecordsDeleted',
            'Value': float(scd_records_deleted),
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment},
                {'Name': 'JobType', 'Value': 'SCD'}
            ]
        })
        
        # SCD integrity score
        integrity_score = payload.get('integrity_score', 100)
        metrics.append({
            'MetricName': 'SCDIntegrityScore',
            'Value': float(integrity_score),
            'Unit': 'Percent',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment}
            ]
        })
        
        # SCD validation errors
        validation_errors = payload.get('validation_errors', 0)
        metrics.append({
            'MetricName': 'SCDValidationErrors',
            'Value': float(validation_errors),
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'Environment', 'Value': environment}
            ]
        })
        
    except Exception as e:
        logger.warning(f"Error processing SCD validation metrics: {e}")
    
    return metrics

def publish_metrics_batch(metrics_data: List[Dict[str, Any]]) -> int:
    """Publish metrics to CloudWatch in batches."""
    if not metrics_data:
        return 0
    
    total_published = 0
    batch_size = 20  # CloudWatch limit
    
    for i in range(0, len(metrics_data), batch_size):
        batch = metrics_data[i:i + batch_size]
        
        try:
            # Add timestamp to all metrics
            for metric in batch:
                metric['Timestamp'] = datetime.now(timezone.utc)
            
            # Publish batch
            response = cloudwatch.put_metric_data(
                Namespace=METRICS_NAMESPACE,
                MetricData=batch
            )
            
            total_published += len(batch)
            logger.info(f"Published batch of {len(batch)} metrics")
            
        except Exception as e:
            logger.error(f"Error publishing metrics batch: {e}")
            # Continue with next batch
    
    return total_published
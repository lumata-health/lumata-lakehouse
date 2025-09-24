"""
sf_user Pipeline Error Handler Lambda Function

Handles pipeline errors, publishes error metrics, and sends detailed alerts.
Processes different types of pipeline failures and provides actionable error information.
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
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

# Configuration
METRICS_NAMESPACE = 'SfUserPipeline'
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
DEFAULT_ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing pipeline errors.
    
    Args:
        event: Event data containing error details
        context: Lambda context object
        
    Returns:
        Dict containing error handling results
    """
    try:
        logger.info(f"Processing error handling request: {json.dumps(event, default=str)}")
        
        # Extract error details
        error_type = event.get('error_type', 'unknown_error')
        execution_id = event.get('execution_id', 'unknown')
        environment = event.get('environment', DEFAULT_ENVIRONMENT)
        
        # Process error based on type
        error_handler = get_error_handler(error_type)
        error_details = error_handler(event, environment)
        
        # Publish error metrics
        metrics_published = publish_error_metrics(error_type, environment, execution_id, error_details)
        
        # Send alert notification
        alert_sent = send_error_alert(error_type, environment, execution_id, error_details)
        
        # Log error handling completion
        logger.info(f"Error handling completed for {error_type} in execution {execution_id}")
        
        return {
            'statusCode': 200,
            'error_type': error_type,
            'execution_id': execution_id,
            'environment': environment,
            'error_details': error_details,
            'metrics_published': metrics_published,
            'alert_sent': alert_sent,
            'handled_at': datetime.now(timezone.utc).isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error in error handler: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'error': str(e),
            'execution_id': event.get('execution_id', 'unknown')
        }

def get_error_handler(error_type: str):
    """Get the appropriate error handler function based on error type."""
    handlers = {
        'glue_job_failure': handle_glue_job_failure,
        'validation_failure': handle_validation_failure,
        'data_quality_failure': handle_data_quality_failure,
        'dbt_run_failure': handle_dbt_run_failure,
        'dbt_test_failure': handle_dbt_test_failure,
        'scd_validation_failure': handle_scd_validation_failure
    }
    
    return handlers.get(error_type, handle_unknown_error)

def handle_glue_job_failure(event: Dict[str, Any], environment: str) -> Dict[str, Any]:
    """Handle Glue job execution failures."""
    error_details = event.get('error_details', {})
    
    # Extract Glue-specific error information
    error_info = {
        'error_category': 'glue_job_failure',
        'severity': 'HIGH',
        'cause': error_details.get('Cause', 'Unknown Glue job failure'),
        'error_message': error_details.get('Error', 'Glue job execution failed'),
        'recommended_actions': [
            'Check Glue job logs in CloudWatch',
            'Verify Salesforce API connectivity and credentials',
            'Check S3 bucket permissions and Iceberg table configuration',
            'Review Glue job script for syntax errors',
            'Verify AWS Secrets Manager access for Salesforce credentials'
        ],
        'investigation_steps': [
            'Review /aws/glue/jobs/sf-user-ingestion-job log group',
            'Check Salesforce API rate limits and quotas',
            'Verify S3 bucket access and Iceberg table schema',
            'Test Salesforce connection manually'
        ]
    }
    
    return error_info

def handle_validation_failure(event: Dict[str, Any], environment: str) -> Dict[str, Any]:
    """Handle data validation failures."""
    error_details = event.get('error_details', {})
    
    error_info = {
        'error_category': 'validation_failure',
        'severity': 'MEDIUM',
        'cause': error_details.get('Cause', 'Data validation failed'),
        'error_message': error_details.get('Error', 'Pipeline validation step failed'),
        'recommended_actions': [
            'Check validation Lambda function logs',
            'Review data quality validation rules',
            'Verify Iceberg table data integrity',
            'Check for schema changes in source data'
        ],
        'investigation_steps': [
            'Review /aws/lambda/sf-user-pipeline-validator logs',
            'Query raw Iceberg tables for data anomalies',
            'Check Salesforce schema changes',
            'Validate data volume and distribution'
        ]
    }
    
    return error_info

def handle_data_quality_failure(event: Dict[str, Any], environment: str) -> Dict[str, Any]:
    """Handle data quality validation failures."""
    validation_result = event.get('validation_result', {})
    payload = validation_result.get('Payload', {}) if validation_result else {}
    
    error_info = {
        'error_category': 'data_quality_failure',
        'severity': 'HIGH',
        'cause': 'Data quality validation failed - data does not meet quality thresholds',
        'error_message': f"Data quality score: {payload.get('data_quality_score', 'unknown')}%",
        'failed_validations': payload.get('failed_validations', []),
        'data_quality_score': payload.get('data_quality_score'),
        'recommended_actions': [
            'Review failed data quality validations',
            'Check for data corruption in source system',
            'Verify field mappings and transformations',
            'Review data quality thresholds and rules'
        ],
        'investigation_steps': [
            'Query raw sf_user data for anomalies',
            'Check Salesforce data quality at source',
            'Review dbt test results and failures',
            'Analyze data distribution and patterns'
        ]
    }
    
    return error_info

def handle_dbt_run_failure(event: Dict[str, Any], environment: str) -> Dict[str, Any]:
    """Handle dbt run failures."""
    error_details = event.get('error_details', {})
    
    error_info = {
        'error_category': 'dbt_run_failure',
        'severity': 'HIGH',
        'cause': error_details.get('Cause', 'dbt model execution failed'),
        'error_message': error_details.get('Error', 'dbt run command failed'),
        'recommended_actions': [
            'Check dbt runner Lambda function logs',
            'Review dbt model SQL for syntax errors',
            'Verify Athena/Glue Catalog connectivity',
            'Check Iceberg table permissions and configuration'
        ],
        'investigation_steps': [
            'Review /aws/lambda/sf-user-dbt-runner logs',
            'Test dbt models individually',
            'Check Athena query history for errors',
            'Verify dbt profiles and connection settings'
        ]
    }
    
    return error_info

def handle_dbt_test_failure(event: Dict[str, Any], environment: str) -> Dict[str, Any]:
    """Handle dbt test failures."""
    error_details = event.get('error_details', {})
    
    error_info = {
        'error_category': 'dbt_test_failure',
        'severity': 'MEDIUM',
        'cause': error_details.get('Cause', 'dbt tests failed'),
        'error_message': error_details.get('Error', 'dbt test command failed'),
        'recommended_actions': [
            'Review failed dbt test results',
            'Check data quality in transformed tables',
            'Verify SCD Type 2 logic correctness',
            'Review test thresholds and expectations'
        ],
        'investigation_steps': [
            'Run dbt tests individually to identify failures',
            'Query dim_sf_user_scd table for data issues',
            'Check SCD integrity and currency flags',
            'Review test definitions and logic'
        ]
    }
    
    return error_info

def handle_scd_validation_failure(event: Dict[str, Any], environment: str) -> Dict[str, Any]:
    """Handle SCD validation failures."""
    error_details = event.get('error_details', {})
    
    error_info = {
        'error_category': 'scd_validation_failure',
        'severity': 'HIGH',
        'cause': error_details.get('Cause', 'SCD Type 2 validation failed'),
        'error_message': error_details.get('Error', 'SCD integrity validation failed'),
        'recommended_actions': [
            'Check SCD Type 2 logic in dbt models',
            'Verify historical tracking for Division and Audit_Phase__c',
            'Review SCD integrity test results',
            'Check for duplicate or missing SCD records'
        ],
        'investigation_steps': [
            'Query dim_sf_user_scd for SCD integrity issues',
            'Check is_current flag management',
            'Verify SCD record versioning and dating',
            'Review SCD macro logic and implementation'
        ]
    }
    
    return error_info

def handle_unknown_error(event: Dict[str, Any], environment: str) -> Dict[str, Any]:
    """Handle unknown or unclassified errors."""
    error_details = event.get('error_details', {})
    
    error_info = {
        'error_category': 'unknown_error',
        'severity': 'MEDIUM',
        'cause': 'Unknown or unclassified pipeline error',
        'error_message': str(error_details),
        'recommended_actions': [
            'Review Step Functions execution logs',
            'Check all Lambda function logs',
            'Verify pipeline configuration and permissions',
            'Contact support team for assistance'
        ],
        'investigation_steps': [
            'Review Step Functions execution history',
            'Check CloudWatch logs for all pipeline components',
            'Verify AWS service status and quotas',
            'Review recent pipeline or infrastructure changes'
        ]
    }
    
    return error_info

def publish_error_metrics(error_type: str, environment: str, execution_id: str, error_details: Dict[str, Any]) -> int:
    """Publish error metrics to CloudWatch."""
    try:
        metrics_data = [
            {
                'MetricName': 'PipelineErrors',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': environment},
                    {'Name': 'ErrorType', 'Value': error_type},
                    {'Name': 'Severity', 'Value': error_details.get('severity', 'UNKNOWN')}
                ],
                'Timestamp': datetime.now(timezone.utc)
            }
        ]
        
        # Publish metrics
        cloudwatch.put_metric_data(
            Namespace=METRICS_NAMESPACE,
            MetricData=metrics_data
        )
        
        logger.info(f"Published error metrics for {error_type}")
        return len(metrics_data)
        
    except Exception as e:
        logger.error(f"Error publishing error metrics: {e}")
        return 0

def send_error_alert(error_type: str, environment: str, execution_id: str, error_details: Dict[str, Any]) -> bool:
    """Send error alert via SNS."""
    if not SNS_TOPIC_ARN:
        logger.warning("SNS_TOPIC_ARN not configured - skipping alert")
        return False
    
    try:
        # Prepare alert message
        alert_subject = f"sf_user Pipeline Error - {error_type.replace('_', ' ').title()} ({environment.upper()})"
        
        alert_message = f"""
sf_user Pipeline Error Alert

Environment: {environment.upper()}
Execution ID: {execution_id}
Error Type: {error_type}
Severity: {error_details.get('severity', 'UNKNOWN')}
Timestamp: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}

Error Details:
- Cause: {error_details.get('cause', 'Unknown')}
- Message: {error_details.get('error_message', 'No message available')}

Recommended Actions:
"""
        
        # Add recommended actions
        for action in error_details.get('recommended_actions', []):
            alert_message += f"• {action}\n"
        
        alert_message += "\nInvestigation Steps:\n"
        
        # Add investigation steps
        for step in error_details.get('investigation_steps', []):
            alert_message += f"• {step}\n"
        
        # Add additional context for specific error types
        if error_type == 'data_quality_failure':
            alert_message += f"\nData Quality Score: {error_details.get('data_quality_score', 'Unknown')}%\n"
            failed_validations = error_details.get('failed_validations', [])
            if failed_validations:
                alert_message += "Failed Validations:\n"
                for validation in failed_validations:
                    alert_message += f"• {validation}\n"
        
        alert_message += f"\nDashboard: https://console.aws.amazon.com/cloudwatch/home#dashboards:name=sf-user-pipeline-{environment}"
        
        # Send SNS notification
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=alert_subject,
            Message=alert_message
        )
        
        logger.info(f"Sent error alert for {error_type} - MessageId: {response.get('MessageId')}")
        return True
        
    except Exception as e:
        logger.error(f"Error sending alert: {e}")
        return False
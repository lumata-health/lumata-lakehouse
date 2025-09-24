# sf_user Pipeline Monitoring and Alerting

This directory contains the monitoring and alerting infrastructure for the sf_user pipeline, providing comprehensive observability, error handling, and performance tracking.

## Overview

The monitoring system provides:
- **Real-time pipeline monitoring** via CloudWatch dashboards
- **Automated error handling** with detailed diagnostics
- **Custom metrics publishing** for pipeline performance
- **Multi-level alerting** for different failure scenarios
- **Data quality validation** and SCD integrity checks

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Step Functions  │───▶│ Lambda Functions│───▶│   CloudWatch    │
│   (Pipeline)    │    │  (Monitoring)   │    │   (Metrics)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Error Handling  │    │ Data Validation │    │ SNS Alerting    │
│   (Automated)   │    │  (Quality/SCD)  │    │ (Notifications) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Components

### 1. CloudWatch Monitoring (`cloudwatch-monitoring.yml`)

**Purpose**: Comprehensive monitoring infrastructure with dashboards, alarms, and log groups.

**Key Features**:
- Custom CloudWatch dashboard for pipeline visualization
- Multi-level alarm system (individual + composite alarms)
- Log group management with retention policies
- Automated SNS alerting integration

**Metrics Tracked**:
- Step Functions execution success/failure rates
- Pipeline execution duration and performance
- Glue job task completion and failure metrics
- Data processing volumes and quality scores
- SCD integrity and historical tracking metrics
- Lambda function error rates and duration

### 2. Lambda Functions

#### Metrics Publisher (`metrics-publisher.py`)

**Purpose**: Publishes detailed custom metrics to CloudWatch for pipeline monitoring.

**Key Capabilities**:
- Processes Step Functions execution results
- Extracts and publishes Glue job metrics (records processed, duration)
- Tracks dbt run and test statistics
- Calculates data quality and SCD integrity scores
- Publishes metrics in batches for efficiency

**Metrics Published**:
```python
# Execution metrics
ExecutionDuration (Seconds)
RecordsProcessed (Count)
JobSuccess (Count)

# dbt metrics  
DbtModelsRun (Count)
DbtModelsFailed (Count)
DbtTestsPassed (Count)
DbtTestsFailed (Count)

# Data quality metrics
DataQualityScore (Percent)
SCDIntegrityScore (Percent)

# SCD processing metrics
RecordsCreated (Count)
RecordsUpdated (Count)
RecordsDeleted (Count)
```

#### Error Handler (`error-handler.py`)

**Purpose**: Intelligent error handling with detailed diagnostics and actionable recommendations.

**Error Types Handled**:
- `glue_job_failure`: Glue job execution failures
- `validation_failure`: Data validation failures  
- `data_quality_failure`: Data quality threshold breaches
- `dbt_run_failure`: dbt model execution failures
- `dbt_test_failure`: dbt test failures
- `scd_validation_failure`: SCD integrity issues

**Error Response Features**:
- Categorized error severity (HIGH/MEDIUM/LOW)
- Detailed root cause analysis
- Actionable recommended actions
- Step-by-step investigation guides
- Automated SNS alert generation

#### Pipeline Validator (`pipeline-validator.py`)

**Purpose**: Comprehensive validation of pipeline execution results and data integrity.

**Validation Types**:

1. **Glue Job Results Validation**:
   - Job execution status verification
   - Minimum record count validation
   - Data freshness checks (within 6 hours)
   - Required field presence validation

2. **SCD Integrity Validation**:
   - Current record uniqueness (one current record per user)
   - Historical integrity (no gaps or overlaps)
   - SCD flag management (is_current, is_deleted)
   - Change tracking accuracy for Division and Audit_Phase__c

**Validation Queries**:
```sql
-- Data freshness validation
SELECT MAX(_extracted_at) as latest_extraction,
       COUNT(*) as total_records
FROM salesforce_raw.sf_user
WHERE _extracted_at >= current_timestamp - interval '1' day

-- SCD current uniqueness validation  
SELECT user_id, COUNT(*) as current_record_count
FROM salesforce_curated.dim_sf_user_scd
WHERE is_current = true AND is_deleted = false
GROUP BY user_id
HAVING COUNT(*) > 1
```

### 3. CloudWatch Alarms

**Individual Alarms**:
- `StepFunctionsFailureAlarm`: Pipeline execution failures
- `StepFunctionsDurationAlarm`: Execution time exceeds 1 hour
- `GlueJobFailureAlarm`: Glue job task failures
- `DataQualityAlarm`: Data quality score below 95%
- `SCDIntegrityAlarm`: SCD integrity score below 98%
- `RecordVolumeAnomalyAlarm`: Record volume below 100 records
- `DbtRunnerErrorAlarm`: dbt runner Lambda errors
- `ValidatorErrorAlarm`: Pipeline validator Lambda errors

**Composite Alarm**:
- `PipelineHealthCompositeAlarm`: Overall pipeline health status

### 4. CloudWatch Dashboard

**Dashboard Widgets**:
1. **Step Functions Executions**: Success/failure/started counts
2. **Pipeline Execution Duration**: Average execution time trends
3. **Glue Job Task Metrics**: Completed vs failed tasks
4. **sf_user Data Processing Metrics**: Records processed/created/updated/deleted
5. **Data Quality Metrics**: Quality and integrity scores
6. **Recent Pipeline Errors**: Log-based error tracking

## Deployment

### Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Step Functions state machine deployed** (from orchestration)
3. **SNS topic created** for alerts
4. **IAM roles configured** for Lambda functions

### Deployment Steps

1. **Deploy monitoring infrastructure**:
   ```powershell
   .\deploy-monitoring.ps1 -AccountId 123456789012 -StateMachineArn "arn:aws:states:..." -SNSTopicArn "arn:aws:sns:..."
   ```

2. **Configure email alerts** (optional):
   ```powershell
   .\deploy-monitoring.ps1 -Environment prod -AccountId 123456789012 -StateMachineArn "arn:aws:states:..." -SNSTopicArn "arn:aws:sns:..." -AlertEmail "admin@company.com"
   ```

### Deployment Process

The deployment script performs the following steps:

1. **Package Lambda functions** into ZIP files
2. **Upload packages to S3** for Lambda deployment
3. **Deploy/update Lambda functions** with appropriate configurations
4. **Deploy CloudFormation stack** with monitoring infrastructure
5. **Configure CloudWatch alarms** and dashboard
6. **Set up SNS subscriptions** (if email provided)

## Configuration

### Environment Variables

**Metrics Publisher Lambda**:
```bash
ENVIRONMENT=dev|staging|prod
```

**Error Handler Lambda**:
```bash
ENVIRONMENT=dev|staging|prod
SNS_TOPIC_ARN=arn:aws:sns:region:account:topic-name
```

**Pipeline Validator Lambda**:
```bash
ENVIRONMENT=dev|staging|prod
ATHENA_DATABASE=salesforce_curated
ATHENA_WORKGROUP=primary
S3_RESULTS_BUCKET=bucket-name
```

### Alarm Thresholds

**Configurable Thresholds** (in CloudFormation template):
- Pipeline execution timeout: 1 hour (3,600,000 ms)
- Data quality threshold: 95%
- SCD integrity threshold: 98%
- Minimum record count: 100 records
- Data freshness window: 6 hours

### Custom Metrics Namespace

All custom metrics are published under the `SfUserPipeline` namespace with dimensions:
- `Environment`: dev/staging/prod
- `JobType`: Ingestion/Transformation/SCD
- `ErrorType`: Specific error categories
- `Severity`: HIGH/MEDIUM/LOW

## Monitoring Workflows

### 1. Normal Pipeline Execution

```
Pipeline Start → Glue Job → Validation → dbt Run → dbt Test → SCD Validation → Metrics Publishing → Success
     ↓              ↓           ↓          ↓         ↓           ↓               ↓
CloudWatch     CloudWatch  CloudWatch CloudWatch CloudWatch CloudWatch   CloudWatch
 Metrics        Metrics     Metrics    Metrics    Metrics    Metrics      Dashboard
```

### 2. Error Handling Workflow

```
Pipeline Error → Error Handler Lambda → Error Categorization → SNS Alert → Investigation Guide
     ↓                    ↓                    ↓                ↓              ↓
Error Metrics      Error Analysis      Recommended Actions   Email/Slack   Troubleshooting
```

### 3. Data Quality Monitoring

```
Data Ingestion → Quality Validation → Score Calculation → Threshold Check → Alert (if needed)
     ↓                 ↓                    ↓                ↓                ↓
Raw Data         Field Validation    Quality Metrics   Alarm Trigger    SNS Notification
```

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**:
   - Check function memory allocation (512MB for validator)
   - Review Athena query complexity and optimization
   - Verify network connectivity to AWS services

2. **Athena Query Failures**:
   - Verify database and table permissions
   - Check S3 results bucket access
   - Validate query syntax and table schemas

3. **Missing Metrics**:
   - Check Lambda function execution logs
   - Verify CloudWatch permissions
   - Review metric publishing batch sizes

4. **False Positive Alarms**:
   - Adjust alarm thresholds based on historical data
   - Review evaluation periods and statistics
   - Consider seasonal or business-driven variations

### Log Locations

**CloudWatch Log Groups**:
- `/aws/stepfunctions/sf-user-pipeline-{environment}`
- `/aws/lambda/sf-user-metrics-publisher-{environment}`
- `/aws/lambda/sf-user-error-handler-{environment}`
- `/aws/lambda/sf-user-pipeline-validator-{environment}`
- `/aws/glue/jobs/sf-user-ingestion-job`

### Debugging Steps

1. **Check Step Functions execution history**
2. **Review Lambda function logs** for specific errors
3. **Query Athena directly** to validate data availability
4. **Test Lambda functions** with sample events
5. **Verify IAM permissions** for all services

## Performance Optimization

### Metrics Publishing Optimization

- **Batch metrics publishing** (20 metrics per CloudWatch API call)
- **Asynchronous processing** for non-critical metrics
- **Efficient data extraction** from execution results

### Validation Query Optimization

- **Partition pruning** using date filters
- **Limit result sets** for large tables
- **Index utilization** on frequently queried columns
- **Query result caching** for repeated validations

### Cost Optimization

- **Log retention policies** (30 days default)
- **Metric retention** aligned with business needs
- **Lambda memory sizing** based on actual usage
- **Athena query optimization** to reduce data scanned

## Security Considerations

### IAM Permissions

**Lambda Execution Role** requires:
- CloudWatch metrics publishing
- Athena query execution
- S3 results bucket access
- SNS publishing (for error handler)

### Data Access

- **Least privilege access** to Iceberg tables
- **Encrypted data transmission** for all AWS service calls
- **Secure credential management** via IAM roles
- **Audit logging** via CloudTrail

## Maintenance

### Regular Tasks

1. **Review alarm thresholds** monthly based on pipeline performance
2. **Update Lambda function dependencies** for security patches
3. **Analyze dashboard usage** and optimize widgets
4. **Clean up old Athena query results** in S3
5. **Review and update error handling logic** based on new failure patterns

### Monitoring Health Checks

1. **Test Lambda functions** with sample events monthly
2. **Verify Athena connectivity** and query performance
3. **Check SNS topic subscriptions** and delivery
4. **Review CloudWatch alarm history** for false positives
5. **Validate dashboard accuracy** against actual pipeline metrics

This monitoring system provides comprehensive observability for the sf_user pipeline, enabling proactive issue detection, automated error handling, and detailed performance tracking.
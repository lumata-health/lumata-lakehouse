# Design Document

## Overview

This design document outlines the technical architecture for a focused Salesforce sf_user data pipeline using AWS Glue jobs for ingestion and dbt Core for transformations. The architecture implements a streamlined AWS-native solution: **AWS Glue → Salesforce API → Iceberg Tables → dbt Core → Iceberg Marts → Athena**.

The design prioritizes AWS-native integration, scalability, and maintainability while providing SCD Type 2 implementation specifically for sf_user data, tracking historical changes in Division and Audit_Phase__c fields.

## Architecture

### High-Level Architecture Diagram

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Salesforce    │    │   AWS Glue      │    │  Iceberg Tables │
│   (sf_user)     │───▶│   Job           │───▶│   (Raw Layer)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ AWS Secrets     │    │   S3 Bucket     │    │  AWS Glue       │
│ Manager         │    │   (Iceberg)     │    │  Catalog        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Amazon Athena   │◀───│  Iceberg Tables │◀───│   dbt Core      │
│   (Analytics)   │    │ (SCD Layer)     │    │ (Transformations)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        ▲
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CloudWatch    │◀───│ Step Functions  │───▶│   EventBridge   │
│   (Monitoring)  │    │ (Orchestration) │    │   (Scheduling)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Component Architecture

#### 1. Data Ingestion Layer
- **AWS Glue Job**: Python-based ETL job that handles Salesforce sf_user data extraction and loading
- **Salesforce API**: REST/Bulk API for sf_user data retrieval using simple-salesforce library
- **AWS Secrets Manager**: Existing Salesforce credentials for authentication
- **Data Loading Strategy**: Incremental loading with Iceberg merge strategy for optimal performance

#### 2. Storage Layer
- **Apache Iceberg Tables**: ACID-compliant table format for both raw and curated sf_user data
- **Amazon S3**: Underlying storage at `s3://lumata-salesforce-lakehouse-iceberg-dev/iceberg/salesforce_raw/`
- **AWS Glue Catalog**: Metadata management for Iceberg tables (queryable via Athena)

#### 3. Transformation Layer
- **dbt Core**: SQL-based transformations for sf_user processing
- **SCD Type 2 Models**: Historical tracking of Division and Audit_Phase__c changes
- **Incremental Models**: Efficient processing of sf_user updates

#### 4. Orchestration Layer
- **AWS Step Functions**: Coordination of Glue job ingestion and dbt transformations
- **Amazon EventBridge**: Automated pipeline scheduling (every 6 hours)
- **Event Triggers**: Change-based processing initiation

#### 5. Monitoring Layer
- **CloudWatch Logs**: Comprehensive pipeline execution logs
- **CloudWatch Metrics**: Performance and data quality monitoring
- **SNS Alerting**: Failure and anomaly notifications

## Components and Interfaces

### AWS Glue Ingestion Job

**Purpose**: Extract sf_user data from Salesforce and write to raw Iceberg tables in S3

**Key Features**:
- Python-based ETL job using PySpark and simple-salesforce
- Incremental extraction based on LastModifiedDate
- Native Iceberg support with Glue 4.0
- Built-in error handling and retry logic
- Integration with AWS Secrets Manager for credentials

**Glue Job Configuration**:
```python
# Glue Job Parameters
{
    "Name": "sf-user-ingestion-job",
    "Role": "arn:aws:iam::ACCOUNT:role/GlueServiceRole",
    "Command": {
        "Name": "glueetl",
        "ScriptLocation": "s3://lumata-salesforce-lakehouse-config-dev/glue_scripts/sf_user_ingestion.py",
        "PythonVersion": "3"
    },
    "DefaultArguments": {
        "--job-language": "python",
        "--enable-glue-datacatalog": "",
        "--enable-continuous-cloudwatch-log": "true",
        "--enable-spark-ui": "true",
        "--spark-event-logs-path": "s3://lumata-salesforce-lakehouse-config-dev/spark-logs/",
        "--additional-python-modules": "simple-salesforce==1.12.4,pyarrow==10.0.1",
        "--conf": "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=s3://lumata-salesforce-lakehouse-iceberg-dev/iceberg/ --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
    },
    "GlueVersion": "4.0",
    "MaxRetries": 2,
    "Timeout": 2880,  # 48 hours
    "MaxCapacity": 10
}
```

**Glue Job Script Structure**:
```python
# sf_user_ingestion.py
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from simple_salesforce import Salesforce
import boto3
import json
from datetime import datetime, timedelta
import logging

class SalesforceIcebergIngestion:
    def __init__(self, glue_context, spark_context):
        self.glue_context = glue_context
        self.spark = glue_context.spark_session
        self.sc = spark_context
        self.secrets_client = boto3.client('secretsmanager', region_name='us-east-1')
        
    def get_salesforce_credentials(self, secret_name: str) -> dict:
        """Retrieve Salesforce credentials from AWS Secrets Manager"""
        response = self.secrets_client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    
    def connect_to_salesforce(self, credentials: dict) -> Salesforce:
        """Establish connection to Salesforce"""
        return Salesforce(
            username=credentials['username'],
            password=credentials['password'],
            security_token=credentials['security_token'],
            domain=credentials.get('domain', 'login')
        )
    
    def get_last_run_timestamp(self) -> datetime:
        """Get last successful run timestamp for incremental loading"""
        # Implementation to read from Glue job bookmark or S3 metadata
        pass
    
    def extract_sf_user_incremental(self, sf_connection: Salesforce, since_date: datetime) -> list:
        """Extract sf_user data incrementally based on LastModifiedDate"""
        soql_query = f"""
        SELECT Id, Name, Division, Audit_Phase__c, LastModifiedDate, 
               IsActive, IsDeleted, CreatedDate
        FROM User 
        WHERE LastModifiedDate > {since_date.isoformat()}
        ORDER BY LastModifiedDate
        """
        
        result = sf_connection.query_all(soql_query)
        return result['records']
    
    def write_to_iceberg(self, data: list, table_name: str):
        """Write data to Iceberg table using merge strategy"""
        if not data:
            logging.info("No data to write")
            return
            
        # Convert to Spark DataFrame
        df = self.spark.createDataFrame(data)
        
        # Add extraction metadata
        df = df.withColumn("_extracted_at", current_timestamp()) \
               .withColumn("_extraction_run_id", lit(self.job_run_id))
        
        # Write to Iceberg table with merge strategy
        df.writeTo(f"glue_catalog.salesforce_raw.{table_name}") \
          .using("iceberg") \
          .option("write-audit-publish", "true") \
          .option("check-nullability", "false") \
          .option("merge-schema", "true") \
          .createOrReplace()
    
    def run_ingestion(self):
        """Main ingestion process"""
        try:
            # Get credentials
            credentials = self.get_salesforce_credentials("salesforce/production/credentials")
            
            # Connect to Salesforce
            sf = self.connect_to_salesforce(credentials)
            
            # Get last run timestamp
            last_run = self.get_last_run_timestamp()
            
            # Extract data
            sf_user_data = self.extract_sf_user_incremental(sf, last_run)
            
            # Write to Iceberg
            self.write_to_iceberg(sf_user_data, "sf_user")
            
            logging.info(f"Successfully processed {len(sf_user_data)} sf_user records")
            
        except Exception as e:
            logging.error(f"Ingestion failed: {str(e)}")
            raise

# Glue job entry point
args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Run ingestion
ingestion = SalesforceIcebergIngestion(glueContext, sc)
ingestion.run_ingestion()

job.commit()
```

### dbt Core Transformation Engine

**Purpose**: Transform raw sf_user Iceberg data into SCD Type 2 analytics-ready tables

**Key Features**:
- SQL-only transformations for sf_user data
- SCD Type 2 implementation for Division and Audit_Phase__c tracking
- Built-in data quality testing
- Automatic documentation generation

**Project Structure**:
```
sf_user_pipeline/
├── dbt_project.yml
├── profiles.yml
├── models/
│   ├── staging/
│   │   ├── _sources.yml
│   │   └── stg_sf_user.sql
│   ├── intermediate/
│   │   └── int_sf_user_changes.sql
│   └── marts/
│       ├── _schema.yml
│       └── dim_sf_user_scd.sql
├── macros/
│   ├── scd_type2_sf_user.sql
│   └── data_quality_checks.sql
├── tests/
│   ├── generic/
│   └── singular/
│       └── test_scd_integrity.sql
└── snapshots/
    └── sf_user_snapshot.sql
```

**Configuration**:
```yaml
# dbt_project.yml
name: 'sf_user_pipeline'
version: '1.0.0'
config-version: 2

model-paths: ["models"]
test-paths: ["tests"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

models:
  sf_user_pipeline:
    +file_format: iceberg
    +table_properties:
      write.format.default: parquet
      write.parquet.compression-codec: snappy
    staging:
      +materialized: view
    intermediate:
      +materialized: ephemeral
    marts:
      +materialized: incremental
      +incremental_strategy: merge
      +on_schema_change: sync_all_columns
      +unique_key: _scd_id
      +merge_update_columns: ['is_current']  # Only update currency flags
      +incremental_predicates: ["lastmodifieddate > (select max(update_date) from {{ this }})"]

snapshots:
  sf_user_pipeline:
    +target_schema: snapshots
    +strategy: timestamp
    +updated_at: lastmodifieddate
```

### Iceberg Table Management

**Purpose**: Provide ACID-compliant, schema-evolving storage layer for sf_user data

**Table Categories**:

1. **Raw Iceberg Tables** (`sf_raw` schema):
   - Direct output from dbtHub Salesforce extraction to Iceberg format
   - Minimal transformations, queryable directly via Athena
   - Full audit trail with extraction timestamps

2. **Curated Iceberg Tables** (`sf_curated` schema):
   - SCD Type 2 implementation for sf_user in Iceberg format
   - Historical tracking of Division and Audit_Phase__c changes
   - Optimized for historical analysis, queryable directly via Athena

**Iceberg Table Schema Examples**:
```sql
-- Raw sf_user Iceberg Table (queryable via Athena)
-- Location: s3://lumata-salesforce-lakehouse-iceberg-dev/iceberg/salesforce_raw/sf_user/
CREATE TABLE glue_catalog.salesforce_raw.sf_user (
    id string,
    name string,
    division string,
    audit_phase__c string,
    lastmodifieddate timestamp,
    isactive boolean,
    isdeleted boolean,
    createddate timestamp,
    _extracted_at timestamp,
    _extraction_run_id string
) USING iceberg
LOCATION 's3://lumata-salesforce-lakehouse-iceberg-dev/iceberg/salesforce_raw/sf_user/'
PARTITIONED BY (days(_extracted_at))
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='snappy',
    'format-version'='2'
);

-- Curated sf_user SCD Type 2 Iceberg Table (queryable via Athena)
-- Location: s3://lumata-salesforce-lakehouse-iceberg-dev/iceberg/salesforce_curated/dim_sf_user_scd/
CREATE TABLE glue_catalog.salesforce_curated.dim_sf_user_scd (
    user_key bigint,
    user_id string,
    name string,
    division string,
    audit_phase__c string,
    is_active boolean,
    update_date timestamp,
    is_current boolean,
    is_deleted boolean,
    _dbt_updated_at timestamp,
    _scd_id string
) USING iceberg
LOCATION 's3://lumata-salesforce-lakehouse-iceberg-dev/iceberg/salesforce_curated/dim_sf_user_scd/'
PARTITIONED BY (is_current, bucket(8, user_id))
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='snappy',
    'format-version'='2'
);
```

## Data Models

### Data Loading Strategy

**Recommended Approach**: **Incremental Loading with Merge Strategy**

**Best Practices for sf_user SCD Type 2**:

1. **Initial Load (First Run)**:
   - Full extraction of all sf_user records from Salesforce
   - Create baseline SCD records with is_current=true
   - Establish initial state for Division and Audit_Phase__c tracking

2. **Incremental Loads (Ongoing)**:
   - Extract only records where LastModifiedDate > last successful run timestamp
   - Use merge strategy to handle updates, inserts, and deletes
   - Maintain SCD Type 2 history for Division and Audit_Phase__c changes

3. **Loading Strategy Details**:
```yaml
loading_strategy:
  raw_layer:
    strategy: "incremental_merge"
    incremental_field: "lastmodifieddate"
    unique_key: "id"
    merge_behavior: "upsert"  # Insert new, update existing
    
  curated_layer:
    strategy: "scd_type2_merge"
    scd_tracked_fields: ["division", "audit_phase__c"]
    change_detection: "field_comparison"
    history_preservation: "full"
    
  performance_optimization:
    batch_size: 10000
    parallel_processing: true
    partition_pruning: true
```

4. **Frequency Recommendations**:
   - **Hourly**: For real-time analytics requirements
   - **Daily**: For standard reporting (recommended for sf_user)
   - **Weekly**: For historical analysis only

5. **Error Handling Strategy**:
   - Failed records: Quarantine and continue processing
   - Schema changes: Auto-evolve with alerts
   - API limits: Automatic retry with exponential backoff

**Why This Strategy is Optimal for sf_user SCD Type 2**:

- **Performance**: Only processes changed records, reducing API calls and processing time
- **Cost Efficiency**: Minimizes Salesforce API usage and compute resources
- **Data Integrity**: Merge strategy ensures no duplicates while preserving history
- **Scalability**: Handles growing user base without performance degradation
- **Reliability**: Lookback window catches late-arriving updates
- **Compliance**: Full history preservation for audit requirements

**Alternative Strategies Considered**:
- **Full Load**: Too expensive for API calls and processing time
- **Append Only**: Would create duplicates and complicate SCD logic
- **Delete/Insert**: Would lose Iceberg's ACID benefits and time travel capabilities

### sf_user Object Configuration

**sf_user Object Mapping**:
```yaml
sf_user:
  source_object: "User"
  raw_iceberg_table: "glue_catalog.sf_raw.sf_user"
  curated_iceberg_table: "glue_catalog.sf_curated.dim_sf_user_scd"
  primary_key: "id"
  incremental_field: "lastmodifieddate"
  scd_type: 2
  estimated_records: 5000
  
  # Authentication via existing AWS Secrets Manager
  credentials:
    source: aws_secrets_manager
    secret_name: "salesforce/production/credentials"
  
  # SCD tracking fields (changes trigger new SCD record)
  scd_tracked_fields:
    - division
    - audit_phase__c
  
  # Field mappings for SCD table
  field_mappings:
    id: user_id
    name: name
    division: division
    audit_phase__c: audit_phase__c
    lastmodifieddate: update_date
    isactive: is_active
    isdeleted: is_deleted
    
  # Data quality rules
  data_quality:
    required_fields: [id, name]
    unique_fields: [id]
    valid_divisions: ["North", "South", "East", "West", "Central"]
    valid_audit_phases: ["Phase1", "Phase2", "Phase3", "Complete"]
    
  # Athena query optimization
  athena_optimization:
    partition_fields: [is_current, update_date]
    clustering_fields: [user_id]
```

### SCD Type 2 Implementation for sf_user

**Purpose**: Track historical changes to Division and Audit_Phase__c fields

**Key SCD Fields**:
- `update_date`: When the record version became effective (from LastModifiedDate)
- `is_current`: Boolean flag for current version (true/false)
- `is_deleted`: Boolean flag for deleted records (true/false)

**Implementation**:
```sql
-- SCD Type 2 macro for sf_user
{% macro scd_type2_sf_user() %}
    with source_data as (
        select 
            id as user_id,
            name,
            division,
            audit_phase__c,
            isactive as is_active,
            lastmodifieddate as update_date,
            isdeleted as is_deleted
        from {{ ref('stg_sf_user') }}
    ),
    
    -- Detect changes in tracked fields
    changes_detected as (
        select *,
            lag(division) over (partition by user_id order by update_date) as prev_division,
            lag(audit_phase__c) over (partition by user_id order by update_date) as prev_audit_phase
        from source_data
    ),
    
    -- Generate SCD records
    scd_records as (
        select 
            {{ dbt_utils.generate_surrogate_key(['user_id', 'update_date']) }} as user_key,
            user_id,
            name,
            division,
            audit_phase__c,
            is_active,
            update_date,
            case 
                when lead(update_date) over (partition by user_id order by update_date) is null 
                then true 
                else false 
            end as is_current,
            is_deleted,
            current_timestamp() as _dbt_updated_at,
            {{ dbt_utils.generate_surrogate_key(['user_id', 'division', 'audit_phase__c']) }} as _scd_id
        from changes_detected
        where division != coalesce(prev_division, '') 
           or audit_phase__c != coalesce(prev_audit_phase, '')
           or prev_division is null  -- First record
    )
    
    select * from scd_records
{% endmacro %}
```

### dbt Model Implementation

**Staging Model** (`stg_sf_user.sql`):
```sql
{{ config(materialized='view') }}

select 
    id,
    name,
    division,
    audit_phase__c,
    lastmodifieddate,
    isactive,
    isdeleted,
    _extracted_at,
    _extraction_run_id
from {{ source('sf_raw', 'sf_user') }}
where _extracted_at >= current_date - interval '7' day  -- Process last 7 days
```

**SCD Dimension Model** (`dim_sf_user_scd.sql`):
```sql
{{ config(
    materialized='incremental',
    file_format='iceberg',
    incremental_strategy='merge',
    unique_key='_scd_id',
    merge_update_columns=['is_current']
) }}

{{ scd_type2_sf_user() }}

{% if is_incremental() %}
-- Update previous records to not current when new version exists
union all

select 
    user_key,
    user_id,
    name,
    division,
    audit_phase__c,
    is_active,
    update_date,
    false as is_current,  -- Mark previous versions as not current
    is_deleted,
    current_timestamp() as _dbt_updated_at,
    _scd_id
from {{ this }}
where user_id in (
    select distinct user_id 
    from {{ ref('stg_sf_user') }}
    where lastmodifieddate > (select max(update_date) from {{ this }})
)
and is_current = true
{% endif %}
```

## Error Handling

### Error Categories and Responses

**1. AWS Glue Job Ingestion Errors**:
- Salesforce API rate limiting: Built-in backoff and retry with exponential backoff
- Authentication failures: Credential refresh from Secrets Manager and retry
- Network timeouts: Configurable retry with exponential backoff
- Glue job failures: Automatic retry with Step Functions

**2. Data Quality Errors**:
- Schema mismatches: Log and continue with schema evolution
- Missing required fields: Quarantine records for review
- Invalid Division/Audit_Phase__c values: Log warnings and continue

**3. dbt Transformation Errors**:
- SCD logic failures: Rollback and alert
- Incremental processing errors: Retry with full refresh
- Test failures: Alert and continue with warnings

### Error Handling Implementation

```python
# AWS Glue job error handling configuration
ERROR_HANDLING_CONFIG = {
    "salesforce_api": {
        "max_retries": 3,
        "backoff_factor": 2,
        "timeout_seconds": 300,
        "rate_limit_retry_delay": 60
    },
    "data_quality": {
        "on_schema_change": "warn_and_continue",
        "on_validation_failure": "quarantine",
        "quarantine_s3_path": "s3://lumata-salesforce-lakehouse-config-dev/quarantine/",
        "max_error_percentage": 5
    },
    "glue_job": {
        "max_retries": 2,
        "timeout_minutes": 2880,  # 48 hours
        "on_failure": "alert_and_stop"
    },
    "notifications": {
        "sns_topic_arn": "arn:aws:sns:us-east-1:ACCOUNT:sf-user-pipeline-alerts",
        "channels": ["email", "slack"]
    }
}
```

### Monitoring and Alerting

**Pipeline Metrics**:
- AWS Glue job duration and success rate
- sf_user record counts and processing volumes
- SCD processing statistics (new, updated, deleted records)
- Data quality test results
- Iceberg table statistics (snapshots, data files, manifest files)

**Alert Triggers**:
- Pipeline failures or timeouts
- Data quality threshold breaches
- SCD integrity violations
- Unexpected data volume changes

**Monitoring Configuration**:
```python
# CloudWatch monitoring configuration
MONITORING_CONFIG = {
    "cloudwatch_metrics": {
        "namespace": "SalesforceIcebergPipeline",
        "metrics": [
            {
                "name": "GlueJobDuration",
                "threshold": 1800,  # 30 minutes
                "comparison": "GreaterThanThreshold"
            },
            {
                "name": "SfUserRecordCount", 
                "expected_range": [4000, 6000],
                "deviation_threshold": 20  # 20% deviation
            },
            {
                "name": "DataQualityScore",
                "threshold": 95,  # 95% success rate
                "comparison": "LessThanThreshold"
            }
        ]
    },
    "cloudwatch_alarms": {
        "sns_topic": "arn:aws:sns:us-east-1:ACCOUNT:sf-user-pipeline-alerts",
        "escalation_minutes": 30
    },
    "log_groups": {
        "glue_job": "/aws/glue/jobs/sf-user-ingestion-job",
        "step_functions": "/aws/stepfunctions/sf-user-pipeline",
        "dbt": "/aws/dbt/sf-user-transformations"
    }
}
```

## Testing Strategy

### Unit Testing
- **dbt Models**: Test sf_user staging and SCD model logic with sample data
- **SCD Macros**: Validate SCD Type 2 logic for Division and Audit_Phase__c tracking
- **Glue Job Scripts**: Test Salesforce connection, extraction logic, and Iceberg writes

### Integration Testing
- **End-to-End Pipeline**: Validate complete sf_user data flow from Salesforce to SCD tables
- **Schema Evolution**: Test handling of sf_user schema changes
- **Incremental Processing**: Verify correct SCD handling of updates and deletes

### Data Quality Testing
- **dbt Tests**: Built-in and custom data quality tests for sf_user
- **SCD Integrity**: Validate SCD Type 2 implementation correctness
- **Business Rules**: Test Division and Audit_Phase__c value validation

**dbt Test Examples**:
```yaml
# models/_schema.yml
models:
  - name: dim_sf_user_scd
    description: "sf_user dimension with SCD Type 2"
    tests:
      - unique:
          column_name: user_key
      - not_null:
          column_name: user_id
    columns:
      - name: user_id
        description: "Salesforce user ID"
        tests:
          - not_null
          - unique:
              where: "is_current = true and is_deleted = false"
      - name: division
        description: "User division"
        tests:
          - accepted_values:
              values: ['North', 'South', 'East', 'West', 'Central']
      - name: audit_phase__c
        description: "Audit phase"
        tests:
          - accepted_values:
              values: ['Phase1', 'Phase2', 'Phase3', 'Complete']

# Custom SCD integrity test
tests:
  - name: test_scd_integrity
    description: "Ensure SCD Type 2 integrity for sf_user"
```

### Deployment Strategy

**Environment Progression**:
1. **Development**: Individual developer testing and sf_user model development
2. **Staging**: Integration testing with production-like sf_user data volumes
3. **Production**: Live system with full monitoring and alerting

**Deployment Pipeline**:
```yaml
# .github/workflows/deploy.yml
name: Deploy sf_user Pipeline
on:
  push:
    branches: [main]
    
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Test Glue job script
        run: |
          python -m pytest tests/test_glue_job.py
      - name: Run dbt tests
        run: |
          dbt deps
          dbt test --profiles-dir ./profiles --models sf_user_pipeline
          
  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - name: Deploy Glue job script to S3
        run: |
          aws s3 cp glue_jobs/sf_user_ingestion.py s3://lumata-salesforce-lakehouse-config-dev/glue_scripts/
      - name: Update Glue job
        run: |
          aws glue update-job --job-name sf-user-ingestion-job --job-update file://glue_job_config.json
      - name: Deploy dbt models
        run: |
          dbt run --profiles-dir ./profiles --target prod --models sf_user_pipeline
```

This design provides a focused, maintainable solution for sf_user data processing with SCD Type 2 implementation, leveraging AWS-native services like Glue jobs and dbt Core for scalable, cloud-native architecture and operations.
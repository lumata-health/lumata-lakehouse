# Design Document

## Overview

This design document outlines the technical architecture for a focused Salesforce sf_user data pipeline using dbtHub for ingestion and dbt Core for transformations. The architecture implements a streamlined 3-component solution: **dbtHub → Salesforce API → Iceberg Tables → dbt Core → Iceberg Marts → Athena/Trino**.

The design prioritizes simplicity and maintainability while providing SCD Type 2 implementation specifically for sf_user data, tracking historical changes in Division and Audit_Phase__c fields.

## Architecture

### High-Level Architecture Diagram

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Salesforce    │    │     dbtHub      │    │  Iceberg Tables │
│   (sf_user)     │───▶│   Ingestion     │───▶│   (Raw Layer)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Athena/Trino    │◀───│  Iceberg Tables │◀───│   dbt Core      │
│   (Analytics)   │    │ (SCD Layer)     │    │ (Transformations)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        ▲
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Monitoring    │◀───│ Orchestration   │───▶│   Scheduling    │
│   (Alerts)      │    │   (Workflow)    │    │   (Triggers)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Component Architecture

#### 1. Data Ingestion Layer
- **dbtHub Framework**: Ingestion framework that handles Salesforce sf_user data fetching
- **Salesforce API**: REST/Bulk API for sf_user data retrieval via dbtHub
- **AWS Secrets Manager**: Existing Salesforce credentials for dbtHub authentication
- **Data Loading Strategy**: Incremental loading with merge strategy for optimal performance

#### 2. Storage Layer
- **Apache Iceberg Tables**: ACID-compliant table format for both raw and curated sf_user data
- **Amazon S3**: Underlying storage for Iceberg tables
- **AWS Glue Catalog**: Metadata management for Iceberg tables (queryable via Athena)

#### 3. Transformation Layer
- **dbt Core**: SQL-based transformations for sf_user processing
- **SCD Type 2 Models**: Historical tracking of Division and Audit_Phase__c changes
- **Incremental Models**: Efficient processing of sf_user updates

#### 4. Orchestration Layer
- **Workflow Engine**: Coordination of dbtHub ingestion and dbt transformations
- **Scheduling**: Automated pipeline execution
- **Event Triggers**: Change-based processing initiation

#### 5. Monitoring Layer
- **Logging**: Comprehensive pipeline execution logs
- **Metrics**: Performance and data quality monitoring
- **Alerting**: Failure and anomaly notifications

## Components and Interfaces

### dbtHub Ingestion Engine

**Purpose**: Extract sf_user data from Salesforce and write to raw Iceberg tables

**Key Features**:
- Declarative configuration for Salesforce sf_user extraction
- Incremental extraction based on LastModifiedDate
- Automatic schema detection and evolution
- Built-in error handling and retry logic

**Configuration Specifications**:
```yaml
# dbtHub source configuration
sources:
  - name: salesforce
    type: salesforce
    connection:
      # Use existing AWS Secrets Manager credentials
      credentials_source: aws_secrets_manager
      secret_name: "salesforce/production/credentials"
      region: "us-east-1"
    
    destination:
      type: iceberg
      catalog: glue_catalog
      database: sf_raw
      s3_location: "s3://data-lake-bucket/sf_raw/"
    
    tables:
      - name: sf_user
        identifier: User
        destination_table: sf_user
        loading_strategy:
          type: incremental
          strategy: merge
          unique_key: Id
          updated_at: LastModifiedDate
          lookback_window: "1 hour"  # Safety buffer for late-arriving data
          full_refresh_schedule: "weekly"  # Weekly full refresh for data integrity
        columns:
          - name: Id
            type: string
          - name: Name
            type: string
          - name: Division
            type: string
          - name: Audit_Phase__c
            type: string
          - name: LastModifiedDate
            type: timestamp
          - name: IsActive
            type: boolean
          - name: IsDeleted
            type: boolean
```

**Interface Specifications**:
```python
class dbtHubConnector:
    def __init__(self, config_path: str):
        self.config = self.load_config(config_path)
        
    def extract_sf_user(self, incremental_date: datetime = None) -> bool:
        """Extract sf_user data with incremental logic"""
        
    def validate_schema(self) -> bool:
        """Validate sf_user schema against Salesforce"""
        
    def get_extraction_stats(self) -> Dict[str, int]:
        """Return extraction statistics for monitoring"""
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
CREATE TABLE glue_catalog.sf_raw.sf_user (
    id string,
    name string,
    division string,
    audit_phase__c string,
    lastmodifieddate timestamp,
    isactive boolean,
    isdeleted boolean,
    _extracted_at timestamp,
    _extraction_run_id string
) USING iceberg
PARTITIONED BY (days(_extracted_at))
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='snappy'
);

-- Curated sf_user SCD Type 2 Iceberg Table (queryable via Athena)
CREATE TABLE glue_catalog.sf_curated.dim_sf_user_scd (
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
PARTITIONED BY (is_current, bucket(8, user_id))
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='snappy'
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

**1. dbtHub Ingestion Errors**:
- Salesforce API rate limiting: Built-in backoff and retry
- Authentication failures: Credential refresh and retry
- Network timeouts: Configurable retry with exponential backoff

**2. Data Quality Errors**:
- Schema mismatches: Log and continue with schema evolution
- Missing required fields: Quarantine records for review
- Invalid Division/Audit_Phase__c values: Log warnings and continue

**3. dbt Transformation Errors**:
- SCD logic failures: Rollback and alert
- Incremental processing errors: Retry with full refresh
- Test failures: Alert and continue with warnings

### Error Handling Implementation

```yaml
# dbtHub error handling configuration
error_handling:
  salesforce_api:
    max_retries: 3
    backoff_factor: 2
    timeout_seconds: 300
    
  data_quality:
    on_schema_change: "warn_and_continue"
    on_test_failure: "warn"
    quarantine_invalid_records: true
    
  pipeline:
    on_failure: "alert_and_stop"
    retry_attempts: 2
    notification_channels: ["email", "slack"]
```

### Monitoring and Alerting

**Pipeline Metrics**:
- dbtHub ingestion duration and success rate
- sf_user record counts and processing volumes
- SCD processing statistics (new, updated, deleted records)
- Data quality test results

**Alert Triggers**:
- Pipeline failures or timeouts
- Data quality threshold breaches
- SCD integrity violations
- Unexpected data volume changes

**Monitoring Configuration**:
```yaml
# Pipeline monitoring configuration
monitoring:
  metrics:
    - name: "sf_user_ingestion_duration"
      threshold: 1800  # 30 minutes
      alert_on_exceed: true
      
    - name: "sf_user_record_count"
      expected_range: [4000, 6000]
      alert_on_deviation: 20  # 20% deviation
      
    - name: "scd_processing_success_rate"
      threshold: 95  # 95% success rate
      alert_on_below: true
      
  alerts:
    channels: ["email", "slack"]
    escalation_minutes: 30
    
  data_quality:
    test_failure_threshold: 3
    critical_tests: ["unique_user_id", "scd_integrity"]
```

## Testing Strategy

### Unit Testing
- **dbt Models**: Test sf_user staging and SCD model logic with sample data
- **SCD Macros**: Validate SCD Type 2 logic for Division and Audit_Phase__c tracking
- **dbtHub Configuration**: Test Salesforce connection and extraction logic

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
      - name: Test dbtHub configuration
        run: |
          dbthub validate --config dbtHub.yml
      - name: Run dbt tests
        run: |
          dbt deps
          dbt test --profiles-dir ./profiles --models sf_user_pipeline
          
  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - name: Deploy dbtHub ingestion
        run: |
          dbthub deploy --config dbtHub.yml --target prod
      - name: Deploy dbt models
        run: |
          dbt run --profiles-dir ./profiles --target prod --models sf_user_pipeline
```

This design provides a focused, maintainable solution for sf_user data processing with SCD Type 2 implementation, leveraging modern tools like dbtHub and dbt Core for simplified architecture and operations.
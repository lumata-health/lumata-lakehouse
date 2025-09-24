# sf_user Pipeline Deployment Guide

## 🎯 Overview

This guide explains how to deploy and run the sf_user pipeline in the **lumata-lakehouse** environment. The pipeline extracts Salesforce User data and implements SCD Type 2 transformations using AWS Glue, Apache Iceberg, and dbt.

## 📁 Current State

### ✅ What We Have (Production-Ready)
- **Complete Pipeline Design**: Full architecture and configuration
- **AWS Glue Job**: Real Salesforce extraction job
- **Deployment Script**: Automated infrastructure deployment
- **dbt Models**: SCD Type 2 transformations
- **Iceberg Tables**: Optimized configurations
- **Testing Framework**: End-to-end validation

### 🚀 Ready to Deploy
All files are now in the correct `lumata-lakehouse/sf_user_pipeline/` directory structure.

## 🚀 Step-by-Step Deployment

### Phase 1: Prerequisites

#### 1.1 Verify AWS Access
```bash
# Ensure AWS CLI is configured
aws sts get-caller-identity

# Should return your account information
```

#### 1.2 Install Dependencies
```bash
# Install required Python packages
pip install boto3 pyyaml simple-salesforce

# Install dbt for transformations
pip install dbt-core dbt-athena-community
```

### Phase 2: Deploy Infrastructure

#### 2.1 Navigate to Pipeline Directory
```bash
cd lumata-lakehouse/sf_user_pipeline
```

#### 2.2 Deploy with Salesforce Credentials (Recommended)
```bash
# Deploy everything in one command
python deploy.py --environment development \
  --sf-username your-salesforce-username \
  --sf-password your-salesforce-password \
  --sf-token your-security-token
```

#### 2.3 Deploy Infrastructure Only (Manual Credentials)
```bash
# Deploy infrastructure without credentials
python deploy.py --environment development

# Then manually add credentials to AWS Secrets Manager
aws secretsmanager create-secret \
  --name "salesforce/development/credentials" \
  --secret-string '{
    "username": "your-salesforce-username",
    "password": "your-salesforce-password", 
    "security_token": "your-security-token",
    "domain": "login.salesforce.com"
  }'
```

### Phase 3: Validate Deployment

#### 3.1 Check Infrastructure
```bash
# Verify S3 buckets were created
aws s3 ls | grep lumata-lakehouse-development

# Verify Glue databases
aws glue get-databases | grep sf_raw_development

# Verify Glue job
aws glue get-job --job-name sf-user-extraction-development
```

#### 3.2 Test Salesforce Connection
```bash
# Test connection manually
python -c "
import boto3, json
from simple_salesforce import Salesforce
secrets = boto3.client('secretsmanager')
creds = json.loads(secrets.get_secret_value(SecretId='salesforce/development/credentials')['SecretString'])
sf = Salesforce(**creds)
print('✓ Salesforce connection successful!')
print(f'✓ User count: {len(sf.query(\"SELECT Id FROM User LIMIT 10\")[\"records\"])}')
"
```

### Phase 4: Run the Pipeline

#### 4.1 Execute Glue Job
```bash
# Start the extraction job
aws glue start-job-run --job-name sf-user-extraction-development

# Monitor job status
aws glue get-job-runs --job-name sf-user-extraction-development --max-results 1
```

#### 4.2 Run dbt Transformations
```bash
# Navigate to dbt project
cd transformations

# Install dbt dependencies
dbt deps --profiles-dir .

# Run dbt models
dbt run --profiles-dir . --target dev

# Run dbt tests
dbt test --profiles-dir . --target dev
```

### Phase 5: Validate Results

#### 5.1 Check Raw Data in Athena
```sql
-- Query raw sf_user data
SELECT COUNT(*) as total_records, 
       MAX(_extracted_at) as latest_extraction,
       COUNT(DISTINCT division) as unique_divisions
FROM sf_raw_development.sf_user;

-- Sample raw data
SELECT id, name, division, audit_phase__c, _extracted_at
FROM sf_raw_development.sf_user 
LIMIT 10;
```

#### 5.2 Check SCD Data in Athena
```sql
-- Query SCD curated data
SELECT COUNT(*) as total_scd_records,
       COUNT(CASE WHEN is_current = true THEN 1 END) as current_records,
       COUNT(CASE WHEN is_current = false THEN 1 END) as historical_records
FROM sf_curated_development.dim_sf_user_scd;

-- Sample SCD data
SELECT user_id, name, division, audit_phase__c, is_current, effective_from, effective_to
FROM sf_curated_development.dim_sf_user_scd 
ORDER BY user_id, effective_from
LIMIT 20;
```

#### 5.3 Run End-to-End Tests
```bash
# Run comprehensive integration test
python tests/test_e2e_integration.py --environment development
```

## 🔧 Configuration Details

### Environment-Specific Settings

The pipeline supports three environments with different configurations:

#### Development Environment
- **S3 Buckets**: `lumata-lakehouse-development-*`
- **Glue Databases**: `sf_raw_development`, `sf_curated_development`
- **Secrets**: `salesforce/development/credentials`

#### Staging Environment
- **S3 Buckets**: `lumata-lakehouse-staging-*`
- **Glue Databases**: `sf_raw_staging`, `sf_curated_staging`
- **Secrets**: `salesforce/staging/credentials`

#### Production Environment
- **S3 Buckets**: `lumata-lakehouse-prod-*`
- **Glue Databases**: `sf_raw`, `sf_curated`
- **Secrets**: `salesforce/production/credentials`

### Iceberg Table Configurations

The pipeline creates optimized Iceberg tables:

#### Raw Table (`sf_user`)
- **Partitioning**: By `_extracted_date`
- **Compression**: Snappy
- **File Size**: 128MB
- **Location**: `s3://lumata-lakehouse-{env}-raw/iceberg/sf_user/`

#### SCD Table (`dim_sf_user_scd`)
- **Partitioning**: By `is_current`, `division`
- **Clustering**: By `user_id`, `update_date`
- **Compression**: ZSTD
- **File Size**: 256MB
- **Location**: `s3://lumata-lakehouse-{env}-raw/iceberg/dim_sf_user_scd/`

## 🚨 Troubleshooting

### Common Issues and Solutions

#### 1. Deployment Script Fails
```bash
# Check AWS permissions
aws iam get-user

# Verify region setting
aws configure get region

# Check for existing resources
aws s3 ls | grep lumata-lakehouse
```

#### 2. Salesforce Connection Issues
```bash
# Verify credentials format
aws secretsmanager get-secret-value --secret-id salesforce/development/credentials

# Test credentials manually
python -c "
from simple_salesforce import Salesforce
sf = Salesforce(username='user', password='pass', security_token='token')
print(sf.describe()['sobjects'][0])
"
```

#### 3. Glue Job Failures
```bash
# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws-glue/jobs/sf-user-extraction"

# View recent log events
aws logs describe-log-streams --log-group-name "/aws-glue/jobs/sf-user-extraction-development"
```

#### 4. dbt Model Failures
```bash
# Debug dbt configuration
cd transformations
dbt debug --profiles-dir .

# Check compiled SQL
dbt compile --profiles-dir . --select dim_sf_user_scd

# Run specific model
dbt run --profiles-dir . --select dim_sf_user_scd --target dev
```

#### 5. Athena Query Issues
```sql
-- Check if tables exist
SHOW TABLES IN sf_raw_development;
SHOW TABLES IN sf_curated_development;

-- Verify table structure
DESCRIBE sf_raw_development.sf_user;
DESCRIBE sf_curated_development.dim_sf_user_scd;

-- Check partitions
SHOW PARTITIONS sf_raw_development.sf_user;
```

## 📊 Monitoring and Operations

### CloudWatch Monitoring
```bash
# View Glue job metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Glue \
  --metric-name glue.driver.aggregate.numCompletedTasks \
  --dimensions Name=JobName,Value=sf-user-extraction-development \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### Performance Monitoring
```sql
-- Monitor data growth
SELECT _extracted_date, COUNT(*) as daily_records
FROM sf_raw_development.sf_user
GROUP BY _extracted_date
ORDER BY _extracted_date DESC
LIMIT 30;

-- Monitor SCD performance
SELECT DATE(effective_from) as change_date, 
       COUNT(*) as changes_count
FROM sf_curated_development.dim_sf_user_scd
WHERE is_current = false
GROUP BY DATE(effective_from)
ORDER BY change_date DESC
LIMIT 30;
```

## 🎯 Next Steps

### 1. Production Deployment
```bash
# Deploy to staging first
python deploy.py --environment staging \
  --sf-username staging-user \
  --sf-password staging-pass \
  --sf-token staging-token

# Then deploy to production
python deploy.py --environment production \
  --sf-username prod-user \
  --sf-password prod-pass \
  --sf-token prod-token
```

### 2. Automation and Scheduling
- Set up EventBridge rules for scheduled execution
- Implement Step Functions for orchestration
- Configure CloudWatch alarms for monitoring

### 3. Performance Optimization
- Monitor query performance and optimize partitioning
- Implement Iceberg table compaction
- Tune dbt model performance

### 4. Data Quality Monitoring
- Implement data quality checks
- Set up alerting for data anomalies
- Create data quality dashboards

## ✅ Deployment Checklist

- [ ] AWS CLI configured with appropriate permissions
- [ ] Python dependencies installed (boto3, dbt, etc.)
- [ ] Salesforce credentials available
- [ ] Infrastructure deployed via `deploy.py`
- [ ] Salesforce credentials stored in Secrets Manager
- [ ] Glue job created and tested
- [ ] Iceberg tables created in Glue Catalog
- [ ] dbt models deployed and tested
- [ ] End-to-end tests passing
- [ ] Athena queries returning expected results
- [ ] CloudWatch monitoring configured

## 🎉 Success Criteria

The deployment is successful when:
1. ✅ Glue job extracts data from Salesforce to raw Iceberg table
2. ✅ dbt transforms raw data into SCD Type 2 curated table
3. ✅ Athena queries return expected results from both tables
4. ✅ End-to-end tests pass completely
5. ✅ SCD Type 2 logic correctly tracks Division and Audit_Phase__c changes

Your sf_user pipeline is now ready for production use in the lumata-lakehouse environment!
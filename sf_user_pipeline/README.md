# sf_user Pipeline

This directory contains the complete sf_user pipeline implementation for extracting Salesforce User data and implementing SCD Type 2 transformations using Apache Iceberg and dbt.

## 🎯 Current Status

### ✅ What's Implemented (Production-Ready)
- **Complete Pipeline Design**: Full architecture and configuration
- **AWS Glue Job**: Real Salesforce extraction job (`ingestion/glue-jobs/sf_user_extraction.py`)
- **Deployment Script**: Automated deployment (`deploy.py`)
- **Infrastructure Setup**: S3, Glue, Athena, IAM resources
- **dbt Models**: SCD Type 2 transformations with integrity checks
- **Iceberg Tables**: Optimized table configurations
- **Comprehensive Testing**: End-to-end validation framework

## 🏗️ Architecture

```
Salesforce (sf_user) → AWS Glue → Iceberg (Raw) → dbt → Iceberg (SCD) → Athena/Analytics
                          ↓
                    CloudWatch Monitoring
```

## 🚀 Quick Start (Deploy & Run)

### Option 1: Automated Deployment
```bash
# Deploy everything automatically
python deploy.py --environment development \
  --sf-username your-sf-username \
  --sf-password your-sf-password \
  --sf-token your-security-token

# Test the deployment
python tests/test_e2e_integration.py --environment development
```

### Option 2: Manual Step-by-Step
```bash
# 1. Deploy infrastructure
python deploy.py --environment development

# 2. Setup Salesforce credentials manually in AWS Secrets Manager
aws secretsmanager create-secret \
  --name "salesforce/development/credentials" \
  --secret-string '{"username":"...","password":"...","security_token":"...","domain":"login.salesforce.com"}'

# 3. Run the pipeline
aws glue start-job-run --job-name "sf-user-extraction-development"

# 4. Check results in Athena
# Query: SELECT * FROM sf_raw_development.sf_user LIMIT 10;
```

## 📊 Validate Results

### Check Raw Data
```sql
-- Check raw sf_user data
SELECT COUNT(*) as total_records, 
       MAX(_extracted_at) as latest_extraction
FROM sf_raw_development.sf_user;
```

### Check SCD Data (after dbt run)
```sql
-- Check SCD curated data
SELECT COUNT(*) as total_scd_records,
       COUNT(CASE WHEN is_current = true THEN 1 END) as current_records
FROM sf_curated_development.dim_sf_user_scd;
```

## 📁 Directory Structure

```
sf_user_pipeline/
├── deploy.py                           # 🚀 Main deployment script
├── config/
│   ├── pipeline-config.yml             # ⚙️ Pipeline configuration
│   └── iceberg-tables.sql              # 🗄️ Iceberg table DDL
├── ingestion/
│   └── glue-jobs/
│       └── sf_user_extraction.py       # 🔧 AWS Glue job for Salesforce extraction
├── transformations/                    # 🔄 dbt transformations (SCD Type 2)
│   ├── dbt_project.yml
│   ├── profiles.yml
│   └── models/
│       └── marts/
│           └── dim_sf_user_scd.sql     # SCD Type 2 model
├── tests/                              # 🧪 Testing framework
│   └── test_e2e_integration.py         # End-to-end integration tests
└── scripts/                            # 🛠️ Utility scripts
```

## 🔧 Configuration

### Environment Configuration
Edit `config/pipeline-config.yml` for environment-specific settings:
- S3 bucket names (lumata-lakehouse-{env}-*)
- Glue database names
- Performance thresholds
- Monitoring settings

### Salesforce Configuration
Credentials stored in AWS Secrets Manager:
```json
{
  "username": "your-salesforce-username",
  "password": "your-salesforce-password", 
  "security_token": "your-security-token",
  "domain": "login.salesforce.com"
}
```

## 🧪 Testing

### Run End-to-End Tests
```bash
# Complete integration test
python tests/test_e2e_integration.py --environment development
```

### Test Individual Components
```bash
# Test dbt models
cd transformations && dbt test --profiles-dir . --target development

# Test Salesforce connection
python -c "
import boto3, json
from simple_salesforce import Salesforce
secrets = boto3.client('secretsmanager')
creds = json.loads(secrets.get_secret_value(SecretId='salesforce/development/credentials')['SecretString'])
sf = Salesforce(**creds)
print('Connection successful!')
"
```

## 🚨 Troubleshooting

### Common Issues

1. **Salesforce Connection Failed**
   - Verify credentials in AWS Secrets Manager
   - Check Salesforce API limits
   - Ensure security token is current

2. **Glue Job Failed**
   - Check CloudWatch logs: `/aws-glue/jobs/sf-user-extraction-development`
   - Verify IAM permissions for Glue service role
   - Check S3 bucket permissions

3. **Iceberg Table Not Found**
   ```sql
   -- Recreate table if needed
   CREATE TABLE sf_raw_development.sf_user (
     id string,
     name string,
     division string,
     audit_phase__c string,
     _extracted_at timestamp
   ) USING iceberg
   LOCATION 's3://lumata-lakehouse-development-raw/iceberg/sf_user/';
   ```

## 🎯 Next Steps

1. **Deploy to Development**: Use `deploy.py` script
2. **Run Tests**: Validate with end-to-end tests
3. **Monitor Performance**: Set up CloudWatch dashboards
4. **Scale to Production**: Deploy to staging/production environments

## 💡 Key Features

- **Production-Ready**: Real AWS Glue jobs and infrastructure
- **SCD Type 2**: Full historical tracking for Division and Audit_Phase__c
- **Iceberg Format**: ACID transactions and schema evolution
- **Automated Deployment**: One-command infrastructure setup
- **Comprehensive Testing**: End-to-end validation
- **Multi-Environment**: Development, staging, production support

This pipeline is ready for production deployment in the lumata-lakehouse environment!
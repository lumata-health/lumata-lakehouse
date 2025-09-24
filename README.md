# Lumata Lakehouse

Modern data lakehouse architecture for Lumata Health analytics, built on Apache Iceberg and AWS services.

## Architecture

```
Data Sources → Ingestion (dbtHub) → Raw Layer (Iceberg) → Transformations (dbt) → Curated Layer (Iceberg) → Analytics
```

## Key Technologies

- **Apache Iceberg** - ACID transactions, schema evolution, time travel
- **dbtHub** - Modern data ingestion framework
- **dbt Core** - SQL-based transformations
- **AWS Athena** - Serverless analytics engine
- **AWS Glue Catalog** - Metadata management

## Current Pipelines

### sf_user Pipeline
Salesforce User data pipeline with SCD Type 2 implementation for tracking Division and Audit_Phase__c changes.

**Location**: `./sf_user_pipeline/`

**Features**:
- Incremental ingestion from Salesforce API
- SCD Type 2 for historical tracking
- Data quality validation
- Multi-environment support

## Quick Start

1. **Setup Pipeline**:
   ```bash
   cd sf_user_pipeline
   ./scripts/setup.sh
   ```

2. **Configure Credentials**:
   ```bash
   # Copy template and fill in values
   cp config/salesforce-credentials.json.template config/salesforce-credentials.json
   
   # Store in AWS Secrets Manager
   aws secretsmanager create-secret \
     --name "salesforce/production/credentials" \
     --secret-string file://config/salesforce-credentials.json
   ```

3. **Run Pipeline**:
   ```bash
   ./scripts/run.sh --env dev
   ```

## Project Structure

```
lumata-lakehouse/
├── lakehouse-config.yml           # Global lakehouse configuration
├── sf_user_pipeline/              # Salesforce sf_user data pipeline
│   ├── ingestion/                 # dbtHub configuration
│   ├── transformations/           # dbt models and tests
│   ├── config/                    # Pipeline configuration
│   └── scripts/                   # Automation scripts
└── README.md                      # This file
```

## Environment Support

- **dev** - Development and testing
- **staging** - Pre-production validation  
- **prod** - Production workloads

Each environment has isolated AWS resources and configurations.
Lumata lakehouse implementation.

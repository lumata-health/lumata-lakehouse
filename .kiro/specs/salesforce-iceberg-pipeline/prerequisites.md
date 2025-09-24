# Prerequisites and Access Requirements

## Overview

This document outlines the prerequisites, AWS permissions, and access requirements needed to implement the Salesforce Iceberg Pipeline. It covers both the current access assessment and additional permissions required for the new architecture.

## AWS Environment Setup

### 1. AWS CLI and SDK Configuration

**Required Tools:**
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install AWS CDK
npm install -g aws-cdk

# Install dbt with Spark adapter
pip install dbt-spark[PyHive]

# Verify installations
aws --version
cdk --version
dbt --version
```

**AWS Profile Configuration:**
```bash
# Configure AWS profile for dev environment
aws configure --profile lumata-dev
# AWS Access Key ID: [Your Access Key]
# AWS Secret Access Key: [Your Secret Key]
# Default region name: us-east-1
# Default output format: json

# Test connectivity
aws sts get-caller-identity --profile lumata-dev
```

### 2. Kiro IDE AWS Integration

**Steps to Connect Kiro to AWS Dev Environment:**

1. **AWS Credentials Setup in Kiro:**
   ```bash
   # In Kiro terminal, configure AWS credentials
   export AWS_PROFILE=lumata-dev
   export AWS_DEFAULT_REGION=us-east-1
   
   # Or create credentials file
   mkdir -p ~/.aws
   cat > ~/.aws/credentials << EOF
   [lumata-dev]
   aws_access_key_id = YOUR_ACCESS_KEY
   aws_secret_access_key = YOUR_SECRET_KEY
   region = us-east-1
   EOF
   ```

2. **Test AWS Connectivity from Kiro:**
   ```bash
   # Test basic AWS access
   aws sts get-caller-identity --profile lumata-dev
   
   # Test S3 access
   aws s3 ls --profile lumata-dev
   
   # Test Glue access
   aws glue get-databases --profile lumata-dev
   ```

## Current Access Assessment

### Existing Permissions Analysis

Based on your current Lumata Data Lake implementation, you likely have these permissions:

**✅ Currently Available Services:**
- **AWS CDK**: Full deployment capabilities
- **Amazon S3**: Read/write access to data buckets
- **AWS Glue**: Job creation and execution
- **Amazon Athena**: Query execution and catalog access
- **AWS Lambda**: Function deployment and execution
- **Amazon DynamoDB**: Table creation and data operations
- **AWS AppFlow**: Flow creation and management
- **Amazon SNS**: Topic creation and publishing
- **AWS CloudWatch**: Logging and monitoring
- **AWS IAM**: Role and policy management (limited)
- **Amazon EventBridge**: Rule creation and management

**Current IAM Permissions (Estimated):**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*",
                "glue:*",
                "athena:*",
                "lambda:*",
                "dynamodb:*",
                "appflow:*",
                "sns:*",
                "cloudwatch:*",
                "events:*",
                "iam:PassRole",
                "iam:GetRole",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy"
            ],
            "Resource": "*"
        }
    ]
}
```

## Additional Permissions Required

### New Services for Iceberg Pipeline

**❗ Additional Access Needed:**

#### 1. Apache Iceberg Support
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "IcebergGlueSupport",
            "Effect": "Allow",
            "Action": [
                "glue:CreateTable",
                "glue:UpdateTable",
                "glue:DeleteTable",
                "glue:GetTable",
                "glue:GetTables",
                "glue:GetPartitions",
                "glue:CreatePartition",
                "glue:UpdatePartition",
                "glue:DeletePartition",
                "glue:BatchCreatePartition",
                "glue:BatchDeletePartition",
                "glue:BatchUpdatePartition"
            ],
            "Resource": [
                "arn:aws:glue:*:*:catalog",
                "arn:aws:glue:*:*:database/salesforce_*",
                "arn:aws:glue:*:*:table/salesforce_*/*"
            ]
        }
    ]
}
```

#### 2. Enhanced Glue Permissions for Spark/Iceberg
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "GlueIcebergJobs",
            "Effect": "Allow",
            "Action": [
                "glue:CreateJob",
                "glue:UpdateJob",
                "glue:DeleteJob",
                "glue:GetJob",
                "glue:GetJobs",
                "glue:StartJobRun",
                "glue:GetJobRun",
                "glue:GetJobRuns",
                "glue:BatchStopJobRun",
                "glue:CreateConnection",
                "glue:UpdateConnection",
                "glue:DeleteConnection",
                "glue:GetConnection",
                "glue:GetConnections"
            ],
            "Resource": "*"
        },
        {
            "Sid": "GlueDevEndpoints",
            "Effect": "Allow",
            "Action": [
                "glue:CreateDevEndpoint",
                "glue:UpdateDevEndpoint",
                "glue:DeleteDevEndpoint",
                "glue:GetDevEndpoint",
                "glue:GetDevEndpoints"
            ],
            "Resource": "*"
        }
    ]
}
```

#### 3. Step Functions for Orchestration
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "StepFunctionsAccess",
            "Effect": "Allow",
            "Action": [
                "states:CreateStateMachine",
                "states:UpdateStateMachine",
                "states:DeleteStateMachine",
                "states:DescribeStateMachine",
                "states:ListStateMachines",
                "states:StartExecution",
                "states:StopExecution",
                "states:DescribeExecution",
                "states:ListExecutions",
                "states:GetExecutionHistory"
            ],
            "Resource": "*"
        }
    ]
}
```

#### 4. Secrets Manager for Salesforce Credentials
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "SecretsManagerAccess",
            "Effect": "Allow",
            "Action": [
                "secretsmanager:CreateSecret",
                "secretsmanager:UpdateSecret",
                "secretsmanager:DeleteSecret",
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:ListSecrets",
                "secretsmanager:PutSecretValue"
            ],
            "Resource": "arn:aws:secretsmanager:*:*:secret:salesforce/*"
        }
    ]
}
```

#### 5. Enhanced S3 Permissions for Iceberg
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3IcebergAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:ListBucketMultipartUploads",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::lumata-datalake-*",
                "arn:aws:s3:::lumata-datalake-*/*"
            ]
        }
    ]
}
```

### Service-Specific Requirements

#### AWS Glue Service Role
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "glue.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

**Attached Policies:**
- `AWSGlueServiceRole`
- `AmazonS3FullAccess` (or restricted to specific buckets)
- Custom policy for Iceberg operations

#### Step Functions Execution Role
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "states.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

## Salesforce Prerequisites

### Salesforce API Access

**Required Salesforce Permissions:**
1. **API Enabled**: Salesforce org must have API access enabled
2. **Connected App**: Create or use existing connected app with:
   - OAuth settings enabled
   - Callback URL configured
   - Required OAuth scopes: `api`, `refresh_token`, `offline_access`

3. **User Permissions**: Salesforce user must have:
   - "API Enabled" permission
   - "View All Data" or object-specific read permissions
   - Access to all required Salesforce objects

**Salesforce Objects Access Required:**
```yaml
required_objects:
  - Account
  - Contact
  - Case
  - Task
  - Event
  - Patient_Encounter__c
  - Clinic_Visit__c
  - Clinic_Visit_Outcome__c
  - Care_Barrier__c
  - Digital_Prescription__c
  - Medication__c
  - ICD10__c
  - User
  - UserRole
  - Call_Audit__c
  - Member_Plan__c
  - Profile
  - Physician_Review__c
```

### Salesforce Credentials Storage

**AWS Secrets Manager Secret Structure:**
```json
{
    "username": "your-sf-username@domain.com",
    "password": "your-sf-password",
    "security_token": "your-sf-security-token",
    "client_id": "connected-app-client-id",
    "client_secret": "connected-app-client-secret",
    "instance_url": "https://your-instance.salesforce.com"
}
```

## Development Environment Setup

### Local Development Tools

**Required Software:**
```bash
# Python environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# dbt installation
pip install dbt-spark[PyHive]==1.6.0

# Spark local setup (for testing)
wget https://archive.apache.org/dist/spark/spark-3.3.0/spark-3.3.0-bin-hadoop3.tgz
tar -xzf spark-3.3.0-bin-hadoop3.tgz
export SPARK_HOME=/path/to/spark-3.3.0-bin-hadoop3
```

**requirements.txt:**
```
boto3==1.28.0
simple-salesforce==1.12.4
pyspark==3.3.0
dbt-spark[PyHive]==1.6.0
great-expectations==0.17.0
pytest==7.4.0
black==23.0.0
flake8==6.0.0
```

### Kiro IDE Configuration

**Environment Variables:**
```bash
# Add to Kiro IDE environment
export AWS_PROFILE=lumata-dev
export AWS_DEFAULT_REGION=us-east-1
export DBT_PROFILES_DIR=/workspace/.dbt
export SPARK_HOME=/opt/spark
export PYTHONPATH=$PYTHONPATH:/workspace/src
```

**Kiro Workspace Structure:**
```
workspace/
├── .aws/
│   ├── credentials
│   └── config
├── .dbt/
│   └── profiles.yml
├── salesforce-pipeline/
│   ├── infrastructure/
│   │   ├── cdk/
│   │   └── glue-scripts/
│   ├── dbt-project/
│   │   ├── models/
│   │   ├── macros/
│   │   └── tests/
│   └── docs/
└── requirements.txt
```

## Permission Validation Checklist

### Pre-Implementation Checks

**✅ AWS Access Validation:**
```bash
# Test current permissions
aws sts get-caller-identity --profile lumata-dev
aws s3 ls --profile lumata-dev
aws glue get-databases --profile lumata-dev
aws athena list-databases --profile lumata-dev

# Test new service access (may fail initially)
aws states list-state-machines --profile lumata-dev
aws secretsmanager list-secrets --profile lumata-dev
```

**✅ Salesforce Access Validation:**
```python
# Test Salesforce connectivity
from simple_salesforce import Salesforce

sf = Salesforce(
    username='your-username',
    password='your-password',
    security_token='your-token'
)

# Test object access
accounts = sf.query("SELECT Id, Name FROM Account LIMIT 5")
print(f"Retrieved {len(accounts['records'])} accounts")
```

### Required Actions Before Implementation

1. **Request Additional AWS Permissions:**
   - Submit IAM policy updates to AWS administrator
   - Request Step Functions access
   - Request Secrets Manager access for Salesforce credentials

2. **Salesforce Setup:**
   - Verify API access and limits
   - Create/configure Connected App
   - Test object-level permissions

3. **Development Environment:**
   - Set up Kiro IDE with AWS integration
   - Install required development tools
   - Configure local testing environment

4. **Security Review:**
   - Review IAM policies with security team
   - Validate encryption requirements
   - Confirm compliance with data governance policies

## Troubleshooting Common Issues

### AWS Permission Issues
```bash
# Common error: Access Denied
# Solution: Check IAM policies and resource ARNs

# Test specific service access
aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::ACCOUNT:user/USERNAME \
    --action-names glue:CreateJob \
    --resource-arns "*"
```

### Salesforce Connection Issues
```python
# Common error: Authentication failure
# Solution: Verify credentials and security token

# Test with simple query
try:
    sf = Salesforce(username=username, password=password, security_token=token)
    result = sf.query("SELECT Id FROM Account LIMIT 1")
    print("Salesforce connection successful")
except Exception as e:
    print(f"Connection failed: {e}")
```

This prerequisites document should help you identify exactly what additional permissions you need and how to set up the development environment properly. Would you like me to help you create specific IAM policy requests or assist with any particular setup step?
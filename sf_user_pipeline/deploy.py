#!/usr/bin/env python3
"""
Deployment script for sf_user pipeline

This script deploys the actual AWS infrastructure and jobs needed to run the sf_user pipeline.
"""

import boto3
import json
import os
import sys
import argparse
from datetime import datetime

class PipelineDeployer:
    def __init__(self, environment='development', region='us-east-1'):
        self.environment = environment
        self.region = region
        
        # Initialize AWS clients
        self.s3_client = boto3.client('s3', region_name=region)
        self.glue_client = boto3.client('glue', region_name=region)
        self.athena_client = boto3.client('athena', region_name=region)
        self.secrets_client = boto3.client('secretsmanager', region_name=region)
        self.iam_client = boto3.client('iam', region_name=region)
        
        # Configuration
        self.bucket_prefix = f"lumata-lakehouse-{environment}"
        self.raw_database = f"sf_raw_{environment}"
        self.curated_database = f"sf_curated_{environment}"
        
    def deploy_infrastructure(self):
        """Deploy the basic AWS infrastructure"""
        print("🚀 Deploying AWS infrastructure...")
        
        # Create S3 buckets
        self._create_s3_buckets()
        
        # Create Glue databases
        self._create_glue_databases()
        
        # Create IAM role for Glue
        self._create_glue_role()
        
        # Upload Glue job script
        self._upload_glue_script()
        
        # Create Glue job
        self._create_glue_job()
        
        print("✅ Infrastructure deployment completed!")
    
    def _create_s3_buckets(self):
        """Create required S3 buckets"""
        buckets = [
            f"{self.bucket_prefix}-raw",
            f"{self.bucket_prefix}-staging", 
            f"{self.bucket_prefix}-scripts",
            f"{self.bucket_prefix}-athena-results"
        ]
        
        for bucket in buckets:
            try:
                if self.region == 'us-east-1':
                    self.s3_client.create_bucket(Bucket=bucket)
                else:
                    self.s3_client.create_bucket(
                        Bucket=bucket,
                        CreateBucketConfiguration={'LocationConstraint': self.region}
                    )
                print(f"✓ Created S3 bucket: {bucket}")
            except self.s3_client.exceptions.BucketAlreadyOwnedByYou:
                print(f"✓ S3 bucket already exists: {bucket}")
            except Exception as e:
                print(f"✗ Failed to create bucket {bucket}: {str(e)}")
    
    def _create_glue_databases(self):
        """Create Glue databases"""
        databases = [
            {
                'Name': self.raw_database,
                'Description': f'Raw Salesforce data for {self.environment}'
            },
            {
                'Name': self.curated_database,
                'Description': f'Curated Salesforce data for {self.environment}'
            }
        ]
        
        for db in databases:
            try:
                self.glue_client.create_database(DatabaseInput=db)
                print(f"✓ Created Glue database: {db['Name']}")
            except self.glue_client.exceptions.AlreadyExistsException:
                print(f"✓ Glue database already exists: {db['Name']}")
            except Exception as e:
                print(f"✗ Failed to create database {db['Name']}: {str(e)}")
    
    def _create_glue_role(self):
        """Create IAM role for Glue jobs"""
        role_name = f"GlueServiceRole-{self.environment}"
        
        trust_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {"Service": "glue.amazonaws.com"},
                    "Action": "sts:AssumeRole"
                }
            ]
        }
        
        try:
            # Create role
            self.iam_client.create_role(
                RoleName=role_name,
                AssumeRolePolicyDocument=json.dumps(trust_policy),
                Description=f"Glue service role for {self.environment} environment"
            )
            
            # Attach managed policies
            policies = [
                'arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole',
                'arn:aws:iam::aws:policy/AmazonS3FullAccess',
                'arn:aws:iam::aws:policy/SecretsManagerReadWrite'
            ]
            
            for policy in policies:
                self.iam_client.attach_role_policy(
                    RoleName=role_name,
                    PolicyArn=policy
                )
            
            print(f"✓ Created IAM role: {role_name}")
            
        except self.iam_client.exceptions.EntityAlreadyExistsException:
            print(f"✓ IAM role already exists: {role_name}")
        except Exception as e:
            print(f"✗ Failed to create IAM role: {str(e)}")
    
    def _upload_glue_script(self):
        """Upload Glue job script to S3"""
        script_bucket = f"{self.bucket_prefix}-scripts"
        script_key = "glue-jobs/sf_user_extraction.py"
        script_path = "ingestion/glue-jobs/sf_user_extraction.py"
        
        try:
            self.s3_client.upload_file(
                script_path,
                script_bucket,
                script_key
            )
            print(f"✓ Uploaded Glue script to s3://{script_bucket}/{script_key}")
        except Exception as e:
            print(f"✗ Failed to upload Glue script: {str(e)}")
    
    def _create_glue_job(self):
        """Create Glue job for sf_user extraction"""
        job_name = f"sf-user-extraction-{self.environment}"
        role_arn = f"arn:aws:iam::{boto3.client('sts').get_caller_identity()['Account']}:role/GlueServiceRole-{self.environment}"
        script_location = f"s3://{self.bucket_prefix}-scripts/glue-jobs/sf_user_extraction.py"
        
        job_config = {
            'Name': job_name,
            'Role': role_arn,
            'Command': {
                'Name': 'glueetl',
                'ScriptLocation': script_location,
                'PythonVersion': '3'
            },
            'DefaultArguments': {
                '--environment': self.environment,
                '--salesforce_secret_name': f'salesforce/{self.environment}/credentials',
                '--raw_database': self.raw_database,
                '--raw_table': 'sf_user',
                '--s3_raw_path': f's3://{self.bucket_prefix}-raw/iceberg',
                '--enable-metrics': '',
                '--enable-continuous-cloudwatch-log': 'true'
            },
            'MaxRetries': 1,
            'Timeout': 60,
            'GlueVersion': '4.0',
            'NumberOfWorkers': 2,
            'WorkerType': 'G.1X'
        }
        
        try:
            self.glue_client.create_job(**job_config)
            print(f"✓ Created Glue job: {job_name}")
        except self.glue_client.exceptions.AlreadyExistsException:
            print(f"✓ Glue job already exists: {job_name}")
            # Update the job
            job_update = {k: v for k, v in job_config.items() if k != 'Name'}
            self.glue_client.update_job(JobName=job_name, JobUpdate=job_update)
            print(f"✓ Updated Glue job: {job_name}")
        except Exception as e:
            print(f"✗ Failed to create Glue job: {str(e)}")
    
    def create_iceberg_tables(self):
        """Create Iceberg tables via Athena"""
        print("🔧 Creating Iceberg tables...")
        
        # Read the Iceberg table DDL
        with open('config/iceberg-tables.sql', 'r') as f:
            ddl_content = f.read()
        
        # Replace placeholders with actual values
        ddl_content = ddl_content.replace('sf_raw_dev', self.raw_database)
        ddl_content = ddl_content.replace('sf_curated_dev', self.curated_database)
        ddl_content = ddl_content.replace('lumata-lakehouse-raw', f'{self.bucket_prefix}-raw')
        
        # Execute DDL via Athena
        try:
            response = self.athena_client.start_query_execution(
                QueryString=ddl_content,
                ResultConfiguration={
                    'OutputLocation': f's3://{self.bucket_prefix}-athena-results/setup/'
                },
                WorkGroup='primary'
            )
            
            query_execution_id = response['QueryExecutionId']
            print(f"✓ Started Athena query execution: {query_execution_id}")
            print("✓ Iceberg tables creation initiated")
            
        except Exception as e:
            print(f"✗ Failed to create Iceberg tables: {str(e)}")
    
    def setup_salesforce_credentials(self, username, password, security_token, domain='login.salesforce.com'):
        """Setup Salesforce credentials in Secrets Manager"""
        print("🔐 Setting up Salesforce credentials...")
        
        secret_name = f'salesforce/{self.environment}/credentials'
        secret_value = {
            'username': username,
            'password': password,
            'security_token': security_token,
            'domain': domain
        }
        
        try:
            self.secrets_client.create_secret(
                Name=secret_name,
                Description=f'Salesforce credentials for {self.environment} environment',
                SecretString=json.dumps(secret_value)
            )
            print(f"✓ Created Salesforce credentials secret: {secret_name}")
        except self.secrets_client.exceptions.ResourceExistsException:
            # Update existing secret
            self.secrets_client.update_secret(
                SecretId=secret_name,
                SecretString=json.dumps(secret_value)
            )
            print(f"✓ Updated Salesforce credentials secret: {secret_name}")
        except Exception as e:
            print(f"✗ Failed to setup Salesforce credentials: {str(e)}")
    
    def test_deployment(self):
        """Test the deployed pipeline"""
        print("🧪 Testing deployed pipeline...")
        
        job_name = f"sf-user-extraction-{self.environment}"
        
        try:
            # Start a test job run
            response = self.glue_client.start_job_run(JobName=job_name)
            job_run_id = response['JobRunId']
            
            print(f"✓ Started test job run: {job_run_id}")
            print(f"Monitor the job in AWS Console or use: aws glue get-job-run --job-name {job_name} --run-id {job_run_id}")
            
        except Exception as e:
            print(f"✗ Failed to start test job: {str(e)}")

def main():
    parser = argparse.ArgumentParser(description='Deploy sf_user pipeline')
    parser.add_argument('--environment', default='development', 
                       choices=['development', 'staging', 'production'],
                       help='Environment to deploy to')
    parser.add_argument('--region', default='us-east-1',
                       help='AWS region')
    parser.add_argument('--sf-username', 
                       help='Salesforce username')
    parser.add_argument('--sf-password',
                       help='Salesforce password')
    parser.add_argument('--sf-token',
                       help='Salesforce security token')
    parser.add_argument('--test-only', action='store_true',
                       help='Only run test, skip deployment')
    
    args = parser.parse_args()
    
    # Initialize deployer
    deployer = PipelineDeployer(args.environment, args.region)
    
    if not args.test_only:
        # Deploy infrastructure
        deployer.deploy_infrastructure()
        
        # Create Iceberg tables
        deployer.create_iceberg_tables()
        
        # Setup Salesforce credentials if provided
        if args.sf_username and args.sf_password and args.sf_token:
            deployer.setup_salesforce_credentials(
                args.sf_username, 
                args.sf_password, 
                args.sf_token
            )
        else:
            print("⚠️ Salesforce credentials not provided. Please set them up manually in AWS Secrets Manager.")
    
    # Test deployment
    deployer.test_deployment()
    
    print("🎉 Deployment completed!")
    print("\nNext steps:")
    print("1. Set up Salesforce credentials if not done already")
    print("2. Run the end-to-end tests: python tests/run_e2e_integration_tests.py")
    print("3. Monitor the job execution in AWS Glue Console")
    print("4. Query the data in Athena to verify results")

if __name__ == "__main__":
    main()
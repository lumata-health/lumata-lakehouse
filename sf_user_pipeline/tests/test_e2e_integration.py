#!/usr/bin/env python3
"""
End-to-End Integration Tests for sf_user Pipeline

This module provides comprehensive end-to-end testing for the complete sf_user pipeline
from AWS Glue job ingestion through dbt SCD transformation.
"""

import os
import sys
import json
import yaml
import boto3
import logging
import subprocess
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class E2EIntegrationTester:
    """End-to-end integration testing for sf_user pipeline"""
    
    def __init__(self, environment: str = "development"):
        self.environment = environment
        self.config = self._load_pipeline_config()
        self.aws_config = self.config['environments'][environment]['aws']
        
        # Initialize AWS clients
        self.glue_client = boto3.client('glue', region_name=self.aws_config['region'])
        self.athena_client = boto3.client('athena', region_name=self.aws_config['region'])
        self.s3_client = boto3.client('s3', region_name=self.aws_config['region'])
        self.secrets_client = boto3.client('secretsmanager', region_name=self.aws_config['region'])
        
        # Test execution tracking
        self.test_run_id = f"e2e_test_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        self.test_results = {}
        
    def _load_pipeline_config(self) -> Dict[str, Any]:
        """Load pipeline configuration"""
        config_path = os.path.join(
            os.path.dirname(__file__), 
            '../config/pipeline-config.yml'
        )
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
    
    def run_complete_integration_test(self) -> bool:
        """Execute complete end-to-end integration test"""
        try:
            logger.info("🚀 Starting complete sf_user pipeline integration test...")
            logger.info(f"Test Run ID: {self.test_run_id}")
            logger.info(f"Environment: {self.environment}")
            
            # Step 1: Validate prerequisites
            if not self._validate_prerequisites():
                return False
            
            # Step 2: Test Glue job execution
            if not self._test_glue_job_execution():
                return False
            
            # Step 3: Validate raw data
            if not self._validate_raw_data():
                return False
            
            # Step 4: Run dbt transformations
            if not self._run_dbt_transformations():
                return False
            
            # Step 5: Validate SCD data
            if not self._validate_scd_data():
                return False
            
            logger.info("✅ Complete end-to-end integration test PASSED")
            return True
            
        except Exception as e:
            logger.error(f"❌ End-to-end integration test FAILED: {str(e)}")
            return False
    
    def _validate_prerequisites(self) -> bool:
        """Validate all prerequisites for testing"""
        try:
            logger.info("🔍 Validating prerequisites...")
            
            # Check AWS credentials
            try:
                caller_identity = boto3.client('sts').get_caller_identity()
                logger.info(f"✓ AWS credentials valid for account: {caller_identity.get('Account', 'Unknown')}")
            except Exception as e:
                logger.error(f"✗ AWS credentials validation failed: {str(e)}")
                return False
            
            # Check Salesforce credentials
            secret_name = self.aws_config['secrets_manager']['salesforce_credentials']
            try:
                response = self.secrets_client.get_secret_value(SecretId=secret_name)
                credentials = json.loads(response['SecretString'])
                required_fields = ['username', 'password', 'security_token', 'domain']
                
                for field in required_fields:
                    if field not in credentials:
                        logger.error(f"✗ Missing field '{field}' in Salesforce credentials")
                        return False
                
                logger.info("✓ Salesforce credentials validated")
            except Exception as e:
                logger.error(f"✗ Salesforce credentials validation failed: {str(e)}")
                return False
            
            # Check Glue job exists
            job_name = f"sf-user-extraction-{self.environment}"
            try:
                self.glue_client.get_job(JobName=job_name)
                logger.info(f"✓ Glue job exists: {job_name}")
            except self.glue_client.exceptions.EntityNotFoundException:
                logger.error(f"✗ Glue job not found: {job_name}")
                return False
            
            logger.info("✅ Prerequisites validation completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"❌ Prerequisites validation failed: {str(e)}")
            return False
    
    def _test_glue_job_execution(self) -> bool:
        """Test Glue job execution"""
        try:
            logger.info("🔄 Testing Glue job execution...")
            
            job_name = f"sf-user-extraction-{self.environment}"
            
            # Start job run
            response = self.glue_client.start_job_run(JobName=job_name)
            job_run_id = response['JobRunId']
            
            logger.info(f"✓ Started Glue job run: {job_run_id}")
            
            # Wait for completion (with timeout)
            max_wait_time = 1800  # 30 minutes
            start_time = time.time()
            
            while time.time() - start_time < max_wait_time:
                response = self.glue_client.get_job_run(JobName=job_name, RunId=job_run_id)
                job_state = response['JobRun']['JobRunState']
                
                if job_state == 'SUCCEEDED':
                    logger.info("✓ Glue job completed successfully")
                    return True
                elif job_state in ['FAILED', 'ERROR', 'TIMEOUT']:
                    logger.error(f"✗ Glue job failed with state: {job_state}")
                    return False
                
                logger.info(f"Glue job state: {job_state}, waiting...")
                time.sleep(30)  # Wait 30 seconds before checking again
            
            logger.error("✗ Glue job timed out")
            return False
            
        except Exception as e:
            logger.error(f"❌ Glue job execution test failed: {str(e)}")
            return False
    
    def _validate_raw_data(self) -> bool:
        """Validate raw data in Iceberg table"""
        try:
            logger.info("🔍 Validating raw data...")
            
            # Query raw table via Athena
            raw_database = self.aws_config['glue']['raw_database']
            query = f"SELECT COUNT(*) as record_count FROM {raw_database}.sf_user WHERE _extracted_date = CURRENT_DATE"
            
            result = self._execute_athena_query(query)
            
            if result and len(result) > 0:
                record_count = result[0]['record_count']
                logger.info(f"✓ Found {record_count} records in raw table")
                return record_count > 0
            else:
                logger.error("✗ No data found in raw table")
                return False
            
        except Exception as e:
            logger.error(f"❌ Raw data validation failed: {str(e)}")
            return False
    
    def _run_dbt_transformations(self) -> bool:
        """Run dbt transformations"""
        try:
            logger.info("🔄 Running dbt transformations...")
            
            dbt_project_dir = os.path.join(os.path.dirname(__file__), '../transformations')
            
            # Change to dbt project directory
            original_cwd = os.getcwd()
            os.chdir(dbt_project_dir)
            
            try:
                # Install dbt dependencies
                deps_result = subprocess.run(
                    ['dbt', 'deps', '--profiles-dir', '.'],
                    capture_output=True, text=True, timeout=300
                )
                
                if deps_result.returncode != 0:
                    logger.error(f"✗ dbt deps failed: {deps_result.stderr}")
                    return False
                
                # Run dbt models
                run_result = subprocess.run(
                    ['dbt', 'run', '--profiles-dir', '.', '--target', self.environment],
                    capture_output=True, text=True, timeout=1800
                )
                
                if run_result.returncode != 0:
                    logger.error(f"✗ dbt run failed: {run_result.stderr}")
                    return False
                
                logger.info("✓ dbt transformations completed successfully")
                return True
                
            finally:
                os.chdir(original_cwd)
            
        except Exception as e:
            logger.error(f"❌ dbt transformations failed: {str(e)}")
            return False
    
    def _validate_scd_data(self) -> bool:
        """Validate SCD data in curated table"""
        try:
            logger.info("🔍 Validating SCD data...")
            
            curated_database = self.aws_config['glue']['curated_database']
            
            # Check total records
            query1 = f"SELECT COUNT(*) as total_records FROM {curated_database}.dim_sf_user_scd"
            result1 = self._execute_athena_query(query1)
            
            # Check current records
            query2 = f"SELECT COUNT(*) as current_records FROM {curated_database}.dim_sf_user_scd WHERE is_current = true"
            result2 = self._execute_athena_query(query2)
            
            if result1 and result2:
                total_records = result1[0]['total_records']
                current_records = result2[0]['current_records']
                
                logger.info(f"✓ Total SCD records: {total_records}")
                logger.info(f"✓ Current records: {current_records}")
                
                return total_records > 0 and current_records > 0
            else:
                logger.error("✗ Failed to query SCD data")
                return False
            
        except Exception as e:
            logger.error(f"❌ SCD data validation failed: {str(e)}")
            return False
    
    def _execute_athena_query(self, query: str) -> List[Dict[str, Any]]:
        """Execute Athena query and return results"""
        try:
            response = self.athena_client.start_query_execution(
                QueryString=query,
                ResultConfiguration={
                    'OutputLocation': self.aws_config['s3']['athena_results']
                },
                WorkGroup='primary'
            )
            
            query_execution_id = response['QueryExecutionId']
            
            # Wait for query completion
            max_wait_time = 300  # 5 minutes
            start_time = time.time()
            
            while time.time() - start_time < max_wait_time:
                response = self.athena_client.get_query_execution(QueryExecutionId=query_execution_id)
                state = response['QueryExecution']['Status']['State']
                
                if state == 'SUCCEEDED':
                    # Get results
                    results = self.athena_client.get_query_results(QueryExecutionId=query_execution_id)
                    
                    # Parse results
                    columns = [col['Label'] for col in results['ResultSet']['ResultSetMetadata']['ColumnInfo']]
                    rows = []
                    
                    for row in results['ResultSet']['Rows'][1:]:  # Skip header row
                        row_data = {}
                        for i, col in enumerate(columns):
                            row_data[col] = row['Data'][i].get('VarCharValue', '')
                        rows.append(row_data)
                    
                    return rows
                    
                elif state in ['FAILED', 'CANCELLED']:
                    logger.error(f"Query failed with state: {state}")
                    return []
                
                time.sleep(5)  # Wait 5 seconds before checking again
            
            logger.error("Query timed out")
            return []
            
        except Exception as e:
            logger.error(f"Athena query execution failed: {str(e)}")
            return []

def main():
    """Main execution function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='sf_user Pipeline End-to-End Integration Tests')
    parser.add_argument('--environment', default='development', 
                       choices=['development', 'staging', 'production'],
                       help='Environment to test against')
    
    args = parser.parse_args()
    
    # Initialize and run integration tests
    tester = E2EIntegrationTester(environment=args.environment)
    
    success = tester.run_complete_integration_test()
    
    if success:
        logger.info("🎉 End-to-end integration test completed successfully!")
        sys.exit(0)
    else:
        logger.error("💥 End-to-end integration test failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
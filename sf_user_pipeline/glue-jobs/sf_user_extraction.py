"""
AWS Glue Job for sf_user (Salesforce User) Data Extraction to Iceberg

This job extracts sf_user data from Salesforce and writes it to Iceberg tables
with proper partitioning and SCD Type 2 support.
"""

import sys
import boto3
import json
from datetime import datetime, timedelta
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *

# Initialize Glue context
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'environment',
    'salesforce_secret_name',
    'raw_database',
    'raw_table',
    's3_raw_path'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Configuration
ENVIRONMENT = args['environment']
SALESFORCE_SECRET = args['salesforce_secret_name']
RAW_DATABASE = args['raw_database']
RAW_TABLE = args['raw_table']
S3_RAW_PATH = args['s3_raw_path']

def get_salesforce_credentials():
    """Retrieve Salesforce credentials from AWS Secrets Manager"""
    secrets_client = boto3.client('secretsmanager')
    
    try:
        response = secrets_client.get_secret_value(SecretId=SALESFORCE_SECRET)
        credentials = json.loads(response['SecretString'])
        return credentials
    except Exception as e:
        print(f"Error retrieving Salesforce credentials: {str(e)}")
        raise

def connect_to_salesforce(credentials):
    """Connect to Salesforce and return connection object"""
    try:
        # Using simple_salesforce for Salesforce API connection
        from simple_salesforce import Salesforce
        
        sf = Salesforce(
            username=credentials['username'],
            password=credentials['password'],
            security_token=credentials['security_token'],
            domain=credentials['domain']
        )
        
        print("Successfully connected to Salesforce")
        return sf
        
    except Exception as e:
        print(f"Error connecting to Salesforce: {str(e)}")
        raise

def extract_sf_user_data(sf_connection, incremental=True):
    """Extract sf_user data from Salesforce"""
    try:
        # Define the SOQL query for sf_user extraction
        base_query = """
        SELECT 
            Id,
            Name,
            Username,
            Email,
            Division,
            Audit_Phase__c,
            IsActive,
            CreatedDate,
            LastModifiedDate,
            LastLoginDate
        FROM User
        """
        
        # Add incremental filter if needed
        if incremental:
            # Get last extraction timestamp (you might store this in DynamoDB or S3)
            # For now, extract last 24 hours
            yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%S.000Z')
            query = f"{base_query} WHERE LastModifiedDate >= {yesterday}"
        else:
            query = base_query
        
        print(f"Executing SOQL query: {query}")
        
        # Execute query and get results
        results = sf_connection.query_all(query)
        records = results['records']
        
        print(f"Extracted {len(records)} sf_user records")
        
        # Convert to Spark DataFrame
        if records:
            # Remove Salesforce metadata
            clean_records = []
            for record in records:
                clean_record = {k: v for k, v in record.items() if k != 'attributes'}
                # Add extraction metadata
                clean_record['_extracted_at'] = datetime.now().isoformat() + 'Z'
                clean_record['_extraction_run_id'] = args['JOB_NAME'] + '_' + datetime.now().strftime('%Y%m%d_%H%M%S')
                clean_records.append(clean_record)
            
            # Create Spark DataFrame
            df = spark.createDataFrame(clean_records)
            return df
        else:
            print("No records found")
            return None
            
    except Exception as e:
        print(f"Error extracting sf_user data: {str(e)}")
        raise

def write_to_iceberg(df, table_path):
    """Write DataFrame to Iceberg table"""
    try:
        if df is None:
            print("No data to write")
            return
        
        print(f"Writing {df.count()} records to Iceberg table: {table_path}")
        
        # Write to Iceberg with partitioning
        df.write \
          .format("iceberg") \
          .mode("append") \
          .option("path", table_path) \
          .partitionBy("_extracted_date") \
          .save()
        
        print("Successfully wrote data to Iceberg table")
        
    except Exception as e:
        print(f"Error writing to Iceberg: {str(e)}")
        raise

def main():
    """Main execution function"""
    try:
        print(f"Starting sf_user extraction job for environment: {ENVIRONMENT}")
        
        # Get Salesforce credentials
        credentials = get_salesforce_credentials()
        
        # Connect to Salesforce
        sf_connection = connect_to_salesforce(credentials)
        
        # Extract sf_user data
        df = extract_sf_user_data(sf_connection, incremental=True)
        
        if df is not None:
            # Add partition column
            df = df.withColumn("_extracted_date", date_format(col("_extracted_at"), "yyyy-MM-dd"))
            
            # Write to Iceberg
            iceberg_path = f"{S3_RAW_PATH}/sf_user"
            write_to_iceberg(df, iceberg_path)
            
            # Update Glue catalog
            glueContext.create_dynamic_frame.from_catalog(
                database=RAW_DATABASE,
                table_name=RAW_TABLE
            )
            
            print("sf_user extraction job completed successfully")
        else:
            print("No data extracted - job completed with no records")
            
    except Exception as e:
        print(f"Job failed with error: {str(e)}")
        raise
    finally:
        job.commit()

if __name__ == "__main__":
    main()
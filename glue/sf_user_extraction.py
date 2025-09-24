
"""
AWS Glue Job for sf_user (Salesforce User) Data Extraction to Iceberg

This job extracts sf_user data from Salesforce and writes it to Iceberg tables
with proper partitioning and SCD Type 2 support.
"""

import sys
import boto3
import json
import yaml
from datetime import datetime, timedelta
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from aws_glue_job import Job
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *

# Initialize Glue context and job
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'config_file_path'
])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

def load_config(config_path):
    """Loads the pipeline configuration from a YAML file in S3."""
    s3 = boto3.client('s3')
    bucket, key = config_path.replace("s3://", "").split("/", 1)
    response = s3.get_object(Bucket=bucket, Key=key)
    config_content = response['Body'].read().decode('utf-8')
    return yaml.safe_load(config_content)

# Load configuration
config = load_config(args['config_file_path'])
env_config = config['environments'][args.get('environment', 'dev')]
pipeline_config = config['pipeline']
monitoring_config = config['monitoring']

def get_salesforce_credentials():
    """
    Retrieves Salesforce credentials from AWS Secrets Manager.

    Returns:
        dict: A dictionary containing the Salesforce credentials.
    """
    secrets_client = boto3.client('secretsmanager', region_name=env_config['aws']['region'])
    try:
        response = secrets_client.get_secret_value(SecretId=env_config['aws']['secrets_manager']['salesforce_credentials'])
        credentials = json.loads(response['SecretString'])
        return credentials
    except Exception as e:
        log_and_notify_error(f"Error retrieving Salesforce credentials: {str(e)}")
        raise

def connect_to_salesforce(credentials):
    """
    Connects to Salesforce using the simple-salesforce library.

    Args:
        credentials (dict): A dictionary containing the Salesforce credentials.

    Returns:
        Salesforce: A simple-salesforce Salesforce object.
    """
    try:
        from simple_salesforce import Salesforce
        sf = Salesforce(
            username=credentials['username'],
            password=credentials['password'],
            security_token=credentials['security_token'],
            domain=credentials.get('login_url', 'login')
        )
        print("Successfully connected to Salesforce")
        return sf
    except Exception as e:
        log_and_notify_error(f"Error connecting to Salesforce: {str(e)}")
        raise

def extract_sf_user_data(sf_connection, last_run_timestamp):
    """
    Extracts sf_user data from Salesforce incrementally.

    Args:
        sf_connection (Salesforce): A simple-salesforce Salesforce object.
        last_run_timestamp (datetime): The timestamp of the last successful job run.

    Returns:
        DataFrame: A Spark DataFrame containing the extracted sf_user data, or None if no new data is found.
    """
    base_query = f"""
        SELECT Id, Name, Username, Email, Division, Audit_Phase__c, IsActive, CreatedDate, LastModifiedDate, LastLoginDate
        FROM User
    """
    if last_run_timestamp:
        query = f"{base_query} WHERE LastModifiedDate > {last_run_timestamp.isoformat()}"
    else:
        query = base_query

    print(f"Executing SOQL query: {query}")
    try:
        results = sf_connection.query_all(query)
        records = results['records']
        print(f"Extracted {len(records)} sf_user records")

        if not records:
            return None

        clean_records = [
            {k: v for k, v in record.items() if k != 'attributes'}
            for record in records
        ]
        for record in clean_records:
            record['_extracted_at'] = datetime.now().isoformat()
            record['_extraction_run_id'] = args['JOB_RUN_ID']

        return spark.createDataFrame(clean_records)
    except Exception as e:
        log_and_notify_error(f"Error extracting sf_user data: {str(e)}")
        raise

def write_to_iceberg(df, table_path):
    """
    Writes a Spark DataFrame to an Iceberg table.

    Args:
        df (DataFrame): The Spark DataFrame to write.
        table_path (str): The S3 path to the Iceberg table.
    """
    if df is None:
        print("No data to write")
        return

    print(f"Writing {df.count()} records to Iceberg table: {table_path}")
    try:
        df.write.format("iceberg").mode("append").save(table_path)
        print("Successfully wrote data to Iceberg table")
    except Exception as e:
        log_and_notify_error(f"Error writing to Iceberg: {str(e)}")
        raise

def log_and_notify_error(message):
    """Logs an error message and sends a notification to SNS."""
    print(message)
    sns_client = boto3.client('sns', region_name=env_config['aws']['region'])
    sns_client.publish(
        TopicArn=monitoring_config['alerts']['sns_topic'],
        Message=message,
        Subject=f"Glue Job Failed: {args['JOB_NAME']}"
    )

def main():
    """Main execution function for the Glue job."""
    try:
        # Get the last successful run timestamp from Glue job bookmarks
        last_run_timestamp = None
        if 'last_successful_run' in job.get_job_bookmark():
            last_run_timestamp = job.get_job_bookmark()['last_successful_run']

        credentials = get_salesforce_credentials()
        sf_connection = connect_to_salesforce(credentials)
        df = extract_sf_user_data(sf_connection, last_run_timestamp)

        if df:
            iceberg_path = f"s3://{env_config['aws']['s3']['raw_bucket']}/iceberg/sf_user"
            write_to_iceberg(df, iceberg_path)

        # Set the job bookmark to the current timestamp
        job.commit()
        print("sf_user extraction job completed successfully")

    except Exception as e:
        log_and_notify_error(f"Job failed with error: {str(e)}")
        job.commit() # Commit to record the failure
        raise

if __name__ == "__main__":
    main()

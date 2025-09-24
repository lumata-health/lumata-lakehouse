# Lumata Lakehouse

This project is a modern data lakehouse for Lumata Health analytics. It provides a scalable and maintainable solution for ingesting, processing, and analyzing data from various sources.

## Architecture

The lakehouse is built on AWS and follows a modern data architecture pattern. The main components are:

- **Ingestion:** AWS Glue is used to extract data from various sources, such as Salesforce.
- **Storage:** Amazon S3 is used as the data lake, and Apache Iceberg is used as the table format to provide ACID transactions and other data warehouse-like features.
- **Transformation:** dbt is used for data transformation. It reads the raw data from the lake, applies business logic, and creates curated datasets for analytics.
- **Orchestration:** AWS Step Functions is used to orchestrate the entire data pipeline, from ingestion to transformation.
- **Monitoring:** Amazon CloudWatch is used for monitoring, logging, and alerting.

## sf_user Pipeline

The `sf_user` pipeline is a key component of the Lumata Lakehouse. It ingests `sf_user` data from Salesforce, processes it, and creates a Type 2 Slowly Changing Dimension (SCD) to track historical changes in the `Division` and `Audit_Phase__c` fields.

### Pipeline Components

- **Glue Job:** The `glue/sf_user_extraction.py` script is an AWS Glue job that extracts `sf_user` data from Salesforce and writes it to an Iceberg table in S3.
- **dbt Project:** The `dbt/` directory contains the dbt project for the `sf_user` pipeline. It includes models for staging, transformation, and the final SCD table.
- **Orchestration:** The `orchestration/` directory contains the AWS Step Functions definition and the Amazon EventBridge schedule for the pipeline.
- **Monitoring:** The `monitoring/` directory contains the Amazon CloudWatch monitoring configuration for the pipeline.
- **Configuration:** The `config/config.yml` file contains the configuration for the pipeline.

### How to Run the Pipeline

1. **Configure the pipeline:** Update the `config/config.yml` file with the appropriate settings for your environment.
2. **Deploy the pipeline:** Run the `scripts/deploy.py` script to deploy the pipeline to your AWS account.
3. **Run the tests:** Run the `scripts/run_tests.py` script to run the tests for the pipeline.

## dbt Project

The `dbt/` directory contains the dbt project for the Lumata Lakehouse. To run the dbt project, you need to have dbt installed and configured.

### How to Run dbt

1. **Install dbt:** Follow the instructions in the [dbt documentation](https://docs.getdbt.com/docs/installation) to install dbt.
2. **Configure your profile:** Create a `profiles.yml` file in your `~/.dbt/` directory with the connection details for your data warehouse.
3. **Run dbt:** Run the `dbt run` command to run the dbt project.

## Contributing

Contributions are welcome! Please read the [contributing guidelines](CONTRIBUTING.md) before submitting a pull request.
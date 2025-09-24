-- Iceberg Table DDL for sf_user Pipeline
-- This file contains the DDL statements for creating Iceberg tables in AWS Glue Catalog

-- Raw sf_user table for storing extracted Salesforce data
CREATE TABLE IF NOT EXISTS sf_raw_development.sf_user (
    id string COMMENT 'Salesforce User ID',
    name string COMMENT 'User full name',
    username string COMMENT 'Salesforce username',
    email string COMMENT 'User email address',
    division string COMMENT 'User division (SCD tracked field)',
    audit_phase__c string COMMENT 'Audit phase custom field (SCD tracked field)',
    isactive boolean COMMENT 'Whether user is active',
    createddate timestamp COMMENT 'User creation date',
    lastmodifieddate timestamp COMMENT 'Last modification date',
    lastlogindate timestamp COMMENT 'Last login date',
    _extracted_at timestamp COMMENT 'Extraction timestamp',
    _extraction_run_id string COMMENT 'Extraction job run ID',
    _extracted_date string COMMENT 'Extraction date for partitioning'
) USING iceberg
PARTITIONED BY (_extracted_date)
LOCATION 's3://lumata-lakehouse-development-raw/iceberg/sf_user/'
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='snappy',
    'write.target-file-size-bytes'='134217728',  -- 128MB
    'format-version'='2',
    'write.delete.mode'='merge-on-read',
    'write.update.mode'='merge-on-read',
    'write.merge.mode'='merge-on-read'
);

-- Curated sf_user SCD Type 2 dimension table
CREATE TABLE IF NOT EXISTS sf_curated_development.dim_sf_user_scd (
    user_key bigint COMMENT 'Surrogate key for SCD records',
    user_id string COMMENT 'Natural key - Salesforce User ID',
    name string COMMENT 'User full name',
    username string COMMENT 'Salesforce username',
    email string COMMENT 'User email address',
    division string COMMENT 'User division (SCD tracked field)',
    audit_phase__c string COMMENT 'Audit phase custom field (SCD tracked field)',
    is_active boolean COMMENT 'Whether user is active',
    update_date timestamp COMMENT 'Date of this record version',
    is_current boolean COMMENT 'Flag indicating current record',
    is_deleted boolean COMMENT 'Flag indicating deleted record',
    effective_from timestamp COMMENT 'Start date for this record version',
    effective_to timestamp COMMENT 'End date for this record version',
    _dbt_updated_at timestamp COMMENT 'dbt processing timestamp',
    _scd_id string COMMENT 'Unique SCD record identifier'
) USING iceberg
PARTITIONED BY (is_current, division)
CLUSTERED BY (user_id, update_date) INTO 16 BUCKETS
LOCATION 's3://lumata-lakehouse-development-raw/iceberg/dim_sf_user_scd/'
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='zstd',
    'write.target-file-size-bytes'='268435456',  -- 256MB
    'format-version'='2',
    'write.delete.mode'='merge-on-read',
    'write.update.mode'='merge-on-read',
    'write.merge.mode'='merge-on-read'
);

-- Create staging environment tables (replace development with staging)
CREATE TABLE IF NOT EXISTS sf_raw_staging.sf_user (
    id string COMMENT 'Salesforce User ID',
    name string COMMENT 'User full name',
    username string COMMENT 'Salesforce username',
    email string COMMENT 'User email address',
    division string COMMENT 'User division (SCD tracked field)',
    audit_phase__c string COMMENT 'Audit phase custom field (SCD tracked field)',
    isactive boolean COMMENT 'Whether user is active',
    createddate timestamp COMMENT 'User creation date',
    lastmodifieddate timestamp COMMENT 'Last modification date',
    lastlogindate timestamp COMMENT 'Last login date',
    _extracted_at timestamp COMMENT 'Extraction timestamp',
    _extraction_run_id string COMMENT 'Extraction job run ID',
    _extracted_date string COMMENT 'Extraction date for partitioning'
) USING iceberg
PARTITIONED BY (_extracted_date)
LOCATION 's3://lumata-lakehouse-staging-raw/iceberg/sf_user/'
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='snappy',
    'write.target-file-size-bytes'='134217728',
    'format-version'='2'
);

CREATE TABLE IF NOT EXISTS sf_curated_staging.dim_sf_user_scd (
    user_key bigint COMMENT 'Surrogate key for SCD records',
    user_id string COMMENT 'Natural key - Salesforce User ID',
    name string COMMENT 'User full name',
    username string COMMENT 'Salesforce username',
    email string COMMENT 'User email address',
    division string COMMENT 'User division (SCD tracked field)',
    audit_phase__c string COMMENT 'Audit phase custom field (SCD tracked field)',
    is_active boolean COMMENT 'Whether user is active',
    update_date timestamp COMMENT 'Date of this record version',
    is_current boolean COMMENT 'Flag indicating current record',
    is_deleted boolean COMMENT 'Flag indicating deleted record',
    effective_from timestamp COMMENT 'Start date for this record version',
    effective_to timestamp COMMENT 'End date for this record version',
    _dbt_updated_at timestamp COMMENT 'dbt processing timestamp',
    _scd_id string COMMENT 'Unique SCD record identifier'
) USING iceberg
PARTITIONED BY (is_current, division)
CLUSTERED BY (user_id, update_date) INTO 16 BUCKETS
LOCATION 's3://lumata-lakehouse-staging-raw/iceberg/dim_sf_user_scd/'
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='zstd',
    'write.target-file-size-bytes'='268435456',
    'format-version'='2'
);

-- Create production environment tables (replace development with production)
CREATE TABLE IF NOT EXISTS sf_raw.sf_user (
    id string COMMENT 'Salesforce User ID',
    name string COMMENT 'User full name',
    username string COMMENT 'Salesforce username',
    email string COMMENT 'User email address',
    division string COMMENT 'User division (SCD tracked field)',
    audit_phase__c string COMMENT 'Audit phase custom field (SCD tracked field)',
    isactive boolean COMMENT 'Whether user is active',
    createddate timestamp COMMENT 'User creation date',
    lastmodifieddate timestamp COMMENT 'Last modification date',
    lastlogindate timestamp COMMENT 'Last login date',
    _extracted_at timestamp COMMENT 'Extraction timestamp',
    _extraction_run_id string COMMENT 'Extraction job run ID',
    _extracted_date string COMMENT 'Extraction date for partitioning'
) USING iceberg
PARTITIONED BY (_extracted_date)
LOCATION 's3://lumata-lakehouse-prod-raw/iceberg/sf_user/'
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='snappy',
    'write.target-file-size-bytes'='134217728',
    'format-version'='2'
);

CREATE TABLE IF NOT EXISTS sf_curated.dim_sf_user_scd (
    user_key bigint COMMENT 'Surrogate key for SCD records',
    user_id string COMMENT 'Natural key - Salesforce User ID',
    name string COMMENT 'User full name',
    username string COMMENT 'Salesforce username',
    email string COMMENT 'User email address',
    division string COMMENT 'User division (SCD tracked field)',
    audit_phase__c string COMMENT 'Audit phase custom field (SCD tracked field)',
    is_active boolean COMMENT 'Whether user is active',
    update_date timestamp COMMENT 'Date of this record version',
    is_current boolean COMMENT 'Flag indicating current record',
    is_deleted boolean COMMENT 'Flag indicating deleted record',
    effective_from timestamp COMMENT 'Start date for this record version',
    effective_to timestamp COMMENT 'End date for this record version',
    _dbt_updated_at timestamp COMMENT 'dbt processing timestamp',
    _scd_id string COMMENT 'Unique SCD record identifier'
) USING iceberg
PARTITIONED BY (is_current, division)
CLUSTERED BY (user_id, update_date) INTO 16 BUCKETS
LOCATION 's3://lumata-lakehouse-prod-raw/iceberg/dim_sf_user_scd/'
TBLPROPERTIES (
    'write.format.default'='parquet',
    'write.parquet.compression-codec'='zstd',
    'write.target-file-size-bytes'='268435456',
    'format-version'='2'
);
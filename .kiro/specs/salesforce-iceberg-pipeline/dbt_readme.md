# dbt (Data Build Tool) Complete Guide

## What is dbt?

**dbt (Data Build Tool)** is a command-line tool that enables data analysts and engineers to transform data in their warehouse more effectively. Think of it as "Git for SQL" - it allows you to:

- Write **SQL SELECT statements** that become **tables and views**
- **Version control** your transformations
- **Test** your data for quality
- **Document** your data models
- Create **dependencies** between models

### Key Concepts

1. **Models**: SQL files that define transformations (SELECT statements)
2. **Sources**: Raw data tables (your Salesforce Iceberg tables)
3. **Seeds**: CSV files with static data
4. **Tests**: Data quality checks
5. **Macros**: Reusable SQL functions
6. **Snapshots**: SCD Type 2 implementations

## dbt Installation and Setup

### Step 1: Install dbt

```bash
# Install dbt with Spark adapter (for Iceberg support)
pip install dbt-spark[PyHive]==1.6.0

# Verify installation
dbt --version
```

### Step 2: Initialize dbt Project

```bash
# Create new dbt project
dbt init salesforce_dw

# Navigate to project directory
cd salesforce_dw
```

### Step 3: Configure Connection (profiles.yml)

Create `~/.dbt/profiles.yml` (or in your project directory):

```yaml
salesforce_dw:
  target: dev
  outputs:
    dev:
      type: spark
      method: session
      host: cluster
      catalog: glue_catalog
      schema: salesforce_raw_dev
      table_format: iceberg
      
    prod:
      type: spark
      method: session  
      host: cluster
      catalog: glue_catalog
      schema: salesforce_raw_prod
      table_format: iceberg
```

## dbt Project Structure Explained

```
salesforce_dw/
├── dbt_project.yml          # Project configuration
├── profiles.yml             # Connection settings
├── models/                  # SQL transformation files
│   ├── staging/            # Raw data cleaning
│   ├── intermediate/       # Business logic
│   └── marts/             # Final analytics tables
├── macros/                 # Reusable SQL functions
├── tests/                  # Custom data tests
├── seeds/                  # Static reference data
├── snapshots/             # SCD Type 2 tables
└── analysis/              # Ad-hoc analysis queries
```

## Step-by-Step Implementation

### Step 1: Configure dbt Project

**File**: `dbt_project.yml`

```yaml
name: 'salesforce_dw'
version: '1.0.0'
config-version: 2

# Connection profile name
profile: 'salesforce_dw'

# Directory paths
model-paths: ["models"]
analysis-paths: ["analysis"]  
test-paths: ["tests"]
seed-paths: ["data"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

# Build artifacts
target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

# Global model configurations
models:
  salesforce_dw:
    # All models use Iceberg format
    +file_format: iceberg
    +table_properties:
      write.format.default: parquet
      write.parquet.compression-codec: snappy
    
    # Staging models (raw data cleaning)
    staging:
      +materialized: view
      
    # Intermediate models (business logic)  
    intermediate:
      +materialized: ephemeral
      
    # Mart models (final analytics tables)
    marts:
      +materialized: incremental
      +incremental_strategy: merge
      +on_schema_change: sync_all_columns

# Test configurations
tests:
  +store_failures: true
  +schema: dbt_test_failures
```

### Step 2: Define Sources (Raw Salesforce Data)

**File**: `models/staging/_sources.yml`

```yaml
version: 2

sources:
  - name: salesforce_raw
    description: "Raw Salesforce data extracted via Glue"
    database: glue_catalog
    schema: salesforce_raw_dev
    
    tables:
      - name: account
        description: "Salesforce Account records"
        columns:
          - name: id
            description: "Salesforce Account ID"
            tests:
              - unique
              - not_null
          - name: name
            description: "Account name"
          - name: lastmodifieddate
            description: "Last modified timestamp"
          - name: _extracted_at
            description: "Data extraction timestamp"
            
      - name: contact
        description: "Salesforce Contact records"
        columns:
          - name: id
            description: "Salesforce Contact ID"
            tests:
              - unique
              - not_null
          - name: accountid
            description: "Related Account ID"
          - name: firstname
            description: "Contact first name"
          - name: lastname
            description: "Contact last name"
            
      - name: case
        description: "Salesforce Case records"
        columns:
          - name: id
            description: "Salesforce Case ID"
            tests:
              - unique
              - not_null
          - name: accountid
            description: "Related Account ID"
          - name: status
            description: "Case status"
```

### Step 3: Create Staging Models (Data Cleaning)

**File**: `models/staging/stg_sf_account.sql`

```sql
{{ config(
    materialized='view',
    description='Cleaned Salesforce Account data'
) }}

select 
    -- Primary key
    id as account_id,
    
    -- Account information
    name as account_name,
    type as account_type,
    
    -- Address fields
    billingstreet as billing_street,
    billingcity as billing_city,
    billingstate as billing_state,
    billingpostalcode as billing_postal_code,
    billingcountry as billing_country,
    
    -- Metadata
    lastmodifieddate,
    isdeleted,
    _extracted_at,
    
    -- Data quality flags
    case 
        when name is null or trim(name) = '' then true 
        else false 
    end as has_missing_name,
    
    case 
        when billingstreet is not null then true 
        else false 
    end as has_billing_address

from {{ source('salesforce_raw', 'account') }}

-- Filter out test accounts (optional)
where not (
    lower(name) like '%test%' 
    or lower(name) like '%demo%'
)
```

**File**: `models/staging/stg_sf_contact.sql`

```sql
{{ config(
    materialized='view',
    description='Cleaned Salesforce Contact data'
) }}

select 
    -- Primary key
    id as contact_id,
    
    -- Foreign keys
    accountid as account_id,
    
    -- Contact information
    firstname,
    lastname,
    concat_ws(' ', firstname, lastname) as full_name,
    email,
    phone,
    
    -- Metadata
    lastmodifieddate,
    isdeleted,
    _extracted_at,
    
    -- Data quality flags
    case 
        when email is null or not email like '%@%' then true 
        else false 
    end as has_invalid_email

from {{ source('salesforce_raw', 'contact') }}
```

### Step 4: Create Address Normalization Macros

**File**: `macros/address_normalization.sql`

```sql
{# Macro to normalize addresses and generate location IDs #}
{% macro normalize_address(street, city, state, postal_code, country) %}
    struct(
        {{ generate_location_id(street, city, state, postal_code) }} as location_id,
        {{ standardize_street(street) }} as street,
        {{ standardize_city(city) }} as city,
        {{ standardize_state(state) }} as state,
        {{ standardize_postal_code(postal_code) }} as postal_code,
        {{ standardize_country(country) }} as country
    )
{% endmacro %}

{# Generate stable location ID from address components #}
{% macro generate_location_id(street, city, state, postal_code) %}
    abs(hash(
        concat_ws('|',
            coalesce({{ standardize_street(street) }}, ''),
            coalesce({{ standardize_city(city) }}, ''),
            coalesce({{ standardize_state(state) }}, ''),
            coalesce({{ standardize_postal_code(postal_code) }}, '')
        )
    ))
{% endmacro %}

{# Standardize street address #}
{% macro standardize_street(street) %}
    upper(trim(regexp_replace({{ street }}, '\\s+', ' ')))
{% endmacro %}

{# Standardize city name #}
{% macro standardize_city(city) %}
    upper(trim({{ city }}))
{% endmacro %}

{# Standardize state code #}
{% macro standardize_state(state) %}
    case 
        when upper(trim({{ state }})) in ('CALIFORNIA', 'CA') then 'CA'
        when upper(trim({{ state }})) in ('NEW YORK', 'NY') then 'NY'
        when upper(trim({{ state }})) in ('TEXAS', 'TX') then 'TX'
        when upper(trim({{ state }})) in ('FLORIDA', 'FL') then 'FL'
        else upper(trim({{ state }}))
    end
{% endmacro %}

{# Standardize postal code #}
{% macro standardize_postal_code(postal_code) %}
    regexp_replace({{ postal_code }}, '[^0-9]', '')
{% endmacro %}

{# Standardize country code #}
{% macro standardize_country(country) %}
    case 
        when upper(trim(coalesce({{ country }}, ''))) in ('UNITED STATES', 'USA', 'US', '') then 'US'
        when upper(trim({{ country }})) = 'CANADA' then 'CA'
        else upper(trim(coalesce({{ country }}, 'US')))
    end
{% endmacro %}
```

### Step 5: Create Intermediate Models (Business Logic)

**File**: `models/intermediate/int_addresses_normalized.sql`

```sql
{{ config(
    materialized='ephemeral',
    description='Normalized addresses with stable location IDs'
) }}

with unique_addresses as (
    select distinct
        billing_street,
        billing_city, 
        billing_state,
        billing_postal_code,
        billing_country
    from {{ ref('stg_sf_account') }}
    where billing_street is not null
),

normalized_addresses as (
    select 
        {{ normalize_address(
            'billing_street', 
            'billing_city', 
            'billing_state', 
            'billing_postal_code', 
            'billing_country'
        ) }} as normalized_address,
        
        -- Keep original for reference
        billing_street as original_street,
        billing_city as original_city,
        billing_state as original_state,
        billing_postal_code as original_postal_code,
        billing_country as original_country
        
    from unique_addresses
)

select * from normalized_addresses
```

### Step 6: Create Mart Models (SCD Type 2)

**File**: `models/marts/dim_account.sql`

```sql
{{ config(
    materialized='incremental',
    file_format='iceberg',
    incremental_strategy='merge',
    unique_key='account_id',
    merge_update_columns=['account_name', 'account_type', 'billing_street', 'billing_city'],
    description='Account dimension with SCD Type 2 history'
) }}

with source_data as (
    select * from {{ ref('stg_sf_account') }}
    
    {% if is_incremental() %}
        -- Only process records modified since last run
        where lastmodifieddate > (
            select max(start_date) 
            from {{ this }}
        )
    {% endif %}
),

address_lookup as (
    select * from {{ ref('int_addresses_normalized') }}
),

accounts_with_addresses as (
    select 
        s.*,
        a.normalized_address
    from source_data s
    left join address_lookup a
        on s.billing_street = a.original_street
        and s.billing_city = a.original_city
        and s.billing_state = a.original_state
        and s.billing_postal_code = a.original_postal_code
        and s.billing_country = a.original_country
),

final as (
    select 
        -- Surrogate key (unique for each version)
        {{ dbt_utils.generate_surrogate_key(['account_id', 'lastmodifieddate']) }} as account_key,
        
        -- Natural key
        account_id,
        
        -- Attributes
        account_name,
        account_type,
        normalized_address,
        
        -- SCD Type 2 fields
        lastmodifieddate as start_date,
        null as end_date,
        true as is_current,
        isdeleted as is_deleted,
        
        -- Metadata
        current_timestamp() as _dbt_updated_at,
        _extracted_at

    from accounts_with_addresses
)

select * from final
```

### Step 7: Create Data Quality Tests

**File**: `models/marts/_schema.yml`

```yaml
version: 2

models:
  - name: dim_account
    description: "Account dimension with SCD Type 2 history"
    
    tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - account_id
            - start_date
    
    columns:
      - name: account_key
        description: "Surrogate key for each account version"
        tests:
          - unique
          - not_null
          
      - name: account_id
        description: "Salesforce Account ID (natural key)"
        tests:
          - not_null
          
      - name: account_name
        description: "Account name"
        tests:
          - not_null
          
      - name: normalized_address
        description: "Standardized address with location ID"
        
      - name: start_date
        description: "When this version became effective"
        tests:
          - not_null
          
      - name: is_current
        description: "True for current version of each account"
        tests:
          - accepted_values:
              values: [true, false]
```

### Step 8: Create Custom Tests

**File**: `tests/assert_one_current_record_per_account.sql`

```sql
-- Test that each account has exactly one current record
select 
    account_id,
    count(*) as current_record_count
from {{ ref('dim_account') }}
where is_current = true
group by account_id
having count(*) != 1
```

## dbt Commands Reference

### Development Commands

```bash
# Install dependencies
dbt deps

# Test connection
dbt debug

# Compile models (check SQL syntax)
dbt compile

# Run specific model
dbt run --models stg_sf_account

# Run all staging models
dbt run --models staging

# Run models and downstream dependencies
dbt run --models stg_sf_account+

# Run models and upstream dependencies  
dbt run --models +dim_account

# Test data quality
dbt test

# Test specific model
dbt test --models dim_account

# Generate documentation
dbt docs generate

# Serve documentation locally
dbt docs serve
```

### Production Commands

```bash
# Full refresh (rebuild all incremental models)
dbt run --full-refresh

# Run and test everything
dbt build

# Run with specific target
dbt run --target prod

# Run with variables
dbt run --vars '{"start_date": "2024-01-01"}'
```

## Running dbt in AWS Glue

### Create dbt Runner Glue Job

**File**: `glue-jobs/dbt_runner.py`

```python
import sys
import subprocess
import os
from awsglue.utils import getResolvedOptions

def run_dbt_command(command, project_dir):
    """Run dbt command and handle errors"""
    try:
        result = subprocess.run(
            command,
            shell=True,
            cwd=project_dir,
            check=True,
            capture_output=True,
            text=True
        )
        print(f"Success: {result.stdout}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error: {e.stderr}")
        return False

def main():
    # Get job parameters
    args = getResolvedOptions(sys.argv, ['JOB_NAME', 'dbt_command'])
    
    # Download dbt project from S3
    project_dir = "/tmp/dbt_project"
    os.makedirs(project_dir, exist_ok=True)
    
    # Sync dbt project from S3
    subprocess.run(f"aws s3 sync s3://lumata-glue-scripts-dev-282815445946/dbt-project/ {project_dir}/", shell=True)
    
    # Set up dbt profiles directory
    profiles_dir = "/tmp/dbt_profiles"
    os.makedirs(profiles_dir, exist_ok=True)
    subprocess.run(f"aws s3 sync s3://lumata-glue-scripts-dev-282815445946/dbt-profiles/ {profiles_dir}/", shell=True)
    
    # Set environment variables
    os.environ['DBT_PROFILES_DIR'] = profiles_dir
    
    # Run dbt command
    dbt_command = args.get('dbt_command', 'dbt run')
    success = run_dbt_command(dbt_command, project_dir)
    
    if not success:
        sys.exit(1)
    
    print("dbt execution completed successfully!")

if __name__ == "__main__":
    main()
```

## Best Practices

### 1. Model Organization
- **Staging**: Clean and standardize raw data
- **Intermediate**: Business logic and calculations  
- **Marts**: Final analytics-ready tables

### 2. Naming Conventions
- **Staging models**: `stg_<source>_<table>`
- **Intermediate models**: `int_<business_concept>`
- **Mart models**: `dim_<entity>` or `fact_<event>`

### 3. Incremental Models
```sql
{{ config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge'
) }}

select * from source_table

{% if is_incremental() %}
    where updated_at > (select max(updated_at) from {{ this }})
{% endif %}
```

### 4. Testing Strategy
- Test **primary keys** (unique, not null)
- Test **foreign key relationships**
- Test **business rules** (custom tests)
- Test **data freshness**

### 5. Documentation
```sql
{{ config(
    description='Account dimension with SCD Type 2 history'
) }}

-- This model creates a slowly changing dimension for accounts
-- It tracks historical changes to account attributes
select ...
```

## Troubleshooting Common Issues

### 1. Connection Issues
```bash
# Test connection
dbt debug

# Check profiles.yml location
echo $DBT_PROFILES_DIR
```

### 2. Model Compilation Errors
```bash
# Compile without running
dbt compile --models problematic_model

# Check compiled SQL
cat target/compiled/salesforce_dw/models/marts/dim_account.sql
```

### 3. Incremental Model Issues
```bash
# Full refresh to rebuild
dbt run --models dim_account --full-refresh

# Check incremental logic
dbt compile --models dim_account
```

### 4. Test Failures
```bash
# Run tests with details
dbt test --store-failures

# Check failed test results
select * from dbt_test_failures.assert_one_current_record_per_account
```

This comprehensive guide should get you started with dbt for the Salesforce Iceberg pipeline. The key is to start simple with staging models and gradually build up to more complex transformations and SCD Type 2 implementations.
#!/bin/bash

# Pipeline execution script
set -e

echo "🔄 Running sf_user pipeline..."

PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="dev"
FULL_REFRESH=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --full-refresh)
            FULL_REFRESH=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --env ENV          Environment (dev, staging, prod)"
            echo "  --full-refresh     Force full refresh"
            echo "  --help             Show help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_status "Environment: $ENVIRONMENT"
print_status "Full refresh: $FULL_REFRESH"

# Step 1: Validate credentials
validate_credentials() {
    print_status "Validating Salesforce credentials..."
    
    local secret_name="salesforce/${ENVIRONMENT}/credentials"
    if aws secretsmanager get-secret-value --secret-id "$secret_name" --region us-east-1 &> /dev/null; then
        print_status "Credentials validated ✓"
    else
        print_error "Credentials not found: $secret_name"
        exit 1
    fi
}

# Step 2: Run dbtHub ingestion
run_ingestion() {
    print_status "Running dbtHub ingestion..."
    
    cd "$PIPELINE_DIR/ingestion"
    
    local cmd="dbthub run --config dbthub.yml"
    if [[ "$FULL_REFRESH" == "true" ]]; then
        cmd="$cmd --full-refresh"
    fi
    
    export DBTHUB_ENV="$ENVIRONMENT"
    
    if command -v dbthub &> /dev/null; then
        eval "$cmd"
        print_status "Ingestion completed ✓"
    else
        print_warning "dbtHub not available, skipping ingestion"
    fi
    
    cd "$PIPELINE_DIR"
}

# Step 3: Run dbt transformations
run_transformations() {
    print_status "Running dbt transformations..."
    
    cd "$PIPELINE_DIR/transformations"
    
    local cmd="dbt run --profiles-dir . --target $ENVIRONMENT"
    if [[ "$FULL_REFRESH" == "true" ]]; then
        cmd="$cmd --full-refresh"
    fi
    
    eval "$cmd"
    print_status "Transformations completed ✓"
    
    # Run tests
    print_status "Running dbt tests..."
    dbt test --profiles-dir . --target "$ENVIRONMENT"
    print_status "Tests completed ✓"
    
    cd "$PIPELINE_DIR"
}

# Step 4: Generate summary
generate_summary() {
    print_status "Pipeline summary:"
    print_status "  - Environment: $ENVIRONMENT"
    print_status "  - Full refresh: $FULL_REFRESH"
    print_status "  - Status: SUCCESS"
}

main() {
    validate_credentials
    run_ingestion
    run_transformations
    generate_summary
    
    print_status "🎉 Pipeline completed successfully!"
}

main "$@"
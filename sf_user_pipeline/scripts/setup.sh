#!/bin/bash

# Setup script for sf_user pipeline infrastructure
set -e

echo "🚀 Setting up sf_user pipeline..."

PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_REGION="us-east-1"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not installed"
        exit 1
    fi
    
    if ! command -v dbt &> /dev/null; then
        print_error "dbt not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    print_status "Prerequisites check passed ✓"
}

# Create Glue databases
create_databases() {
    print_status "Creating Glue databases..."
    
    aws glue create-database \
        --database-input Name=sf_raw,Description="Raw Salesforce data" \
        --region $AWS_REGION 2>/dev/null || print_warning "sf_raw may exist"
    
    aws glue create-database \
        --database-input Name=sf_curated,Description="Curated Salesforce data" \
        --region $AWS_REGION 2>/dev/null || print_warning "sf_curated may exist"
    
    print_status "Databases created ✓"
}

# Initialize dbt
initialize_dbt() {
    print_status "Initializing dbt..."
    
    cd "$PIPELINE_DIR/transformations"
    
    if dbt debug --profiles-dir .; then
        print_status "dbt connection verified ✓"
    else
        print_error "dbt connection failed"
        exit 1
    fi
    
    cd "$PIPELINE_DIR"
}

# Setup monitoring
setup_monitoring() {
    print_status "Setting up monitoring..."
    
    aws logs create-log-group \
        --log-group-name /aws/sf-user-pipeline \
        --region $AWS_REGION 2>/dev/null || print_warning "Log group may exist"
    
    print_status "Monitoring setup ✓"
}

main() {
    check_prerequisites
    create_databases
    initialize_dbt
    setup_monitoring
    
    print_status "🎉 Setup completed!"
    echo ""
    print_status "Next steps:"
    echo "1. Configure Salesforce credentials in AWS Secrets Manager"
    echo "2. Create Iceberg tables: execute config/iceberg-tables.sql"
    echo "3. Run pipeline: ./scripts/run.sh --env dev"
}

main "$@"
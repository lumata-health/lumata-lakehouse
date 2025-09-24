#!/bin/bash

# Quick deployment script for sf_user pipeline in lumata-lakehouse
# This script provides a simple interface for deploying the pipeline

set -e  # Exit on any error

echo "🚀 sf_user Pipeline Quick Deploy Script"
echo "======================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local level=$1
    local message=$2
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    print_status "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_status "ERROR" "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_status "ERROR" "AWS credentials not configured. Run 'aws configure'."
        exit 1
    fi
    
    # Check Python
    if ! command -v python &> /dev/null && ! command -v python3 &> /dev/null; then
        print_status "ERROR" "Python not found. Please install Python 3.8+."
        exit 1
    fi
    
    print_status "INFO" "Prerequisites check passed ✓"
}

# Install Python dependencies
install_dependencies() {
    print_status "INFO" "Installing Python dependencies..."
    
    # Try to install required packages
    pip install boto3 pyyaml simple-salesforce dbt-core dbt-athena-community || {
        print_status "WARN" "Failed to install some packages. You may need to install them manually."
    }
    
    print_status "INFO" "Dependencies installation completed ✓"
}

# Get user input for deployment
get_deployment_config() {
    echo ""
    print_status "INFO" "Please provide deployment configuration:"
    
    # Environment
    read -p "Environment (development/staging/production) [development]: " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-development}
    
    # Salesforce credentials
    read -p "Salesforce Username: " SF_USERNAME
    read -s -p "Salesforce Password: " SF_PASSWORD
    echo ""
    read -s -p "Salesforce Security Token: " SF_TOKEN
    echo ""
    
    # Validate inputs
    if [[ -z "$SF_USERNAME" || -z "$SF_PASSWORD" || -z "$SF_TOKEN" ]]; then
        print_status "ERROR" "All Salesforce credentials are required."
        exit 1
    fi
    
    print_status "INFO" "Configuration collected ✓"
}

# Deploy the pipeline
deploy_pipeline() {
    print_status "INFO" "Deploying sf_user pipeline to $ENVIRONMENT environment..."
    
    # Run the deployment script
    python deploy.py \
        --environment "$ENVIRONMENT" \
        --sf-username "$SF_USERNAME" \
        --sf-password "$SF_PASSWORD" \
        --sf-token "$SF_TOKEN"
    
    if [ $? -eq 0 ]; then
        print_status "INFO" "Pipeline deployment completed successfully ✓"
    else
        print_status "ERROR" "Pipeline deployment failed"
        exit 1
    fi
}

# Test the deployment
test_deployment() {
    print_status "INFO" "Testing the deployed pipeline..."
    
    # Test Salesforce connection
    python -c "
import boto3, json
from simple_salesforce import Salesforce
try:
    secrets = boto3.client('secretsmanager')
    creds = json.loads(secrets.get_secret_value(SecretId='salesforce/$ENVIRONMENT/credentials')['SecretString'])
    sf = Salesforce(**creds)
    print('✓ Salesforce connection test passed')
except Exception as e:
    print(f'✗ Salesforce connection test failed: {e}')
    exit(1)
"
    
    # Run end-to-end test if available
    if [ -f "tests/test_e2e_integration.py" ]; then
        print_status "INFO" "Running end-to-end integration test..."
        python tests/test_e2e_integration.py --environment "$ENVIRONMENT" || {
            print_status "WARN" "End-to-end test failed. Check the logs for details."
        }
    fi
    
    print_status "INFO" "Testing completed ✓"
}

# Show next steps
show_next_steps() {
    echo ""
    print_status "INFO" "🎉 Deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Run the Glue job:"
    echo "   aws glue start-job-run --job-name sf-user-extraction-$ENVIRONMENT"
    echo ""
    echo "2. Check raw data in Athena:"
    echo "   SELECT * FROM sf_raw_$ENVIRONMENT.sf_user LIMIT 10;"
    echo ""
    echo "3. Run dbt transformations:"
    echo "   cd transformations && dbt run --profiles-dir . --target ${ENVIRONMENT:0:3}"
    echo ""
    echo "4. Check SCD data in Athena:"
    echo "   SELECT * FROM sf_curated_$ENVIRONMENT.dim_sf_user_scd LIMIT 10;"
    echo ""
    echo "5. Monitor the pipeline:"
    echo "   - CloudWatch Logs: /aws-glue/jobs/sf-user-extraction-$ENVIRONMENT"
    echo "   - AWS Glue Console: Check job runs and metrics"
    echo ""
}

# Main execution
main() {
    echo ""
    print_status "INFO" "Starting sf_user pipeline deployment in lumata-lakehouse..."
    
    # Change to pipeline directory
    cd "$(dirname "$0")/.."
    
    # Execute deployment steps
    check_prerequisites
    install_dependencies
    get_deployment_config
    deploy_pipeline
    test_deployment
    show_next_steps
    
    print_status "INFO" "All done! Your sf_user pipeline is ready to use."
}

# Execute main function
main "$@"
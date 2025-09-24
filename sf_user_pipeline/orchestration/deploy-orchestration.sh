#!/bin/bash

# sf_user Pipeline Orchestration Deployment Script
# Deploys Step Functions workflow and EventBridge scheduling infrastructure

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STACK_NAME_PREFIX="sf-user-pipeline-orchestration"
TEMPLATE_FILE="$SCRIPT_DIR/orchestration-infrastructure.yml"

# Default values
ENVIRONMENT="dev"
AWS_REGION="us-east-1"
ACCOUNT_ID=""
GLUE_JOB_NAME="sf-user-ingestion-job"
S3_BUCKET_NAME="lumata-salesforce-lakehouse-iceberg-dev"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy sf_user pipeline orchestration infrastructure (Step Functions + EventBridge)

OPTIONS:
    -e, --environment ENV       Environment (dev, staging, prod) [default: dev]
    -r, --region REGION         AWS region [default: us-east-1]
    -a, --account-id ID         AWS Account ID (required)
    -g, --glue-job-name NAME    Glue job name [default: sf-user-ingestion-job]
    -b, --bucket-name NAME      S3 bucket name [default: lumata-salesforce-lakehouse-iceberg-dev]
    -h, --help                  Show this help message

EXAMPLES:
    # Deploy to dev environment
    $0 --environment dev --account-id 123456789012

    # Deploy to production with custom settings
    $0 --environment prod --account-id 123456789012 --region us-west-2

    # Deploy with custom Glue job name
    $0 --environment staging --account-id 123456789012 --glue-job-name custom-sf-user-job

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -a|--account-id)
            ACCOUNT_ID="$2"
            shift 2
            ;;
        -g|--glue-job-name)
            GLUE_JOB_NAME="$2"
            shift 2
            ;;
        -b|--bucket-name)
            S3_BUCKET_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$ACCOUNT_ID" ]]; then
    print_error "Account ID is required. Use --account-id option."
    show_usage
    exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_error "Environment must be one of: dev, staging, prod"
    exit 1
fi

# Set stack name
STACK_NAME="${STACK_NAME_PREFIX}-${ENVIRONMENT}"

print_status "Starting sf_user pipeline orchestration deployment..."
print_status "Environment: $ENVIRONMENT"
print_status "Region: $AWS_REGION"
print_status "Account ID: $ACCOUNT_ID"
print_status "Stack Name: $STACK_NAME"
print_status "Glue Job Name: $GLUE_JOB_NAME"
print_status "S3 Bucket: $S3_BUCKET_NAME"

# Validate AWS CLI and credentials
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed or not in PATH"
    exit 1
fi

print_status "Validating AWS credentials..."
if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
    print_error "AWS credentials not configured or invalid"
    exit 1
fi

# Validate CloudFormation template
print_status "Validating CloudFormation template..."
if ! aws cloudformation validate-template \
    --template-body "file://$TEMPLATE_FILE" \
    --region "$AWS_REGION" &> /dev/null; then
    print_error "CloudFormation template validation failed"
    exit 1
fi

print_success "Template validation passed"

# Check if stack exists
print_status "Checking if stack exists..."
STACK_EXISTS=false
if aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" &> /dev/null; then
    STACK_EXISTS=true
    print_status "Stack exists - will update"
else
    print_status "Stack does not exist - will create"
fi

# Prepare CloudFormation parameters
PARAMETERS=(
    "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
    "ParameterKey=AccountId,ParameterValue=$ACCOUNT_ID"
    "ParameterKey=GlueJobName,ParameterValue=$GLUE_JOB_NAME"
    "ParameterKey=S3BucketName,ParameterValue=$S3_BUCKET_NAME"
)

# Deploy or update stack
if [[ "$STACK_EXISTS" == "true" ]]; then
    print_status "Updating CloudFormation stack..."
    CHANGE_SET_NAME="sf-user-pipeline-update-$(date +%Y%m%d-%H%M%S)"
    
    # Create change set
    aws cloudformation create-change-set \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters "${PARAMETERS[@]}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION"
    
    print_status "Waiting for change set creation..."
    aws cloudformation wait change-set-create-complete \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME" \
        --region "$AWS_REGION"
    
    # Describe changes
    print_status "Change set created. Reviewing changes..."
    aws cloudformation describe-change-set \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME" \
        --region "$AWS_REGION" \
        --query 'Changes[].{Action:Action,ResourceType:ResourceChange.ResourceType,LogicalId:ResourceChange.LogicalResourceId}' \
        --output table
    
    # Execute change set
    print_status "Executing change set..."
    aws cloudformation execute-change-set \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME" \
        --region "$AWS_REGION"
    
    print_status "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION"
else
    print_status "Creating CloudFormation stack..."
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters "${PARAMETERS[@]}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --enable-termination-protection \
        --region "$AWS_REGION"
    
    print_status "Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION"
fi

# Get stack outputs
print_status "Retrieving stack outputs..."
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs' \
    --output json)

if [[ "$OUTPUTS" != "null" && "$OUTPUTS" != "[]" ]]; then
    print_success "Stack deployment completed successfully!"
    echo
    print_status "Stack Outputs:"
    echo "$OUTPUTS" | jq -r '.[] | "  \(.OutputKey): \(.OutputValue)"'
    echo
    
    # Extract key outputs
    STATE_MACHINE_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="StateMachineArn") | .OutputValue')
    SNS_TOPIC_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="SNSTopicArn") | .OutputValue')
    
    print_status "Key Resources Created:"
    echo "  Step Functions State Machine: $STATE_MACHINE_ARN"
    echo "  SNS Alerts Topic: $SNS_TOPIC_ARN"
    echo
else
    print_warning "No stack outputs available"
fi

# Verify Step Functions state machine
print_status "Verifying Step Functions state machine..."
if aws stepfunctions describe-state-machine \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --region "$AWS_REGION" &> /dev/null; then
    print_success "Step Functions state machine is active and ready"
else
    print_warning "Could not verify Step Functions state machine status"
fi

# Verify EventBridge rule
print_status "Verifying EventBridge schedule rule..."
RULE_NAME="sf-user-pipeline-schedule-${ENVIRONMENT}"
if aws events describe-rule \
    --name "$RULE_NAME" \
    --region "$AWS_REGION" &> /dev/null; then
    print_success "EventBridge schedule rule is active"
    
    # Show rule details
    RULE_STATE=$(aws events describe-rule \
        --name "$RULE_NAME" \
        --region "$AWS_REGION" \
        --query 'State' \
        --output text)
    SCHEDULE_EXPRESSION=$(aws events describe-rule \
        --name "$RULE_NAME" \
        --region "$AWS_REGION" \
        --query 'ScheduleExpression' \
        --output text)
    
    print_status "Schedule Details:"
    echo "  Rule State: $RULE_STATE"
    echo "  Schedule: $SCHEDULE_EXPRESSION (6-hourly execution)"
else
    print_warning "Could not verify EventBridge rule status"
fi

print_success "sf_user pipeline orchestration deployment completed!"
print_status "Next steps:"
echo "  1. Configure SNS topic subscriptions for alerts"
echo "  2. Deploy Lambda functions for pipeline validation and error handling"
echo "  3. Test pipeline execution manually before enabling schedule"
echo "  4. Monitor CloudWatch logs and metrics"

# Save deployment information
DEPLOYMENT_INFO_FILE="$PROJECT_ROOT/deployment-info-${ENVIRONMENT}.json"
cat > "$DEPLOYMENT_INFO_FILE" << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "$ENVIRONMENT",
  "aws_region": "$AWS_REGION",
  "account_id": "$ACCOUNT_ID",
  "stack_name": "$STACK_NAME",
  "state_machine_arn": "$STATE_MACHINE_ARN",
  "sns_topic_arn": "$SNS_TOPIC_ARN",
  "glue_job_name": "$GLUE_JOB_NAME",
  "s3_bucket_name": "$S3_BUCKET_NAME"
}
EOF

print_status "Deployment information saved to: $DEPLOYMENT_INFO_FILE"
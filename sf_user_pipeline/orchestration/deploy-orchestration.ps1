# sf_user Pipeline Orchestration Deployment Script (PowerShell)
# Deploys Step Functions workflow and EventBridge scheduling infrastructure

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1",
    
    [Parameter(Mandatory=$true)]
    [string]$AccountId,
    
    [Parameter(Mandatory=$false)]
    [string]$GlueJobName = "sf-user-ingestion-job",
    
    [Parameter(Mandatory=$false)]
    [string]$S3BucketName = "lumata-salesforce-lakehouse-iceberg-dev",
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host @"
sf_user Pipeline Orchestration Deployment Script

DESCRIPTION:
    Deploys Step Functions workflow and EventBridge scheduling infrastructure
    for the sf_user pipeline orchestration.

PARAMETERS:
    -Environment    Environment (dev, staging, prod) [default: dev]
    -Region         AWS region [default: us-east-1]
    -AccountId      AWS Account ID (required)
    -GlueJobName    Glue job name [default: sf-user-ingestion-job]
    -S3BucketName   S3 bucket name [default: lumata-salesforce-lakehouse-iceberg-dev]
    -Help           Show this help message

EXAMPLES:
    # Deploy to dev environment
    .\deploy-orchestration.ps1 -AccountId 123456789012

    # Deploy to production with custom settings
    .\deploy-orchestration.ps1 -Environment prod -AccountId 123456789012 -Region us-west-2

    # Deploy with custom Glue job name
    .\deploy-orchestration.ps1 -Environment staging -AccountId 123456789012 -GlueJobName custom-sf-user-job
"@
    exit 0
}

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$StackNamePrefix = "sf-user-pipeline-orchestration"
$TemplateFile = Join-Path $ScriptDir "orchestration-infrastructure.yml"
$StackName = "$StackNamePrefix-$Environment"

# Function to write colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Start deployment
Write-Status "Starting sf_user pipeline orchestration deployment..."
Write-Status "Environment: $Environment"
Write-Status "Region: $Region"
Write-Status "Account ID: $AccountId"
Write-Status "Stack Name: $StackName"
Write-Status "Glue Job Name: $GlueJobName"
Write-Status "S3 Bucket: $S3BucketName"

# Validate AWS CLI
try {
    $null = Get-Command aws -ErrorAction Stop
    Write-Status "AWS CLI found"
} catch {
    Write-Error "AWS CLI is not installed or not in PATH"
    exit 1
}

# Validate AWS credentials
Write-Status "Validating AWS credentials..."
try {
    $callerIdentity = aws sts get-caller-identity --region $Region --output json | ConvertFrom-Json
    Write-Status "AWS credentials validated for account: $($callerIdentity.Account)"
} catch {
    Write-Error "AWS credentials not configured or invalid"
    exit 1
}

# Validate CloudFormation template
Write-Status "Validating CloudFormation template..."
try {
    $null = aws cloudformation validate-template --template-body "file://$TemplateFile" --region $Region 2>$null
    Write-Success "Template validation passed"
} catch {
    Write-Error "CloudFormation template validation failed"
    exit 1
}

# Check if stack exists
Write-Status "Checking if stack exists..."
$StackExists = $false
try {
    $null = aws cloudformation describe-stacks --stack-name $StackName --region $Region --output json 2>$null
    $StackExists = $true
    Write-Status "Stack exists - will update"
} catch {
    Write-Status "Stack does not exist - will create"
}

# Prepare CloudFormation parameters
$Parameters = @(
    "ParameterKey=Environment,ParameterValue=$Environment",
    "ParameterKey=AccountId,ParameterValue=$AccountId",
    "ParameterKey=GlueJobName,ParameterValue=$GlueJobName",
    "ParameterKey=S3BucketName,ParameterValue=$S3BucketName"
)

# Deploy or update stack
if ($StackExists) {
    Write-Status "Updating CloudFormation stack..."
    $ChangeSetName = "sf-user-pipeline-update-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    # Create change set
    aws cloudformation create-change-set `
        --stack-name $StackName `
        --change-set-name $ChangeSetName `
        --template-body "file://$TemplateFile" `
        --parameters $Parameters `
        --capabilities CAPABILITY_NAMED_IAM `
        --region $Region
    
    Write-Status "Waiting for change set creation..."
    aws cloudformation wait change-set-create-complete `
        --stack-name $StackName `
        --change-set-name $ChangeSetName `
        --region $Region
    
    # Describe changes
    Write-Status "Change set created. Reviewing changes..."
    aws cloudformation describe-change-set `
        --stack-name $StackName `
        --change-set-name $ChangeSetName `
        --region $Region `
        --query 'Changes[].{Action:Action,ResourceType:ResourceChange.ResourceType,LogicalId:ResourceChange.LogicalResourceId}' `
        --output table
    
    # Execute change set
    Write-Status "Executing change set..."
    aws cloudformation execute-change-set `
        --stack-name $StackName `
        --change-set-name $ChangeSetName `
        --region $Region
    
    Write-Status "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete `
        --stack-name $StackName `
        --region $Region
} else {
    Write-Status "Creating CloudFormation stack..."
    aws cloudformation create-stack `
        --stack-name $StackName `
        --template-body "file://$TemplateFile" `
        --parameters $Parameters `
        --capabilities CAPABILITY_NAMED_IAM `
        --enable-termination-protection `
        --region $Region
    
    Write-Status "Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete `
        --stack-name $StackName `
        --region $Region
}

# Get stack outputs
Write-Status "Retrieving stack outputs..."
$OutputsJson = aws cloudformation describe-stacks `
    --stack-name $StackName `
    --region $Region `
    --query 'Stacks[0].Outputs' `
    --output json

if ($OutputsJson -and $OutputsJson -ne "null" -and $OutputsJson -ne "[]") {
    $Outputs = $OutputsJson | ConvertFrom-Json
    Write-Success "Stack deployment completed successfully!"
    Write-Host ""
    Write-Status "Stack Outputs:"
    
    foreach ($output in $Outputs) {
        Write-Host "  $($output.OutputKey): $($output.OutputValue)"
    }
    Write-Host ""
    
    # Extract key outputs
    $StateMachineArn = ($Outputs | Where-Object { $_.OutputKey -eq "StateMachineArn" }).OutputValue
    $SNSTopicArn = ($Outputs | Where-Object { $_.OutputKey -eq "SNSTopicArn" }).OutputValue
    
    Write-Status "Key Resources Created:"
    Write-Host "  Step Functions State Machine: $StateMachineArn"
    Write-Host "  SNS Alerts Topic: $SNSTopicArn"
    Write-Host ""
} else {
    Write-Warning "No stack outputs available"
}

# Verify Step Functions state machine
Write-Status "Verifying Step Functions state machine..."
try {
    $null = aws stepfunctions describe-state-machine --state-machine-arn $StateMachineArn --region $Region 2>$null
    Write-Success "Step Functions state machine is active and ready"
} catch {
    Write-Warning "Could not verify Step Functions state machine status"
}

# Verify EventBridge rule
Write-Status "Verifying EventBridge schedule rule..."
$RuleName = "sf-user-pipeline-schedule-$Environment"
try {
    $RuleDetails = aws events describe-rule --name $RuleName --region $Region --output json | ConvertFrom-Json
    Write-Success "EventBridge schedule rule is active"
    
    Write-Status "Schedule Details:"
    Write-Host "  Rule State: $($RuleDetails.State)"
    Write-Host "  Schedule: $($RuleDetails.ScheduleExpression) (6-hourly execution)"
} catch {
    Write-Warning "Could not verify EventBridge rule status"
}

Write-Success "sf_user pipeline orchestration deployment completed!"
Write-Status "Next steps:"
Write-Host "  1. Configure SNS topic subscriptions for alerts"
Write-Host "  2. Deploy Lambda functions for pipeline validation and error handling"
Write-Host "  3. Test pipeline execution manually before enabling schedule"
Write-Host "  4. Monitor CloudWatch logs and metrics"

# Save deployment information
$DeploymentInfoFile = Join-Path $ProjectRoot "deployment-info-$Environment.json"
$DeploymentInfo = @{
    deployment_timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    environment = $Environment
    aws_region = $Region
    account_id = $AccountId
    stack_name = $StackName
    state_machine_arn = $StateMachineArn
    sns_topic_arn = $SNSTopicArn
    glue_job_name = $GlueJobName
    s3_bucket_name = $S3BucketName
} | ConvertTo-Json -Depth 3

$DeploymentInfo | Out-File -FilePath $DeploymentInfoFile -Encoding UTF8
Write-Status "Deployment information saved to: $DeploymentInfoFile"
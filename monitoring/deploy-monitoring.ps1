# sf_user Pipeline Monitoring Deployment Script (PowerShell)
# Deploys CloudWatch monitoring, Lambda functions, and alerting infrastructure

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1",
    
    [Parameter(Mandatory=$true)]
    [string]$AccountId,
    
    [Parameter(Mandatory=$true)]
    [string]$StateMachineArn,
    
    [Parameter(Mandatory=$true)]
    [string]$SNSTopicArn,
    
    [Parameter(Mandatory=$false)]
    [string]$GlueJobName = "sf-user-ingestion-job",
    
    [Parameter(Mandatory=$false)]
    [string]$AlertEmail = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host @"
sf_user Pipeline Monitoring Deployment Script

DESCRIPTION:
    Deploys CloudWatch monitoring, Lambda functions, and alerting infrastructure
    for the sf_user pipeline monitoring and observability.

PARAMETERS:
    -Environment      Environment (dev, staging, prod) [default: dev]
    -Region           AWS region [default: us-east-1]
    -AccountId        AWS Account ID (required)
    -StateMachineArn  ARN of the Step Functions state machine (required)
    -SNSTopicArn      ARN of the SNS topic for alerts (required)
    -GlueJobName      Glue job name [default: sf-user-ingestion-job]
    -AlertEmail       Email address for alerts [optional]
    -Help             Show this help message

EXAMPLES:
    # Deploy monitoring to dev environment
    .\deploy-monitoring.ps1 -AccountId 123456789012 -StateMachineArn "arn:aws:states:..." -SNSTopicArn "arn:aws:sns:..."

    # Deploy with email alerts
    .\deploy-monitoring.ps1 -Environment prod -AccountId 123456789012 -StateMachineArn "arn:aws:states:..." -SNSTopicArn "arn:aws:sns:..." -AlertEmail "admin@company.com"
"@
    exit 0
}

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$StackNamePrefix = "sf-user-pipeline-monitoring"
$TemplateFile = Join-Path $ScriptDir "cloudwatch-monitoring.yml"
$StackName = "$StackNamePrefix-$Environment"

# Lambda function paths
$LambdaDir = Join-Path $ScriptDir "lambda-functions"
$MetricsPublisherPath = Join-Path $LambdaDir "metrics-publisher.py"
$ErrorHandlerPath = Join-Path $LambdaDir "error-handler.py"
$PipelineValidatorPath = Join-Path $LambdaDir "pipeline-validator.py"

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
Write-Status "Starting sf_user pipeline monitoring deployment..."
Write-Status "Environment: $Environment"
Write-Status "Region: $Region"
Write-Status "Account ID: $AccountId"
Write-Status "Stack Name: $StackName"
Write-Status "State Machine ARN: $StateMachineArn"
Write-Status "SNS Topic ARN: $SNSTopicArn"

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

# Create Lambda deployment packages
Write-Status "Creating Lambda deployment packages..."

# Create temporary directory for Lambda packages
$TempDir = Join-Path $env:TEMP "sf-user-lambda-packages"
if (Test-Path $TempDir) {
    Remove-Item -Recurse -Force $TempDir
}
New-Item -ItemType Directory -Path $TempDir | Out-Null

# Package metrics publisher
$MetricsPublisherZip = Join-Path $TempDir "metrics-publisher.zip"
Compress-Archive -Path $MetricsPublisherPath -DestinationPath $MetricsPublisherZip -Force
Write-Status "Created metrics publisher package: $MetricsPublisherZip"

# Package error handler
$ErrorHandlerZip = Join-Path $TempDir "error-handler.zip"
Compress-Archive -Path $ErrorHandlerPath -DestinationPath $ErrorHandlerZip -Force
Write-Status "Created error handler package: $ErrorHandlerZip"

# Package pipeline validator
$PipelineValidatorZip = Join-Path $TempDir "pipeline-validator.zip"
Compress-Archive -Path $PipelineValidatorPath -DestinationPath $PipelineValidatorZip -Force
Write-Status "Created pipeline validator package: $PipelineValidatorZip"

# Upload Lambda packages to S3
$S3Bucket = "lumata-salesforce-lakehouse-config-dev"
$S3Prefix = "lambda-packages/sf-user-pipeline"

Write-Status "Uploading Lambda packages to S3..."

aws s3 cp $MetricsPublisherZip "s3://$S3Bucket/$S3Prefix/metrics-publisher.zip" --region $Region
aws s3 cp $ErrorHandlerZip "s3://$S3Bucket/$S3Prefix/error-handler.zip" --region $Region
aws s3 cp $PipelineValidatorZip "s3://$S3Bucket/$S3Prefix/pipeline-validator.zip" --region $Region

Write-Success "Lambda packages uploaded to S3"

# Deploy Lambda functions first
Write-Status "Deploying Lambda functions..."

# Deploy metrics publisher Lambda
$MetricsPublisherFunction = "sf-user-metrics-publisher-$Environment"
try {
    # Check if function exists
    $null = aws lambda get-function --function-name $MetricsPublisherFunction --region $Region 2>$null
    
    # Update existing function
    aws lambda update-function-code `
        --function-name $MetricsPublisherFunction `
        --s3-bucket $S3Bucket `
        --s3-key "$S3Prefix/metrics-publisher.zip" `
        --region $Region | Out-Null
    
    Write-Status "Updated existing metrics publisher Lambda function"
} catch {
    # Create new function
    aws lambda create-function `
        --function-name $MetricsPublisherFunction `
        --runtime python3.9 `
        --role "arn:aws:iam::${AccountId}:role/sf-user-pipeline-lambda-role-$Environment" `
        --handler metrics-publisher.lambda_handler `
        --code S3Bucket=$S3Bucket,S3Key="$S3Prefix/metrics-publisher.zip" `
        --timeout 300 `
        --memory-size 256 `
        --environment Variables="{ENVIRONMENT=$Environment}" `
        --region $Region | Out-Null
    
    Write-Status "Created new metrics publisher Lambda function"
}

# Deploy error handler Lambda
$ErrorHandlerFunction = "sf-user-error-handler-$Environment"
try {
    # Check if function exists
    $null = aws lambda get-function --function-name $ErrorHandlerFunction --region $Region 2>$null
    
    # Update existing function
    aws lambda update-function-code `
        --function-name $ErrorHandlerFunction `
        --s3-bucket $S3Bucket `
        --s3-key "$S3Prefix/error-handler.zip" `
        --region $Region | Out-Null
    
    Write-Status "Updated existing error handler Lambda function"
} catch {
    # Create new function
    aws lambda create-function `
        --function-name $ErrorHandlerFunction `
        --runtime python3.9 `
        --role "arn:aws:iam::${AccountId}:role/sf-user-pipeline-lambda-role-$Environment" `
        --handler error-handler.lambda_handler `
        --code S3Bucket=$S3Bucket,S3Key="$S3Prefix/error-handler.zip" `
        --timeout 300 `
        --memory-size 256 `
        --environment Variables="{ENVIRONMENT=$Environment,SNS_TOPIC_ARN=$SNSTopicArn}" `
        --region $Region | Out-Null
    
    Write-Status "Created new error handler Lambda function"
}

# Deploy pipeline validator Lambda
$PipelineValidatorFunction = "sf-user-pipeline-validator-$Environment"
try {
    # Check if function exists
    $null = aws lambda get-function --function-name $PipelineValidatorFunction --region $Region 2>$null
    
    # Update existing function
    aws lambda update-function-code `
        --function-name $PipelineValidatorFunction `
        --s3-bucket $S3Bucket `
        --s3-key "$S3Prefix/pipeline-validator.zip" `
        --region $Region | Out-Null
    
    Write-Status "Updated existing pipeline validator Lambda function"
} catch {
    # Create new function
    aws lambda create-function `
        --function-name $PipelineValidatorFunction `
        --runtime python3.9 `
        --role "arn:aws:iam::${AccountId}:role/sf-user-pipeline-lambda-role-$Environment" `
        --handler pipeline-validator.lambda_handler `
        --code S3Bucket=$S3Bucket,S3Key="$S3Prefix/pipeline-validator.zip" `
        --timeout 600 `
        --memory-size 512 `
        --environment Variables="{ENVIRONMENT=$Environment,ATHENA_DATABASE=salesforce_curated,S3_RESULTS_BUCKET=$S3Bucket}" `
        --region $Region | Out-Null
    
    Write-Status "Created new pipeline validator Lambda function"
}

Write-Success "Lambda functions deployed successfully"

# Validate CloudFormation template
Write-Status "Validating CloudFormation template..."
try {
    $null = aws cloudformation validate-template --template-body "file://$TemplateFile" --region $Region 2>$null
    Write-Success "Template validation passed"
} catch {
    Write-Error "CloudFormation template validation failed"
    exit 1
}

# Check if monitoring stack exists
Write-Status "Checking if monitoring stack exists..."
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
    "ParameterKey=StateMachineArn,ParameterValue=$StateMachineArn",
    "ParameterKey=GlueJobName,ParameterValue=$GlueJobName",
    "ParameterKey=SNSTopicArn,ParameterValue=$SNSTopicArn"
)

if ($AlertEmail) {
    $Parameters += "ParameterKey=AlertEmail,ParameterValue=$AlertEmail"
}

# Deploy or update monitoring stack
if ($StackExists) {
    Write-Status "Updating CloudFormation monitoring stack..."
    $ChangeSetName = "sf-user-monitoring-update-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    # Create change set
    aws cloudformation create-change-set `
        --stack-name $StackName `
        --change-set-name $ChangeSetName `
        --template-body "file://$TemplateFile" `
        --parameters $Parameters `
        --capabilities CAPABILITY_IAM `
        --region $Region
    
    Write-Status "Waiting for change set creation..."
    aws cloudformation wait change-set-create-complete `
        --stack-name $StackName `
        --change-set-name $ChangeSetName `
        --region $Region
    
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
    Write-Status "Creating CloudFormation monitoring stack..."
    aws cloudformation create-stack `
        --stack-name $StackName `
        --template-body "file://$TemplateFile" `
        --parameters $Parameters `
        --capabilities CAPABILITY_IAM `
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
    Write-Success "Monitoring stack deployment completed successfully!"
    Write-Host ""
    Write-Status "Stack Outputs:"
    
    foreach ($output in $Outputs) {
        Write-Host "  $($output.OutputKey): $($output.OutputValue)"
    }
    Write-Host ""
    
    # Extract key outputs
    $DashboardURL = ($Outputs | Where-Object { $_.OutputKey -eq "DashboardURL" }).OutputValue
    $CompositeAlarmArn = ($Outputs | Where-Object { $_.OutputKey -eq "CompositeAlarmArn" }).OutputValue
    
    Write-Status "Key Resources Created:"
    Write-Host "  CloudWatch Dashboard: $DashboardURL"
    Write-Host "  Composite Alarm: $CompositeAlarmArn"
    Write-Host ""
} else {
    Write-Warning "No stack outputs available"
}

# Clean up temporary files
Remove-Item -Recurse -Force $TempDir

Write-Success "sf_user pipeline monitoring deployment completed!"
Write-Status "Next steps:"
Write-Host "  1. Access the CloudWatch dashboard to view pipeline metrics"
Write-Host "  2. Configure SNS topic subscriptions for email/Slack alerts"
Write-Host "  3. Test Lambda functions with sample pipeline events"
Write-Host "  4. Review and adjust CloudWatch alarm thresholds as needed"
Write-Host "  5. Set up additional monitoring dashboards for business metrics"

# Save deployment information
$DeploymentInfoFile = Join-Path $ProjectRoot "monitoring-deployment-info-$Environment.json"
$DeploymentInfo = @{
    deployment_timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    environment = $Environment
    aws_region = $Region
    account_id = $AccountId
    monitoring_stack_name = $StackName
    state_machine_arn = $StateMachineArn
    sns_topic_arn = $SNSTopicArn
    lambda_functions = @{
        metrics_publisher = $MetricsPublisherFunction
        error_handler = $ErrorHandlerFunction
        pipeline_validator = $PipelineValidatorFunction
    }
    dashboard_url = $DashboardURL
    composite_alarm_arn = $CompositeAlarmArn
} | ConvertTo-Json -Depth 3

$DeploymentInfo | Out-File -FilePath $DeploymentInfoFile -Encoding UTF8
Write-Status "Monitoring deployment information saved to: $DeploymentInfoFile"
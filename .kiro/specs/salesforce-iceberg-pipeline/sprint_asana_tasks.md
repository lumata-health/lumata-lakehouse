# ASANA Sprint Tasks - Salesforce Lakehouse Redesign (2 Weeks)

## Sprint Overview
**Sprint Goal**: Complete infrastructure setup + deliver working SCD Type 2 for sf_account  
**Duration**: 2 weeks  
**Key Milestone**: Production-ready sf_account with full SCD capabilities

---

## Week 1: Infrastructure & Raw Layer Setup

### Task 1: Project Setup and Repository Structure
**Priority**: High  
**Estimated Time**: 4 hours  
**Assignee**: Deepak Saini  

**Description**:
Set up the redesign project structure in lumata-datalake repository and initialize all necessary components.

**Acceptance Criteria**:
- [ ] Create `redesign/` folder in lumata-datalake repo
- [ ] Set up complete directory structure (infrastructure, glue-jobs, dbt-project, scripts, config, docs)
- [ ] Initialize git tracking for redesign folder
- [ ] Create project README with architecture overview
- [ ] Set up development environment configuration

**Deliverables**:
- Complete project structure
- Initial README documentation
- Development environment ready

---

### Task 2: AWS Infrastructure Deployment
**Priority**: High  
**Estimated Time**: 8 hours  
**Assignee**: Deepak Saini  

**Description**:
Deploy complete AWS infrastructure using CloudFormation templates for the entire Salesforce Iceberg pipeline.

**Acceptance Criteria**:
- [ ] Create CloudFormation templates for S3 buckets, Glue Catalog, IAM roles
- [ ] Deploy infrastructure to dev environment (282815445946)
- [ ] Create Glue databases: salesforce_raw_dev, salesforce_marts_dev
- [ ] Configure S3 buckets with proper encryption and lifecycle policies
- [ ] Set up IAM roles with necessary permissions for Glue and dbt
- [ ] Test basic AWS connectivity and permissions

**Deliverables**:
- CloudFormation templates (JSON)
- Deployed infrastructure in dev environment
- Infrastructure validation report

---

### Task 3: Salesforce Data Extraction - All Objects
**Priority**: High  
**Estimated Time**: 12 hours  
**Assignee**: Deepak Saini  

**Description**:
Create and deploy AWS Glue job to extract ALL Salesforce objects to raw Iceberg tables.

**Acceptance Criteria**:
- [ ] Create Glue job for Salesforce API extraction
- [ ] Configure Spark for Apache Iceberg support
- [ ] Implement extraction for all 25+ Salesforce objects
- [ ] Write data to raw Iceberg tables with proper partitioning
- [ ] Add comprehensive error handling and logging
- [ ] Test extraction with sample data from each object
- [ ] Validate raw Iceberg tables are created and populated

**Deliverables**:
- Salesforce extraction Glue job (Python)
- Raw Iceberg tables for all objects
- Extraction validation report

---

### Task 4: dbt Project Foundation Setup
**Priority**: High  
**Estimated Time**: 6 hours  
**Assignee**: Deepak Saini  

**Description**:
Set up complete dbt project with Iceberg support and create source definitions for all Salesforce objects.

**Acceptance Criteria**:
- [ ] Initialize dbt project with Spark adapter
- [ ] Configure profiles.yml for Iceberg support
- [ ] Create source definitions for all raw Salesforce tables
- [ ] Set up project structure (staging, intermediate, marts folders)
- [ ] Create basic macros library for reusable patterns
- [ ] Test dbt connectivity to Glue Catalog
- [ ] Validate dbt can read from raw Iceberg tables

**Deliverables**:
- Complete dbt project setup
- Source definitions for all objects
- Basic macro library
- dbt connectivity validation

---

## Week 2: sf_account End-to-End SCD Implementation

### Task 5: sf_account Staging Model and Data Cleaning
**Priority**: High  
**Estimated Time**: 6 hours  
**Assignee**: Deepak Saini  

**Description**:
Create staging model for sf_account with comprehensive data cleaning and validation.

**Acceptance Criteria**:
- [ ] Create stg_sf_account.sql with data cleaning logic
- [ ] Implement data quality flags and validation rules
- [ ] Add standardization for text fields and addresses
- [ ] Create data quality tests for staging model
- [ ] Validate staging model produces clean, consistent data
- [ ] Document data transformations and business rules

**Deliverables**:
- stg_sf_account staging model
- Data quality tests
- Data cleaning documentation

---

### Task 6: Address Normalization Framework
**Priority**: High  
**Estimated Time**: 8 hours  
**Assignee**: Deepak Saini  

**Description**:
Implement comprehensive address normalization with stable location ID generation.

**Acceptance Criteria**:
- [ ] Create address normalization macros (standardize_street, standardize_city, etc.)
- [ ] Implement stable location ID generation algorithm
- [ ] Create intermediate model for address normalization
- [ ] Test address normalization with sample data
- [ ] Validate location IDs are stable across runs
- [ ] Create address lookup and deduplication logic

**Deliverables**:
- Address normalization macros
- Intermediate address model
- Location ID generation logic
- Address normalization tests

---

### Task 7: SCD Type 2 Implementation for sf_account
**Priority**: Critical  
**Estimated Time**: 10 hours  
**Assignee**: Deepak Saini  

**Description**:
Implement complete SCD Type 2 for sf_account with full historical tracking.

**Acceptance Criteria**:
- [ ] Create dim_account mart model with SCD Type 2 logic
- [ ] Implement incremental processing with merge strategy
- [ ] Add SCD columns: start_date, end_date, is_current, is_deleted
- [ ] Create surrogate key generation for each record version
- [ ] Implement change detection based on LastModifiedDate
- [ ] Test SCD logic with sample data changes
- [ ] Validate historical tracking works correctly

**Deliverables**:
- dim_account SCD Type 2 model
- SCD testing and validation
- Historical tracking demonstration

---

### Task 8: Data Quality Testing and Validation
**Priority**: High  
**Estimated Time**: 6 hours  
**Assignee**: Deepak Saini  

**Description**:
Create comprehensive data quality tests and validate sf_account pipeline end-to-end.

**Acceptance Criteria**:
- [ ] Create dbt tests for dim_account (uniqueness, not null, relationships)
- [ ] Implement custom tests for SCD Type 2 logic
- [ ] Create data comparison scripts (old vs new system)
- [ ] Validate data accuracy >99% compared to current system
- [ ] Test incremental processing and change detection
- [ ] Create performance benchmarks and optimization

**Deliverables**:
- Complete dbt test suite
- Data validation scripts
- Performance benchmarks
- Quality assurance report

---

### Task 9: Pipeline Orchestration and Monitoring
**Priority**: Medium  
**Estimated Time**: 6 hours  
**Assignee**: Deepak Saini  

**Description**:
Set up basic orchestration and monitoring for the sf_account pipeline.

**Acceptance Criteria**:
- [ ] Create Step Functions workflow for sf_account pipeline
- [ ] Set up CloudWatch logging and basic monitoring
- [ ] Configure SNS alerts for pipeline failures
- [ ] Create manual trigger for pipeline execution
- [ ] Test end-to-end pipeline execution
- [ ] Document pipeline operation procedures

**Deliverables**:
- Step Functions workflow
- Basic monitoring setup
- Pipeline operation documentation

---

### Task 10: Stakeholder Demo Preparation
**Priority**: High  
**Estimated Time**: 4 hours  
**Assignee**: Deepak Saini  

**Description**:
Prepare comprehensive demonstration of working sf_account SCD implementation for stakeholders.

**Acceptance Criteria**:
- [ ] Create demo queries showing SCD Type 2 capabilities
- [ ] Prepare historical analysis examples
- [ ] Document address normalization benefits
- [ ] Create performance comparison with current system
- [ ] Prepare demo environment and sample data
- [ ] Create presentation materials for stakeholder review

**Deliverables**:
- Demo queries and examples
- Stakeholder presentation
- Demo environment setup
- Performance comparison report

---

## Sprint Success Metrics

### Week 1 Success Criteria
- ✅ Complete infrastructure deployed and operational
- ✅ Raw Iceberg tables populated with all Salesforce objects
- ✅ dbt project foundation ready for transformations
- ✅ All AWS services configured and tested

### Week 2 Success Criteria ⭐ **SPRINT GOAL**
- ✅ **Production-ready sf_account with SCD Type 2**
- ✅ **Address normalization operational**
- ✅ **Historical tracking and point-in-time queries working**
- ✅ **Data quality >99% compared to current system**
- ✅ **Stakeholder demo ready**

## Risk Mitigation

### High-Risk Tasks
1. **Task 3 (Salesforce Extraction)**: Salesforce API rate limits
   - **Mitigation**: Implement exponential backoff, test with small datasets first

2. **Task 7 (SCD Implementation)**: Complex SCD logic
   - **Mitigation**: Start with simple SCD, iterate to full implementation

3. **Task 8 (Data Validation)**: Data quality issues
   - **Mitigation**: Continuous validation during development, not just at end

### Contingency Plans
- **If Salesforce extraction issues**: Focus on subset of objects, expand later
- **If SCD complexity issues**: Implement basic versioning first, enhance later
- **If performance issues**: Optimize partitioning and query patterns

## Daily Standups Focus

### Week 1 Daily Questions
- Infrastructure deployment progress?
- Salesforce extraction working for which objects?
- Any AWS permission or configuration issues?

### Week 2 Daily Questions  
- SCD Type 2 logic working correctly?
- Data quality validation results?
- Any performance or data consistency issues?
- Demo preparation status?

## Sprint Retrospective Items

### What to Measure
- **Infrastructure deployment time** vs estimates
- **Data extraction success rate** by object
- **SCD implementation complexity** vs expectations
- **Data quality accuracy** vs current system
- **Team learning curve** with new technologies

This sprint structure ensures you deliver the key milestone (working SCD for sf_account) while building the foundation for all subsequent objects.
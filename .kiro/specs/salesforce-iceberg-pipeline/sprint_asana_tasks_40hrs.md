# ASANA Sprint Tasks - Salesforce Lakehouse Redesign (40 Hours Total)

## Sprint Capacity
**Daily Availability**: 4 hours/day  
**Sprint Duration**: 10 working days (2 weeks)  
**Total Capacity**: 40 hours  
**Sprint Goal**: Working SCD Type 2 for sf_account + infrastructure foundation

---

## Week 1: Infrastructure & Foundation (20 hours)

### Day 1: Project Setup and AWS Infrastructure (4 hours)

#### Task 1A: Project Structure Setup
**Time**: 1.5 hours  
**Priority**: High  

**Description**: Set up redesign project structure and initialize development environment.

**Acceptance Criteria**:
- [ ] Create `redesign/` folder in lumata-datalake repo
- [ ] Set up directory structure (infrastructure, glue-jobs, dbt-project, scripts, config)
- [ ] Initialize git tracking and create project README
- [ ] Configure AWS profile for development

**Deliverables**: Complete project structure, README

---

#### Task 1B: CloudFormation Infrastructure
**Time**: 2.5 hours  
**Priority**: High  

**Description**: Create and deploy basic AWS infrastructure using CloudFormation.

**Acceptance Criteria**:
- [ ] Create CloudFormation template for S3 buckets and Glue Catalog
- [ ] Deploy to dev environment (282815445946)
- [ ] Create Glue databases: salesforce_raw_dev, salesforce_marts_dev
- [ ] Test basic AWS connectivity

**Deliverables**: Deployed infrastructure, validation report

---

### Day 2: Salesforce Connectivity and Basic Extraction (4 hours)

#### Task 2A: Salesforce Connection Setup
**Time**: 2 hours  
**Priority**: High  

**Description**: Test Salesforce API connectivity and create basic extraction utility.

**Acceptance Criteria**:
- [ ] Test connection using existing Salesforce credentials
- [ ] Create basic Salesforce client utility
- [ ] Test data extraction from Account object (sample)
- [ ] Document available Salesforce objects

**Deliverables**: Salesforce connection utility, connectivity validation

---

#### Task 2B: Basic Glue Job Framework
**Time**: 2 hours  
**Priority**: High  

**Description**: Create basic Glue job framework for Salesforce extraction.

**Acceptance Criteria**:
- [ ] Create Glue job template with Iceberg configuration
- [ ] Implement basic extraction for Account object only
- [ ] Test writing to Iceberg table
- [ ] Add basic error handling and logging

**Deliverables**: Basic Glue job, test Iceberg table

---

### Day 3: Expand Extraction to Key Objects (4 hours)

#### Task 3: Multi-Object Extraction
**Time**: 4 hours  
**Priority**: High  

**Description**: Expand Glue job to extract key Salesforce objects to raw Iceberg tables.

**Acceptance Criteria**:
- [ ] Extract Account, Contact, Case objects (core healthcare objects)
- [ ] Write to properly partitioned Iceberg tables
- [ ] Implement parallel processing for multiple objects
- [ ] Add comprehensive logging and error handling
- [ ] Validate raw tables are populated correctly

**Deliverables**: Multi-object extraction, raw Iceberg tables for core objects

---

### Day 4: dbt Project Setup (4 hours)

#### Task 4: dbt Foundation
**Time**: 4 hours  
**Priority**: High  

**Description**: Set up complete dbt project with Iceberg support.

**Acceptance Criteria**:
- [ ] Initialize dbt project with Spark adapter
- [ ] Configure profiles.yml for Iceberg connectivity
- [ ] Create source definitions for Account, Contact, Case
- [ ] Set up project structure (staging, marts folders)
- [ ] Test dbt connectivity to Glue Catalog
- [ ] Create basic staging model for Account

**Deliverables**: Complete dbt project, basic staging model

---

### Day 5: Address Normalization Framework (4 hours)

#### Task 5: Address Normalization
**Time**: 4 hours  
**Priority**: High  

**Description**: Create address normalization macros and framework.

**Acceptance Criteria**:
- [ ] Create address normalization macros (standardize functions)
- [ ] Implement stable location ID generation
- [ ] Create intermediate address model
- [ ] Test with sample Account address data
- [ ] Validate location IDs are consistent

**Deliverables**: Address normalization macros, intermediate model

---

## Week 2: SCD Implementation & Demo (20 hours)

### Day 6: SCD Type 2 Foundation (4 hours)

#### Task 6: SCD Type 2 Setup
**Time**: 4 hours  
**Priority**: Critical  

**Description**: Implement basic SCD Type 2 structure for sf_account.

**Acceptance Criteria**:
- [ ] Create dim_account mart model with SCD columns
- [ ] Implement basic SCD logic (start_date, end_date, is_current)
- [ ] Add surrogate key generation
- [ ] Test with initial Account data load
- [ ] Validate SCD structure is correct

**Deliverables**: Basic SCD Type 2 model, initial testing

---

### Day 7: SCD Incremental Processing (4 hours)

#### Task 7: SCD Incremental Logic
**Time**: 4 hours  
**Priority**: Critical  

**Description**: Implement incremental processing and change detection for SCD.

**Acceptance Criteria**:
- [ ] Add incremental materialization with merge strategy
- [ ] Implement change detection based on LastModifiedDate
- [ ] Test incremental updates with sample data changes
- [ ] Validate historical versions are preserved
- [ ] Test current record flagging works correctly

**Deliverables**: Working incremental SCD processing

---

### Day 8: Data Quality and Validation (4 hours)

#### Task 8: Data Quality Framework
**Time**: 4 hours  
**Priority**: High  

**Description**: Create data quality tests and validation for sf_account SCD.

**Acceptance Criteria**:
- [ ] Create dbt tests for dim_account (uniqueness, not null)
- [ ] Implement custom SCD validation tests
- [ ] Create data comparison with current system (sample)
- [ ] Test data quality and accuracy
- [ ] Document any data discrepancies

**Deliverables**: Data quality test suite, validation report

---

### Day 9: Pipeline Integration and Testing (4 hours)

#### Task 9: End-to-End Pipeline
**Time**: 4 hours  
**Priority**: High  

**Description**: Integrate all components and test complete sf_account pipeline.

**Acceptance Criteria**:
- [ ] Create end-to-end pipeline: Extraction → Staging → SCD
- [ ] Test complete pipeline execution
- [ ] Validate data flows correctly through all stages
- [ ] Add basic monitoring and logging
- [ ] Create manual pipeline execution procedure

**Deliverables**: Working end-to-end pipeline, execution documentation

---

### Day 10: Demo Preparation and Documentation (4 hours)

#### Task 10: Stakeholder Demo
**Time**: 4 hours  
**Priority**: High  

**Description**: Prepare comprehensive demo and documentation for stakeholders.

**Acceptance Criteria**:
- [ ] Create demo queries showing SCD Type 2 capabilities
- [ ] Prepare historical analysis examples
- [ ] Document address normalization benefits
- [ ] Create performance comparison (basic)
- [ ] Prepare demo presentation
- [ ] Document next steps for remaining objects

**Deliverables**: Demo materials, presentation, documentation

---

## Adjusted Sprint Scope

### **What We're Delivering (40 hours)**:
✅ **Complete infrastructure** for entire project  
✅ **Raw data extraction** for core objects (Account, Contact, Case)  
✅ **Full SCD Type 2 for sf_account** with address normalization  
✅ **Working end-to-end pipeline** for main business entity  
✅ **Stakeholder demo** showing SCD capabilities  

### **What We're Deferring**:
❌ **All 25+ objects** → Focus on core 3 objects (Account, Contact, Case)  
❌ **Advanced orchestration** → Basic manual execution  
❌ **Complete monitoring** → Basic logging only  
❌ **Performance optimization** → Basic functionality first  

## Daily Schedule (4 hours/day)

### **Recommended Daily Breakdown**:
- **Hour 1**: Planning and setup
- **Hours 2-3**: Core development work  
- **Hour 4**: Testing and documentation

### **Daily Deliverables**:
Each day has **one clear deliverable** that builds toward the sprint goal.

## Risk Mitigation (40-hour constraints)

### **Scope Management**:
- **Focus on sf_account only** for SCD implementation
- **Defer complex features** to future sprints
- **Prioritize working demo** over perfect implementation

### **Time Management**:
- **Daily time-boxing** - stick to 4-hour limit
- **Clear daily goals** - one major deliverable per day
- **Buffer built-in** - simpler tasks toward end of week

### **Quality Assurance**:
- **Continuous testing** - validate as you build
- **Incremental demos** - show progress daily
- **Documentation as you go** - don't defer to end

## Sprint Success Criteria (Adjusted)

### **Minimum Viable Product (MVP)**:
✅ **Working SCD Type 2 for sf_account**  
✅ **Address normalization operational**  
✅ **Historical queries working**  
✅ **Basic data quality validation**  
✅ **Stakeholder demo ready**  

### **Stretch Goals** (if time permits):
- SCD for sf_contact
- Advanced data quality tests
- Performance benchmarks

This adjusted plan ensures you deliver the core value (SCD for sf_account) within your 40-hour constraint while building the foundation for future sprints.
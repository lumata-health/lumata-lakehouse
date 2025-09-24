# Revised Implementation Plan - Phased Approach

## Overview

**Strategic Approach**: Start with end-to-end implementation for `sf_account` only, then expand to other objects in business-focused phases.

**Timeline**: 5 weeks (reduced from 7 weeks)
**Key Benefit**: Stakeholders see working SCD implementation for main table within 2 weeks

## Phase Structure

### Phase 1: Infrastructure & Raw Layer (Week 1)
- **Goal**: Complete infrastructure + raw data extraction for ALL objects
- **Deliverable**: Raw Iceberg tables for all 25+ Salesforce objects

### Phase 2: Healthcare Core - sf_account End-to-End (Week 2)  
- **Goal**: Complete SCD Type 2 implementation for sf_account ONLY
- **Deliverable**: Production-ready dim_account with full SCD capabilities
- **Stakeholder Value**: Main table ready for use and testing

### Phase 3A: Healthcare Objects (Week 3)
- **Goal**: sf_contact, sf_case, sf_patient_encounter
- **Leverage**: Existing patterns from sf_account

### Phase 3B: Clinical Objects (Week 4)
- **Goal**: sf_clinic_visit, sf_care_barrier, sf_medication, sf_icd10
- **Focus**: Clinical data transformations

### Phase 3C: Operational & Historical (Week 5)
- **Goal**: sf_user, sf_task, sf_event, history tables
- **Complete**: Migration and old system decommission

---

## Phase 1: Infrastructure & Raw Layer (Week 1)

### Day 1-2: Infrastructure Foundation
**Objective**: Deploy complete infrastructure for entire project

**Tasks**:
1. **CloudFormation Infrastructure**
   ```bash
   # Deploy S3 buckets, Glue Catalog, IAM roles
   python infrastructure/deploy.py dev
   ```

2. **Glue Job for ALL Objects**
   ```python
   # Extract ALL 25+ Salesforce objects to raw Iceberg tables
   objects = [
       'Account', 'Contact', 'Case', 'Task', 'Event',
       'Patient_Encounter__c', 'Clinic_Visit__c', 'Care_Barrier__c',
       'Digital_Prescription__c', 'Medication__c', 'ICD10__c',
       'User', 'UserRole', 'Call_Audit__c', 'Member_Plan__c'
       # ... all objects
   ]
   ```

**Deliverables**:
- ✅ Complete AWS infrastructure
- ✅ Raw Iceberg tables for ALL Salesforce objects
- ✅ Foundation for all subsequent phases

### Day 3-5: dbt Foundation & Testing
**Objective**: Set up dbt project and validate raw data

**Tasks**:
1. **dbt Project Setup**
   ```yaml
   # Complete dbt project with Iceberg support
   # Source definitions for all raw tables
   # Macro library for reusable patterns
   ```

2. **Raw Data Validation**
   ```sql
   -- Validate all raw tables have data
   -- Test Salesforce connectivity
   -- Verify Iceberg table functionality
   ```

**Deliverables**:
- ✅ Complete dbt project foundation
- ✅ Source definitions for all objects
- ✅ Validated raw data extraction

---

## Phase 2: Healthcare Core - sf_account End-to-End (Week 2)

### Day 1-3: sf_account Complete Implementation
**Objective**: Production-ready sf_account with full SCD Type 2

**Tasks**:
1. **Staging Model**
   ```sql
   -- models/staging/stg_sf_account.sql
   -- Clean and standardize sf_account data
   -- Data quality flags and validation
   ```

2. **Address Normalization**
   ```sql
   -- macros/address_normalization.sql
   -- Generate stable location IDs
   -- Standardize address components
   ```

3. **SCD Type 2 Implementation**
   ```sql
   -- models/marts/dim_account.sql
   -- Complete SCD Type 2 with history tracking
   -- Incremental processing with merge strategy
   ```

**Deliverables**:
- ✅ Production-ready dim_account table
- ✅ Address normalization with stable location IDs
- ✅ Full SCD Type 2 implementation
- ✅ Data quality tests passing

### Day 4-5: Validation & Stakeholder Demo
**Objective**: Validate and demonstrate working solution

**Tasks**:
1. **Data Validation**
   ```python
   # Compare with existing sf_account data
   # Validate SCD Type 2 logic
   # Performance testing
   ```

2. **Stakeholder Demo Preparation**
   ```sql
   -- Create demo queries showing SCD capabilities
   -- Historical analysis examples
   -- Address normalization benefits
   ```

**Deliverables**:
- ✅ **STAKEHOLDER DEMO READY**
- ✅ Validation report (>99% accuracy)
- ✅ Performance benchmarks
- ✅ Reusable patterns documented

---

## Phase 3A: Healthcare Objects (Week 3)

### Healthcare-Focused Objects
**Objects**: `sf_contact`, `sf_case`, `sf_patient_encounter`

**Approach**: Leverage existing patterns from sf_account

**Day 1-2: sf_contact**
```sql
-- Implement SCD Type 2 for contacts
-- Link to dim_account via account_id
-- Patient contact information management
```

**Day 3-4: sf_case & sf_patient_encounter**
```sql
-- Healthcare cases and clinical encounters
-- Link to patients and accounts
-- Clinical workflow support
```

**Day 5: Integration & Testing**
```sql
-- Cross-object relationships
-- Healthcare data mart foundation
-- End-to-end testing
```

**Deliverables**:
- ✅ 3 additional production-ready objects
- ✅ Healthcare data relationships
- ✅ Integrated healthcare data mart

---

## Phase 3B: Clinical Objects (Week 4)

### Clinical-Focused Objects
**Objects**: `sf_clinic_visit`, `sf_care_barrier`, `sf_medication`, `sf_icd10`

**Focus**: Clinical data transformations and medical coding

**Day 1-2: Clinical Visits**
```sql
-- sf_clinic_visit, sf_clinic_visit_outcome
-- Clinical workflow and outcomes
-- Provider and patient relationships
```

**Day 3-4: Clinical Data**
```sql
-- sf_care_barrier - barriers to care
-- sf_medication - medication management
-- sf_icd10 - diagnosis coding
```

**Day 5: Clinical Analytics**
```sql
-- Clinical data mart
-- Medical coding standardization
-- Care quality metrics
```

**Deliverables**:
- ✅ Clinical data mart
- ✅ Medical coding support
- ✅ Care analytics foundation

---

## Phase 3C: Operational & Historical (Week 5)

### Operational Objects
**Objects**: `sf_user`, `sf_user_role`, `sf_task`, `sf_event`

**Day 1-2: User Management**
```sql
-- sf_user, sf_user_role
-- System user tracking
-- Role-based analytics
```

**Day 3: Activity Tracking**
```sql
-- sf_task, sf_event
-- Activity and workflow tracking
-- Operational metrics
```

### Historical Tables & Migration
**Day 4-5: Complete Migration**
```sql
-- History tables (sf_account_history, sf_contact_history)
-- Final validation and testing
-- Production cutover
-- Old system decommission
```

**Deliverables**:
- ✅ Complete object coverage
- ✅ Operational analytics
- ✅ Historical tracking
- ✅ **FULL SYSTEM OPERATIONAL**

---

## Object Categorization

### Healthcare Core (Phase 2)
- `sf_account` - **Primary focus, complete SCD implementation**

### Healthcare Objects (Phase 3A)
- `sf_contact` - Patient contacts
- `sf_case` - Healthcare cases  
- `sf_patient_encounter` - Clinical encounters

### Clinical Objects (Phase 3B)
- `sf_clinic_visit` - Clinical visits
- `sf_clinic_visit_outcome` - Visit outcomes
- `sf_care_barrier` - Care barriers
- `sf_medication` - Medications
- `sf_icd10` - Diagnosis codes

### Operational Objects (Phase 3C)
- `sf_user` - System users
- `sf_user_role` - User roles
- `sf_task` - Tasks and activities
- `sf_event` - Events and appointments
- `sf_call_audit` - Call tracking

### Historical Objects (Phase 3C)
- `sf_account_history` - Account changes
- `sf_contact_history` - Contact changes
- `sf_account_history_v2` - Enhanced history

---

## Success Metrics by Phase

### Phase 1 Success
- ✅ All raw tables populated
- ✅ Infrastructure fully operational
- ✅ dbt project foundation ready

### Phase 2 Success ⭐ **KEY MILESTONE**
- ✅ sf_account SCD Type 2 working
- ✅ Address normalization operational
- ✅ **Stakeholders can start using main table**
- ✅ Patterns established for other objects

### Phase 3A Success
- ✅ Healthcare data mart operational
- ✅ Patient-centric analytics enabled
- ✅ Cross-object relationships working

### Phase 3B Success
- ✅ Clinical analytics enabled
- ✅ Medical coding support
- ✅ Care quality metrics available

### Phase 3C Success
- ✅ **Complete system operational**
- ✅ Old system decommissioned
- ✅ Full SCD coverage for all objects

---

## Timeline Benefits

### Week 2 Milestone
- **Stakeholders get working sf_account** with full SCD capabilities
- **Early validation** of approach and patterns
- **Business value delivery** starts immediately
- **Risk mitigation** through early feedback

### Accelerated Timeline
- **5 weeks vs 7 weeks** (30% faster)
- **Phased value delivery** instead of big-bang approach
- **Lower risk** with incremental validation
- **Stakeholder engagement** throughout process

### Resource Efficiency
- **Reusable patterns** from sf_account implementation
- **Parallel development** possible after Phase 2
- **Reduced complexity** with focused phases
- **AI assistance** enables faster development

This approach delivers immediate business value while building toward the complete solution systematically.
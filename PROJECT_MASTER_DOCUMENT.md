# PROJECT MASTER DOCUMENT
## Guia Roll App
Author: Didier Alfaro
Domain: Operational Guide Role Management System

---

# 1. SYSTEM VISION

Guia Roll App is a deterministic operational system designed to generate daily guide assignments based on:

- Hierarchical priority (1 > 2 > 3)
- Monthly equity balancing
- Historical workload
- Availability constraints (day_off / vacation)
- Audit tracking
- Controlled publishing workflow

The system guarantees operational fairness and structural consistency.

---

# 2. CORE DOMAIN MODELS

## Guide

Represents an operational guide.

Fields:
- name
- priority (1 highest)
- active (boolean)
- total_worked_days
- start_date

Rules:
- Priority 1 always precedes 2 and 3
- Historical workload affects equity sorting

---

## WorkDay

Represents a single operational day.

Fields:
- date
- guides_requested
- status (draft, generated, published)
- published_at

Lifecycle:

draft → generated → published

Rules:
- No past dates allowed
- Only draft can generate roles
- Only generated can publish
- Published days may be reset or regenerated

---

## GuideDay

Join model between Guide and WorkDay.

Fields:
- status (worked, standby, day_off, vacation)
- role_primary
- role_secondary
- manually_modified

This is the real operational assignment entity.

---

## MonthlyBalance

Tracks per-guide monthly workload.

Fields:
- worked_days
- bus_days
- balance

---

## WorkDayVersion

JSON audit log for events:
- generate_roles
- publish
- unpublish
- reset_roll
- regenerate_with_new_count

---

# 3. OPERATIONAL FLOW

## Create WorkDay
Operator creates WorkDay in draft state.

## Set Availability
GuideDay records may be pre-created with:
- day_off
- vacation

## Generate Roles
draft → generate_roles! → generated

Algorithm:
1. Sort guides by:
   - priority
   - monthly deviation from average
   - worked_this_month
   - total_worked_days
2. Assign worked up to guides_requested
3. Others → standby
4. Respect day_off and vacation
5. Update balances
6. Save snapshot

## Publish
generated → publish → published

Validates:
worked_count == guides_requested

## Reset Roll
generated/published → reset_roll → draft

- Reverts balances if necessary
- Deletes guide_days
- Allows redefining availability

## Regenerate with New Count
published/generated → regenerate_with_new_count → draft → generate_roles

- Reverts balances
- Deletes guide_days
- Updates guides_requested
- Regenerates algorithmically

---

# 4. BUSINESS RULES

1. Only one WorkDay per date
2. Priority 1 always precedes lower priorities
3. Cannot assign worked to day_off/vacation
4. Cannot publish incomplete assignments
5. Reset must restore equity
6. Changing guides_requested triggers regeneration

---

# 5. SYSTEM ARCHITECTURE

WorkDay
  ↳ GuideDay
      ↳ Guide
  ↳ WorkDayVersion

Guide
  ↳ MonthlyBalance

Service Layer:
RoleGenerator

Controller Layer:
WorkDaysController

---

# 6. AUDIT & TRACEABILITY

All structural events are logged in WorkDayVersion as JSON snapshots.

Ensures:
- Operational traceability
- Change history
- Accountability

---

# 7. KNOWN TECHNICAL RISKS

- Missing DB unique index on date
- No automated test suite
- Historical days not locked
- Manual DB edits could break equity

---

# 8. RECOMMENDED IMPROVEMENTS

Phase 1:
- Add unique index on work_days.date
- Add automated tests
- Restrict editing of historical days

Phase 2:
- Equity dashboard improvements
- Historical deviation graphs
- Monthly comparative reports

Phase 3:
- Predictive allocation model
- AI-based optimization
- PDF export for official roll

---

# 9. SYSTEM PHILOSOPHY

This system does not assign roles by favoritism.
It assigns roles by:

- Hierarchical priority
- Mathematical equity
- Historical balance
- Real availability

It is an operational justice engine.

---
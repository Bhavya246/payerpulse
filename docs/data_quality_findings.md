# Data quality framework: first run

29 rules (8 reconciliation, 6 completeness, 13 validity, 2 consistency; 13 CRITICAL, 13 WARN, 3 INFO).
Each rule is a SQL check stored in `audit.dq_rule`; `audit.usp_run_dq` runs them all and writes results to
`audit.dq_result`; `audit.v_dq_latest` feeds the monitoring report.

**Run 1 (2026-11-23):** 21 PASS, 5 WARN, 3 INFO, 0 FAIL, 0 ERROR, 27 seconds.

All warehouse-to-staging reconciliations (row counts and dollar totals) pass exactly. No claims or prescription
fills are dated after a member's death, no date inversions, no coverage months above 12.

| Rule | Finding | Share | Handling |
|---|---|---:|---|
| CMP01 | Outpatient claims without dates (segment-2 only) | 278 (0.04%) | Kept; excluded from time-based KPIs |
| CMP02 | Inpatient claims without principal diagnosis | 27 (0.04%) | Excluded from diagnosis-based KPIs |
| CMP04 | Carrier lines with neither NPI nor HCPCS | 1,106 (0.01%) | Kept for dollars; excluded from procedure analysis |
| VAL04 | Claims with a negative payment | 2,621 (0.05%) | Kept; payment totals are net |
| VAL05 | Length of stay differs from utilization days | 3,596 (5.39%) | ALOS uses calendar days |
| VAL06 | Admission date differs from claim from-date | 53 (0.08%) | Documented |
| VAL10 | Placeholder DRG `OTH` | 225 (0.34%) | Excluded from DRG-level KPIs |
| VAL11 | Placeholder NDC `OTHER` | 23 | Excluded from drug-level KPIs |

**Negative test:** one inpatient claim was deliberately given an end date before its start date inside a
transaction; rule VAL02 reported 1 failure, and the change was rolled back.

DE-SynPUF is synthetic: these findings describe the dataset, not real Medicare data.

## Coverage findings (member-years, before KPI definitions)

- 83.5% / 90.8% / 86.3% of member-years (2008 / 2009 / 2010) have a full year of Part A and Part B.
- Part A and B differ for 7.6% / 3.8% / 8.4%: these members average roughly 10 months of Part A and 2 of Part B
  (hospital-only coverage), so inpatient rates use Part A months and outpatient/carrier rates use Part B months.
- HMO months appear for 23.1% / 29.1% / 32.4% of member-years.
- 4,676 / 5,983 / 5,655 member-years have zero A and B months, yet 1,396 / 222 / 11 of them have claims in that year.
  Candidate rule: "claims in a year with no Part A/B coverage" (WARN).
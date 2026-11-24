# KPI catalog

DE-SynPUF is synthetic (2008-2010, ICD-9). KPI values demonstrate method, not real Medicare experience.
Claims are assigned to the year of their through-date. 2010 is not comparable with 2008-2009: the CMS manual
notes lower 2010 claim counts (attrition and disclosure treatment).

## Exposure (member months)

Only annual coverage-month totals exist (no monthly enrollment), so exposure is approximated per member-year.

| Rule | Definition |
|---|---|
| Months alive | 12; the month of death in the year of death; 0 if dead before the year |
| Inpatient exposure | MIN(Part A months, months alive) |
| Outpatient / carrier exposure | MIN(Part B months, months alive) |
| Rx exposure | MIN(Part D months, months alive) |
| HMO months | Not subtracted |
| Alignment | A claim counts only if the member has exposure in that category in that year |

Evidence from profiling:
- Part A and B differ for 7.6% / 3.8% / 8.4% of member-years (2008/2009/2010): hospital-only members average about
  10 months of Part A and 2 of Part B.
- HMO members (12 HMO months) have the same fee-for-service claims and dollars as non-HMO members
  (2008: 18.8 vs 20.2 claims; $4,761 vs $4,733), so HMO months do not reduce exposure here.
- 91.6% of members who died (5,002 of 5,461) still show 12 months of Part A in the year of death, so exposure is capped at the month of death.
- 4,676 / 5,983 / 5,655 member-years have no A/B months but are alive; 1,629 of them have claims in that year (rule CMP07).
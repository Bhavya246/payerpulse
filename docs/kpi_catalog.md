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

## PMPM (Medicare paid per member month)

PMPM = Medicare paid / member months, by service category, each with its own exposure
(inpatient: Part A months; outpatient and carrier: Part B months; Rx: Part D months).
Total medical PMPM = inpatient + outpatient + carrier PMPM. Claims are assigned to the year of their through-date.

| Year | Inpatient | Outpatient | Carrier | Total medical | Rx (gross cost) |
|---|---:|---:|---:|---:|---:|
| 2008 | 196.43 | 62.83 | 118.75 | 378.01 | 154.01 |
| 2009 | 191.76 | 74.47 | 130.39 | 396.62 | 129.39 |
| 2010 | 109.29 | 42.71 | 83.99 | 235.99 | 77.73 |

**Bridge to the warehouse:** PMPM numerators $1,268,429,660 + claims of members with no exposure $9,566,600 (0.75%)
+ undated outpatient claims $392,320 (0.03%) = $1,278,388,580, the reconciled total Medicare paid.

**Validation against the CMS manual (Table 8):** Medicare paid per beneficiary agrees within -2.4% to -0.9% (inpatient)
and +4.9% to +7.4% (outpatient, carrier). PMPM runs 5-22% above the manual's mean divided by 12 because our
denominator is exposure (86.9% / 91.9% / 90.4% of member-years x 12 for Part B), not all beneficiaries.

**Caveat:** 2010 is not comparable. The CMS manual notes lower 2010 claim counts (attrition and disclosure treatment),
so the ~40% drop in 2010 PMPM is a property of the synthetic file, not a trend.
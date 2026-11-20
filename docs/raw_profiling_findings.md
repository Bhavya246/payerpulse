# Raw layer: load reconciliation and profiling findings

**Source:** CMS DE-SynPUF Sample 1 (synthetic Medicare claims, 2008-2010, ICD-9 coded).
**Environment:** SQL Server 2025 (local), database `PayerPulse`, schema `raw`.
**Note:** DE-SynPUF is fully synthetic. CMS states that relationships between variables were altered
for disclosure protection, so clinical rates here are not realistic. This project demonstrates
reporting engineering and methods, not medical findings.

## 1. Load reconciliation

All files were loaded with `BULK INSERT` as text (no type conversion) and reconciled to the row counts
published in the CMS DE-SynPUF User Manual (Table 2).

| Source | Rows loaded | CMS published | Result |
|---|---:|---:|---|
| Beneficiary summary 2008 | 116,352 | 116,352 | Match |
| Beneficiary summary 2009 | 114,538 | 114,538 | Match |
| Beneficiary summary 2010 | 112,754 | 112,754 | Match |
| Inpatient claims | 66,773 | 66,773 | Match |
| Outpatient claims | 790,790 | 790,790 | Match |
| Carrier claims (A + B) | 4,741,335 | 4,741,335 | Match |
| Prescription drug events | 5,552,421 | 5,552,421 | Match |

Results are recorded in `audit.load_log`.

## 2. Profiling results (before building staging)

| Check | Result |
|---|---|
| Duplicate claim IDs, carrier and PDE | None (IDs unique) |
| Repeated `clm_id`, inpatient | 66,773 rows, 66,705 distinct claim IDs |
| Repeated `clm_id`, outpatient | 790,790 rows, 779,815 distinct claim IDs |
| Unique key `(clm_id, segment)` | Unique in both inpatient and outpatient |
| Missing claim dates | 68 inpatient and 11,253 outpatient rows, all of them `segment = 2` |
| Unparseable dates | 0 |
| Claim end date before start date | 0 |
| Discharge before admission (inpatient) | 0 |
| Non-numeric payment amounts | 0 |
| Negative `clm_pmt_amt` | 55 inpatient, 2,566 outpatient, 0 in PDE (smallest value is -100.00) |
| Orphan claims (member not in beneficiary file) | 0 in inpatient, outpatient, PDE |
| NDC codes (PDE) | 5,552,398 are 11 characters; 23 are the text `OTHER` |
| DRG codes (inpatient) | `OTH` appears 258 times |
| Heart failure flag | Only values 1 and 2 (101,752 yes, 241,892 no across 343,644 member-years) |
| Members with a death date | 5,461 of 343,644 member-years |

## 3. What the findings mean

- ** rows are continuation records, not bad data.** The codebook states a claim has at most
  two segments, one segment per 45 revenue lines. Segment 2 is a payment-only continuation record: in the 68 inpatient claims that have one, it carries no diagnosis or HCPCS codes. Discharge dates match segment 1 (in the sampled pairs), but segment 2’s admission date is 3-5 weeks earlier and differs in 61 of 68 pairs. It is not known which admission date is correct, so segment-2 dates are not used. All claim attributes come from segment 1; only payment amounts are summed across segments.
- **Placeholder codes:** `OTHER` (NDCSegment 2) and `OTH` (DRG) appear to be disclosure-treatment placeholders.
  The codebook says these fields were imputed, suppressed or coarsened but does not define these values.
- **Negative payments** are small (down to -100.00), consistent with adjustments.
- Segment-1 consistency (inpatient, 66,705 claims): discharge date = claim through-date in 100%; admission date = claim from-date in 99.9% (53 exceptions); calendar length of stay = utilization days in 94.6% (3,596 exceptions). Segment-1 dates are internally consistent and are used for all admission, LOS and readmission logic.
- Carrier service lines: all 13 line slots carry an amount on every one of the 4,741,335 claims (61,637,355 = 13 × 4,741,335), so empty slots hold zeros. A line is therefore identified by provider NPI or HCPCS code, never by amounts. Dollar totals are reconciled across all 13 slots against staging.

## 4. Rules adopted for staging

1. A claim is identified by `(claim type, clm_id)`; a row by `(clm_id, segment)`.
2. Claim counts, admissions, dates, member and provider come from segment 1 only.
3. Claim payment is the sum of payments across all segments.
4. Segment-2 rows are kept (they hold payments), never dropped.
5. Negative payments are kept and flagged (`is_adjustment`); payment totals are net of adjustments.
6. `OTHER` NDC and `OTH` DRG rows are kept and flagged, and excluded from drug-level and DRG-level KPIs.
7. Chronic condition flags: 1 = yes, 2 = no, converted to true/false. ESRD: `Y` = true, `0` = false.
8. Dates are `YYYYMMDD` text, converted with `TRY_CONVERT(date, x, 112)`. Report year follows the claim
   through-date, as the CMS manual defines.

## 5. Performance baseline (before indexing)

No indexes exist on the raw tables. Orphan-claim check (inpatient, outpatient and PDE claims against
`raw.beneficiary_summary`, using `NOT EXISTS`), measured 2026-11-19:

| Metric | Value |
|---|---:|
| Elapsed time | 32.4 s |
| CPU time | 4.6 s |

This query will be re-run after indexing, under the same conditions, to measure the improvement.
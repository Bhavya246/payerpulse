# PayerPulse

End-to-end healthcare claims reporting platform on CMS DE-SynPUF (synthetic Medicare claims, 2008-2010; ICD-9 coded).

**Status:** in progress.
- [x] Raw layer: 8 CMS files (11M+ claim rows) loaded into SQL Server and reconciled to published row counts
- [x] Staging layer: typed tables, flags, conversion checks, dollar reconciliation, audit log
- [ ] Star schema warehouse (dimensions, then facts)
- [ ] Data quality framework, KPI catalog
- [ ] Power BI dashboards, paginated reports

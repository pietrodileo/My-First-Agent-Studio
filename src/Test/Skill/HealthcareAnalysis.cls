Class Test.Skill.HealthcareAnalysis Extends %AI.Agent.Skill
{
XData SUMMARY [ MimeType="text/yaml" ]
{
name: synthetic-healthcare-analysis-brief
description: Build a reproducible, evidence-bound briefing from synthetic healthcare records.
parameters:
  - name: request
    description: Cohort filters and analysis requested by the user
    type: string
    required: true
tags:
  - healthcare
  - synthetic-data
  - analysis
}
XData INSTRUCTIONS [ MimeType="text/markdown" ]
{
Use `SearchPatients` to retrieve bounded records and `SummarizePatients` for full-cohort aggregates. Use StatisticsMCP only on values already returned by an IRIS tool. Never invent, interpolate, or silently extend data.

Write sections in this order:

1. Scope: filters, source, row count, and truncation.
2. Findings: exact aggregate values with units.
3. Example records: patient codes only, never names.
4. Limitations: synthetic random data, no causal or population inference.
5. Next analysis: one safe reproducible follow-up query.

Clearly distinguish IRIS aggregate results from calculations produced by StatisticsMCP. If a tool returns an error, report it and stop that analysis path. Never diagnose, score individual risk, recommend treatment, or present this dataset as clinical evidence.
}
}

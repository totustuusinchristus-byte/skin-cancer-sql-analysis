# Skin Cancer SQL Analysis

A PostgreSQL capstone examining patient demographics, environmental factors and lesion characteristics in a supplied skin cancer dataset.

## Tools
- PostgreSQL 18
- pgAdmin
- SQL joins, temporary views, CTEs, aggregations and window functions

## Analysis
- Validate patient and lesion records.
- Join patient and lesion tables using patient_id.
- Summarise diagnoses, age groups, exposures and symptoms.
- Compare body regions and lesion sizes.
- Prepare metadata for future modelling.

## Key findings
- The joined dataset contains 1,088 records.
- ACK is the most frequent diagnosis: 461 records (42.4%).
- BCC, SCC and MEL together account for 346 records (31.8%).
- Their combined proportion increases from 3.5% among patients under 30 to 40.7% among those aged 70+.
- Substantial missing measurements limit comparisons of lesion size and skin type.

## Files
- `Skin_cancer_SQL_Analysis.sql`: analytical queries.
- `Skin_Cancer_SQL_Report.pdf`: findings, limitations and recommendations.

## Running the SQL
1. Restore the supplied course database into PostgreSQL.
2. Confirm that public.table1 and public.table2 exist.
3. Open the SQL file in pgAdmin Query Tool.
4. Run the script in order within the same session.

The source database is not included in this repository.

## Limitations
Findings describe this sample and do not establish causation or population risk. BCC/SCC/MEL is a descriptive grouping, not a diagnostic model. Repeated lesion IDs and missing measurements require further investigation.

## Project context
DermAI Diagnostics is the fictional company named in the course brief.

## Author
Hyginus Echezona Okonkwo

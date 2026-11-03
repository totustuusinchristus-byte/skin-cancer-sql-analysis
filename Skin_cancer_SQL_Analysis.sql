-- DermAI Diagnostics | PostgreSQL 18 | Read-only analytical script
-- Restore Skin_Cancer_Dataset into a NEW empty database first.
-- The backup contains public.table1 (patients) and public.table2 (lesions).
-- Execute this script in pgAdmin Query Tool or psql; each SELECT is a result table.
-- Unit: one lesion per patient in this particular snapshot. Malignant proxy: BCC/SCC/MEL.

-- 01. Source and join checks
SELECT (SELECT COUNT(*) FROM public.table1) AS patients,
       (SELECT COUNT(*) FROM public.table2) AS lesions,
       (SELECT COUNT(*) FROM public.table1 p JOIN public.table2 l USING (patient_id)) AS joined_rows,
       (SELECT COUNT(*) FROM public.table2 l LEFT JOIN public.table1 p USING (patient_id)
        WHERE p.patient_id IS NULL) AS orphan_lesions,
       (SELECT COUNT(*) FROM (SELECT patient_id FROM public.table2 GROUP BY 1 HAVING COUNT(*) > 1) x) AS patients_with_multiple_lesions,
       (SELECT COUNT(*) FROM (SELECT lesion_id FROM public.table2 GROUP BY 1 HAVING COUNT(*) > 1) x) AS repeated_lesion_ids;

-- 02. Reusable joined analytical view; no writes to supplied tables
CREATE OR REPLACE TEMP VIEW dermai_analysis AS
SELECT p.patient_id, l.lesion_id, p.age, p.gender, p.smoke, p.drink,
       p.pesticide, p.skin_cancer_history, p.cancer_history,
       p.has_piped_water, p.has_sewage_system,
       NULLIF(upper(trim(p.background_father)), 'UNK') AS father_background,
       NULLIF(upper(trim(p.background_mother)), 'UNK') AS mother_background,
       l.fitspatrick, l.region, l.diameter_1, l.diameter_2,
       l.diagnostic, l.itch, l.grew, l.hurt, l.changed, l.bleed,
       l.elevation, l.biopsed, l.img_id,
       (l.diagnostic IN ('BCC','SCC','MEL')) AS malignant_proxy,
       CASE WHEN l.diameter_1 > 0 AND l.diameter_2 > 0
            THEN (l.diameter_1+l.diameter_2)/2.0 END AS mean_diameter_mm
FROM public.table1 p
JOIN public.table2 l ON l.patient_id = p.patient_id;

-- 03. Diagnosis mix and biopsy coverage
SELECT diagnostic, COUNT(*) AS lesions,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct_all,
       COUNT(*) FILTER (WHERE biopsed) AS biopsied,
       COUNT(*) FILTER (WHERE NOT biopsed) AS not_biopsied
FROM dermai_analysis GROUP BY diagnostic ORDER BY lesions DESC;

-- 04. Age bands, denominators included
SELECT CASE WHEN age < 30 THEN 'Under 30' WHEN age < 50 THEN '30-49'
            WHEN age < 70 THEN '50-69' ELSE '70+' END AS age_band,
       COUNT(*) AS lesions, COUNT(*) FILTER (WHERE malignant_proxy) AS malignant,
       ROUND(100.0*COUNT(*) FILTER (WHERE malignant_proxy)/NULLIF(COUNT(*),0),1) AS malignant_pct
FROM dermai_analysis GROUP BY 1 ORDER BY MIN(age);

-- 05. Demographic/environmental associations, unadjusted only
WITH strata AS (
 SELECT 'Gender' factor, gender category, malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Smokes', smoke::text, malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Alcohol', drink::text, malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Pesticide exposure', pesticide::text, malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Prior skin cancer', skin_cancer_history::text, malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Family cancer history', cancer_history::text, malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Piped water', has_piped_water::text, malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Sewage system', has_sewage_system::text, malignant_proxy FROM dermai_analysis
)
SELECT factor, category, COUNT(*) AS lesions,
       COUNT(*) FILTER (WHERE malignant_proxy) AS malignant,
       ROUND(100.0*COUNT(*) FILTER (WHERE malignant_proxy)/NULLIF(COUNT(*),0),1) AS malignant_pct
FROM strata GROUP BY factor,category ORDER BY factor,category;

-- 06. Lesion symptoms, unadjusted descriptive associations
WITH symptoms AS (
 SELECT 'Itch' feature, itch present, malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Growth',grew,malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Pain',hurt,malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Change',changed,malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Bleeding',bleed,malignant_proxy FROM dermai_analysis
 UNION ALL SELECT 'Elevation',elevation,malignant_proxy FROM dermai_analysis
)
SELECT feature,present,COUNT(*) lesions,COUNT(*) FILTER (WHERE malignant_proxy) malignant,
       ROUND(100.0*COUNT(*) FILTER (WHERE malignant_proxy)/NULLIF(COUNT(*),0),1) malignant_pct
FROM symptoms GROUP BY feature,present ORDER BY feature,present;

-- 07. Anatomical location
SELECT region,COUNT(*) lesions,COUNT(*) FILTER (WHERE malignant_proxy) malignant,
       ROUND(100.0*COUNT(*) FILTER (WHERE malignant_proxy)/NULLIF(COUNT(*),0),1) malignant_pct
FROM dermai_analysis GROUP BY region ORDER BY lesions DESC;

-- 08. Size: zeros treated as unavailable, not as real lesion diameters
SELECT diagnostic,COUNT(*) lesions,
       COUNT(mean_diameter_mm) valid_size_pairs,
       ROUND(AVG(mean_diameter_mm)::numeric,1) avg_mean_diameter_mm,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mean_diameter_mm)::numeric,1) median_mean_diameter_mm
FROM dermai_analysis GROUP BY diagnostic ORDER BY lesions DESC;

-- 09. Quality/label leakage checks
SELECT COUNT(*) rows_total,
       COUNT(*) FILTER (WHERE fitspatrick = 0) fitzpatrick_zero,
       COUNT(*) FILTER (WHERE diameter_1 = 0 AND diameter_2 = 0) both_diameters_zero,
       COUNT(*) FILTER (WHERE diameter_1 < 0 OR diameter_2 < 0) negative_diameter,
       COUNT(*) FILTER (WHERE malignant_proxy AND NOT biopsed) malignant_without_biopsy,
       COUNT(*) FILTER (WHERE NOT malignant_proxy AND biopsed) other_with_biopsy,
       COUNT(*) FILTER (WHERE age IS NULL OR gender IS NULL OR diagnostic IS NULL) essential_nulls
FROM dermai_analysis;

-- 10. ML-ready metadata (descriptive export only; no model performance claim).
-- -- Retain patient_id and lesion_id for record tracking.
-- Exclude biopsy status and img_id; convert zero-coded measurements to NULL.
-- For future modelling, exclude identifiers from predictors.
-- Keep records with a verified label only for supervised training, if provenance is confirmed.
SELECT patient_id, lesion_id, age, gender, smoke, drink, pesticide,
       skin_cancer_history, cancer_history, region,
       NULLIF(fitspatrick,0) AS fitzpatrick_skin_type,
       NULLIF(diameter_1,0) AS diameter_1_mm,
       NULLIF(diameter_2,0) AS diameter_2_mm,
       itch,grew,hurt,changed,bleed,elevation,diagnostic,malignant_proxy
FROM dermai_analysis ORDER BY patient_id,lesion_id;
-- Review labels, consent, provenance, and train/test separation before any modeling.

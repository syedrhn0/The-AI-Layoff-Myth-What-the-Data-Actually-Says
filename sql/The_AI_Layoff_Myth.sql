CREATE DATABASE layoff_investigation;
USE layoff_investigation;

-- checking layoff table
SELECT COUNT(*) FROM layoffs_raw;

-- creating new table
CREATE TABLE layoffs_clean (
    layoff_id            INT AUTO_INCREMENT PRIMARY KEY,
    company              VARCHAR(200),
    location             VARCHAR(200),
    country              VARCHAR(100),
    industry             VARCHAR(100),
    stage                VARCHAR(100),
    date_layoff          DATE,
    year                 INT,
    month                INT,
    quarter              VARCHAR(10),
    total_laid_off       INT,
    percentage_laid_off  DECIMAL(6,2),
    funds_raised_mil     DECIMAL(12,2),
    source               VARCHAR(1000),
    layoff_era           VARCHAR(50),
    layoff_size_bucket   VARCHAR(20)
);

-- copying data from layoffs_raw table
INSERT INTO layoffs_clean (
    company,
    location,
    country,
    industry,
    stage,
    date_layoff,
    year,
    month,
    quarter,
    total_laid_off,
    percentage_laid_off,
    funds_raised_mil,
    source,
    layoff_era,
    layoff_size_bucket
)
SELECT
    -- Text columns: trim whitespace
    TRIM(company),
    TRIM(location),
    TRIM(country),
    TRIM(industry),
    TRIM(stage),
 
    -- Date conversion: M/D/YYYY -> DATE
    -- STR_TO_DATE handles formats like 4/3/2026 and 3/31/2026
    STR_TO_DATE(TRIM(`date`), '%c/%e/%Y'),
 
    -- Year extracted from converted date
    YEAR(STR_TO_DATE(TRIM(`date`), '%c/%e/%Y')),
 
    -- Month extracted from converted date
    MONTH(STR_TO_DATE(TRIM(`date`), '%c/%e/%Y')),
 
    -- Quarter derived from month
    CASE
        WHEN MONTH(STR_TO_DATE(TRIM(`date`), '%c/%e/%Y')) IN (1,2,3)  THEN 'Q1'
        WHEN MONTH(STR_TO_DATE(TRIM(`date`), '%c/%e/%Y')) IN (4,5,6)  THEN 'Q2'
        WHEN MONTH(STR_TO_DATE(TRIM(`date`), '%c/%e/%Y')) IN (7,8,9)  THEN 'Q3'
        WHEN MONTH(STR_TO_DATE(TRIM(`date`), '%c/%e/%Y')) IN (10,11,12) THEN 'Q4'
        ELSE NULL
    END,
 
    -- total_laid_off: convert to INT, NULL if empty or non-numeric
	CASE
		WHEN TRIM(total_laid_off) = '' OR total_laid_off IS NULL THEN NULL
		ELSE CAST(CAST(TRIM(total_laid_off) AS DECIMAL(10,2)) AS UNSIGNED)
	END,
 
    -- percentage_laid_off: 0-1 in CSV -> multiply by 100 -> store as 0-100
    CASE
        WHEN TRIM(percentage_laid_off) = '' OR percentage_laid_off IS NULL THEN NULL
        ELSE ROUND(CAST(TRIM(percentage_laid_off) AS DECIMAL(10,6)) * 100, 2)
    END,
 
    -- funds_raised: already in millions in the CSV
    CASE
        WHEN TRIM(funds_raised) = '' OR funds_raised IS NULL THEN NULL
        ELSE CAST(TRIM(funds_raised) AS DECIMAL(12,2))
    END,
 
    TRIM(source),
 
    -- layoff_era: your primary analytical dimension
    -- Era boundaries based on real-world events:
    --   2020-2021: COVID pandemic forced shutdowns
    --   2022-2023: Companies reversed pandemic over-hiring
    --   2024-2026: AI adoption cited as restructuring driver
    CASE
        WHEN YEAR(STR_TO_DATE(TRIM(`date`), '%c/%e/%Y')) IN (2020, 2021) THEN 'Pandemic Era'
        WHEN YEAR(STR_TO_DATE(TRIM(`date`), '%c/%e/%Y')) IN (2022, 2023) THEN 'Over-Hiring Correction Era'
        WHEN YEAR(STR_TO_DATE(TRIM(`date`), '%c/%e/%Y')) IN (2024, 2025, 2026) THEN 'AI Pivot Era'
        ELSE 'Unknown'
    END,
 
    -- layoff_size_bucket: only where total_laid_off is known
    CASE
        WHEN TRIM(total_laid_off) = '' OR total_laid_off IS NULL THEN NULL
        WHEN CAST(CAST(TRIM(total_laid_off) AS DECIMAL(10,2)) AS UNSIGNED) < 100    THEN 'Small'
        WHEN CAST(CAST(TRIM(total_laid_off) AS DECIMAL(10,2)) AS UNSIGNED) < 1000   THEN 'Medium'
        WHEN CAST(CAST(TRIM(total_laid_off) AS DECIMAL(10,2)) AS UNSIGNED) < 5000   THEN 'Large'
        ELSE 'Mega'
    END
 
FROM layoffs_raw;

-- VERIFICATION after INSERT:
SELECT COUNT(*) AS total_rows FROM layoffs_clean;

-- Fix industry NULLs
UPDATE layoffs_clean SET industry = 'Other' WHERE industry IS NULL;

-- Fix country NULLs (2 rows: Fit Analytics, Ludia)
-- Cannot reliably guess country - label as Unknown
UPDATE layoffs_clean SET country = 'Unknown' WHERE country IS NULL;
 
-- Fix stage NULLs (5 rows)
-- Cannot reliably determine funding stage - label as Unknown
UPDATE layoffs_clean SET stage = 'Unknown' WHERE stage IS NULL;
 
-- Standardize country names for consistency
-- These specific mismatches were found in the data
UPDATE layoffs_clean SET country = 'United States' WHERE country IN ('US', 'USA', 'U.S.');
UPDATE layoffs_clean SET country = 'United Kingdom' WHERE country IN ('UK', 'U.K.');


-- VERIFICATION:
SELECT industry, COUNT(*)  FROM layoffs_clean  
WHERE industry IS NULL OR industry = '' GROUP BY industry;
 
SELECT DISTINCT country FROM layoffs_clean ORDER BY country;
 
SELECT layoff_size_bucket, COUNT(*) FROM layoffs_clean GROUP BY layoff_size_bucket 
ORDER BY layoff_size_bucket;

-- Fix: NULL, empty string, and whitespace-only values
UPDATE layoffs_clean SET industry = 'Other'
WHERE industry IS NULL OR TRIM(industry) = '';


-- REMOVE DUPLICATE ROWS
-- A duplicate = same company + same date + same total_laid_off
SELECT company, date_layoff, total_laid_off, country, COUNT(*) as cnt
FROM layoffs_clean GROUP BY company, date_layoff, total_laid_off, country
HAVING cnt > 1 ORDER BY company;


-- Delete true duplicates (keep lowest layoff_id)
-- This uses a subquery to identify which IDs to keep
DELETE FROM layoffs_clean
WHERE layoff_id NOT IN (
    SELECT min_id FROM (
        SELECT MIN(layoff_id) AS min_id
        FROM layoffs_clean
        GROUP BY company, date_layoff, total_laid_off, country
    ) AS keepers
);
 
 
 -- VERIFICATION:
SELECT COUNT(*) AS rows_after_dedup FROM layoffs_clean;
-- Expected: approximately 4335 rows (removed ~7 true duplicates)
-- (Cars24: -1, Beyond Meat: -1, Cazoo: -1, Terminus: -1, others: small)
 
SELECT company, date_layoff, total_laid_off, country, COUNT(*) as cnt
FROM layoffs_clean
GROUP BY company, date_layoff, total_laid_off, country
HAVING cnt > 1;
-- Expected: 0 rows (Oda will not appear here since countries differ)





-- 2026 AI TRACKER TABLE


-- creating layoff_2026_ai TABLE
CREATE TABLE layoffs_2026_ai_clean (
	layoff_ai_id INT AUTO_INCREMENT PRIMARY KEY,
	company VARCHAR(100),
	layoff_date DATE,
	jobs_cut INT,
	pct_workforce_cut DECIMAL(5,2),
	sector VARCHAR(100),
	country VARCHAR(100),
	region VARCHAR(100),
	ai_cited VARCHAR(20),
	reason_stated VARCHAR(300),
	simultaneous_ai_investment_bn DECIMAL(10,2),
	roles_most_affected VARCHAR(300),
	replacement_roles VARCHAR(300),
	verified_source VARCHAR(500),
	stock_reaction VARCHAR(20),
	stock_change_day_pct DECIMAL(5,2),
	pre_layoff_headcount INT,
	layoffs_2024 INT,
	layoffs_2025 INT,
	layoff_size_category VARCHAR(20)
);

INSERT INTO layoffs_2026_ai_clean (company, layoff_date, jobs_cut, pct_workforce_cut, sector, 
country, region, ai_cited, reason_stated, simultaneous_ai_investment_bn, roles_most_affected, 
replacement_roles, verified_source, stock_reaction, stock_change_day_pct, pre_layoff_headcount, 
layoffs_2024, layoffs_2025, layoff_size_category)
	SELECT company, layoff_date, jobs_cut, pct_workforce_cut, sector, country, region, ai_cited, 
	reason_stated, simultaneous_ai_investment_bn, roles_most_affected, replacement_roles, verified_source, 
    stock_reaction,	stock_change_day_pct, pre_layoff_headcount, layoffs_2024, layoffs_2025, layoff_size_category
    FROM layoffs_2026_ai_raw;
    

-- VERIFICATION after import:
SELECT COUNT(*) FROM layoffs_2026_ai_clean;
-- Expected: 28 rows
 
SELECT company, layoff_date, jobs_cut, ai_cited FROM layoffs_2026_ai_clean ORDER BY company;
-- ai_cited is not in the form of 1 or 0
-- lets update it:
UPDATE layoffs_2026_ai_clean SET ai_cited = CASE WHEN ai_cited = 'True' THEN 1 ELSE 0 END;
 
-- Remove the Algoma Steel duplicate (keep March 7 announcement, remove March 23)
-- March 7 = announcement date, March 23 = effective date (same event)
DELETE FROM layoffs_2026_ai_clean
WHERE company = 'Algoma Steel'
  AND layoff_date = '2026-03-23';
 
-- VERIFICATION:
SELECT COUNT(*) FROM layoffs_2026_ai_clean;
-- Expected: 27 rows
 
SELECT ai_cited, COUNT(*) FROM layoffs_2026_ai_clean GROUP BY ai_cited;
-- Expected: 0 (not cited) = 13, 1 (cited) = 14
-- Note: after removing Algoma Steel (ai_cited = False), 
-- the split becomes 13 False, 14 True
    
    
    
    
 -- COMPANY BRIDGE TABLE   
 -- Purpose: Maps company names between layoffs_clean and layoffs_2026_ai_clean.
-- Needed because names differ between datasets.
-- Built manually based on data analysis.   
    
 CREATE TABLE company_bridge (
    bridge_id        INT AUTO_INCREMENT PRIMARY KEY,
    clean_name       VARCHAR(200),  -- name in layoffs_clean
    ai_tracker_name  VARCHAR(200)   -- name in layoffs_2026_ai
);   
    
-- These 15 matches were identified by cross-referencing both datasets
-- Exact matches (13 companies match perfectly):
INSERT INTO company_bridge (clean_name, ai_tracker_name) VALUES
('Amazon',     'Amazon'),
('Block',      'Block'),
('Atlassian',  'Atlassian'),
('Oracle',     'Oracle'),
('Salesforce', 'Salesforce'),
('Autodesk',   'Autodesk'),
('eBay',       'eBay'),
('Pinterest',  'Pinterest'),
('Ericsson',   'Ericsson'),
('ASML',       'ASML'),
('Ocado',      'Ocado'),
('Livspace',   'Livspace'),
('Workday',    'Workday');

-- Near matches (name differs between datasets):
-- layoffs.csv has 'Meta', tracker has 'Meta Reality Labs' and 'Meta Platforms (Planned)'
INSERT INTO company_bridge (clean_name, ai_tracker_name) VALUES
('Meta',       'Meta Reality Labs'),
('Meta',       'Meta Platforms (Planned)');

-- layoffs.csv has 'WiseTech', tracker has 'WiseTech Global'
INSERT INTO company_bridge (clean_name, ai_tracker_name) VALUES
('WiseTech',   'WiseTech Global');


-- Companies in tracker with NO match in layoffs_clean 2026 data:
-- Cisco, T-Mobile, SK Battery America, Walgreens, Telefonica, xAI,
-- Palo Alto Networks, General Motors Tech, Ergo Insurance, ams OSRAM
-- These companies appear in the tracker but were not tracked in layoffs.fyi
-- for 2026. They will appear only in the 2026 evidence page (not joined).


-- VERIFICATION:
SELECT * FROM company_bridge;
-- Expected: 16 rows
 
SELECT cb.clean_name, cb.ai_tracker_name, ai.ai_cited, ai.reason_stated
FROM company_bridge cb
JOIN layoffs_2026_ai_clean ai ON cb.ai_tracker_name = ai.company
ORDER BY cb.clean_name;
-- Expected: 16 rows showing matched companies with their AI citation status





-- VIEWS

-- VIEW 1: Yearly summary
-- Powers: KPI cards, year bar chart, top-level numbers

CREATE VIEW v_layoffs_by_year AS
SELECT
    year,
    COUNT(*)                                    AS total_events,
    COUNT(CASE WHEN total_laid_off IS NOT NULL
               THEN 1 END)                      AS events_with_numbers,
    SUM(total_laid_off)                         AS reported_jobs_lost,
    ROUND(AVG(percentage_laid_off), 2)          AS avg_pct_workforce_cut,
    COUNT(DISTINCT company)                     AS companies_affected,
    COUNT(DISTINCT industry)                    AS industries_affected,
    layoff_era
FROM layoffs_clean
GROUP BY year, layoff_era
ORDER BY year;
 
-- Test it:
SELECT * FROM v_layoffs_by_year;
 
 
-- VIEW 2: Era summary (your primary comparison view)
-- Powers: Era KPI cards, era comparison bar charts

CREATE VIEW v_layoffs_by_era AS
SELECT
    layoff_era,
    COUNT(*)                                    AS total_events,
    SUM(total_laid_off)                         AS reported_jobs_lost,
    ROUND(AVG(percentage_laid_off), 2)          AS avg_pct_workforce_cut,
    COUNT(DISTINCT company)                     AS companies_affected,
    COUNT(DISTINCT industry)                    AS industries_affected,
    ROUND(AVG(funds_raised_mil), 2)             AS avg_funds_raised_mil,
    -- Era ordering field for correct sort in Power BI
    CASE layoff_era
        WHEN 'Pandemic Era'               THEN 1
        WHEN 'Over-Hiring Correction Era' THEN 2
        WHEN 'AI Pivot Era'               THEN 3
    END                                         AS era_order
FROM layoffs_clean
GROUP BY layoff_era
ORDER BY era_order;
 
-- Test it:
SELECT * FROM v_layoffs_by_era;
 
 
-- VIEW 3: Industry breakdown by era
-- Powers: Stacked bar showing which industries dominated each era

CREATE VIEW v_layoffs_by_era_industry AS
SELECT
    layoff_era,
    industry,
    COUNT(*)            AS total_events,
    SUM(total_laid_off) AS reported_jobs_lost,
    ROUND(AVG(percentage_laid_off), 2) AS avg_pct_cut,
    CASE layoff_era
        WHEN 'Pandemic Era'               THEN 1
        WHEN 'Over-Hiring Correction Era' THEN 2
        WHEN 'AI Pivot Era'               THEN 3
    END AS era_order
FROM layoffs_clean
WHERE industry IS NOT NULL AND industry != ''
GROUP BY layoff_era, industry
ORDER BY era_order, total_events DESC;
 
-- Test it:
SELECT * FROM v_layoffs_by_era_industry WHERE layoff_era = 'AI Pivot Era' ORDER BY total_events DESC LIMIT 10;
 
 
-- VIEW 4: Company stage breakdown by era
-- Powers: Grouped bar showing Post-IPO vs startup split per era

CREATE VIEW v_layoffs_by_era_stage AS
SELECT
    layoff_era,
    stage,
    COUNT(*)            AS total_events,
    SUM(total_laid_off) AS reported_jobs_lost,
    ROUND(AVG(percentage_laid_off), 2) AS avg_pct_cut,
    CASE layoff_era
        WHEN 'Pandemic Era'               THEN 1
        WHEN 'Over-Hiring Correction Era' THEN 2
        WHEN 'AI Pivot Era'               THEN 3
    END AS era_order
FROM layoffs_clean
WHERE stage IS NOT NULL AND stage != ''
GROUP BY layoff_era, stage
ORDER BY era_order, total_events DESC;
 
-- Test it:
SELECT * FROM v_layoffs_by_era_stage;
 
 
-- VIEW 5: Quarterly trend (your main timeline chart)
-- Powers: Line/area chart across the full 2020-2026 timeline

CREATE VIEW v_layoffs_quarterly_trend AS
SELECT
    year,
    quarter,
    CONCAT(year, '-', quarter)          AS year_quarter,   -- e.g. "2024-Q1"
    layoff_era,
    COUNT(*)                            AS total_events,
    SUM(total_laid_off)                 AS reported_jobs_lost,
    ROUND(AVG(percentage_laid_off), 2)  AS avg_pct_cut,
    COUNT(DISTINCT company)             AS companies_affected,
    -- Sort key for correct chronological order in Power BI
    (year * 10 + 
        CASE quarter WHEN 'Q1' THEN 1 
                     WHEN 'Q2' THEN 2 
                     WHEN 'Q3' THEN 3 
                     WHEN 'Q4' THEN 4 END) AS sort_key
FROM layoffs_clean
WHERE year IS NOT NULL AND quarter IS NOT NULL
GROUP BY year, quarter, year_quarter, layoff_era
ORDER BY sort_key;
 
-- Test it:
SELECT * FROM v_layoffs_quarterly_trend ORDER BY sort_key;
 
 
-- VIEW 6: Country breakdown by era (top 15 countries only)
-- Powers: Map visual and country bar chart

CREATE VIEW v_layoffs_by_country_era AS
SELECT
    country,
    layoff_era,
    COUNT(*)            AS total_events,
    SUM(total_laid_off) AS reported_jobs_lost,
    ROUND(AVG(percentage_laid_off), 2) AS avg_pct_cut,
    CASE layoff_era
        WHEN 'Pandemic Era'               THEN 1
        WHEN 'Over-Hiring Correction Era' THEN 2
        WHEN 'AI Pivot Era'               THEN 3
    END AS era_order
FROM layoffs_clean
WHERE country IN (
    -- Top 15 countries by total events (pre-calculated from data)
    SELECT country FROM (
        SELECT country, COUNT(*) AS cnt
        FROM layoffs_clean
        WHERE country IS NOT NULL AND country NOT IN ('Unknown','')
        GROUP BY country
        ORDER BY cnt DESC
        LIMIT 15
    ) AS top_countries
)
GROUP BY country, layoff_era
ORDER BY country, era_order;
 
-- Test it:
SELECT * FROM v_layoffs_by_country_era ORDER BY reported_jobs_lost DESC LIMIT 20;
 
 
-- VIEW 7: 2026 AI evidence (your evidence page - joins both datasets)
-- Powers: Page 3 of dashboard - the direct AI investigation

CREATE VIEW v_2026_ai_evidence AS
SELECT
    ai.company,
    ai.layoff_date,
    ai.jobs_cut,
    ai.pct_workforce_cut,
    ai.sector,
    ai.country,
    ai.region,
    ai.ai_cited,
    CASE ai.ai_cited WHEN 1 THEN 'AI Cited' ELSE 'Not Cited' END AS ai_cited_label,
    ai.reason_stated,
    ai.simultaneous_ai_investment_bn,
    ai.roles_most_affected,
    CASE 
        WHEN ai.replacement_roles = 'None announced' THEN 'No replacement roles announced'
        ELSE ai.replacement_roles 
    END AS replacement_roles,
    ai.stock_reaction,
    ai.stock_change_day_pct,
    ai.pre_layoff_headcount,
    ai.layoffs_2024,
    ai.layoffs_2025,
    ai.layoff_size_category,
    -- Historical context: total prior layoffs at this company
    (ai.layoffs_2024 + ai.layoffs_2025)     AS prior_layoffs_2024_2025,
    -- Is this a repeat offender? (had layoffs in BOTH prior years)
    CASE 
        WHEN ai.layoffs_2024 > 0 AND ai.layoffs_2025 > 0 THEN 'Serial'
        WHEN ai.layoffs_2024 > 0 OR  ai.layoffs_2025 > 0 THEN 'Repeat'
        ELSE 'First Time'
    END AS layoff_history_type,
    -- Investment vs cuts ratio (how much AI investment per job cut?)
    CASE 
        WHEN ai.jobs_cut > 0 
        THEN ROUND((ai.simultaneous_ai_investment_bn * 1000000000) / ai.jobs_cut, 0)
        ELSE NULL 
    END AS ai_investment_per_job_cut_usd
FROM layoffs_2026_ai_clean ai
ORDER BY ai.jobs_cut DESC;
 
-- Test it:
SELECT * FROM v_2026_ai_evidence;
 
 
-- VIEW 8: Size bucket distribution by era
-- Powers: Showing whether layoffs are getting larger over time

CREATE VIEW v_size_bucket_by_era AS
SELECT
    layoff_era,
    layoff_size_bucket,
    COUNT(*) AS total_events,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY layoff_era), 2) AS pct_of_era,
    CASE layoff_era
        WHEN 'Pandemic Era'               THEN 1
        WHEN 'Over-Hiring Correction Era' THEN 2
        WHEN 'AI Pivot Era'               THEN 3
    END AS era_order,
    CASE layoff_size_bucket
        WHEN 'Small' THEN 1
        WHEN 'Medium' THEN 2
        WHEN 'Large'  THEN 3
        WHEN 'Mega'   THEN 4
        ELSE 5
    END AS size_order
FROM layoffs_clean
WHERE layoff_size_bucket IS NOT NULL
GROUP BY layoff_era, layoff_size_bucket
ORDER BY era_order, size_order;
 
-- Test it:
SELECT * FROM v_size_bucket_by_era;





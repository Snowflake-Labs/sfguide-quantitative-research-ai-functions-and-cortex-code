-- Copyright 2026 Snowflake Inc.
-- SPDX-License-Identifier: Apache-2.0
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

/*-----------------------------------------------------------------------------
  FSI AI SQL & Data Science Agent Demo - Teardown Script
  
  This script removes all objects created by the demo.
  
  WARNING: This will permanently delete all data and objects!
  
  Run this script to clean up after completing the demo.
-----------------------------------------------------------------------------*/

USE ROLE FSI_DEMO_ROLE;

-- ============================================================================
-- Drop Snowflake Intelligence Agent
-- ============================================================================
DROP AGENT IF EXISTS FSI_DEMO_DB.ANALYTICS.QUANTITATIVE_RESEARCH_AGENT;

-- ============================================================================
-- Drop Cortex Search Service
-- ============================================================================
DROP CORTEX SEARCH SERVICE IF EXISTS FSI_DEMO_DB.ANALYTICS.DOW_ANALYSTS_SENTIMENT_ANALYSIS;

-- ============================================================================
-- Drop Semantic View
-- ============================================================================
DROP SEMANTIC VIEW IF EXISTS FSI_DEMO_DB.ANALYTICS.ANALYST_SENTIMENTS_VIEW;

-- ============================================================================
-- Drop Notebooks
-- ============================================================================
DROP NOTEBOOK IF EXISTS FSI_DEMO_DB.ANALYTICS.START_HERE;
DROP NOTEBOOK IF EXISTS FSI_DEMO_DB.ANALYTICS.TRAIN_ML_MODELS;
DROP NOTEBOOK IF EXISTS FSI_DEMO_DB.ANALYTICS.CREATE_CORTEX_COMPONENTS;

-- ============================================================================
-- Drop ML Models from Registry (if created)
-- ============================================================================
-- Note: Models are named FIS_{YEAR}Q{QUARTER} based on when training ran.
-- Check existing models with: SHOW MODELS IN SCHEMA FSI_DEMO_DB.ANALYTICS;
-- Then drop each one, e.g.:
-- DROP MODEL IF EXISTS FSI_DEMO_DB.ANALYTICS.FIS_2024Q4;
-- DROP MODEL IF EXISTS FSI_DEMO_DB.ANALYTICS.FIS_2025Q1;
-- DROP MODEL IF EXISTS FSI_DEMO_DB.ANALYTICS.FIS_2025Q2;
-- DROP MODEL IF EXISTS FSI_DEMO_DB.ANALYTICS.FIS_2025Q3;
-- DROP MODEL IF EXISTS FSI_DEMO_DB.ANALYTICS.FIS_2025Q4;

-- ============================================================================
-- Drop Stored Procedures
-- ============================================================================
DROP PROCEDURE IF EXISTS FSI_DEMO_DB.ANALYTICS.GET_TOP_BOTTOM_STOCK_PREDICTIONS(STRING, INTEGER);
DROP PROCEDURE IF EXISTS FSI_DEMO_DB.ANALYTICS.SEND_EMAIL(VARCHAR, VARCHAR, VARCHAR);

-- ============================================================================
-- Drop Tables
-- ============================================================================
DROP TABLE IF EXISTS FSI_DEMO_DB.ANALYTICS.FSI_DATA;
DROP TABLE IF EXISTS FSI_DEMO_DB.ANALYTICS.AI_TRANSCRIPTS_ANALYSTS_SENTIMENTS;
DROP TABLE IF EXISTS FSI_DEMO_DB.ANALYTICS.UNIQUE_TRANSCRIPTS;

-- ============================================================================
-- Drop Git Repository
-- ============================================================================
DROP GIT REPOSITORY IF EXISTS FSI_DEMO_DB.ANALYTICS.FSI_DEMO_REPO;

-- ============================================================================
-- Drop Stages (none currently used)
-- ============================================================================
-- Note: SEMANTIC_MODELS stage removed - using semantic view instead

-- ============================================================================
-- Drop Notification Integration (requires ACCOUNTADMIN)
-- ============================================================================
USE ROLE ACCOUNTADMIN;
DROP NOTIFICATION INTEGRATION IF EXISTS EMAIL_INTEGRATION;

-- ============================================================================
-- Drop Git API Integration
-- ============================================================================
DROP API INTEGRATION IF EXISTS GIT_HTTPS_API;

-- ============================================================================
-- Drop Database
-- ============================================================================
USE ROLE FSI_DEMO_ROLE;
DROP DATABASE IF EXISTS FSI_DEMO_DB;

-- ============================================================================
-- Drop Warehouse
-- ============================================================================
DROP WAREHOUSE IF EXISTS FSI_DEMO_WH;

-- ============================================================================
-- Drop Compute Pool (requires ACCOUNTADMIN)
-- ============================================================================
USE ROLE ACCOUNTADMIN;
DROP COMPUTE POOL IF EXISTS FSI_DEMO_COMPUTE_POOL;

-- ============================================================================
-- Drop Snowflake Intelligence Object
-- ============================================================================
DROP SNOWFLAKE INTELLIGENCE IF EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

-- ============================================================================
-- Drop Demo Role
-- ============================================================================
DROP ROLE IF EXISTS FSI_DEMO_ROLE;

SELECT 'Teardown completed successfully!' AS STATUS;

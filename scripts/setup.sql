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

-- ============================================================================
-- FSI Demo Setup Script
-- Purpose: Setup for Quantitative Research with AI SQL and Cortex Code
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ============================================================================
-- Auto-install Snowflake Public Data (Free) from Marketplace
-- Note: May require manual acceptance on some accounts
-- ============================================================================
CREATE WAREHOUSE IF NOT EXISTS FSI_DEMO_WH WITH WAREHOUSE_SIZE = 'LARGE' AUTO_SUSPEND = 300 AUTO_RESUME = TRUE;
USE WAREHOUSE FSI_DEMO_WH;
CALL SYSTEM$REQUEST_LISTING_AND_WAIT('GZTSZ290BV255');
CALL SYSTEM$ACCEPT_LEGAL_TERMS('DATA_EXCHANGE_LISTING', 'GZTSZ290BV255');
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_PUBLIC_DATA_FREE FROM LISTING 'GZTSZ290BV255';

-- Set query tag for tracking
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"quantitative_research_aisql_cortex","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"source":"sql"}}';

-- ============================================================================
-- SECTION 1: Role and Grants Setup
-- ============================================================================

CREATE ROLE IF NOT EXISTS FSI_DEMO_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE FSI_DEMO_ROLE;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE FSI_DEMO_ROLE;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE FSI_DEMO_ROLE;

-- Grant access to Snowflake Marketplace Free Public Data (imported database)
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_PUBLIC_DATA_FREE TO ROLE FSI_DEMO_ROLE;

SET CURRENT_USER = (SELECT CURRENT_USER());   
GRANT ROLE FSI_DEMO_ROLE TO USER IDENTIFIER($CURRENT_USER);

-- Enable cross-region Cortex features
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

USE ROLE FSI_DEMO_ROLE;

-- ============================================================================
-- SECTION 2: Database and Schema Setup
-- ============================================================================

CREATE DATABASE IF NOT EXISTS FSI_DEMO_DB;
CREATE SCHEMA IF NOT EXISTS FSI_DEMO_DB.ANALYTICS;

-- Grant explicit privileges on database and schema to FSI_DEMO_ROLE
GRANT USAGE ON DATABASE FSI_DEMO_DB TO ROLE FSI_DEMO_ROLE;
GRANT ALL PRIVILEGES ON SCHEMA FSI_DEMO_DB.ANALYTICS TO ROLE FSI_DEMO_ROLE;
GRANT CREATE TABLE ON SCHEMA FSI_DEMO_DB.ANALYTICS TO ROLE FSI_DEMO_ROLE;
GRANT CREATE STAGE ON SCHEMA FSI_DEMO_DB.ANALYTICS TO ROLE FSI_DEMO_ROLE;

USE DATABASE FSI_DEMO_DB;
USE SCHEMA ANALYTICS;

-- ============================================================================
-- SECTION 3: Warehouse and Compute Pool Setup
-- ============================================================================

CREATE OR REPLACE WAREHOUSE FSI_DEMO_WH WITH 
    WAREHOUSE_SIZE = 'LARGE'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE FSI_DEMO_WH;

-- Create dedicated compute pool for container notebooks
USE ROLE ACCOUNTADMIN;
CREATE COMPUTE POOL IF NOT EXISTS FSI_DEMO_COMPUTE_POOL
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_M
  AUTO_SUSPEND_SECS = 300
  AUTO_RESUME = TRUE;

GRANT USAGE ON COMPUTE POOL FSI_DEMO_COMPUTE_POOL TO ROLE FSI_DEMO_ROLE;
USE ROLE FSI_DEMO_ROLE;

-- ============================================================================
-- SECTION 4: Snowflake Intelligence and Cortex Setup
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- Enable cross-region Cortex (required for accounts not in Cortex-enabled regions)
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- Create Snowflake Intelligence object
CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

-- Snowflake Intelligence grants
GRANT CREATE SNOWFLAKE INTELLIGENCE ON ACCOUNT TO ROLE FSI_DEMO_ROLE;
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE FSI_DEMO_ROLE;
GRANT MODIFY ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE FSI_DEMO_ROLE;
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE PUBLIC;

-- AI/Cortex component creation grants
GRANT CREATE AGENT ON SCHEMA FSI_DEMO_DB.ANALYTICS TO ROLE FSI_DEMO_ROLE;
GRANT CREATE CORTEX SEARCH SERVICE ON SCHEMA FSI_DEMO_DB.ANALYTICS TO ROLE FSI_DEMO_ROLE;
GRANT CREATE SEMANTIC VIEW ON SCHEMA FSI_DEMO_DB.ANALYTICS TO ROLE FSI_DEMO_ROLE;

-- Account-level Cortex privileges (required for LLM functions)
GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO ROLE FSI_DEMO_ROLE;

USE ROLE FSI_DEMO_ROLE;
USE DATABASE FSI_DEMO_DB;
USE SCHEMA ANALYTICS;

-- ============================================================================
-- SECTION 5: Table Setup
-- ============================================================================

-- FSI_DATA: Pre-computed features from Cybersyn price data
-- This enables faster training - features are computed once during setup
CREATE OR REPLACE TABLE FSI_DATA AS
WITH dow30_prices AS (
    -- Get DOW 30 stock prices from Cybersyn
    SELECT 
        ticker,
        date,
        value AS price
    FROM SNOWFLAKE_PUBLIC_DATA_FREE.PUBLIC_DATA_FREE.STOCK_PRICE_TIMESERIES
    WHERE ticker IN ('MMM', 'AXP', 'AMGN', 'AMZN', 'AAPL', 'BA', 'CAT', 'CVX', 'CSCO', 'KO', 'DIS', 'GS', 'HD', 'HON', 'IBM', 'JNJ', 'JPM', 'MCD', 'MRK', 'MSFT', 'NKE', 'PG', 'RTX', 'CRM', 'SHW', 'TRV', 'UNH', 'V', 'WMT', 'NVDA')
      AND variable = 'post-market_close'
      AND date >= '2020-01-01'
),
with_returns AS (
    SELECT 
        ticker,
        date,
        price,
        LN(price / LAG(price, 1) OVER (PARTITION BY ticker ORDER BY date)) AS return
    FROM dow30_prices
),
with_features AS (
    SELECT 
        ticker,
        date,
        price,
        return,
        -- r_1: 1-day return
        return AS r_1,
        -- r_5_1: return from t-5 to t-1 (4 days)
        LN(LAG(price, 1) OVER (PARTITION BY ticker ORDER BY date) / 
           LAG(price, 5) OVER (PARTITION BY ticker ORDER BY date)) AS r_5_1,
        -- r_10_5: return from t-10 to t-5 (5 days)
        LN(LAG(price, 5) OVER (PARTITION BY ticker ORDER BY date) / 
           LAG(price, 10) OVER (PARTITION BY ticker ORDER BY date)) AS r_10_5,
        -- r_21_10: return from t-21 to t-10 (11 days)
        LN(LAG(price, 10) OVER (PARTITION BY ticker ORDER BY date) / 
           LAG(price, 21) OVER (PARTITION BY ticker ORDER BY date)) AS r_21_10,
        -- r_63_21: return from t-63 to t-21 (42 days)
        LN(LAG(price, 21) OVER (PARTITION BY ticker ORDER BY date) / 
           LAG(price, 63) OVER (PARTITION BY ticker ORDER BY date)) AS r_63_21,
        -- y: target variable - return from t+2 to t+6 (forward 5-day return)
        LN(LEAD(price, 6) OVER (PARTITION BY ticker ORDER BY date) / 
           LEAD(price, 2) OVER (PARTITION BY ticker ORDER BY date)) AS y
    FROM with_returns
)
SELECT * FROM with_features
WHERE r_1 IS NOT NULL 
  AND r_5_1 IS NOT NULL 
  AND r_10_5 IS NOT NULL 
  AND r_21_10 IS NOT NULL 
  AND r_63_21 IS NOT NULL;

-- AI_TRANSCRIPTS_ANALYSTS_SENTIMENTS: Populated by Notebook 1
-- NOTE: Notebook 1 uses CREATE OR REPLACE to ensure data is populated
CREATE TABLE IF NOT EXISTS AI_TRANSCRIPTS_ANALYSTS_SENTIMENTS (
    primary_ticker VARCHAR,
    event_timestamp TIMESTAMP_NTZ,
    event_type VARCHAR,
    created_at TIMESTAMP_NTZ,
    sentiment_score NUMBER(38,0),
    unique_analyst_count NUMBER(38,0),
    sentiment_reason VARCHAR
);

-- UNIQUE_TRANSCRIPTS: Staging table for transcript deduplication
CREATE OR REPLACE TABLE UNIQUE_TRANSCRIPTS (
    primary_ticker VARCHAR,
    event_timestamp TIMESTAMP_NTZ,
    event_type VARCHAR,
    created_at TIMESTAMP_NTZ,
    transcript VARIANT
);

-- Populate UNIQUE_TRANSCRIPTS from Marketplace data (DOW Jones 30 tickers)
INSERT INTO UNIQUE_TRANSCRIPTS
WITH filtered_transcripts AS (
    SELECT *
    FROM SNOWFLAKE_PUBLIC_DATA_FREE.PUBLIC_DATA_FREE.COMPANY_EVENT_TRANSCRIPT_ATTRIBUTES
    WHERE primary_ticker IN ('MMM', 'AXP', 'AMGN', 'AMZN', 'AAPL', 'BA', 'CAT', 'CVX', 'CSCO', 'KO', 'DIS', 'GS', 'HD', 'HON', 'IBM', 'JNJ', 'JPM', 'MCD', 'MRK', 'MSFT', 'NKE', 'PG', 'RTX', 'CRM', 'SHW', 'TRV', 'UNH', 'V', 'WMT', 'NVDA')
      AND event_type = 'Earnings Call'
      AND transcript_type = 'SPEAKERS_ANNOTATED'
      AND transcript IS NOT NULL
      AND event_timestamp >= '2024-01-01'
    ORDER BY event_timestamp DESC
),
deduplicated_transcripts AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY primary_ticker, event_timestamp
            ORDER BY created_at ASC   -- keep the earliest version (point-in-time)
        ) AS rn
    FROM filtered_transcripts
)
SELECT
    primary_ticker,
    event_timestamp,
    event_type,
    created_at,
    transcript
FROM deduplicated_transcripts
WHERE rn = 1;

-- ============================================================================
-- SECTION 7: Stored Procedures
-- ============================================================================

-- Stock Performance Predictor using registered ML models
CREATE OR REPLACE PROCEDURE GET_TOP_BOTTOM_STOCK_PREDICTIONS(
    MODEL_NAME STRING DEFAULT NULL,
    TOP_N INTEGER DEFAULT 5
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'pandas', 'numpy')
HANDLER = 'main'
EXECUTE AS OWNER
AS
$$
import pandas as pd
import json
import snowflake.snowpark as snowpark
import snowflake.snowpark.functions as F
from snowflake.snowpark.window import Window

def get_latest_model(session: snowpark.Session) -> str:
    """Dynamically find the latest registered ML model."""
    try:
        session.sql("SHOW MODELS LIKE 'FIS_%'").collect()
        result = session.sql("""
            SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) 
            ORDER BY "created_on" DESC LIMIT 1
        """).collect()
        if result:
            return result[0][0]
    except:
        pass
    return None

def parse_prediction(prediction_json):
    """Parse prediction JSON from ML model output."""
    try:
        if isinstance(prediction_json, str):
            prediction_dict = json.loads(prediction_json)
            return float(prediction_dict['output_feature_0'])
        elif isinstance(prediction_json, dict) and 'output_feature_0' in prediction_json:
            return float(prediction_json['output_feature_0'])
        else:
            return float(prediction_json)
    except:
        return None
        
def get_top_bottom_stock_predictions(session: snowpark.Session, 
                                   model_name: str = None,
                                   top_n: int = 5) -> str:
    """
    Generate stock forecasts using batch predictions for maximum performance.
    Uses registered ML models to predict stock returns based on momentum features.
    If model_name is not provided, automatically uses the latest FIS_* model.
    """
    
    try:
        # Auto-detect latest model if not specified
        if model_name is None or model_name.strip() == '':
            model_name = get_latest_model(session)
            if model_name is None:
                return "ERROR: No ML models found. Please run the TRAIN_ML_MODELS notebook first."
        
        # Validate FSI data source exists
        fsi_table_name = "FSI_DATA"
        
        try:
            fsi_df = session.table(fsi_table_name)
            schema = fsi_df.schema
            column_names = [field.name for field in schema.fields]
            
            # Find column mappings
            ticker_col = None
            date_col = None
            price_col = None
            
            for col_name in column_names:
                clean_name = col_name.strip('"').upper()
                if clean_name in ['TICKER', 'SYMBOL']:
                    ticker_col = col_name
                elif clean_name in ['DATE', 'DT']:
                    date_col = col_name
                elif clean_name in ['PRICE', 'CLOSE', 'CLOSE_PRICE']:
                    price_col = col_name
            
            if not all([ticker_col, date_col, price_col]):
                return f"ERROR: FSI_DATA missing required columns. Found: {column_names}. Need: ticker, date, price columns."
                
        except Exception as e:
            raise ValueError(f"""ERROR: {str(e)}""")
        
        # Check for pre-calculated features
        feature_columns = {}
        for col_name in column_names:
            clean_name = col_name.strip('"').upper()
            if clean_name == 'R_1':
                feature_columns['r_1'] = col_name
            elif clean_name == 'R_5_1':
                feature_columns['r_5_1'] = col_name
            elif clean_name == 'R_10_5':
                feature_columns['r_10_5'] = col_name
            elif clean_name == 'R_21_10':
                feature_columns['r_21_10'] = col_name
            elif clean_name == 'R_63_21':
                feature_columns['r_63_21'] = col_name
        
        window_spec = Window.partition_by(F.col(ticker_col)).order_by(F.col(date_col).desc())
        
        # Get latest record per ticker with complete features
        latest_features_df = fsi_df.filter(
            F.col(feature_columns['r_1']).is_not_null() &
            F.col(feature_columns['r_5_1']).is_not_null() &
            F.col(feature_columns['r_10_5']).is_not_null() &
            F.col(feature_columns['r_21_10']).is_not_null() &
            F.col(feature_columns['r_63_21']).is_not_null()
        ).with_column(
            "row_num", 
            F.row_number().over(window_spec)
        ).filter(
            F.col("row_num") == 1
        ).select(
            F.col(ticker_col).alias("ticker"),
            F.col(feature_columns['r_1']).alias("r_1"),
            F.col(feature_columns['r_5_1']).alias("r_5_1"),
            F.col(feature_columns['r_10_5']).alias("r_10_5"),
            F.col(feature_columns['r_21_10']).alias("r_21_10"),
            F.col(feature_columns['r_63_21']).alias("r_63_21")
        )
        
        # Batch predict using registered model (use fully qualified name)
        batch_predictions_df = latest_features_df.with_column(
            "prediction_json",
            F.call_function(f"FSI_DEMO_DB.ANALYTICS.{model_name}!PREDICT", 
                          F.col("r_1"), 
                          F.col("r_5_1"), 
                          F.col("r_10_5"), 
                          F.col("r_21_10"), 
                          F.col("r_63_21"))
        ).select(
            F.col("ticker"),
            F.col("prediction_json")
        )
        
        prediction_results = batch_predictions_df.collect()
        
        # Process all predictions
        predictions = []
        for row in prediction_results:
            try:
                ticker = row[0]
                prediction_json = row[1]
                prediction_value = parse_prediction(prediction_json)
                
                if prediction_value is not None:
                    predictions.append((ticker, prediction_value))
                    
            except Exception as e:
                continue
        
        if not predictions:
            return "ERROR: No valid predictions could be generated for any symbols."
        
        # Sort predictions by value (descending)
        predictions.sort(key=lambda x: x[1], reverse=True)
        
        # Get top N and bottom N
        top_n_results = predictions[:top_n]
        bottom_n_results = predictions[-top_n:] if len(predictions) >= top_n else []
        
        # Format the output
        result = f"Using model: {model_name}\n\n"
        result += f"TOP {top_n} PREDICTED PERFORMERS:\n"
        for i, (symbol, prediction) in enumerate(top_n_results, 1):
            result += f"{i}. {symbol}: {prediction:.6f}\n"
        
        if bottom_n_results:
            result += f"\nBOTTOM {top_n} PREDICTED PERFORMERS:\n"
            for i, (symbol, prediction) in enumerate(bottom_n_results, 1):
                result += f"{i}. {symbol}: {prediction:.6f}\n"
        
        return result
        
    except Exception as e:
        return f"ERROR generating predictions: {str(e)}"

def main(session: snowpark.Session, model_name: str = None, top_n: int = 5) -> str:
    """Main handler function for the stored procedure."""
    return get_top_bottom_stock_predictions(session, model_name, top_n)
$$;

-- Email notification integration (requires ACCOUNTADMIN)
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE NOTIFICATION INTEGRATION EMAIL_INTEGRATION
  TYPE=EMAIL
  ENABLED=TRUE
  DEFAULT_SUBJECT = 'Snowflake Intelligence';

-- Grant usage on email integration to FSI_DEMO_ROLE
GRANT USAGE ON INTEGRATION EMAIL_INTEGRATION TO ROLE FSI_DEMO_ROLE;

-- Switch back to FSI_DEMO_ROLE for procedure creation
USE ROLE FSI_DEMO_ROLE;
USE DATABASE FSI_DEMO_DB;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE PROCEDURE SEND_EMAIL(
    RECIPIENT_EMAIL VARCHAR DEFAULT NULL,
    SUBJECT VARCHAR DEFAULT 'Snowflake Intelligence',
    BODY VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'send_email'
AS
$$
def send_email(session, recipient_email, subject, body):
    try:
        # Get current user's email if not provided
        if not recipient_email or recipient_email.strip() == '':
            result = session.sql("SELECT CURRENT_USER()").collect()
            current_user = result[0][0] if result else None
            if current_user:
                # Get user's email from SHOW USERS
                session.sql(f"SHOW USERS LIKE '{current_user}'").collect()
                user_info = session.sql("SELECT \"email\" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))").collect()
                if user_info and user_info[0][0]:
                    recipient_email = user_info[0][0]
                else:
                    return "Error: Could not determine recipient email. Please provide an email address."
            else:
                return "Error: Could not determine current user. Please provide an email address."
        
        # Use default subject if not provided
        if not subject or subject.strip() == '':
            subject = 'Snowflake Intelligence'
        
        # Check if body is provided
        if not body or body.strip() == '':
            return "Error: Email body is required."
        
        # Escape single quotes in the body to prevent SQL injection
        escaped_body = body.replace("'", "''")
        escaped_subject = subject.replace("'", "''")
        
        # Execute the system procedure call
        session.sql(f"""
            CALL SYSTEM$SEND_EMAIL(
                'EMAIL_INTEGRATION',
                '{recipient_email}',
                '{escaped_subject}',
                '{escaped_body}',
                'text/html'
            )
        """).collect()
        
        return f'Email sent successfully to {recipient_email} with subject: "{subject}"'
    except Exception as e:
        return f"Error sending email: {str(e)}"
$$;

-- Grant usage on procedures to the role
GRANT USAGE ON PROCEDURE GET_TOP_BOTTOM_STOCK_PREDICTIONS(STRING, INTEGER) TO ROLE FSI_DEMO_ROLE;
GRANT USAGE ON PROCEDURE SEND_EMAIL(VARCHAR, VARCHAR, VARCHAR) TO ROLE FSI_DEMO_ROLE;

-- ============================================================================
-- SECTION 8: Git Integration for Automated Notebook Deployment
-- ============================================================================

USE ROLE FSI_DEMO_ROLE;
USE DATABASE FSI_DEMO_DB;
USE SCHEMA ANALYTICS;

-- Switch to ACCOUNTADMIN to create API integration
USE ROLE ACCOUNTADMIN;

-- Create Git API integration for public repository
CREATE OR REPLACE API INTEGRATION GIT_HTTPS_API
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/')
  ENABLED = TRUE;

GRANT USAGE ON INTEGRATION GIT_HTTPS_API TO ROLE FSI_DEMO_ROLE;

-- Switch back to FSI_DEMO_ROLE to create git repository
USE ROLE FSI_DEMO_ROLE;
USE DATABASE FSI_DEMO_DB;
USE SCHEMA ANALYTICS;

-- Create Git repository (public repo - no credentials needed)
CREATE OR REPLACE GIT REPOSITORY FSI_DEMO_REPO
  API_INTEGRATION = GIT_HTTPS_API
  ORIGIN = 'https://github.com/Snowflake-Labs/sfguide-quantitative-research-ai-functions-and-cortex-code.git';

-- Fetch latest code from repository
ALTER GIT REPOSITORY FSI_DEMO_REPO FETCH;

-- Create warehouse notebooks (faster for ML training)
-- Note: Warehouse notebooks run both Python and SQL on warehouse
CREATE OR REPLACE NOTEBOOK START_HERE
  FROM '@FSI_DEMO_REPO/branches/main/notebooks'
  MAIN_FILE = '0_start_here.ipynb'
  QUERY_WAREHOUSE = FSI_DEMO_WH
  IDLE_AUTO_SHUTDOWN_TIME_SECONDS = 3600;

ALTER NOTEBOOK START_HERE ADD LIVE VERSION FROM LAST;

CREATE OR REPLACE NOTEBOOK TRAIN_ML_MODELS
  FROM '@FSI_DEMO_REPO/branches/main/notebooks'
  MAIN_FILE = '1_train_and_register_ml_models.ipynb'
  QUERY_WAREHOUSE = FSI_DEMO_WH
  IDLE_AUTO_SHUTDOWN_TIME_SECONDS = 3600;

ALTER NOTEBOOK TRAIN_ML_MODELS ADD LIVE VERSION FROM LAST;

CREATE OR REPLACE NOTEBOOK CREATE_CORTEX_COMPONENTS
  FROM '@FSI_DEMO_REPO/branches/main/notebooks'
  MAIN_FILE = '2_create_cortex_components.ipynb'
  QUERY_WAREHOUSE = FSI_DEMO_WH
  IDLE_AUTO_SHUTDOWN_TIME_SECONDS = 3600;

ALTER NOTEBOOK CREATE_CORTEX_COMPONENTS ADD LIVE VERSION FROM LAST;

-- ============================================================================
-- SECTION 9: Completion
-- ============================================================================

SELECT 'Setup completed successfully! Next steps:' AS STATUS,
       '1. Run Notebook: START_HERE (extracts sentiment using AI Functions)' AS STEP_1,
       '2. Run Notebook: TRAIN_ML_MODELS (trains and registers ML models)' AS STEP_2,
       '3. Run Script: create_cortex_components.sql (creates Cortex Search, Semantic View, and Agent)' AS STEP_3;

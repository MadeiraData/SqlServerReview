/*
    DESCRIPTION:
        Ensures TempDB files grow together.
        - SQL Server < 2016: Checks if Trace Flag 1117 is enabled.
        - SQL Server ≥ 2016: Checks if 'is_autogrow_all_files' is enabled.
*/

DECLARE 
    @ProductVersion		DECIMAL(3, 1)	= SUBSTRING(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)), 0, CHARINDEX('.', CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)), 4)),
	@EngineEdition		INT				= CAST (SERVERPROPERTY('EngineEdition') AS NVARCHAR(128)),
    @TF1117Enabled		BIT,
    @AutoGrowAllFiles	BIT;


-- Check if Trace Flag 1117 is enabled globally (For SQL Server < 2016)
SELECT @TF1117Enabled = 
    CASE WHEN EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'default trace enabled' AND value_in_use = 1117) 
         THEN 1 ELSE 0 END;

-- Check if is_autogrow_all_files is enabled (For SQL Server ≥ 2016)
SELECT @AutoGrowAllFiles = is_autogrow_all_files 
FROM tempdb.sys.filegroups;

-- Construct Additional Info as XML
SET @AdditionalInfo = 
    (
        SELECT 
            SQLVersion =
							CASE	
								WHEN @EngineEdition BETWEEN 1 AND 4	THEN SUBSTRING(@@VERSION, 0, CHARINDEX(' (', @@VERSION, 0))
								WHEN @EngineEdition = 5				THEN 'Azure SQL Database'			
								WHEN @EngineEdition = 8				THEN 'Azure SQL Managed Instance'
							END,
            AutoGrowthBehaviorCheck = 
                CASE 
                    WHEN @ProductVersion >= 13 AND @AutoGrowAllFiles = 1 THEN 'Good! SQL Server version greated then 2016 and is_autogrow_all_files is Enabled'
                    WHEN @ProductVersion >= 13 AND @AutoGrowAllFiles = 0 THEN 'Bad! SQL Server version greated then 2016, but is_autogrow_all_files is Disabled'
                    WHEN @ProductVersion < 13 AND @TF1117Enabled = 1 THEN 'Good! SQL Server version less/equal then 2016 and Trace Flag 1117 is Enable'
                    WHEN @ProductVersion < 13 AND @TF1117Enabled = 0 THEN 'Bad! SQL Server version less/equal then 2016, but Trace Flag 1117 is NOT Enabled'
                END
        FOR XML PATH(''), 
		ROOT('TempDBAutoGrowth')
    );

-- Insert Check Results
INSERT INTO #Checks
(
    CheckId,
    Title,
    RequiresAttention,
    WorstCaseImpact,
    CurrentStateImpact,
    RecommendationEffort,
    RecommendationRisk,
    AdditionalInfo
)
SELECT
    CheckId                 = {CheckId},
    Title                   = N'{CheckTitle}',
    RequiresAttention        = 
								CASE 
									WHEN (@ProductVersion >= 13 AND @AutoGrowAllFiles = 0)
											OR (@ProductVersion < 13 AND @TF1117Enabled = 0) THEN 1
									ELSE 0  -- Everything is fine
								END,
    WorstCaseImpact         = 2,  -- Medium impact (TempDB performance risk)
    CurrentStateImpact      =
								CASE 
									WHEN (@ProductVersion >= 13 AND @AutoGrowAllFiles = 0)
											OR (@ProductVersion < 13 AND @TF1117Enabled = 0) THEN 2
									ELSE 0
								END,
    RecommendationEffort    = 1,  -- Low effort (Adjust settings)
    RecommendationRisk      = 1,  -- Low risk
    AdditionalInfo          = 
								CASE 
									WHEN (@ProductVersion >= 13 AND @AutoGrowAllFiles = 0)
											OR (@ProductVersion < 13 AND @TF1117Enabled = 0) THEN @AdditionalInfo
									ELSE NULL
								END

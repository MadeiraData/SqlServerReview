/*
    DESCRIPTION:
        Ensures TempDB uses uniform extent allocation.
        - SQL Server < 2016: Checks if Trace Flag 1118 is enabled.
        - SQL Server ≥ 2016: Checks if 'is_mixed_page_allocation_on' is disabled.
*/

DECLARE 
    @ProductVersion		DECIMAL(3, 1)	= SUBSTRING(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)), 0, CHARINDEX('.', CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)), 4)),
	@EngineEdition		INT				= CAST (SERVERPROPERTY('EngineEdition') AS NVARCHAR(128)),
	@TF1118Enabled		BIT,
    @MixedPage			BIT;

-- Check if Trace Flag 1118 is enabled globally (For SQL Server < 2016)
SELECT @TF1118Enabled = 
    CASE WHEN EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'default trace enabled' AND value_in_use = 1118) 
         THEN 1 ELSE 0 END;

-- Check if is_mixed_page_allocation_on is enabled (For SQL Server ≥ 2016)
SELECT 
	@MixedPage = is_mixed_page_allocation_on 
FROM
	#sys_databases 
WHERE
	database_id = 2;

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
            UniformExtentCheck = 
                CASE 
                    WHEN @ProductVersion >= 13 AND @MixedPage = 0 THEN 'Good! SQL Server version greated then 2016 and Mixed Page Allocation is Disabled'
                    WHEN @ProductVersion >= 13 AND @MixedPage = 1 THEN 'Bad! SQL Server version greated then 2016, but Mixed Page Allocation is Enabled - Should be Disabled)'
                    WHEN @ProductVersion < 13 AND @TF1118Enabled = 1 THEN 'Good! SQL Server version less/equal then 2016 and Trace Flag 1118 is Enabled)'
                    WHEN @ProductVersion < 13 AND @TF1118Enabled = 0 THEN 'Bad! SQL Server version less/equal then 2016, but Trace Flag 1117 is NOT Enabled)'
                END
        FOR XML PATH(''), 
		ROOT('TempDBUniformExtents')
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
    AdditionalInfo,
	[Responsible DBA Team]
)
SELECT
    CheckId                 = @CheckId,
    Title                   = N'{CheckTitle}',
    RequiresAttention       = 
								CASE 
									WHEN @ProductVersion >= 13 AND @MixedPage = 1 THEN 1  -- SQL 2016+ issue
									WHEN @ProductVersion < 13 AND @TF1118Enabled = 0 THEN 1  -- SQL < 2016 issue
									ELSE 0  -- Everything is fine
								END,
    WorstCaseImpact         = 2,  -- Medium impact (TempDB allocation issues)
    CurrentStateImpact      =
								CASE 
									WHEN (@ProductVersion >= 13 AND @MixedPage = 1)
											OR (@ProductVersion < 13 AND @TF1118Enabled = 0) THEN 2
									ELSE 0
								END,
    RecommendationEffort    = 1,  -- Low effort (Adjust settings)
    RecommendationRisk      = 1,  -- Low risk
    AdditionalInfo          = 
								CASE 
									WHEN (@ProductVersion >= 13 AND @MixedPage = 1)
											OR (@ProductVersion < 13 AND @TF1118Enabled = 0) THEN @AdditionalInfo
									ELSE NULL
								END,
	[Responsible DBA Team]					= 'Production';


DECLARE 
    @ProductVersion						NVARCHAR(50),
    @Major								INT,
    @NumaNodeCount						INT,
    @LogicalProcessorPerNumaNodeCount	INT,
    @EffectiveMaxDOP					INT,
    @LogicalProcessorThreshold			INT,
    @RecommendedMaxDOP					INT = 0,
    @RecommendationText					NVARCHAR(500);

-- Get SQL Server version
SET @ProductVersion = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(50));
SET @Major = CAST(LEFT(@ProductVersion, CHARINDEX('.', @ProductVersion) - 1) AS INT);

-- Get the MaxDOP setting
SELECT @EffectiveMaxDOP = CAST(value_in_use AS INT)
FROM sys.configurations
WHERE [name] = N'max degree of parallelism';

IF @EffectiveMaxDOP = 0
BEGIN
    SELECT @EffectiveMaxDOP = COUNT(*)
    FROM sys.dm_os_schedulers
    WHERE scheduler_id <= 1048575 AND is_online = 1;
END

-- Get NUMA node and logical processor counts
SELECT 
    @NumaNodeCount = COUNT(DISTINCT memory_node_id),
    @LogicalProcessorPerNumaNodeCount = MAX(online_scheduler_count)
FROM 
(
    SELECT 
        memory_node_id, 
        SUM(online_scheduler_count) AS online_scheduler_count
    FROM sys.dm_os_nodes
    WHERE memory_node_id <> 64 AND node_id <> 64 -- Exclude DAC node
    GROUP BY memory_node_id
) AS m;

SET @LogicalProcessorThreshold = CASE WHEN @NumaNodeCount = 1 THEN 8 ELSE 16 END;

-- Set the textual recommendation
SELECT 
    @RecommendationText = 
    CASE
        -- SQL Server 2008 through 2014
        WHEN @Major BETWEEN 10 AND 12 AND @NumaNodeCount = 1 AND @LogicalProcessorPerNumaNodeCount <= 8		THEN 'Keep MAXDOP at or under the number of logical processors'
        WHEN @Major BETWEEN 10 AND 12 AND @NumaNodeCount = 1 AND @LogicalProcessorPerNumaNodeCount > 8		THEN 'Keep MAXDOP at 8'
        WHEN @Major BETWEEN 10 AND 12 AND @NumaNodeCount > 1 AND @LogicalProcessorPerNumaNodeCount <= 8		THEN 'Keep MAXDOP at or under the number of logical processors per NUMA node'
        WHEN @Major BETWEEN 10 AND 12 AND @NumaNodeCount > 1 AND @LogicalProcessorPerNumaNodeCount > 8		THEN 'Keep MAXDOP at 8'

        -- SQL Server 2016 and later
        WHEN @Major > 12 AND @NumaNodeCount = 1 AND @LogicalProcessorPerNumaNodeCount <= 8					THEN 'Keep MAXDOP at or under the number of logical processors'
        WHEN @Major > 12 AND @NumaNodeCount = 1 AND @LogicalProcessorPerNumaNodeCount > 8					THEN 'Keep MAXDOP at 8'
        WHEN @Major > 12 AND @NumaNodeCount > 1 AND @LogicalProcessorPerNumaNodeCount <= 16					THEN 'Keep MAXDOP at or under the number of logical processors per NUMA node'
        WHEN @Major > 12 AND @NumaNodeCount > 1 AND @LogicalProcessorPerNumaNodeCount > 16					THEN 'Keep MAXDOP at half the number of logical processors per NUMA node with a MAX value of 16'

    END;

-- Determine the recommended MAXDOP based on Microsoft guidelines
SELECT 
    @RecommendedMaxDOP = 
    CASE
        -- SQL Server 2008 through 2014
        WHEN @Major BETWEEN 10 AND 12 AND @NumaNodeCount = 1 AND @LogicalProcessorPerNumaNodeCount <= 8 THEN @LogicalProcessorPerNumaNodeCount
        WHEN @Major BETWEEN 10 AND 12 AND @NumaNodeCount = 1 AND @LogicalProcessorPerNumaNodeCount > 8 THEN 8
        WHEN @Major BETWEEN 10 AND 12 AND @NumaNodeCount > 1 AND @LogicalProcessorPerNumaNodeCount <= 8 THEN @LogicalProcessorPerNumaNodeCount
        WHEN @Major BETWEEN 10 AND 12 AND @NumaNodeCount > 1 AND @LogicalProcessorPerNumaNodeCount > 8 THEN 8

        -- SQL Server 2016 and later
        WHEN @Major > 12 AND @NumaNodeCount = 1 AND @LogicalProcessorPerNumaNodeCount <= 8 THEN @LogicalProcessorPerNumaNodeCount
        WHEN @Major > 12 AND @NumaNodeCount = 1 AND @LogicalProcessorPerNumaNodeCount > 8 THEN 8
        WHEN @Major > 12 AND @NumaNodeCount > 1 AND @LogicalProcessorPerNumaNodeCount <= 16 THEN @LogicalProcessorPerNumaNodeCount
        WHEN @Major > 12 AND @NumaNodeCount > 1 AND @LogicalProcessorPerNumaNodeCount > 16 AND @LogicalProcessorPerNumaNodeCount / 2 <= 16 THEN @LogicalProcessorPerNumaNodeCount / 2
        WHEN @Major > 12 AND @NumaNodeCount > 1 AND @LogicalProcessorPerNumaNodeCount > 16 AND @LogicalProcessorPerNumaNodeCount / 2 > 16 THEN 16
    END;

	-- Set AdditionalInfo only if there's a misconfiguration
    SET @AdditionalInfo = 
    (
        SELECT
			@EffectiveMaxDOP																	AS EffectiveMaxDOP,
			@NumaNodeCount																		AS NumaNodeCount,
			@LogicalProcessorPerNumaNodeCount													AS LogicalProcessorPerNumaNodeCount,
			@LogicalProcessorThreshold															AS LogicalProcessorThreshold,
			REPLACE(SUBSTRING(@@VERSION, 0, CHARINDEX(' (', @@VERSION, 0)), 'Microsoft ', '')	AS SQLServerVersion,
			CASE
				WHEN @EffectiveMaxDOP = 1	THEN N'Current MaxDOP is set to 1, which suppresses parallel plan generation! '
				ELSE N''
			END	+ @RecommendationText															AS Recommendation,
			@RecommendedMaxDOP																	AS RecommendedMaxDOP
		WHERE
			@EffectiveMaxDOP != @RecommendedMaxDOP
			OR @EffectiveMaxDOP = 1
        FOR XML PATH(N''), 
		ROOT(N'MaxDOPCheck')
    );

-- Insert check result into #Checks table
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
	CheckId					= @CheckId ,
	Title					= N'{CheckTitle}' ,
    RequiresAttention = 
        CASE 
            WHEN @AdditionalInfo IS NULL THEN 0 
            ELSE 1 
        END,
    WorstCaseImpact = 3, -- High
    CurrentStateImpact = 
        CASE 
            WHEN @AdditionalInfo IS NULL THEN 0 
            ELSE 3 -- High
        END,
    RecommendationEffort = 
        CASE 
            WHEN @AdditionalInfo IS NULL THEN 0 
            ELSE 2 -- Moderate
        END,
    RecommendationRisk = 1, -- Low risk to change
    AdditionalInfo = @AdditionalInfo,
	[Responsible DBA Team] = N'Production/Development';


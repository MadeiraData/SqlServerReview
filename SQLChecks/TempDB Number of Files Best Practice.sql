/*
    DESCRIPTION:
        Checks if the number of TempDB data files follows best practices.
        Recommends increasing/decreasing the number of files based on CPU cores and Microsoft guidelines.
*/

DECLARE
    @CPUCount					TINYINT,
    @TempDBFiles				TINYINT,
    @RecommendedTempDBFiles		TINYINT;

	-- Get the number of logical processors (excluding scheduler inefficiencies)
	SELECT 
		@CPUCount = COUNT(*) 
	FROM
		sys.dm_os_schedulers 
	WHERE
		[status] = N'VISIBLE ONLINE' 
		AND is_online = 1;

	-- Get the number of TempDB data files
	SELECT 
		@TempDBFiles = COUNT(*) 
	FROM
		master.sys.master_files
	WHERE
		database_id = 2
		AND [type] = 0;

	-- Determine recommended number of TempDB files based on best practices
	SET @RecommendedTempDBFiles =
									CASE 
										WHEN @CPUCount <= 8 THEN @CPUCount  -- Match CPU count if ≤ 8
										WHEN @CPUCount > 8 THEN 8  -- Use 8 files when CPU > 8
									END;

	-- Construct Additional Info as XML for structured reporting
	SET @AdditionalInfo = 
		(
			SELECT 
				CurrentTempDBFiles = @TempDBFiles,
				RecommendedFiles = @RecommendedTempDBFiles,
				ContentionRisk = 
					CASE 
						WHEN @TempDBFiles = @RecommendedTempDBFiles THEN 'Optimal'
						WHEN @TempDBFiles > @CPUCount THEN 'Potential Overhead (Too Many Files)'
						WHEN @TempDBFiles < @RecommendedTempDBFiles THEN 'Potential Contention (Too Few Files)'
						WHEN @CPUCount > 8 AND @TempDBFiles % 4 <> 0 THEN 'Not a multiple of 4 (Consider Adjusting)'
						ELSE 'Likely OK'
					END
			FOR XML PATH(''), 
			ROOT('TempDBConfiguration')
		);

	-- Insert Check Results into the #Checks Table
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
				WHEN @TempDBFiles = @RecommendedTempDBFiles THEN 0  -- No issue
				WHEN @TempDBFiles > @CPUCount THEN 1  -- Too many files
				WHEN @TempDBFiles < @RecommendedTempDBFiles THEN 1  -- Too few files
				WHEN @CPUCount > 8 AND @TempDBFiles % 4 <> 0 THEN 1  -- Not a multiple of 4
				ELSE 0
			END,
		WorstCaseImpact         = 2,  -- Medium impact
		CurrentStateImpact      =
			CASE 
				WHEN @TempDBFiles = @RecommendedTempDBFiles THEN 0
				ELSE 2
			END,
		RecommendationEffort    = 1,  -- Low effort to adjust
		RecommendationRisk      = 1,  -- Low risk to adjust
		AdditionalInfo          = @AdditionalInfo;

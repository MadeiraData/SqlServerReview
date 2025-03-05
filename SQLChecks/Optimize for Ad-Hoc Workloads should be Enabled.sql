
/*
	DESCRIPTION:
		The optimize for ad hoc workloads option is used to improve the efficiency of the plan cache for workloads that contain many single use ad hoc batches. 
		When this option is set to 1, the Database Engine stores a small compiled plan stub in the plan cache when a batch is compiled for the first time, instead of the full compiled plan. 
		This helps to relieve memory pressure by not allowing the plan cache to become filled with compiled plans that are not reused.
		
		The compiled plan stub allows the Database Engine to recognize that this ad hoc batch has been compiled before but has only stored a compiled plan stub.
		When this batch is invoked (compiled or executed) again, the Database Engine compiles the batch, removes the compiled plan stub from the plan cache, and adds the full compiled plan to the plan cache.

		If the number of single-use plans take a significant portion of SQL Server Database Engine memory in an OLTP server, 
		and these plans are Ad-hoc plans, use this server option to decrease memory usage with these objects.
		
		https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/optimize-for-ad-hoc-workloads-server-configuration-option?view=sql-server-2017

*/

		DECLARE
			@AdhocRatio					AS DECIMAL(3,2) ,
			@OptimizeForAdhocWorkloads	AS BIT;

		SELECT
			@AdhocRatio	= CAST (SUM (CASE WHEN objtype = N'Adhoc' AND usecounts = 1 THEN CAST (size_in_bytes AS DECIMAL(19,2)) ELSE 0 END) / SUM (CAST (size_in_bytes AS DECIMAL(19,2))) AS DECIMAL(3,2))
		FROM
			sys.dm_exec_cached_plans;

		SELECT
			@OptimizeForAdhocWorkloads = CAST (value_in_use AS BIT)
		FROM
			sys.configurations
		WHERE
			[name] = N'optimize for ad hoc workloads';

		SET @AdditionalInfo =
			(
				SELECT
					AdhocRatio		= @AdhocRatio ,
					CurrentConfig	= @OptimizeForAdhocWorkloads
				FOR XML
					PATH (N'') ,
					ROOT (N'OptimizeForAdhocWorkloads')
			);

		INSERT INTO
			#Checks
		(
			CheckId ,
			Title ,
			RequiresAttention ,
			WorstCaseImpact ,
			CurrentStateImpact ,
			RecommendationEffort ,
			RecommendationRisk ,
			AdditionalInfo
		)
		SELECT
			CheckId					= {CheckId} ,
			Title					= N'{CheckTitle}' ,
			RequiresAttention		=
				CASE
					WHEN @AdhocRatio > 0.5 AND @OptimizeForAdhocWorkloads = 0
						THEN 1
					ELSE
						0
				END ,
			WorstCaseImpact			= 1 ,	-- Low
			CurrentStateImpact		=
				CASE
					WHEN @AdhocRatio > 0.5 AND @OptimizeForAdhocWorkloads = 0
						THEN 1	-- Low
					ELSE
						0	-- None
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdhocRatio > 0.5 AND @OptimizeForAdhocWorkloads = 0
						THEN 1	-- Low
					ELSE
						0	-- None
				END ,
			RecommendationRisk		=
				CASE
					WHEN @AdhocRatio > 0.5 AND @OptimizeForAdhocWorkloads = 0
						THEN 1	-- Low
					ELSE
						0	-- None
				END ,
			AdditionalInfo			= 
				CASE
					WHEN @AdhocRatio > 0.5 AND @OptimizeForAdhocWorkloads = 0
						THEN @AdditionalInfo
					ELSE
						NULL
				END;

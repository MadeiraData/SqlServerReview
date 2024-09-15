
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
			AdditionalInfo			= @AdditionalInfo;

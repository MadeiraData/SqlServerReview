		DECLARE
			@AdditionalInfo				AS XML ,
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

		INSERT INTO
			#Checks
		(
			CheckId ,
			Title ,
			RequiresAttention ,
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
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 1 ,	-- Low
			RecommendationEffort	= 1 ,	-- Low
			RecommendationRisk		= 1 ,	-- Low
			AdditionalInfo			= @AdditionalInfo;

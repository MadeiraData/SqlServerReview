
		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = [name]
				FROM
					sys.databases
				WHERE
					is_auto_create_stats_on = 0
				ORDER BY
					database_id ASC
				FOR XML
					PATH (N'') ,
					ROOT (N'Databases')
			);

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
			CurrentStateImpact		= 3 ,	-- High
			RecommendationEffort	= 1 ,	-- Low
			RecommendationRisk		= 1 ,	-- Low
			AdditionalInfo			= @AdditionalInfo;

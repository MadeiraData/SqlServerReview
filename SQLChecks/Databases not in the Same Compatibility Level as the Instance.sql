
		DECLARE
			@InstanceCompatibilityLevel AS TINYINT;

		SET @InstanceCompatibilityLevel = CAST (LEFT (CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) , CHARINDEX (N'.' , CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128))) - 1) AS TINYINT) * 10;

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = [name]
				FROM
					sys.databases
				WHERE
					[compatibility_level] != @InstanceCompatibilityLevel
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
			CurrentStateImpact		= 2 ,	-- Medium
			RecommendationEffort	= 2 ,	-- Medium
			RecommendationRisk		= 3 ,	-- Medium
			AdditionalInfo			= @AdditionalInfo;


		DECLARE
			@InstanceCompatibilityLevel	AS TINYINT ,
			@NumberOfDatabases			AS INT;

		SET @InstanceCompatibilityLevel = CAST (LEFT (CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) , CHARINDEX (N'.' , CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128))) - 1) AS TINYINT) * 10;

		SELECT
			@NumberOfDatabases = COUNT (*)
		FROM
			sys.databases
		WHERE
			[compatibility_level] != @InstanceCompatibilityLevel;

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
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			WorstCaseImpact			= 2 ,	-- Medium
			CurrentStateImpact		=
				CASE
					WHEN @NumberOfDatabases = 0
						THEN 0	-- None
					ELSE
						2	-- Medium
				END ,
			RecommendationEffort	=
				CASE
					WHEN @NumberOfDatabases = 0
						THEN 0	-- None
					WHEN @NumberOfDatabases BETWEEN 1 AND 5
						THEN 2	-- Medium
					ELSE
						3	-- High
				END ,
			RecommendationRisk		=
				CASE
					WHEN @NumberOfDatabases = 0
						THEN 0	-- None
					ELSE
						2	-- Medium
				END ,
			AdditionalInfo			= @AdditionalInfo;

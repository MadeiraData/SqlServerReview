
/*
	DESCRIPTION:
		If this option is enabled, SQL Server will run the sqlservr.exe process and threads as High Priority instead of its usual Normal priority. 
		Hence, when SQL Server service will request CPU, other processes in need of CPU time won’t be prioritized. 
		In some scenarios it can lead to problems and most of the time it won’t bring any benefit. 
		Microsoft do not recommend to enable this feature, see this Microsoft Support article (search for Priority Boost).

	More Info/sources:
		https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-priority-boost-server-configuration-option
		https://www.brentozar.com/blitz/priority-boost
		https://www.sqlbadpractices.com/boost-sql-server-priority
		
*/

		SET @AdditionalInfo =
			(
				SELECT
					'Priority Boost is enabled'
				FROM 
					sys.configurations
				WHERE
					[name] = 'priority boost'
					AND CONVERT(int, [value]) = 0
				FOR XML
					PATH (N'') ,
					ROOT (N'PriorityBoost')
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
			WorstCaseImpact			= 3 ,	-- High
			CurrentStateImpact		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- High
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- High
				END ,
			RecommendationRisk		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END ,
			AdditionalInfo			= @AdditionalInfo;


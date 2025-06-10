/*
	DESCRIPTION:
		Indicates that the SQL Agent service is offline.
			
		This check is ignored for Express editions.
		
*/

		SET @AdditionalInfo =
			(
				SELECT
					servicename		AS [Name],
					status_desc		AS [status]
				FROM
					sys.dm_server_services
				WHERE
					servicename LIKE 'SQL Server Agent%'
					AND [status] != 4		--- Running
					AND CONVERT(int, SERVERPROPERTY('EngineEdition')) <> 4
				FOR XML
					PATH (N'') ,
					ROOT (N'Services')
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
			AdditionalInfo,
			[Responsible DBA Team]
		)
		SELECT
			CheckId					= @CheckId ,
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
			AdditionalInfo			= @AdditionalInfo,
			[Responsible DBA Team]					= N'Production';


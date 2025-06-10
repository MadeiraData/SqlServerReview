
/*
	DESCRIPTION:
		Instant file initialization (IFI) allows SQL Server to skip the zero-writing step and begin using the allocated space immediately for data files. 
		It doesn’t impact growths of your transaction log files (untill SQL Server 2022 (16.x)), those still need all the zeroes.

	More Info/sources:
		https://learn.microsoft.com/en-us/sql/relational-databases/databases/database-instant-file-initialization
		https://www.sqlshack.com/sql-server-setup-instant-file-initialization-ifi
		https://www.brentozar.com/blitz/instant-file-initialization

*/

		SET @AdditionalInfo =
			(
				SELECT
					servicename								AS ServiceName,
					service_account							AS ServiceAccount,
					instant_file_initialization_enabled		AS IsIFIenabled
				FROM
					sys.dm_server_services
				WHERE
					servicename LIKE 'SQL Server (%'
					AND instant_file_initialization_enabled != N'Y'
				FOR XML
					PATH (N'') ,
					ROOT (N'IFI')
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
			[Responsible DBA Team]					= N'Production/Development';


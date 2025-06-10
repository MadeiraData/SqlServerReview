
/*
	DESCRIPTION:
		Sometimes, and especially in production environments, the value in that global variable is important and is used as part of business processes.
		And if @@SERVERNAME doesn’t reflect the actual server name, it could cause problems.
		
		Also, the @@SERVERNAME variable is what’s used by SQL Server Replication. So, if it has an incorrect value, you may encounter a situation where replication doesn’t work because it doesn’t recognize the correct server name.
		Either way, it’s always best to have SQL Server save the correct meta-data of your machine.
		
*/

	DECLARE 
		@LocalServerName	SYSNAME			= @@SERVERNAME,
		@ActualServerName	NVARCHAR(128)	= CONVERT(NVARCHAR(MAX),SERVERPROPERTY('ServerName'));

		SET @AdditionalInfo =
			(
				
				SELECT *
				FROM
					(
						SELECT
							[name]				AS [LocalServerName],
							@ActualServerName	AS [ActualServerName]
						FROM
							sys.servers 
						WHERE
							server_id = 0
							AND [name] != @LocalServerName

					UNION

						SELECT
							@LocalServerName	AS [LocalServerName],
							@ActualServerName	AS [ActualServerName]
						FROM
							sys.servers 
						WHERE
							server_id = 0
							AND @LocalServerName != @ActualServerName
						)a
				FOR XML
					PATH (N'') ,
					ROOT (N'Server')
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


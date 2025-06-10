
/*
	DESCRIPTION:
		The configuration in question ("remote admin connections") determines whether the SQL Server would allow such connections to be made from outside the instance. 
		If it's turned off, then DAC connections can only be made to "localhost".
		By default, the connection is only allowed from a client running locally on the server. 
		Rule of thumb: In clustered environments, the setting should be on and available. Otherwise, it should remain disabled.

	More Info/sources:
		https://www.brentozar.com/blitz/remote-dedicated-admin-connection
		https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/remote-admin-connections-server-configuration-option
		https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/diagnostic-connection-for-database-administrators
		
*/


		SET @AdditionalInfo =
			(
				SELECT
					'Remote DAC listener is disabled'
				FROM 
					sys.configurations
				WHERE
					[name] = 'remote admin connections'
					AND CONVERT(int, [value]) = 0
				FOR XML
					PATH (N'') ,
					ROOT (N'RemoteDAC')
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


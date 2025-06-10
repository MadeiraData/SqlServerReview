
/*
	DESCRIPTION:
		Lightweight pooling is a feature in SQL Server that reduces the system overhead associated with the excessive context switching sometimes seen in symmetric multiprocessing (SMP) environments. 
		Instead of one thread per SQL Server SPID, lightweight pooling uses one thread to handle several execution contexts. 
		Fibers are used to assume the identity of the thread they are executing and are non-preemptive to other SQL Server threads running on the server

	More Info/sources:
		https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/lightweight-pooling-server-configuration-option
		
*/

		SET @AdditionalInfo =
			(
				SELECT
					'Lightweight Pooling is enabled', CONVERT(int, [value])
				FROM 
					sys.configurations
				WHERE
					[name] = 'lightweight pooling'
					AND CONVERT(int, [value]) != 0
				FOR XML
					PATH (N'') ,
					ROOT (N'LightweightPooling')
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


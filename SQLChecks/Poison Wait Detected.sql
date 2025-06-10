/*
	DESCRIPTION:
		Whenever SQL Server needs to wait while it’s executing queries, it tracks that time as a wait statistic.
		Some waits are what we call poison: any occurrence of them means your SQL Server may feel unusable while this wait type is happening. 

		https://www.brentozar.com/blitz/poison-wait-detected/
		https://www.sqlskills.com/blogs/paul/wait-statistics-or-please-tell-me-where-it-hurts/
*/

SET @AdditionalInfo =
	(
		SELECT *
		FROM
			#WaitsStats
		WHERE	
			WaitType IN 
						(
							'CMEMTHREAD',
							'IO_QUEUE_LIMIT',
							'IO_RETRY',
							'LOG_RATE_GOVERNOR',
							'POOL_LOG_RATE_GOVERNOR',
							'PREEMPTIVE_DEBUG',
							'RESMGR_THROTTLED',
							'RESOURCE_SEMAPHORE',
							'RESOURCE_SEMAPHORE_QUERY_COMPILE',
							'THREADPOOL'
						)
			OR WaitType LIKE 'SE_REPL%'
		FOR XML
			PATH (N'WaitData') ,
			ROOT (N'PoisonWait')
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
						3	-- High
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						3	-- High
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


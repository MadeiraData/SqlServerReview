/*
	DESCRIPTION:
		Whenever SQL Server needs to wait while it’s executing queries, it tracks that time as a wait statistic.
		Some waits are what we call Worrying: any occurrence of them means your SQL Server may feel unusable while this wait type is happening. 

		https://www.sqlskills.com/blogs/paul/worrying-wait-type/
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
							'ASYNC_NETWORK_IO',
							'WRITELOG',
							'CXPACKET',
							'CXCONSUMER',
							'CXSYNC_PORT',
							'SOS_SCHEDULER_YIELD',
							'LCK_M_X',
							'LCK_M_IX',
							'PAGEIOLATCH_SH',
							'PAGEIOLATCH_EX',
							'PAGEIOLATCH_UP',
							'PAGELATCH_SH',
							'PAGELATCH_EX',
							'PAGELATCH_UP'
						)
		FOR XML
			PATH (N'WaitData') ,
			ROOT (N'WorryingWait')
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
						2	-- High
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						2	-- High
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


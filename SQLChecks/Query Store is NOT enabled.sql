
/*
	DESCRIPTION:
		Query Store is disabled, preventing queries performance, plans, and runtime statistics tracking and troubleshooting. 
		Query Store in SQL Server helps boost query performance by supporting features like optimized plan forcing, memory grant feedback, and better cardinality and parallelism adjustments.

	More Info/sources:
		https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store
		https://github.com/microsoft/sqlworkshops-sql2022workshop/blob/main/sql2022workshop/03_BuiltinQueryIntelligence.md
	
*/


		SET @AdditionalInfo =
			(
				SELECT
					[name]		AS DBName,
					'OFF'		AS CurrentState	 
				FROM 
					#sys_databases
				WHERE
					state_desc = 'ONLINE'			-- databases in online state only
					AND DATABASEPROPERTYEX([name], 'Updateability') = 'READ_WRITE'
					AND user_access = 0				-- accessable databases only
					AND is_query_store_on = 0		-- databases with QS enabled only
					AND database_id > 4				-- exclude system databases
					AND [name] != 'rdsadmin'		-- exclude AWS RDS system database
				FOR XML
					PATH (N'') ,
					ROOT (N'QSnotEnabled')
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


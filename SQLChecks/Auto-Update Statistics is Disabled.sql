
/*
	DESCRIPTION:
		DB Configuration: Auto update stats is disabled.
		This may cause poor query performance due to suboptimal query plans.
		Auto-update statistics should be enabled.
		 
		Remediation command:
		ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS ON;
		 
		More info:
		https://docs.microsoft.com/sql/relational-databases/statistics/statistics
		 

*/
		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = [name]
				FROM
					#sys_databases
				WHERE
					is_auto_update_stats_on = 0
				AND
					source_database_id IS NULL		-- Not a database snapshots
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
						THEN 0	-- None
					ELSE
						3	-- High
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0	-- None
					ELSE
						1	-- Low
				END ,
			RecommendationRisk		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0	-- None
					ELSE
						1	-- Low
				END ,
			AdditionalInfo			= @AdditionalInfo,
			[Responsible DBA Team]					= N'Production';

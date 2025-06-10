
/*
	DESCRIPTION:
		This alerts when AUTO_SHRINK is enabled for one or more databases.
		An occasional shrinking of a database may be needed in response to a one-time data deletion event and/or to reduce excessive allocated but unused space in data files. However, shrinking should not be executed continuously by keeping auto-shrink enabled at all times, because it causes persistent and high resource utilization that will negatively impact workload performance. Auto-shrink should be disabled for the vast majority of databases.
		 
		More info:
		https://docs.microsoft.com/troubleshoot/sql/admin/considerations-autogrow-autoshrink#considerations-for-auto_shrink
		https://support.microsoft.com/help/2160663/
 

*/

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = [name]
				FROM
					#sys_databases
				WHERE
					is_auto_shrink_on = 1
				AND
					source_database_id IS NULL	-- Not a database snapshots
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
			WorstCaseImpact			= 1 ,	-- Low
			CurrentStateImpact		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
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



/*
	DESCRIPTION:
		Missing indexes in SQL Server are indexes that the query optimizer identifies as potentially beneficial for improving query performance. 
		These suggestions are based on the analysis of executed queries and their “impact.” 
		However, it does not necessarily mean the “recommended” index is needed, and it does not mean there are no other possible indexes that might have a greater impact.

	More Info/sources:
		https://www.brentozar.com/archive/2013/08/how-to-master-sql-server-index-tuning/
		https://www.i-programmer.info/programming/database/3208-improve-sql-performance-find-your-missing-indexes.html
		https://github.com/MadeiraData/MadeiraToolbox/blob/master/Health%20Check%20Scripts/Missing_Index_Detailed_Recommendations.sql
		
*/

		SET @AdditionalInfo =
			(
				SELECT
					[DatabaseName] + '.' + QUOTENAME([schema_name]) + '.' + QUOTENAME(table_name)	AS [TableName],
					total_missing_indexes															AS [MissingIndexesHighImpact] 
				FROM
					(
						SELECT
							QUOTENAME(DB_NAME(database_id))							AS [DatabaseName],
							OBJECT_SCHEMA_NAME (dm_mid.[object_id], database_id)	AS [schema_name],
							OBJECT_NAME (dm_mid.[object_id], database_id)			AS [table_name],
							COUNT(*)												AS total_missing_indexes,
							SUM(dm_migs.avg_user_impact)							AS total_impact,
							SUM(dm_migs.avg_total_user_cost)						AS total_cost
						FROM
							sys.dm_db_missing_index_groups dm_mig 
							INNER JOIN sys.dm_db_missing_index_group_stats dm_migs ON dm_migs.group_handle = dm_mig.index_group_handle 
							INNER JOIN sys.dm_db_missing_index_details dm_mid ON dm_mig.index_handle = dm_mid.index_handle  
						WHERE 
							dm_migs.avg_total_user_cost > 5
							AND dm_migs.avg_user_impact > 65
							AND dm_migs.unique_compiles > 20
							AND database_id > 4
							AND DB_NAME(database_id) NOT IN ('SSISDB', 'ReportServer', 'ReportServerTempDB', 'distribution', 'HangFireScheduler')
						GROUP BY
							database_id,
							dm_mid.[object_id]
				) AS q
				WHERE
					total_cost > 20
				ORDER BY
					total_cost DESC,
					total_impact DESC
				FOR XML
					PATH (N'ObjectName') ,
					ROOT (N'MissingIndexesHighImpact')
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
			[Responsible DBA Team]					= N'Development';


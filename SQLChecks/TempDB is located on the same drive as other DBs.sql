/*
	DESCRIPTION:
		This script verifies if tempdb is on the same drive as other database files.
		Having tempdb on the same drive as other databases can cause I/O contention, affecting overall database performance.

		https://learn.microsoft.com/en-us/sql/relational-databases/databases/tempdb-database

*/

SET @AdditionalInfo =
	(
		SELECT
			DB_NAME(database_id)	AS DatabaseName,
			[name]					AS [FileName],
			physical_name			AS [Location]
		FROM
			sys.master_files AS DBs
		WHERE
			DBs.database_id != DB_ID('tempdb')
			AND EXISTS
					(
						SELECT 1
						FROM
							sys.master_files AS Tdb
						WHERE
							Tdb.database_id = DB_ID('tempdb')
							AND LEFT(DBs.physical_name, 2) = LEFT(Tdb.physical_name, 2)
			)
		FOR XML
			PATH (N'') ,
			ROOT (N'TempDBonSameLocationWithDBs')
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
			[Responsible DBA Team]					= N'Production';


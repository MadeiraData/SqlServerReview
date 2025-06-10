
/*
	DESCRIPTION:
		This condition alerts about very old table statistics with a high number of rows that were changed since the last statistics update.
		If such are found, then you should probably optimize the index and statistics maintenance jobs.
		 
		Outdated statistics may severely impact performance due to inaccurate row estimations in execution plans.
		 
		See also
		https://www.madeiradata.com/post/the-most-important-performance-factor-in-sql-server
		https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-stats-properties-transact-sql

*/

		DECLARE
			@DatabaseName	AS SYSNAME ,
			@Command		AS NVARCHAR(MAX);

		IF OBJECT_ID('tempdb.dbo.#StatCheckDBs', 'U') IS NOT NULL
		BEGIN
			DROP TABLE #StatCheckDBs;
		END

		CREATE TABLE #StatCheckDBs (DatabaseName	NVARCHAR(128));

		DECLARE
			DatabasesCursor
		CURSOR
			LOCAL
			FAST_FORWARD
		FOR
			SELECT
				[name]
			FROM
				#sys_databases
			WHERE
				is_auto_update_stats_on = 0
			AND
				source_database_id IS NULL;	-- Not a database snapshots

		OPEN DatabasesCursor;

		FETCH NEXT FROM
			DatabasesCursor
		INTO
			@DatabaseName;

		WHILE
			@@FETCH_STATUS = 0
		BEGIN

			SET @Command =
				N'
					USE
						' + QUOTENAME (@DatabaseName) + N';

					IF NOT EXISTS
						(
							SELECT
								NULL
							FROM
								sys.stats AS Stats
							CROSS APPLY
								sys.dm_db_stats_properties (Stats.[object_id] , Stats.stats_id) AS StatsProperties
							WHERE
								StatsProperties.last_updated > DATEADD (MONTH , -1 , SYSDATETIME ())
						)
					BEGIN

						INSERT INTO
							#StatCheckDBs
						(
							DatabaseName
						)
						SELECT
							DatabaseName = DB_NAME ();

					END;
				';

			EXECUTE sys.sp_executesql
				@stmt = @Command;

			FETCH NEXT FROM
				DatabasesCursor
			INTO
				@DatabaseName;

		END;

		CLOSE DatabasesCursor;

		DEALLOCATE DatabasesCursor;

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = Databases.DatabaseName
				FROM
					#StatCheckDBs AS Databases
				ORDER BY
					DatabaseName ASC
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
			[Responsible DBA Team]					= 'Production';

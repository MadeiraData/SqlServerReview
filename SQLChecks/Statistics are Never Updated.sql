		DECLARE
			@DatabaseName					AS SYSNAME ,
			@AdditionalInfo					AS XML ,
			@Command						AS NVARCHAR(MAX)

		DROP TABLE IF EXISTS
			#Databases;

		CREATE TABLE
			#Databases
		(
			DatabaseName SYSNAME NOT NULL
		);

		DECLARE
			DatabasesCursor
		CURSOR
			LOCAL
			FAST_FORWARD
		FOR
			SELECT
				DatabaseName = [name]
			FROM
				sys.databases
			WHERE
				is_auto_update_stats_on = 0;

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
								StatsProperties.last_updated > DATEADD (MONTH , -1 , SYSDATETIME ());
						)
					BEGIN

						INSERT INTO
							#Databases
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
					#Databases AS Databases
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
			CurrentStateImpact ,
			RecommendationEffort ,
			RecommendationRisk ,
			AdditionalInfo
		)
		SELECT
			CheckId					= '{CheckId}' ,
			Title					= N'{CheckTitle}' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 3 ,	-- High
			RecommendationEffort	= 1 ,	-- Low
			RecommendationRisk		= 1 ,	-- Low
			AdditionalInfo			= @AdditionalInfo;

		DROP TABLE
			#Databases;

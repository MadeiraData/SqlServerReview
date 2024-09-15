
		DECLARE
			@DatabaseName	AS SYSNAME ,
			@Command		AS NVARCHAR(MAX);

		DROP TABLE IF EXISTS
			#FragmentedIndexes;

		CREATE TABLE
			#FragmentedIndexes
		(
			DatabaseName	SYSNAME	NOT NULL ,
			SchemaName		SYSNAME	NOT NULL ,
			TableName		SYSNAME	NOT NULL ,
			IndexName		SYSNAME	NOT NULL
		);

		IF
			CURSOR_STATUS ('local' , N'DatabasesCursor') = -3
		BEGIN

			DECLARE
				DatabasesCursor
			CURSOR
				LOCAL
				FAST_FORWARD
			FOR
				SELECT
					DatabaseName = [name]
				FROM
					sys.databases;

		END
		ELSE
		BEGIN

			CLOSE DatabasesCursor;

		END;

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

					INSERT INTO
						#FragmentedIndexes
					(
						DatabaseName ,
						SchemaName ,
						TableName ,
						IndexName
					)
					SELECT
						DatabaseName	= DB_NAME () ,
						SchemaName		= SCHEMA_NAME (Tables.schema_id) ,
						TableName		= Tables.name ,
						IndexName		= ISNULL (Indexes.name , N''Heap'')
					FROM
						sys.tables AS Tables
					INNER JOIN
						sys.indexes AS Indexes
					ON
						Tables.object_id = Indexes.object_id
					WHERE
						Indexes.is_disabled = 0
					AND
						EXISTS
							(
								SELECT
									NULL
								FROM
									sys.dm_db_index_physical_stats (DB_ID () , Tables.object_id , Indexes.index_id , NULL , ''LIMITED'') AS IndexPhysicalStats
								WHERE
									IndexPhysicalStats.page_count > 1000
								AND
									IndexPhysicalStats.avg_fragmentation_in_percent > 70
							);
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
					DatabaseName	= [Database].DatabaseName ,
					SchemaName		= FragmentedIndex.SchemaName ,
					TableName		= FragmentedIndex.TableName ,
					IndexName		= FragmentedIndex.IndexName
				FROM
					(
						SELECT DISTINCT
							DatabaseName
						FROM
							#FragmentedIndexes
					)
					AS
						[Database]
				INNER JOIN
					#FragmentedIndexes AS FragmentedIndex
				ON
					[Database].DatabaseName = FragmentedIndex.DatabaseName
				ORDER BY
					DatabaseName	ASC ,
					SchemaName		ASC ,
					TableName		ASC ,
					IndexName		ASC
				FOR XML
					AUTO ,
					ROOT (N'FragmentedIndexes')
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
			CheckId					= {CheckId} ,
			Title					= N'{CheckTitle}' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 2 ,	-- Medium
			RecommendationEffort	= 1 ,	-- Low
			RecommendationRisk		= 2 ,	-- Medium
			AdditionalInfo			= @AdditionalInfo;

		DROP TABLE
			#FragmentedIndexes;

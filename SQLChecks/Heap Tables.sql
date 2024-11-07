
		DECLARE
			@DatabaseName	AS SYSNAME ,
			@Command		AS NVARCHAR(MAX) ,
			@NumberOfTables	AS INT;

		DROP TABLE IF EXISTS
			#HeapTables;

		CREATE TABLE
			#HeapTables
		(
			DatabaseName	SYSNAME	NOT NULL ,
			SchemaName		SYSNAME	NOT NULL ,
			TableName		SYSNAME	NOT NULL
		);

		DROP TABLE IF EXISTS
			#DatabaseRowSizes

		CREATE TABLE
			#DatabaseRowSizes
		(
			DatabaseName	SYSNAME	NOT NULL ,
			TotalRowSize	BIGINT	NOT NULL ,
			HeapRowSize		BIGINT	NOT NULL
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
				database_id > 4	-- Only User Databases
			AND
				[state] = 0;	-- Online

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
						#HeapTables
					(
						DatabaseName ,
						SchemaName ,
						TableName
					)
					SELECT
						DatabaseName	= DB_NAME () ,
						SchemaName		= SCHEMA_NAME (Tables.schema_id) ,
						TableName		= Tables.name
					FROM
						sys.tables AS Tables
					INNER JOIN
						sys.indexes AS Indexes
					ON
						Tables.object_id = Indexes.object_id
					WHERE
						Indexes.index_id = 0;

					INSERT INTO
						#DatabaseRowSizes
					(
						DatabaseName ,
						TotalRowSize ,
						HeapRowSize
					)
					SELECT
						DatabaseName	= DB_NAME () ,
						TotalRowSize	= ISNULL (SUM (Partitions.rows) , 0) ,
						HeapRowSize		=
							ISNULL
							(
								SUM
								(
									CASE
										WHEN Indexes.index_id = 0
											THEN Partitions.rows
										ELSE
											0
									END
								) ,
								0
							)
					FROM
						sys.tables AS Tables
					INNER JOIN
						sys.indexes AS Indexes
					ON
						Tables.object_id = Indexes.object_id
					INNER JOIN
						sys.partitions AS Partitions
					ON
						Indexes.object_id = Partitions.object_id
					AND
						Indexes.index_id = Partitions.index_id
					WHERE
						Indexes.index_id IN (0,1);';

			EXECUTE sys.sp_executesql
				@stmt = @Command;

			FETCH NEXT FROM
				DatabasesCursor
			INTO
				@DatabaseName;

		END;

		CLOSE DatabasesCursor;

		DEALLOCATE DatabasesCursor;

		SELECT
			@NumberOfTables = COUNT (*)
		FROM
			#HeapTables;

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName	= [Database].DatabaseName ,
					SchemaName		= HeapTable.SchemaName ,
					TableName		= HeapTable.TableName
				FROM
					(
						SELECT DISTINCT
							DatabaseName
						FROM
							#HeapTables
					)
					AS
						[Database]
				INNER JOIN
					#HeapTables AS HeapTable
				ON
					[Database].DatabaseName = HeapTable.DatabaseName
				ORDER BY
					DatabaseName	ASC ,
					SchemaName		ASC ,
					TableName		ASC
				FOR XML
					AUTO ,
					ROOT (N'HeapTables')
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
			WorstCaseImpact			= 2 ,	-- Medium
			CurrentStateImpact		=
				CASE
					WHEN @NumberOfTables = 0
						THEN 0	-- None
					ELSE
						2	-- Medium
				END ,
			RecommendationEffort	=
				CASE
					WHEN @NumberOfTables = 0
						THEN 0	-- None
					WHEN @NumberOfTables BETWEEN 1 AND 5
						THEN 2	-- Medium
					ELSE
						3	-- High
				END ,
			RecommendationRisk		=
				CASE
					WHEN @NumberOfTables = 0
						THEN 0	-- None
					ELSE
						3	-- High
				END ,
			AdditionalInfo			= @AdditionalInfo;

		DROP TABLE
			#HeapTables;

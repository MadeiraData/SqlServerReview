/*
	DESCRIPTION:
		If a table is a heap and does not have any nonclustered indexes, then the entire table must be examined (a table scan) to find any row. This can be acceptable when the table is tiny, such as a list of the 12 regional offices of a company.
		When a table is stored as a heap, individual rows are identified by reference to a row identifier (RID) consisting of the file number, data page number, and slot on the page. The row id is a small and efficient structure. Sometimes data architects use heaps when data is always accessed through nonclustered indexes and the RID is smaller than a clustered index key.
		Heap tables can have detrimental implications on performance in the following scenarios:
		·When the data is frequently returned in a sorted order. A clustered index on the sorting column could avoid the sorting operation.
		·When the data is frequently grouped together. Data must be sorted before it is grouped, and a clustered index on the sorting column could avoid the sorting operation.
		·When ranges of data are frequently queried from the table. A clustered index on the range column will avoid sorting the entire heap.
		·When there are no nonclustered indexes and the table is large. In a heap, all rows of the heap must be read to find any row.
		There are cases where heaps perform better than tables with clustered indexes.  For example, if you’ve got a staging table where data is inserted and then selected back out (without doing any updates whatsoever) then heaps may be faster.  However, unless you’ve tested and proven that a heap is the right answer for your issue, it’s probably not.
		To resolve this issue, we’ll need to:
		·List the heaps (tables with no clustered indexes)
		·If they’re not actively being queried (like if the seeks, scans, updates are null), then they might be leftover backup tables.
		·If they’re being actively queried, determine the right clustering index.  Sometimes there’s already a primary key, but someone just forgot to set it as the clustered index.
		 
		You can use this script to generate "guestimated" clustered index recommendations for all heap tables in the instance.
		 
		More info:
		·(Eitan Blumin) Script to generate "guestimated" clustered index recommendations
		·(Microsoft Docs) Heaps (Tables Without Clustered Indexes)
		·(MSSQL Tips) SQL Server Clustered Tables vs Heap Tables
		·(Brent Ozar) Tables Without Clustered Indexes
		·(Paul S. Randal) Indexing Strategies for SQL Server Performance

*/
		DECLARE
			@DatabaseName	AS SYSNAME ,
			@Command		AS NVARCHAR(MAX) ,
			@NumberOfTables	AS INT;

		IF OBJECT_ID('tempdb.dbo.#HeapTables', 'U') IS NOT NULL
		BEGIN
			DROP TABLE #HeapTables;
		END

		CREATE TABLE
			#HeapTables
		(
			DatabaseName	SYSNAME	NOT NULL ,
			SchemaName		SYSNAME	NOT NULL ,
			TableName		SYSNAME	NOT NULL ,
			[RowCount]		BIGINT
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
				#sys_databases
			WHERE
				database_id > 4				-- Only User Databases
			AND
				[state] = 0					-- Online
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

					INSERT INTO
						#HeapTables
					(
						DatabaseName ,
						SchemaName ,
						TableName ,
						[RowCount]
					)
					SELECT
						DatabaseName	= DB_NAME () ,
						SchemaName		= SCHEMA_NAME (Tables.schema_id) ,
						TableName		= Tables.name ,
						[RowCount]		= SUM(partition_stats.row_count)
					FROM
						sys.tables AS Tables
					INNER JOIN
						sys.indexes AS Indexes
					ON
						Tables.object_id = Indexes.object_id
					INNER JOIN sys.dm_db_partition_stats AS partition_stats
					ON	
						Indexes.object_id = partition_stats.object_id
						AND Indexes.index_id = partition_stats.index_id
					WHERE
						Indexes.index_id = 0
					GROUP BY
						Tables.schema_id ,
						Tables.name
					HAVING
						SUM(partition_stats.row_count) > 200000;

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
					TableName		= HeapTable.TableName ,
					[Rows]			= [RowCount]
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
					TableName		ASC ,
					[RowCount]
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

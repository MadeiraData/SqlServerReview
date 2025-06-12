
/*
	DESCRIPTION:
		High index fragmentation occurs when the logical order of index pages doesn’t match their physical order, leading to inefficient data retrieval and slower query performance.
		Frequent insert, update, and delete operations cause pages to split and data to scatter, resulting in fragmentation.

		Impact: Increased I/O operations and longer query execution times.
		Detection: Use sys.dm_db_index_physical_stats to identify fragmented indexes.
		Maintenance: Reorganize or rebuild indexes based on fragmentation level.
		
		https://www.sqlshack.com/how-to-identify-and-resolve-sql-server-index-fragmentation/
		https://learn.microsoft.com/en-us/sql/relational-databases/indexes/reorganize-and-rebuild-indexes?view=sql-server-ver16
		https://www.mssqltips.com/sqlservertip/4331/sql-server-index-fragmentation-overview/

*/
IF '$(CheckIndexFragmentation)' = 'Yes'
BEGIN
		DECLARE
			@DatabaseName		AS SYSNAME ,
			@Command			AS NVARCHAR(MAX) ,
			@NumberOfIndexes	AS INT;

		IF OBJECT_ID('tempdb.dbo.#FragmentedIndexes', 'U') IS NOT NULL
		BEGIN
			DROP TABLE #FragmentedIndexes;
		END


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
					#sys_databases
				WHERE
					database_id NOT IN (2,3)	-- Not tempdb and model
				AND
					[state] = 0					-- Online
				AND
					source_database_id IS NULL;	-- Not a database snapshots

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
						Indexes.is_disabled = 0		-- Disabled indexes
						AND
						Indexes.type <> 0			-- Exclude heap tables
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

		SELECT
			@NumberOfIndexes = COUNT (*)
		FROM
			#FragmentedIndexes;


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
			
		DROP TABLE
			#FragmentedIndexes;
END
ELSE
BEGIN
	SET @AdditionalInfo = '<SKIPPED>Index fragmentation check was skipped. Index fragmentation health cannot be guaranteed on this server.</SKIPPED>'
END

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
			WorstCaseImpact			= 2 ,	-- Medium
			CurrentStateImpact		=
				CASE
					WHEN @NumberOfIndexes = 0
						THEN 0	-- None
					WHEN @NumberOfIndexes BETWEEN 1 AND 10
						THEN 1	-- Low
					ELSE
						2	-- Medium
				END ,
			RecommendationEffort	=
				CASE
					WHEN @NumberOfIndexes = 0
						THEN 0	-- None
					ELSE
						1	-- Low
				END ,
			RecommendationRisk		=
				CASE
					WHEN @NumberOfIndexes = 0
						THEN 0	-- None
					ELSE
						2	-- Medium
				END ,
			AdditionalInfo			= @AdditionalInfo,
			[Responsible DBA Team]					= N'Production';

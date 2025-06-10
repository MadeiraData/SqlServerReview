
/*
	DESCRIPTION:
		This query retrieves all the foreign keys in spesific DB that dont have corresponding indexes.

		Creating an index on foreign key columns is generally considered a good practice. In most cases, it will enhance queries performance, as those columns will be widely used for joining related tables.
		Sometimes developers forget to create such indexes, or simply don't know that they can improve performance. Missing indices are usually identified only when users report long execution or loading times.
		It is much better to check databases every now and then and create indexeses in timely manner.

	More Info/sources:
		https://dataedo.com/kb/query/sql-server/list-all-foreign-keys-without-an-index-in-sql-server-database
		https://github.com/MadeiraData/MadeiraToolbox/blob/master/Best%20Practices%20Checklists/Foreign_Keys_Without_Corresponding_Indexes.sql
		
*/

	DECLARE @tbk_FKwithoutCorrespondingIndexes TABLE
		(
			DBname					NVARCHAR(128),
			SchemaName				NVARCHAR(128),
			TableName				NVARCHAR(128),
			ForeignKeyName			NVARCHAR(128),
			ForeignKeyColumns		NVARCHAR(128),
			ReferencedSchemaName	NVARCHAR(128),
			ReferencedTableName		NVARCHAR(128)	
		)

	DECLARE
		@CurrDB								SYSNAME,
		@spExecuteSQL						NVARCHAR(1000),
		@SQL_FKwithoutCorrespondingIndexes	NVARCHAR(MAX) = N'
SELECT
	DB_NAME(),
	SchemaName				= OBJECT_SCHEMA_NAME(ForeignKeysWithColumns.ObjectId),
	TableName				= OBJECT_NAME(ForeignKeysWithColumns.ObjectId),
	ForeignKeyName			= ForeignKeysWithColumns.ForeignKeyName,
	ForeignKeyColumns		= ForeignKeysWithColumns.ForeignKeyColumnList,
	ReferencedSchemaName	= OBJECT_SCHEMA_NAME(ForeignKeysWithColumns.ReferencedObjectId),
	ReferencedTableName		= OBJECT_NAME(ForeignKeysWithColumns.ReferencedObjectId)
FROM
	(
		SELECT
			ObjectId				= ForeignKeys.parent_object_id,
			ReferencedObjectId		= ForeignKeys.referenced_object_id,
			ForeignKeyColumnList	= ForeignKeyColumns.ForeignKeyColumnList,
			ForeignKeyName			= ForeignKeys.[name]
		FROM
			sys.foreign_keys AS ForeignKeys
		CROSS APPLY
			(
				SELECT
					STUFF
					(
						
						(
							SELECT
								N'','' + QUOTENAME(Columns.[name])
							FROM
								sys.foreign_key_columns AS ForeignKeyColumns
							INNER JOIN
								sys.columns AS Columns
							ON
								ForeignKeyColumns.parent_object_id = Columns.[object_id]
							AND
								ForeignKeyColumns.parent_column_id = Columns.column_id
							WHERE
								ForeignKeyColumns.constraint_object_id = ForeignKeys.[object_id]
							ORDER BY
								ForeignKeyColumns.constraint_column_id ASC
							FOR XML PATH (N'''')
						)
						, 1, 1, N''''
					)
					AS ForeignKeyColumnList
			)
			AS ForeignKeyColumns
	)
	AS ForeignKeysWithColumns
	LEFT OUTER JOIN
		(
			SELECT
				ObjectId	= Indexes.[object_id],
				IndexKeysList	= IndexKeys.IndexKeysList
			FROM
				sys.indexes AS Indexes
			CROSS APPLY
				(
					SELECT
						STUFF
						(
						
							(
								SELECT
									N'','' + QUOTENAME(Columns.[name])
								FROM
									sys.index_columns AS IndexColumns
								INNER JOIN
									sys.columns AS Columns
								ON
									IndexColumns.[object_id] = Columns.[object_id]
								AND
									IndexColumns.column_id = Columns.column_id
								WHERE
									IndexColumns.[object_id] = Indexes.[object_id]
								AND
									IndexColumns.index_id = Indexes.index_id
								ORDER BY
									IndexColumns.index_column_id ASC
								FOR XML PATH (N'''')
							)
							, 1, 1, N''''
						)
						AS IndexKeysList
				)
				AS IndexKeys
		)
		AS IndexesWithColumns
	ON
		ForeignKeysWithColumns.ObjectId = IndexesWithColumns.ObjectId
	AND (
		IndexesWithColumns.IndexKeysList LIKE REPLACE(REPLACE(ForeignKeysWithColumns.ForeignKeyColumnList,''['',''_''),'']'',''_'') + N''%''
		OR
		ForeignKeysWithColumns.ForeignKeyColumnList LIKE REPLACE(REPLACE(IndexesWithColumns.IndexKeysList,''['',''_''),'']'',''_'') + N''%''
		)
WHERE
	IndexesWithColumns.ObjectId IS NULL
ORDER BY
	SchemaName		ASC,
	TableName		ASC,
	ForeignKeyName	ASC;	
	
	'		

	DECLARE DBs CURSOR LOCAL FAST_FORWARD
	FOR

		SELECT
			[name]
		FROM
			#sys_databases WITH (NOLOCK)
		WHERE
			[state] = 0 													/* online only */
			AND HAS_DBACCESS([name]) = 1 									/* accessible only  */
			AND database_id > 4 
			AND is_distributor = 0 											/* ignore system databases */
			AND DATABASEPROPERTYEX([name], 'Updateability') = 'READ_WRITE'	/* writeable only */

	OPEN DBs

		WHILE 1=1
		BEGIN
			FETCH NEXT FROM DBs INTO @CurrDB;
			IF @@FETCH_STATUS <> 0 BREAK;

			SET @spExecuteSQL = QUOTENAME(@CurrDB) + N'..sp_executesql'

			INSERT INTO @tbk_FKwithoutCorrespondingIndexes
			EXEC @spExecuteSQL
							@SQL_FKwithoutCorrespondingIndexes WITH RECOMPILE;
		END

	CLOSE DBs;
	DEALLOCATE DBs;


		SET @AdditionalInfo =
			(
				SELECT
					DBname,
					SchemaName,
					TableName,
					ForeignKeyName,
					ForeignKeyColumns,
					ReferencedSchemaName,
					ReferencedTableName
				FROM
					@tbk_FKwithoutCorrespondingIndexes					
				FOR XML
					PATH (N'ForeignKey'),
					ROOT (N'FK_WithoutCorrespondingIndexes')
			);

		INSERT INTO
			#Checks
		(
			CheckId,
			Title,
			RequiresAttention,
			WorstCaseImpact,
			CurrentStateImpact,
			RecommendationEffort,
			RecommendationRisk,
			AdditionalInfo,
			[Responsible DBA Team]
		)
		SELECT
			CheckId					= @CheckId,
			Title					= N'{CheckTitle}',
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END,
			WorstCaseImpact			= 3,	-- High
			CurrentStateImpact		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- High
				END,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- High
				END,
			RecommendationRisk		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END,
			AdditionalInfo			= @AdditionalInfo,
			[Responsible DBA Team]					= N'Production';


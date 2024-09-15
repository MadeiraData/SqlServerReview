
		DECLARE
			@DatabaseName	AS SYSNAME ,
			@Command		AS NVARCHAR(MAX);

		DROP TABLE IF EXISTS
			#ColumnsWithObsoleteDataTypes;

		CREATE TABLE
			#ColumnsWithObsoleteDataTypes
		(
			DatabaseName	SYSNAME	NOT NULL ,
			SchemaName		SYSNAME	NOT NULL ,
			TableName		SYSNAME	NOT NULL ,
			ColumnName		SYSNAME	NOT NULL ,
			DataType		SYSNAME	NOT NULL
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
					sys.databases
				WHERE
					database_id > 4;	-- Only User Databases

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
						#ColumnsWithObsoleteDataTypes
					(
						DatabaseName ,
						SchemaName ,
						TableName ,
						ColumnName ,
						DataType
					)
					SELECT
						DatabaseName	= DB_NAME () ,
						SchemaName		= SCHEMA_NAME (Tables.schema_id) ,
						TableName		= Tables.name ,
						ColumnName		= Columns.name ,
						DataType		= Types.name
					FROM
						sys.tables AS Tables
					INNER JOIN
						sys.columns AS Columns
					ON
						Tables.object_id = Columns.object_id
					INNER JOIN
						sys.types AS Types
					ON
						Columns.system_type_id = Types.system_type_id
					WHERE
						Types.system_type_id IN (34,35,99);

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
					SchemaName		= [Column].SchemaName ,
					TableName		= [Column].TableName ,
					ColumnName		= [Column].ColumnName ,
					DataType		= [Column].DataType
				FROM
					(
						SELECT DISTINCT
							DatabaseName
						FROM
							#ColumnsWithObsoleteDataTypes
					)
					AS
						[Database]
				INNER JOIN
					#ColumnsWithObsoleteDataTypes AS [Column]
				ON
					[Database].DatabaseName = [Column].DatabaseName
				ORDER BY
					DatabaseName	ASC ,
					SchemaName		ASC ,
					TableName		ASC ,
					ColumnName		ASC
				FOR XML
					AUTO ,
					ROOT (N'ColumnsWithObsoleteDataTypes')
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
			CurrentStateImpact		= 1 ,	-- Low
			RecommendationEffort	= 2 ,	-- Medium
			RecommendationRisk		= 2 ,	-- Medium
			AdditionalInfo			= @AdditionalInfo;

		DROP TABLE
			#ColumnsWithObsoleteDataTypes;

		BREAK;
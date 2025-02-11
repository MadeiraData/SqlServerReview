/* 
	DESCRIPTION:
		The condition checks for identity columns where their last value has reached more than 80% of the maxium value for its column data type.

		This indicates a very dangerous situation where a table using an identity column is nearing a situation where it won't be possible anymore to add more data into it, due to an impending overflow exception.

		This scenario usually happens due to improper planning ahead during the design phase of the database table data types, and/or retention policies of the data within.
		It can also happen due to something unexpected happening which caused a table to suddenly increase in size beyond what it was expected to have been.
		For example, a table has a TINYINT identity column, but someone accidentally inserted too much data into it, even though they shouldn't have.
		But, usually, it's just due to improper database design.

*/
		
DECLARE @IdentityColumns AS TABLE
(
	DatabaseName	SYSNAME			NULL,
	SchemaName		SYSNAME			NULL,
	TableName		SYSNAME			NULL,
	ColumnName		SYSNAME			NULL,
	LastValue		SQL_VARIANT		NULL,
	MaxValue		SQL_VARIANT		NULL,
	PercentUsed		DECIMAL(10, 2)	NULL
);
 
DECLARE 
	@CurrDB				SYSNAME,
	@spExecuteSQL		NVARCHAR(1000),
	@IdentityColumnsCommand	NVARCHAR(MAX) = N'
SELECT 
	DB_NAME(),
	OBJECT_SCHEMA_NAME(identity_columns.object_id),
	OBJECT_NAME(identity_columns.object_id),
	columns.[name],
	Last_Value,
	Calc1.MaxValue,
	Calc2.Percent_Used      
FROM
	sys.identity_columns WITH (NOLOCK)
	INNER JOIN sys.columns WITH (NOLOCK) ON columns.column_id = identity_columns.column_id AND columns.object_id = identity_columns.object_id
	INNER JOIN sys.types ON types.system_type_id = columns.system_type_id
	CROSS APPLY (SELECT MaxValue = CASE WHEN identity_columns.max_length = 1 THEN 256 ELSE POWER(2.0, identity_columns.max_length * 8 - 1) - 1 END) Calc1
	CROSS APPLY (SELECT Percent_Used = CAST(CAST(Last_Value AS FLOAT) *100.0/MaxValue AS DECIMAL(10, 2))) Calc2
WHERE 
	Calc2.Percent_Used > 80
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

	WHILE 1 = 1
	BEGIN
		FETCH NEXT FROM DBs INTO @CurrDB;
		IF @@FETCH_STATUS <> 0 BREAK;

		SET @spExecuteSQL = QUOTENAME(@CurrDB) + N'.sys.sp_executesql'

		INSERT INTO @IdentityColumns
							(
								DatabaseName,
								SchemaName,
								TableName,
								ColumnName,
								LastValue,
								MaxValue,
								PercentUsed
							) 
		EXEC @spExecuteSQL
					@IdentityColumnsCommand WITH RECOMPILE;
	END

CLOSE DBs;
DEALLOCATE DBs;

SET @AdditionalInfo =
	(
		SELECT
			CONCAT(QUOTENAME(DatabaseName), '.', QUOTENAME(SchemaName), '.', QUOTENAME(TableName), '.', QUOTENAME(ColumnName))		AS TableName,
			LastValue																						AS ReachedUsedValue,
			MaxValue																						AS MaxPossibleValue,
			CONVERT(VARCHAR(MAX), PercentUsed)																AS PercentUsedOfMaxValue
		FROM 
			@IdentityColumns
		FOR XML
			PATH('IdentityColumn'), 
			ROOT('Details')
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
			AdditionalInfo			= @AdditionalInfo;


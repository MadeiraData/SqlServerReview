/* 
	DESCRIPTION:
		The condition checks for non-cycling sequence objects where their last value has reached more than 80% of its maximum value.
		This indicates a very dangerous situation where anything using the Sequence is nearing a situation where it won't be possible anymore to get more values from it, due to an impending overflow exception.
 
		This scenario usually happens due to improper planning ahead during the design phase of the database tables using the sequence object, and/or retention policies of the data within.
		It can also happen due to something unexpected happening which caused a sequence to suddenly generate values beyond what it was expected to have been.
		For example, a sequence configured with the TINYINT data type, but someone accidentally inserted too much data with it, even though they shouldn't have.
		But, usually, it's just due to improper database design.

*/
		
DECLARE @Sequences AS TABLE
(
	DatabaseName	SYSNAME,
	SchemaName		SYSNAME,
	SequenceName	SYSNAME,
	LastValue		SQL_VARIANT,
	MaxValue		SQL_VARIANT,
	PercentUsed		FLOAT
);
 
DECLARE 
	@CurrDB				SYSNAME,
	@spExecuteSQL		NVARCHAR(1000),
	@SequencesCommand	NVARCHAR(MAX) = N'
SELECT
	DB_NAME(),
	OBJECT_SCHEMA_NAME(sequences.object_id), 
	OBJECT_NAME(sequences.object_id),
	sequences.current_value,
	sequences.maximum_value, 
	CAST(CAST(sequences.current_value AS FLOAT)/CAST(sequences.maximum_value AS FLOAT) *100.0 AS DECIMAL(10, 2))
FROM
	sys.sequences WITH (NOLOCK)
WHERE
	is_cycling = 0
	AND sequences.current_value IS NOT NULL
	AND CAST(CAST(sequences.current_value AS FLOAT)/CAST(sequences.maximum_value AS FLOAT) *100.0 AS DECIMAL(10, 2)) > 80
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

		INSERT INTO @Sequences
							(
								DatabaseName,
								SchemaName,
								SequenceName,
								LastValue,
								MaxValue,
								PercentUsed
							) 
		EXEC @spExecuteSQL
						@SequencesCommand WITH RECOMPILE;
	END

CLOSE DBs;
DEALLOCATE DBs;

SET @AdditionalInfo =
	(
		SELECT
			CONCAT(QUOTENAME(DatabaseName), '.', QUOTENAME(SchemaName), '.', QUOTENAME(SequenceName))		AS SequenceName,
			LastValue																						AS ReachedUsedValue,
			MaxValue																						AS MaxPossibleValue,
			CONVERT(varchar(max), PercentUsed)																AS PercentUsedOfMaxValue
		FROM 
			@Sequences
		FOR XML
			PATH('Sequence'), 
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


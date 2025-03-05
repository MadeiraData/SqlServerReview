
/*
	DESCRIPTION:
		The condition checks the Query Store state for all databases in the instance, using the sys.database_query_store_options dynamic management view.
		When the actual_state_desc column is equal to ERROR, or when the desired_state is different from the actual_state, then the alert is triggered.

	More Info/sources:
		https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store
		https://learn.microsoft.com/en-us/sql/relational-databases/performance/best-practice-with-the-query-store
		https://www.sqlskills.com/blogs/erin/query-store-best-practices		
*/

DECLARE	@tmp AS TABLE
				(
					DBName				SYSNAME			COLLATE database_default,
					actual_state_desc	NVARCHAR(64)	COLLATE database_default, 
					desired_state_desc	NVARCHAR(64)	COLLATE database_default
				);

INSERT INTO @tmp
EXEC sp_MSforeachdb '
IF EXISTS
	(
		SELECT 1 
		FROM 
			#sys_databases
		WHERE
			state_desc = ''ONLINE''			-- databases in online state only
			AND name = ''?'' 
			AND DATABASEPROPERTYEX([name], ''Updateability'') = ''READ_WRITE''
			AND user_access = 0				-- accessable databases only
			AND is_query_store_on = 1		-- databases with QS enabled only
			AND database_id > 4				-- exclude system databases
			AND [name] != ''rdsadmin''		-- exclude AWS RDS system database
	)
	AND OBJECT_ID(''[?].sys.database_query_store_options'') IS NOT NULL
BEGIN
	SELECT 
		''?'', 
		actual_state_desc, 
		desired_state_desc
	FROM	
		[?].sys.database_query_store_options
	WHERE
		actual_state_desc = ''ERROR''
		OR desired_state <> actual_state
		OR [readonly_reason] != 0
END
	'

		SET @AdditionalInfo =
			(
				SELECT
					DBName,
					actual_state_desc		AS ActualState,
					desired_state_desc		AS DesiredState
				FROM
					@tmp
				FOR XML
					PATH (N'') ,
					ROOT (N'QSErrorState')
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


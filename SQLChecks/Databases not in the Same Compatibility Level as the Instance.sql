
/*

	DESCRIPTION:
		This condition evaluates to True when a database has a compatibility level that does not match that of the Master database (current compatibility level).
		Compatibility mode allows an older database to run on a newer version of SQL Server at the expense of not being able to run newer features.  
		While some databases need to use an older compatibility mode, not all of them do.
		If there are databases, which must run in compatibility mode, please make provisions to exclude them in order to reduce false positive values.
 

*/
		DECLARE
			@InstanceCompatibilityLevel	AS TINYINT ,
			@NumberOfDatabases			AS INT;

		SET @InstanceCompatibilityLevel = CAST (LEFT (CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) , CHARINDEX (N'.' , CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128))) - 1) AS TINYINT) * 10;

		SELECT
			@NumberOfDatabases = COUNT (*)
		FROM
			#sys_databases
		WHERE
			[compatibility_level] != @InstanceCompatibilityLevel
		AND
			source_database_id IS NULL;	-- Not a database snapshots

		SET @AdditionalInfo =
			(
				SELECT
					[@DatabaseName] = [name],
					[@compatibility_level] = [compatibility_level]
				FROM
					#sys_databases
				WHERE
					[compatibility_level] != @InstanceCompatibilityLevel
				AND
					source_database_id IS NULL	-- Not a database snapshots
				ORDER BY
					database_id ASC
				FOR XML
					PATH (N'Database') ,
					ROOT (N'Databases')
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
					WHEN @NumberOfDatabases = 0
						THEN 0	-- None
					ELSE
						2	-- Medium
				END ,
			RecommendationEffort	=
				CASE
					WHEN @NumberOfDatabases = 0
						THEN 0	-- None
					WHEN @NumberOfDatabases BETWEEN 1 AND 5
						THEN 2	-- Medium
					ELSE
						3	-- High
				END ,
			RecommendationRisk		=
				CASE
					WHEN @NumberOfDatabases = 0
						THEN 0	-- None
					ELSE
						2	-- Medium
				END ,
			AdditionalInfo			= @AdditionalInfo,
			[Responsible DBA Team]					= N'Development';

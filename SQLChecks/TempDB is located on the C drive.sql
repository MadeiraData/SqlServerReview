/*
	DESCRIPTION:
		This script checks if the tempdb files are stored on the C drive.
		Storing tempdb on the C drive can lead to performance issues and potential conflicts with the operating system files.

		https://learn.microsoft.com/en-us/sql/relational-databases/databases/tempdb-database
*/

SET @AdditionalInfo =
	(
		SELECT
			[name]			AS [@name],
			physical_name	AS [@Location]
		FROM
			sys.master_files
		WHERE
			database_id = DB_ID('tempdb')
			AND physical_name LIKE 'C:%'
		FOR XML
			PATH (N'File') ,
			ROOT (N'TempDBonCdrive')
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
			WorstCaseImpact			= 3 ,	-- High
			CurrentStateImpact		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						2	-- High
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						2	-- High
				END ,
			RecommendationRisk		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END ,
			AdditionalInfo			= @AdditionalInfo,
			[Responsible DBA Team]					= N'Production';


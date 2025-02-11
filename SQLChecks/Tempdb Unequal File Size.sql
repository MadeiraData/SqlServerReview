/*
	DESCRIPTION:
		The benefits of having multiple tempdb files can be lost if one of those files grows larger than the other files. 
		This condition will evaulate to True if your tempdb files are not the same size.
 		The query counts the distinct tempdb file sizes from sys.master_files. 
 
		See Also:
		https://blogs.sentryone.com/aaronbertrand/sql-server-2016-tempdb-fixes/
		http://www.sqlskills.com/blogs/paul/correctly-adding-data-files-tempdb/

*/

DECLARE
	@TempDB_NumOfFiles		INT,
	@TempDB_Unequal_sizes	INT

SELECT
	@TempDB_NumOfFiles		= COUNT([file_id]),
	@TempDB_Unequal_sizes	= COUNT(DISTINCT size)
FROM
	sys.master_files
WHERE
	database_id = 2
	AND type_desc <> 'LOG';

SET @AdditionalInfo =
	(
		SELECT
			@TempDB_NumOfFiles		AS NumOfFiles,
			@TempDB_Unequal_sizes	AS UnequalSize
		WHERE
			@TempDB_Unequal_sizes > 1
		FOR XML
			PATH (N'') ,
			ROOT (N'TempDB')
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
						3	-- High
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						3	-- High
				END ,
			RecommendationRisk		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END ,
			AdditionalInfo			= @AdditionalInfo;


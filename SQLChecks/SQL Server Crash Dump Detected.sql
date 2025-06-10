/*
	DESCRIPTION:
		When a severe error occurs, SQL Server would sometimes automatically create a memory dump file (.mdmp) which contains a snapshot of the SQL Server memory buffer.
 
		Such files would normally be accompanied by additional log, txt, and xel files that may contain additional information.
		Once detected, you should collect the memory dump file and all of the other files created around the same time, and package them into a compressed zip archive for later use.
 
		These files can be used when opening a support case with Microsoft support, for them to analyze and find what caused the failure.
 
		For more info:
		https://www.brentozar.com/archive/2019/02/what-should-you-do-about-memory-dumps/


*/

		SET @AdditionalInfo =
			(
				SELECT
					CONVERT(NVARCHAR, CONVERT(DATETIME,creation_time), 121),
					[filename]	AS FileLocation
				FROM
					sys.dm_server_memory_dumps
				WHERE
					creation_time > DATEADD(DAY,-30,GETDATE())
				ORDER BY
					creation_time DESC
				FOR XML
					PATH (N'') ,
					ROOT (N'CrashDumpDetails')
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
						3
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
			AdditionalInfo			= @AdditionalInfo,
			[Responsible DBA Team]					= N'Production/Development';


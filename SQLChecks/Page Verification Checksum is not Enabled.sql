


/*
	DESCRIPTION:
		This option discovers damaged database pages caused by disk I/O path errors. 
		Disk I/O path errors can be the cause of database corruption problems and are generally caused by power failures or disk hardware failures that occur at the time the page is being written to disk.

	More Info/sources:
		https://learn.microsoft.com/en-us/sql/relational-databases/policy-based-management/set-the-page-verify-database-option-to-checksum
		https://www.sqlskills.com/blogs/glenn/setting-your-page-verify-database-option-to-checksum/
		https://www.madeiradata.com/post/torn-page-detection-in-sql-server-a-legacy-feature-worth-knowing-for-data-integrity
		
*/


		SET @AdditionalInfo =
			(
				SELECT
					QUOTENAME([name]) COLLATE database_default			AS DBname,
					CASE
						WHEN page_verify_option_desc COLLATE database_default = 'NONE'	THEN	'Disabled'
						ELSE page_verify_option_desc COLLATE database_default	
					END													AS SetOption 
				FROM 
					sys.databases
				WHERE 
					page_verify_option_desc COLLATE database_default != 'CHECKSUM'
				FOR XML 
					PATH (N'') ,
					ROOT (N'PageVerificationChecksum')
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





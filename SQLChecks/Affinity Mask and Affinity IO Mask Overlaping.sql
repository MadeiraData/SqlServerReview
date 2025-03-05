/*
	DESCRIPTION:
		This query checks the configuration of CPU affinity masks in SQL Server. 
		It retrieves the values of affinity mask, affinity I/O mask, affinity64 mask, and affinity64 I/O mask to determine if there is any overlap between the CPU affinity settings for regular and I/O operations.

	More Info/sources:
		https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/affinity-input-output-mask-server-configuration-option
		https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/affinity-mask-server-configuration-option
		https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/affinity64-input-output-mask-server-configuration-option
	
		
*/

		SET @AdditionalInfo =
			(
				SELECT 
					'Current Affinity Mask and Affinity I/O Mask are overlaping'
				FROM
					(
						SELECT
							affin = (SELECT CONVERT(int,[value]) FROM sys.configurations WHERE [name] = 'affinity mask'),
							affinIO = (SELECT CONVERT(int,[value]) FROM sys.configurations WHERE [name] = 'affinity I/O mask'),
							affin64 = (SELECT CONVERT(int, [value]) FROM sys.configurations WHERE [name] = 'affinity64 mask'),
							affin64IO = (SELECT CONVERT(int, [value]) FROM sys.configurations WHERE [name] = 'affinity64 I/O mask')
					) AS a
				WHERE 
					(affin & affinIO <> 0)
					OR (affin & affinIO <> 0 AND affin64 & affin64IO <> 0)
				FOR XML
					PATH (N'') ,
					ROOT (N'Affinity')
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


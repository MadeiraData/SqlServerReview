
/*
	DESCRIPTION:

*/

		DECLARE
			@NumberOfPlans AS INT;

		SET @AdditionalInfo = NULL;

		SELECT @NumberOfPlans = COUNT(*)
		FROM
			#Plans2Check AS p
		WHERE
			UserFunctionFilter = 1;

		SET @AdditionalInfo = 
							(
								SELECT
									N'Query Plans with User Function Filter'	AS AdditionalInfo,
									@NumberOfPlans								AS NumberOfPlans
								WHERE
									@NumberOfPlans > 0
								FOR XML
									PATH (N'') ,
									ROOT (N'QueryPlanswithUserFunctionFilter')
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
					WHEN @NumberOfPlans = 0
						THEN 0	-- None
					WHEN @NumberOfPlans BETWEEN 1 AND 10
						THEN 1	-- Low
					WHEN @NumberOfPlans BETWEEN 11 AND 30
						THEN 2	-- Medium
					ELSE
						3	-- High
				END ,
			RecommendationEffort	=
				CASE
					WHEN @NumberOfPlans = 0
						THEN 0	-- None
					WHEN @NumberOfPlans BETWEEN 1 AND 10
						THEN 1	-- Low
					WHEN @NumberOfPlans BETWEEN 11 AND 30
						THEN 2	-- Medium
					ELSE
						3	-- High
				END ,
			RecommendationRisk		=
				CASE
					WHEN @NumberOfPlans = 0
						THEN 0	-- None
					ELSE
						2	-- Medium
				END ,
			AdditionalInfo			= @AdditionalInfo,
			[Responsible DBA Team]					= N'Development';


		DECLARE
			@NumberOfPlans AS INT;

		SET @AdditionalInfo = NULL;

		WITH
			XMLNAMESPACES (DEFAULT N'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
		SELECT
			@AdditionalInfo = N'Found Query Plans with Index Spools or Table Spools'
		FROM
			sys.dm_exec_cached_plans AS CachedPlans
		CROSS APPLY
			sys.dm_exec_query_plan (CachedPlans.[plan_handle]) AS QueryPlans
		WHERE
		(
			QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Index Spool"][1])') = 1
		OR
			QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Table Spool"][1])') = 1
		)
		AND
			QueryPlans.query_plan.query('.').exist('data(//Object[@Schema!="[sys]"][1])') = 1;

		SET @NumberOfPlans = @@ROWCOUNT;

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
			AdditionalInfo			= NULL;

		BREAK;


		SET @AdditionalInfo = NULL;

		WITH
			XMLNAMESPACES (DEFAULT N'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
		SELECT TOP (1)
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

		INSERT INTO
			#Checks
		(
			CheckId ,
			Title ,
			RequiresAttention ,
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
			CurrentStateImpact		= 2 ,	-- Medium
			RecommendationEffort	= 3 ,	-- High
			RecommendationRisk		= 2 ,	-- Medium
			AdditionalInfo			= NULL;

		BREAK;

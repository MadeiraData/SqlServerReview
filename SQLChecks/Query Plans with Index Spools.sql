
/*
	DESCRIPTION:
		Indicates that SQL Server’s query optimizer has chosen to use an Index Spool operator in the execution plan. 
		This operator temporarily stores intermediate results in a hidden table (spool) to optimize certain types of queries, especially those involving complex joins or subqueries.
		
		While Index Spools can improve performance in some scenarios, they often indicate suboptimal query plans. 
		It’s generally better to address the underlying issues, such as adding appropriate indexes or rewriting the query to avoid the need for spools.

		Index Spools can be introduced for several reasons:
			Missing Indexes: The optimizer might use an Index Spool to compensate for missing indexes that could otherwise speed up the query.
			Complex Joins: In cases where the query involves complex joins, the optimizer might use an Index Spool to store intermediate results for reuse.
			Recursive Queries: Recursive Common Table Expressions (CTEs) often use spools to manage intermediate results.
			Modifications: Queries that involve wide modifications or cascading actions might use Index Spools to track changes.

		https://erikdarling.com/indexing-sql-server-queries-for-performance-fixing-an-eager-index-spool/
		https://erikdarling.com/common-query-plan-patterns-spools-from-nowhere/

*/

		DECLARE
			@NumberOfPlans AS INT;

		SET @AdditionalInfo = NULL;

		WITH
			XMLNAMESPACES (DEFAULT N'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
		SELECT
			@AdditionalInfo = N'Found Query Plans with Index Spools'
		FROM
			sys.dm_exec_cached_plans AS CachedPlans
		CROSS APPLY
			sys.dm_exec_query_plan (CachedPlans.[plan_handle]) AS QueryPlans
		WHERE
		(
			QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Index Spool"][1])') = 1
		)
		AND
			QueryPlans.query_plan.query('.').exist('data(//Object[@Schema!="[sys]"][1])') = 1;

		SET @NumberOfPlans = @@ROWCOUNT;

		SET @AdditionalInfo = 
							(
								SELECT
									@AdditionalInfo		AS AdditionalInfo,
									@NumberOfPlans		AS NumberOfPlans
								WHERE
									@NumberOfPlans > 0
								FOR XML
									PATH (N'') ,
									ROOT (N'QueryPlanswithIndexSpool')
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
			AdditionalInfo			= @AdditionalInfo;

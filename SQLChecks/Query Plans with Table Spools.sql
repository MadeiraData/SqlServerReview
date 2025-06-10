
/*
	DESCRIPTION:
		Indicates that SQL Server’s query optimizer has chosen to use a Table Spool operator in the execution plan. 
		This operator temporarily stores a copy of all data it reads in a worktable (in tempdb) and can later return extra copies of these rows without having to call its child operators to produce them again. 

		While Table Spools can improve performance in some scenarios, they often indicate suboptimal query plans. 
		It’s generally better to address the underlying issues, such as adding appropriate indexes or rewriting the query to avoid the need for spools.

		Table Spools can be introduced for several reasons:
			Repeated Data Access: The optimizer might use a Table Spool to avoid repeatedly accessing the same data.
			Complex Joins: In cases where the query involves complex joins, the optimizer might use a Table Spool to store intermediate results for reuse.
			Wide Updates: Queries that involve wide modifications might use Table Spools to ensure data consistency.
			Halloween Protection: To ensure that an original copy of the data is available after an insert, update, or delete operation changes the base data.

		https://sqlserverfast.com/epr/table-spool/ 
		https://www.sqlservercentral.com/blogs/performance-tuning-exercise-lazy-table-spool

*/

		DECLARE
			@NumberOfPlans AS INT;

		SET @AdditionalInfo = NULL;

		--WITH
		--	XMLNAMESPACES (DEFAULT N'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
		--SELECT
		--	@AdditionalInfo = N'Found Query Plans with Table Spools'
		--FROM
		--	sys.dm_exec_cached_plans AS CachedPlans
		--CROSS APPLY
		--	sys.dm_exec_query_plan (CachedPlans.[plan_handle]) AS QueryPlans
		--WHERE
		--(
		--	QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Table Spool"][1])') = 1
		--)
		--AND
		--	QueryPlans.query_plan.query('.').exist('data(//Object[@Schema!="[sys]"][1])') = 1;

		--SET @NumberOfPlans = @@ROWCOUNT;

		--SET @AdditionalInfo = 
		--					(
		--						SELECT
		--							@AdditionalInfo		AS AdditionalInfo,
		--							@NumberOfPlans		AS NumberOfPlans
		--						WHERE
		--							@NumberOfPlans > 0
		--						FOR XML
		--							PATH (N'') ,
		--							ROOT (N'QueryPlanswithTableSpool')
		--					);

		SELECT @NumberOfPlans = COUNT(*)
		FROM
			#Plans2Check AS p
		WHERE
			TableSpool = 1;

		SET @AdditionalInfo = 
							(
								SELECT
									N'Query Plans with Table Spools'	AS AdditionalInfo,
									@NumberOfPlans						AS NumberOfPlans
								WHERE
									@NumberOfPlans > 0
								FOR XML
									PATH (N'') ,
									ROOT (N'QueryPlanswithTableSpool')
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

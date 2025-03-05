/*
	DESCRIPTION:
		The instance configuration "cost threshold for parallelism" is what determines for SQL Server the minimum sub-tree cost before it starts considering to create a parallelism plan. The default "out-of-the-box" value of this configuration is 5.
		 
		More info:
		https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-cost-threshold-for-parallelism-server-configuration-option
		https://eitanblumin.com/2018/11/06/planning-to-increase-cost-threshold-for-parallelism-like-a-smart-person
		https://michaeljswart.com/2022/01/measure-the-effect-of-cost-threshold-for-parallelism 

*/

DECLARE
	@CurrentCostThreshold	INT;

	SELECT @CurrentCostThreshold = CAST(value_in_use AS INT)
	FROM sys.configurations
	WHERE [name] = 'cost threshold for parallelism';

IF @CurrentCostThreshold <= 5
BEGIN
	SET @AdditionalInfo =
		(
			SELECT @CurrentCostThreshold	AS [CurrentValue]
			FOR XML
				PATH (N'') ,
				ROOT (N'CostThresholdForParallelism')
		);
END

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
			WorstCaseImpact			= 1 ,	-- Low
			CurrentStateImpact		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END ,
			RecommendationRisk		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END ,
			AdditionalInfo			= @AdditionalInfo;


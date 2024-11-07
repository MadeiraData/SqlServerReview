

-- View the results

SELECT
	InstanceScore = CAST (ROUND ((1.0 - CAST (SUM (CurrentStateImpact) AS DECIMAL(19,2)) / CAST (SUM (WorstCaseImpact) AS DECIMAL(19,2))) * 100.0 , 0) AS TINYINT)
FROM
	#Checks;

SELECT
	[Check Id]				= CheckId ,
	[Problem Description]	= Title ,
	[Requires Attention]	= RequiresAttention ,
	[Current State Impact]	=
		CASE CurrentStateImpact
			WHEN 0 THEN N'None'
			WHEN 1 THEN N'Low'
			WHEN 2 THEN N'Medium'
			WHEN 3 THEN N'High'
		END ,
	[Recommendation Effort]	= 
		CASE RecommendationEffort
			WHEN 0 THEN N'None'
			WHEN 1 THEN N'Low'
			WHEN 2 THEN N'Medium'
			WHEN 3 THEN N'High'
		END ,
	[Recommendation Risk]	=
		CASE RecommendationRisk
			WHEN 0 THEN N'None'
			WHEN 1 THEN N'Low'
			WHEN 2 THEN N'Medium'
			WHEN 3 THEN N'High'
		END ,
	[Additional Info]		= AdditionalInfo
FROM
	#Checks
ORDER BY
	#Checks.RequiresAttention		DESC ,
	#Checks.CurrentStateImpact		DESC ,
	#Checks.RecommendationEffort	ASC ,
	#Checks.RecommendationRisk		ASC;

IF EXISTS
	(
		SELECT
			NULL
		FROM
			#Errors
	)
BEGIN

	SELECT
		CheckId ,
		ErrorNumber ,
		ErrorMessage ,
		ErrorSeverity ,
		ErrorState ,
		IsDeadlockRetry
	FROM
		#Errors
	ORDER BY
		CheckId			ASC ,
		IsDeadlockRetry	ASC;

END;
GO

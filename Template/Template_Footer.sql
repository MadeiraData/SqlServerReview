

-- View the results

SELECT
	InstanceScore = CAST (ROUND ((1.0 - CAST (SUM (CurrentStateImpact) AS DECIMAL(19,2)) / CAST (SUM (WorstCaseImpact) AS DECIMAL(19,2))) * 100.0 , 0) AS TINYINT)
FROM
	#Checks;
GO


SELECT
	Output_1 = N'Failed Checks that Require Attention:';
GO


SELECT
	[Check Id]				= CheckId ,
	[Problem Description]	= Title ,
	[Current State Impact]	=
		CASE CurrentStateImpact
			WHEN 1 THEN N'Low'
			WHEN 2 THEN N'Medium'
			WHEN 3 THEN N'High'
		END ,
	[Recommendation Effort]	= 
		CASE RecommendationEffort
			WHEN 1 THEN N'Low'
			WHEN 2 THEN N'Medium'
			WHEN 3 THEN N'High'
		END ,
	[Recommendation Risk]	=
		CASE RecommendationRisk
			WHEN 1 THEN N'Low'
			WHEN 2 THEN N'Medium'
			WHEN 3 THEN N'High'
		END ,
	[Additional Info]		= AdditionalInfo ,
	[Responsible DBA Team],
	[Instance Score Impact]	= CAST (ROUND (CAST (CurrentStateImpact AS DECIMAL(19,2)) / (SELECT CAST (SUM (WorstCaseImpact) AS DECIMAL(19,2)) FROM #Checks) * 100.0 , 0) AS TINYINT)
FROM
	#Checks
WHERE
	RequiresAttention = 1
ORDER BY
	#Checks.CurrentStateImpact		DESC ,
	#Checks.RecommendationEffort	ASC ,
	#Checks.RecommendationRisk		ASC;
GO


SELECT
	Output_2 = N'Passed Checks that Don''t Require Attention:';
GO


SELECT
	[Check Id]				= CheckId ,
	[Problem Description]	= Title ,
	[Additional Info]		= AdditionalInfo,
	[Responsible DBA Team]
FROM
	#Checks
WHERE
	RequiresAttention = 0
ORDER BY
	#Checks.CurrentStateImpact DESC;
GO


IF EXISTS
	(
		SELECT
			NULL
		FROM
			#Errors
	)
BEGIN

	SELECT
		Output_3 = N'Errors:';

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

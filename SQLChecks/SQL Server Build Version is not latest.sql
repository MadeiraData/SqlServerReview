
/*
    DESCRIPTION:
        Indicate that SQL Server build version is not latest (aka Service Pack / Cummulative Updates / Hotfix / GDR Security Fix).

*/

DECLARE
    @CurrentBuildVersion			AS NVARCHAR(128)	= CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)),
	@LatestBuildVersion		AS NVARCHAR(128)

SET @AdditionalInfo = NULL;
SELECT
	@LatestBuildVersion =
	CASE
		WHEN (LEN([Values]) - LEN(REPLACE([Values],'.',''))) < 3 THEN CONCAT([Values], '.0')
		ELSE [Values]
	END
FROM
	(
        VALUES ('16.0.4195.2'),('15.0.4430.1'),('14.0.3490.10'),('13.0.7050.2'),('12.0.6449.1'),('11.0.7512.11'),('10.50.6785.2'),('10.0.6814.4'),('9.00.5324'),('8.00.2283'),('7.00.1063'),('6.50.479')
	) AS x([Values])
WHERE
    SUBSTRING([Values], 0, CHARINDEX('.', [Values], 0)) = SUBSTRING(@CurrentBuildVersion, 0, CHARINDEX('.', @CurrentBuildVersion, 0));

IF @CurrentBuildVersion < @LatestBuildVersion
BEGIN

	SET @AdditionalInfo = 
						(
							SELECT
								@LatestBuildVersion		AS Latest,
								@CurrentBuildVersion	AS [Current]
							FOR XML
								PATH (N'') ,
								ROOT (N'BuildVersion')
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
			WorstCaseImpact			= 2 ,   -- Medium
			CurrentStateImpact		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0	-- None
					ELSE
						2   -- Medium
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0	-- None
					ELSE
						2   -- Medium
				END ,
			RecommendationRisk		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0	-- None
					ELSE
						2	-- Medium
				END ,
			AdditionalInfo			= @AdditionalInfo,
            [Responsible DBA Team]					= N'Production/Development';



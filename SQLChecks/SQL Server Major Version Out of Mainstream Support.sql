
/*
    DESCRIPTION:
        Each SQL Server major version has a very specific product lifecycle, indicating the end of its mainstream support:
            Once a version reaches the end of its mainstream support, no more updates and hotfixes will be released for it. Only security hotfixes.
        
        As with most Microsoft products, Microsoft provides mainstream support for a product for 5 years after its initial release.
        This means that for the first 5-6 years you may see new smaller features or enhancements added to the product along with any bug fixes and security patches.

        Please consider upgrading to the latest SQL Version to enjoy bug fixes, performance improvements, and security updates for as long as possible, as well as the latest features and improvements offered in the newest version.

        For a list of reasons to upgrade the SQL Server version, visit this article - https://www.madeiradata.com/post/five-reasons-to-upgrade-your-sql-server

*/    

DECLARE
    @ServerMajorVersion1		AS NVARCHAR(128) = REPLACE(SUBSTRING(@@VERSION, 0, CHARINDEX(' (', @@VERSION, 0)), 'Microsoft ', '')

SET @AdditionalInfo = NULL;

DECLARE 
	@Version1					VARCHAR(24), 
	@ReleaseYear1				INT,
	@MainstreamSupportEndYear1	INT, 
	@ExtendedSupportEndYear1	INT

SELECT
	@Version1					= [Version], 
	@ReleaseYear1				= [ReleaseYear],
	@MainstreamSupportEndYear1	= [MainstreamSupportEndYear], 
	@ExtendedSupportEndYear1	= [ExtendedSupportEndYear]
FROM
	(
        VALUES ('SQL Server 2022', '2022', '2028', '2033'),('SQL Server 2019', '2019', '2025', '2030'),('SQL Server 2017', '2017', '2022', '2027'),('SQL Server 2016', '2016', '2021', '2026'),('SQL Server 2014', '2014', '2019', '2024'),('SQL Server 2012', '2012', '2017', '2022'),('SQL Server 2008 R2', '2010', '2012', '2019'),('SQL Server 2008', '2008', '2012', '2019'),('SQL Server 2005', '2006', '2011', '2016'),('SQL Server 2000', '2000', '2005', '2013')
	) AS x([Version], [ReleaseYear], [MainstreamSupportEndYear], [ExtendedSupportEndYear])
WHERE
	[Version] = @ServerMajorVersion1;

SET @AdditionalInfo = 
(
	SELECT
		@Version1					AS CurrentServerVersion,
		@ReleaseYear1				AS ReleaseYear,
		@MainstreamSupportEndYear1	AS MainstreamSupportEndYear,
		@ExtendedSupportEndYear1	AS ExtendedSupportEndYear
    WHERE
        @MainstreamSupportEndYear1 < YEAR(GETDATE())
	FOR XML
		PATH (N'') ,
		ROOT (N'ServerMajorVersion')
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
			WorstCaseImpact			= 
				CASE
					WHEN @MainstreamSupportEndYear1 < YEAR(GETDATE())-1	
						THEN 0	-- Non
					WHEN @MainstreamSupportEndYear1 >= YEAR(GETDATE())
						AND @ExtendedSupportEndYear1 < YEAR(GETDATE())-2
						THEN 1	-- Low
					WHEN @ExtendedSupportEndYear1 = YEAR(GETDATE())
						THEN 2	-- Medium
					ELSE 3		-- High
				END,
			CurrentStateImpact		=
				CASE
					WHEN @MainstreamSupportEndYear1 < YEAR(GETDATE())-1	
						THEN 0	-- Non
					WHEN @MainstreamSupportEndYear1 >= YEAR(GETDATE())
						AND @ExtendedSupportEndYear1 < YEAR(GETDATE())-2
						THEN 1	-- Low
					WHEN @ExtendedSupportEndYear1 = YEAR(GETDATE())
						THEN 2	-- Medium
					ELSE 3		-- High
				END,
			RecommendationEffort	= 1,
			RecommendationRisk		= 3,
			AdditionalInfo			= @AdditionalInfo,
            [Responsible DBA Team]					= N'Production/Development';


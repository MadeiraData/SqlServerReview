Param
(
    [string]$OutputScriptFilePath1 = "SQLChecks\SQL Server Major Version Out of Mainstream Support.sql"
    ,[string]$OutputScriptFilePath2 = "SQLChecks\SQL Server Major Version Out of Extended Support.sql"
)

# Define the URL
$url = "https://learn.microsoft.com/en-us/sql/sql-server/end-of-support/sql-server-end-of-support-overview"

# Fetch the HTML content
$html = Invoke-WebRequest -Uri $url -TimeoutSec 10

# Check for internet connection
if ($html.StatusCode -eq 200) {

    # Parse the HTML content to extract the Lifecycle dates table
    $tables = $html.ParsedHtml.getElementsByTagName("table")
    $builds = @()

    # Assuming the Lifecycle dates table is the first table on the page
    $lifecycleTable = $tables[1]
    for ($i = 1; $i -lt $lifecycleTable.rows.length; $i++) {
        $row = $lifecycleTable.rows[$i]
        $builds += @{
            Version = $row.cells[0].innerText
            ReleaseYear = $row.cells[1].innerText
            MainstreamSupportEndYear = $row.cells[2].innerText
            ExtendedSupportEndYear = $row.cells[3].innerText
        }
    }
    		
    # Convert the parsed data to a DataTable
    $dataTable = New-Object System.Data.DataTable
    $dataTable.Columns.Add("Version", [string]) | Out-Null
    $dataTable.Columns.Add("ReleaseYear", [string]) | Out-Null
    $dataTable.Columns.Add("MainstreamSupportEndYear", [string]) | Out-Null
    $dataTable.Columns.Add("ExtendedSupportEndYear", [string]) | Out-Null

    $builds | ForEach-Object {
        $row = $dataTable.NewRow()
        $row["Version"] = $_.Version
        $row["ReleaseYear"] = $_.ReleaseYear
        $row["MainstreamSupportEndYear"] = $_.MainstreamSupportEndYear
        $row["ExtendedSupportEndYear"] = $_.ExtendedSupportEndYear
        $dataTable.Rows.Add($row)
    }

    # Insert data into the row-constructor
    $ValuesList = ""
    foreach ($row in $dataTable.Rows) {
        $Version = $($row.Version)
        $ReleaseYear = $($row.ReleaseYear)
        $MainstreamSupportEndYear = $($row.MainstreamSupportEndYear)
        $ExtendedSupportEndYear = $($row.ExtendedSupportEndYear)

        $ValuesList += "('$Version', '$ReleaseYear', '$MainstreamSupportEndYear', '$ExtendedSupportEndYear'),"
    }

   # Remove the trailing comma
    $ValuesList = $ValuesList.TrimEnd(',')

    $ValuesList += "
	) AS x([Version], [ReleaseYear], [MainstreamSupportEndYear], [ExtendedSupportEndYear])
WHERE
"

    # SQL scripts headers and footers
    $MainstreamScriptHeader = "
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
        VALUES "

    $ExtendedScriptHeader = "
/*
    DESCRIPTION:
        Each SQL Server major version has a very specific product lifecycle, indicating the end of its extended support:
            Once a version reaches the end of its extended support, no more updates of any kind will be released for it, not even security hotfixes.
        
        As with most Microsoft products, Microsoft provides mainstream support for a product for 5 years after its initial release.
        After this mainstream support ends you will usually get another 5 years of extended support at which time you can only expect bug fixes and security patches.

        Please consider upgrading to the latest SQL Version to enjoy bug fixes, performance improvements, and security updates for as long as possible, as well as the latest features and improvements offered in the newest version.

        For a list of reasons to upgrade the SQL Server version, visit this article - https://www.madeiradata.com/post/five-reasons-to-upgrade-your-sql-server

*/    

DECLARE
	@ServerMajorVersion2		AS NVARCHAR(128) = REPLACE(SUBSTRING(@@VERSION, 0, CHARINDEX(' (', @@VERSION, 0)), 'Microsoft ', '')

SET @AdditionalInfo = NULL;

DECLARE 
	@Version2					VARCHAR(24), 
	@ReleaseYear2				INT,
	@MainstreamSupportEndYear2	INT, 
	@ExtendedSupportEndYear2	INT

SELECT
	@Version2					= [Version], 
	@ReleaseYear2				= [ReleaseYear],
	@MainstreamSupportEndYear2	= [MainstreamSupportEndYear], 
	@ExtendedSupportEndYear2	= [ExtendedSupportEndYear]
FROM
	(
        VALUES "

    $MainstreamScriptFooter = "	[Version] = @ServerMajorVersion1;

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

    "
    $ExtendedScriptFooter = "	[Version] = @ServerMajorVersion2

SET @AdditionalInfo = 
(
	SELECT
		@Version2					AS CurrentServerVersion,
		@ReleaseYear2				AS ReleaseYear,
		@MainstreamSupportEndYear2	AS MainstreamSupportEndYear,
		@ExtendedSupportEndYear2	AS ExtendedSupportEndYear
    WHERE
        @ExtendedSupportEndYear2 < YEAR(GETDATE())
	FOR XML
		PATH (N'') ,
		ROOT (N'ServerMajorVersion')
);

    "
$MainstreamScript_End = 
"
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
"
$ExtendedScript_End = 
"
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
					WHEN @MainstreamSupportEndYear2 < YEAR(GETDATE())-1	
						THEN 0	-- Non
					WHEN @MainstreamSupportEndYear2 >= YEAR(GETDATE())
						AND @ExtendedSupportEndYear2 < YEAR(GETDATE())-2
						THEN 1	-- Low
					WHEN @ExtendedSupportEndYear2 = YEAR(GETDATE())
						THEN 2	-- Medium
					ELSE 3		-- High
				END,
			CurrentStateImpact		=
				CASE
					WHEN @MainstreamSupportEndYear2 < YEAR(GETDATE())-1	
						THEN 0	-- Non
					WHEN @MainstreamSupportEndYear2 >= YEAR(GETDATE())
						AND @ExtendedSupportEndYear2 < YEAR(GETDATE())-2
						THEN 1	-- Low
					WHEN @ExtendedSupportEndYear2 = YEAR(GETDATE())
						THEN 2	-- Medium
					ELSE 3		-- High
				END,
			RecommendationEffort	= 1,
			RecommendationRisk		= 3,
			AdditionalInfo			= @AdditionalInfo,
            [Responsible DBA Team]					= N'Production/Development';
"

    $MainstreamScriptHeader + $ValuesList + $MainstreamScriptFooter + $MainstreamScript_End | Out-File $OutputScriptFilePath1 -Force
    $ExtendedScriptHeader + $ValuesList + $ExtendedScriptFooter + $ExtendedScript_End | Out-File $OutputScriptFilePath2 -Force
} else {
    Write-Host "Internet connection is not available. Output file will not be changed."
}

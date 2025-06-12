Param
(
    [string]$OutputScriptFilePath = "SQLChecks\SQL Server Build Version is not latest.sql"
)

# Define the URL
$url = "https://learn.microsoft.com/en-us/troubleshoot/sql/releases/download-and-install-latest-updates"

# Fetch the HTML content
$html = Invoke-WebRequest -Uri $url -TimeoutSec 10

# Check for internet connection
if ($html.StatusCode -eq 200) {


    # Add a small delay to ensure content is fully loaded
    Start-Sleep -Seconds 5

    # Parse the HTML content to extract the first row of each table, skipping the first two tables
    $tables = $html.ParsedHtml.getElementsByTagName("table")
    $builds = @()

    # Iterate through tables, starting from the 2nd one (index 1)
    for ($i = 1; $i -lt $tables.length; $i++) {
        $table = $tables[$i]
        $rows = $table.getElementsByTagName("tr")

        # Get the first row (after the header row)
        if ($rows.length -gt 1) {
            $firstRow = $rows[1]  # Skip header and get the first data row

            # Get the version from the first column of the first data row
            $versionCell = $firstRow.getElementsByTagName("td")[0]
            $version = $versionCell.innerText.Trim()

            # Add the version to the builds array
            $builds += [PSCustomObject]@{
                Version = $version
            }
        }
    }

    # Convert the parsed data to a DataTable
    $dataTable = New-Object System.Data.DataTable
    $dataTable.Columns.Add("Version", [string]) | Out-Null

    # Populate the DataTable
    $builds | ForEach-Object {
        $row = $dataTable.NewRow()
        $row["Version"] = $_.Version
        $dataTable.Rows.Add($row)
    }

    # Generate SQL script values
    $VALUES = ""
    foreach ($row in $dataTable.Rows) {
        $Version = $($row["Version"])
        $VALUES += "('$Version')," 
    }

    # Remove the trailing comma
    $VALUES = $VALUES.TrimEnd(',')

    # SQL script header and footer
    $SQLBuildScript_Header = "
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
        VALUES "

    $SQLBuildScript_Footer = "
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

"

    # Output the full SQL script to the file
    $SQLBuildScript_Header + $VALUES + $SQLBuildScript_Footer | Out-File $OutputScriptFilePath -Force

} else {
    Write-Host "Internet connection is not available. Output file will not be changed."
}

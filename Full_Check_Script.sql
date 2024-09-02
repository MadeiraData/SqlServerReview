USE
	[master];
GO

GO
:setvar ThresholdParam 10
GO
:on error exit
GO
/*
Detect SQLCMD mode and disable script execution if SQLCMD mode is not supported.
To re-enable the script after enabling SQLCMD mode, execute the following:
SET NOEXEC OFF; 
*/
:setvar __IsSqlCmdEnabled "True"
GO
IF N'$(__IsSqlCmdEnabled)' NOT LIKE N'True'
BEGIN
    PRINT N'SQLCMD mode must be enabled to successfully execute this script.';
    SET NOEXEC ON;
END
GO

-- Local variables and temporary tables

DECLARE
	@CheckId						AS INT ,
	@AdditionalInfo					AS XML ,
	@DeadlockRetry					AS BIT ,
	@DatabaseName					AS SYSNAME ,
	@Command						AS NVARCHAR(MAX) ,
	@InstanceCompatibilityLevel		AS TINYINT ,
	@AdhocRatio						AS DECIMAL(3,2) ,
	@OptimizeForAdhocWorkloads		AS BIT ,
	@OperatingSystemArchitecture	AS NVARCHAR(4) ,
	@SQLServerArchitecture			AS NVARCHAR(4) ,
	@CurrentMaxMemorySetting_MB		AS INT ,
	@MaxWorkerThreads				AS INT ,
	@TotalPhysicalMemory_MB			AS INT ,
	@RecommendedMaxMemorySetting_MB	AS INT;

DROP TABLE IF EXISTS
	#Checks;

CREATE TABLE
	#Checks
(
	CheckId					INT				NOT NULL ,
	Title					NVARCHAR(100)	NOT NULL ,
	RequiresAttention		BIT				NOT NULL ,
	CurrentStateImpact		TINYINT			NOT NULL ,
	RecommendationEffort	TINYINT			NOT NULL ,
	RecommendationRisk		TINYINT			NOT NULL ,
	AdditionalInfo			XML				NULL
);

DROP TABLE IF EXISTS
	#Errors;

CREATE TABLE
	#Errors
(
	CheckId			INT				NOT NULL ,
	ErrorNumber		INT				NOT NULL ,
	ErrorMessage	NVARCHAR(4000)	NOT NULL ,
	ErrorSeverity	INT				NOT NULL ,
	ErrorState		INT				NOT NULL ,
	IsDeadlockRetry	BIT				NOT NULL
);


-- Display general information about the instance

SET @OperatingSystemArchitecture =
	CASE
		WHEN @@VERSION LIKE N'%<X86>%'	THEN N'X86'
		WHEN @@VERSION LIKE N'%<X64>%'	THEN N'X64'
		WHEN @@VERSION LIKE N'%<IA64>%' THEN N'IA64'
	END;

SET @SQLServerArchitecture =
	CASE
		WHEN @@VERSION LIKE N'%(X86)%'	THEN N'X86'
		WHEN @@VERSION LIKE N'%(X64)%'	THEN N'X64'
		WHEN @@VERSION LIKE N'%(IA64)%' THEN N'IA64'
	END;

SELECT
	ServerName					= SERVERPROPERTY ('ServerName') ,
	InstanceVersion				=
		CASE
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '8%'	THEN N'2000'
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '9%'	THEN N'2005'
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '10.0%'	THEN N'2008'
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '10.5%'	THEN N'2008 R2'
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '11%'	THEN N'2012'
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '12%'	THEN N'2014'
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '13%'	THEN N'2016'
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '14%'	THEN N'2017'
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '15%'	THEN N'2019'
			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '16%'	THEN N'2022'
		END ,
	ProductLevel				= SERVERPROPERTY ('ProductLevel') ,
	ProductUpdateLevel			= SERVERPROPERTY ('ProductUpdateLevel') ,										-- Applies to: SQL Server 2012 (11.x) through current version in updates beginning in late 2015
	ProductBuildNumber			= SERVERPROPERTY ('ProductVersion') ,
	InstanceEdition				= SERVERPROPERTY ('Edition') ,
	IsPartOfFCI					= SERVERPROPERTY ('IsClustered') ,
	IsEnabledForAG				= SERVERPROPERTY ('IsHadrEnabled') ,											-- Applies to: SQL Server 2012 (11.x) and later
	HostPlatform				= HostInfo.host_distribution ,													-- Applies to: SQL Server 2017 (14.x) and later
	OperatingSystemArchitecture	= @OperatingSystemArchitecture ,
	SQLServerArchitecture		= @SQLServerArchitecture ,
	VirtualizationType			= SystemInfo.virtual_machine_type_desc ,										-- Applies to: SQL Server 2008 R2 and later
	NumberOfCores				= SystemInfo.cpu_count ,
	PhysicalMemory_GB			= CAST (ROUND (SystemInfo.physical_memory_kb / 1024.0 / 1024.0 , 0) AS INT) ,	-- Applies to: SQL Server 2012 (11.x) and later
	LastServiceRestartDateTime	= SystemInfo.sqlserver_start_time
FROM
	sys.dm_os_host_info AS HostInfo
CROSS JOIN
	sys.dm_os_sys_info AS SystemInfo;

GO

GO
DECLARE
	  @CheckId			AS INT = 1
	, @DeadlockRetry	AS BIT = 0


-- Check #1

WHILE
	1 = 1
BEGIN

	BEGIN TRY

		DECLARE
			@AdditionalInfo					AS XML

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = [name]
				FROM
					sys.databases
				WHERE
					is_auto_create_stats_on = 0
				ORDER BY
					database_id ASC
				FOR XML
					PATH (N'') ,
					ROOT (N'Databases')
			);

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
			CheckId					= '1' ,
			Title					= N'Auto Create Statistics is Off' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 3 ,	-- High
			RecommendationEffort	= 1 ,	-- Low
			RecommendationRisk		= 1 ,	-- Low
			AdditionalInfo			= @AdditionalInfo;
		BREAK;

	END TRY
	BEGIN CATCH

		INSERT INTO
			#Errors
		(
			CheckId ,
			ErrorNumber ,
			ErrorMessage ,
			ErrorSeverity ,
			ErrorState ,
			IsDeadlockRetry
		)
		SELECT
			CheckId			= @CheckId ,
			ErrorNumber		= ERROR_NUMBER () ,
			ErrorMessage	= ERROR_MESSAGE () ,
			ErrorSeverity	= ERROR_SEVERITY () ,
			ErrorState		= ERROR_STATE () ,
			IsDeadlockRetry	= @DeadlockRetry;

		IF
			ERROR_NUMBER () = 1205	-- Deadlock
		AND
			@DeadlockRetry = 0
		BEGIN
			SET @DeadlockRetry = 1
		END
		ELSE
		BEGIN
			BREAK;
		END;

	END CATCH;

END;
GO
DECLARE
	  @CheckId			AS INT = 2
	, @DeadlockRetry	AS BIT = 0


-- Check #2

WHILE
	1 = 1
BEGIN

	BEGIN TRY
		DECLARE
			@DatabaseName					AS SYSNAME ,
			@AdditionalInfo					AS XML ,
			@Command						AS NVARCHAR(MAX)

		DROP TABLE IF EXISTS
			#HeapTables;

		CREATE TABLE
			#HeapTables
		(
			DatabaseName	SYSNAME	NOT NULL ,
			SchemaName		SYSNAME	NOT NULL ,
			TableName		SYSNAME	NOT NULL
		);

		DROP TABLE IF EXISTS
			#DatabaseRowSizes

		CREATE TABLE
			#DatabaseRowSizes
		(
			DatabaseName	SYSNAME	NOT NULL ,
			TotalRowSize	BIGINT	NOT NULL ,
			HeapRowSize		BIGINT	NOT NULL
		);

		DECLARE
			DatabasesCursor
		CURSOR
			LOCAL
			FAST_FORWARD
		FOR
			SELECT
				DatabaseName = [name]
			FROM
				sys.databases
			WHERE
				database_id != 2;	-- tempdb

		OPEN DatabasesCursor;

		FETCH NEXT FROM
			DatabasesCursor
		INTO
			@DatabaseName;

		WHILE
			@@FETCH_STATUS = 0
		BEGIN

			SET @Command =
				N'
					USE
						' + QUOTENAME (@DatabaseName) + N';

					INSERT INTO
						#HeapTables
					(
						DatabaseName ,
						SchemaName ,
						TableName
					)
					SELECT
						DatabaseName	= DB_NAME () ,
						SchemaName		= SCHEMA_NAME (Tables.schema_id) ,
						TableName		= Tables.name
					FROM
						sys.tables AS Tables
					INNER JOIN
						sys.indexes AS Indexes
					ON
						Tables.object_id = Indexes.object_id
					WHERE
						Indexes.index_id = 0;

					INSERT INTO
						#DatabaseRowSizes
					(
						DatabaseName ,
						TotalRowSize ,
						HeapRowSize
					)
					SELECT
						DatabaseName	= DB_NAME () ,
						TotalRowSize	= ISNULL (SUM (Partitions.rows) , 0) ,
						HeapRowSize		=
							ISNULL
							(
								SUM
								(
									CASE
										WHEN Indexes.index_id = 0
											THEN Partitions.rows
										ELSE
											0
									END
								) ,
								0
							)
					FROM
						sys.tables AS Tables
					INNER JOIN
						sys.indexes AS Indexes
					ON
						Tables.object_id = Indexes.object_id
					INNER JOIN
						sys.partitions AS Partitions
					ON
						Indexes.object_id = Partitions.object_id
					AND
						Indexes.index_id = Partitions.index_id
					WHERE
						Indexes.index_id IN (0,1);';

			EXECUTE sys.sp_executesql
				@stmt = @Command;

			FETCH NEXT FROM
				DatabasesCursor
			INTO
				@DatabaseName;

		END;

		CLOSE DatabasesCursor;

		DEALLOCATE DatabasesCursor;

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName	= [Database].DatabaseName ,
					SchemaName		= HeapTable.SchemaName ,
					TableName		= HeapTable.TableName
				FROM
					(
						SELECT DISTINCT
							DatabaseName
						FROM
							#HeapTables
					)
					AS
						[Database]
				INNER JOIN
					#HeapTables AS HeapTable
				ON
					[Database].DatabaseName = HeapTable.DatabaseName
				ORDER BY
					DatabaseName	ASC ,
					SchemaName		ASC ,
					TableName		ASC
				FOR XML
					AUTO ,
					ROOT (N'HeapTables')
			);

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
			CheckId					= '2' ,
			Title					= N'Heap Tables' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 2 ,	-- Medium
			RecommendationEffort	= 3 ,	-- High
			RecommendationRisk		= 3 ,	-- High
			AdditionalInfo			= @AdditionalInfo;

		DROP TABLE
			#HeapTables;

		BREAK;

	END TRY
	BEGIN CATCH

		INSERT INTO
			#Errors
		(
			CheckId ,
			ErrorNumber ,
			ErrorMessage ,
			ErrorSeverity ,
			ErrorState ,
			IsDeadlockRetry
		)
		SELECT
			CheckId			= @CheckId ,
			ErrorNumber		= ERROR_NUMBER () ,
			ErrorMessage	= ERROR_MESSAGE () ,
			ErrorSeverity	= ERROR_SEVERITY () ,
			ErrorState		= ERROR_STATE () ,
			IsDeadlockRetry	= @DeadlockRetry;

		IF
			ERROR_NUMBER () = 1205	-- Deadlock
		AND
			@DeadlockRetry = 0
		BEGIN
			SET @DeadlockRetry = 1
		END
		ELSE
		BEGIN
			BREAK;
		END;

	END CATCH;

END;
GO
DECLARE
	  @CheckId			AS INT = 3
	, @DeadlockRetry	AS BIT = 0


-- Check #3

WHILE
	1 = 1
BEGIN

	BEGIN TRY
		DECLARE
			@DatabaseName					AS SYSNAME ,
			@AdditionalInfo					AS XML ,
			@Command						AS NVARCHAR(MAX)

		DROP TABLE IF EXISTS
			#Databases;

		CREATE TABLE
			#Databases
		(
			DatabaseName SYSNAME NOT NULL
		);

		DECLARE
			DatabasesCursor
		CURSOR
			LOCAL
			FAST_FORWARD
		FOR
			SELECT
				DatabaseName = [name]
			FROM
				sys.databases
			WHERE
				is_auto_update_stats_on = 0;

		OPEN DatabasesCursor;

		FETCH NEXT FROM
			DatabasesCursor
		INTO
			@DatabaseName;

		WHILE
			@@FETCH_STATUS = 0
		BEGIN

			SET @Command =
				N'
					USE
						' + QUOTENAME (@DatabaseName) + N';

					IF NOT EXISTS
						(
							SELECT
								NULL
							FROM
								sys.stats AS Stats
							CROSS APPLY
								sys.dm_db_stats_properties (Stats.[object_id] , Stats.stats_id) AS StatsProperties
							WHERE
								StatsProperties.last_updated > DATEADD (MONTH , -1 , SYSDATETIME ());
						)
					BEGIN

						INSERT INTO
							#Databases
						(
							DatabaseName
						)
						SELECT
							DatabaseName = DB_NAME ();

					END;
				';

			EXECUTE sys.sp_executesql
				@stmt = @Command;

			FETCH NEXT FROM
				DatabasesCursor
			INTO
				@DatabaseName;

		END;

		CLOSE DatabasesCursor;

		DEALLOCATE DatabasesCursor;

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = Databases.DatabaseName
				FROM
					#Databases AS Databases
				ORDER BY
					DatabaseName ASC
				FOR XML
					PATH (N'') ,
					ROOT (N'Databases')
			);

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
			CheckId					= '3' ,
			Title					= N'Statistics are Never Updated' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 3 ,	-- High
			RecommendationEffort	= 1 ,	-- Low
			RecommendationRisk		= 1 ,	-- Low
			AdditionalInfo			= @AdditionalInfo;

		DROP TABLE
			#Databases;

		BREAK;

	END TRY
	BEGIN CATCH

		INSERT INTO
			#Errors
		(
			CheckId ,
			ErrorNumber ,
			ErrorMessage ,
			ErrorSeverity ,
			ErrorState ,
			IsDeadlockRetry
		)
		SELECT
			CheckId			= @CheckId ,
			ErrorNumber		= ERROR_NUMBER () ,
			ErrorMessage	= ERROR_MESSAGE () ,
			ErrorSeverity	= ERROR_SEVERITY () ,
			ErrorState		= ERROR_STATE () ,
			IsDeadlockRetry	= @DeadlockRetry;

		IF
			ERROR_NUMBER () = 1205	-- Deadlock
		AND
			@DeadlockRetry = 0
		BEGIN
			SET @DeadlockRetry = 1
		END
		ELSE
		BEGIN
			BREAK;
		END;

	END CATCH;

END;
GO
GO
SET NOEXEC OFF;

-- View the results

SELECT
	InstanceScore = CAST (ROUND ((1.0 - CAST (SUM (CurrentStateImpact * CAST (RequiresAttention AS INT)) AS DECIMAL(19,2)) / CAST (SUM (CurrentStateImpact) AS DECIMAL(19,2))) * 100.0 , 0) AS TINYINT)
FROM
	#Checks;

SELECT
	[Check Id]				= CheckId ,
	[Problem Description]	= Title ,
	[Requires Attention]	= RequiresAttention ,
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


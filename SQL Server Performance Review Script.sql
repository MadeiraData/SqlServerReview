USE
	[master];
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


-- Check #1 - Heap Tables

SET @DeadlockRetry = 0;
SET @CheckId = 1;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

		DROP TABLE IF EXISTS
			#HeapTables;

		CREATE TABLE
			#HeapTables
		(
			DatabaseName	SYSNAME	NOT NULL ,
			SchemaName		SYSNAME	NOT NULL ,
			TableName		SYSNAME	NOT NULL
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
			CheckId					= @CheckId ,
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

			DROP TABLE IF EXISTS
				#HeapTables;

			BREAK;

		END;

	END CATCH;

END;


-- Check #2 - Auto Create Statistics is Off

SET @DeadlockRetry = 0;
SET @CheckId = 2;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

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
			CheckId					= @CheckId ,
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


-- Check #3 - Statistics are Never Updated

SET @DeadlockRetry = 0;
SET @CheckId = 3;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

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
			CheckId					= @CheckId ,
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

			DROP TABLE IF EXISTS
				#Databases;

			BREAK;

		END;

	END CATCH;

END;


-- Check #4 - Optimize for Ad-Hoc Workloads should be Enabled

SET @DeadlockRetry = 0;
SET @CheckId = 4;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

		SELECT
			@AdhocRatio	= CAST (SUM (CASE WHEN objtype = N'Adhoc' AND usecounts = 1 THEN CAST (size_in_bytes AS DECIMAL(19,2)) ELSE 0 END) / SUM (CAST (size_in_bytes AS DECIMAL(19,2))) AS DECIMAL(3,2))
		FROM
			sys.dm_exec_cached_plans;

		SELECT
			@OptimizeForAdhocWorkloads = CAST (value_in_use AS BIT)
		FROM
			sys.configurations
		WHERE
			[name] = N'optimize for ad hoc workloads';

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
			CheckId					= @CheckId ,
			Title					= N'Optimize for Ad-Hoc Workloads should be Enabled' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 1 ,	-- Low
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


-- Check #5 - Indexes with High Fragmentation

SET @DeadlockRetry = 0;
SET @CheckId = 5;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

		DROP TABLE IF EXISTS
			#FragmentedIndexes;

		CREATE TABLE
			#FragmentedIndexes
		(
			DatabaseName	SYSNAME	NOT NULL ,
			SchemaName		SYSNAME	NOT NULL ,
			TableName		SYSNAME	NOT NULL ,
			IndexName		SYSNAME	NOT NULL
		);

		IF
			CURSOR_STATUS ('local' , N'DatabasesCursor') = -3
		BEGIN

			DECLARE
				DatabasesCursor
			CURSOR
				LOCAL
				FAST_FORWARD
			FOR
				SELECT
					DatabaseName = [name]
				FROM
					sys.databases;

		END
		ELSE
		BEGIN

			CLOSE DatabasesCursor;

		END;

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
						#FragmentedIndexes
					(
						DatabaseName ,
						SchemaName ,
						TableName ,
						IndexName
					)
					SELECT
						DatabaseName	= DB_NAME () ,
						SchemaName		= SCHEMA_NAME (Tables.schema_id) ,
						TableName		= Tables.name ,
						IndexName		= ISNULL (Indexes.name , N''Heap'')
					FROM
						sys.tables AS Tables
					INNER JOIN
						sys.indexes AS Indexes
					ON
						Tables.object_id = Indexes.object_id
					WHERE
						Indexes.is_disabled = 0
					AND
						EXISTS
							(
								SELECT
									NULL
								FROM
									sys.dm_db_index_physical_stats (DB_ID () , Tables.object_id , Indexes.index_id , NULL , ''LIMITED'') AS IndexPhysicalStats
								WHERE
									IndexPhysicalStats.page_count > 1000
								AND
									IndexPhysicalStats.avg_fragmentation_in_percent > 70
							);
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
					DatabaseName	= [Database].DatabaseName ,
					SchemaName		= FragmentedIndexes.SchemaName ,
					TableName		= FragmentedIndexes.TableName ,
					IndexName		= FragmentedIndexes.IndexName
				FROM
					(
						SELECT DISTINCT
							DatabaseName
						FROM
							#FragmentedIndexes
					)
					AS
						[Database]
				INNER JOIN
					#FragmentedIndexes AS FragmentedIndexes
				ON
					[Database].DatabaseName = FragmentedIndexes.DatabaseName
				ORDER BY
					DatabaseName	ASC ,
					SchemaName		ASC ,
					TableName		ASC ,
					IndexName		ASC
				FOR XML
					AUTO ,
					ROOT (N'FragmentedIndexes')
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
			CheckId					= @CheckId ,
			Title					= N'Indexes with High Fragmentation' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 2 ,	-- Medium
			RecommendationEffort	= 1 ,	-- Low
			RecommendationRisk		= 2 ,	-- Medium
			AdditionalInfo			= @AdditionalInfo;

		DROP TABLE
			#FragmentedIndexes;

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

			DROP TABLE IF EXISTS
				#FragmentedIndexes;

			IF
				CURSOR_STATUS ('local' , N'DatabasesCursor') != -3
			BEGIN

				CLOSE DatabasesCursor;

				DEALLOCATE DatabasesCursor;

			END;

			BREAK;

		END;

	END CATCH;

END;


-- Check #6 - Databases not in the Same Compatibility Level as the Instance

SET @DeadlockRetry = 0;
SET @CheckId = 6;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

		SET @InstanceCompatibilityLevel = CAST (LEFT (CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) , CHARINDEX (N'.' , CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128))) - 1) AS TINYINT) * 10;

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = [name]
				FROM
					sys.databases
				WHERE
					[compatibility_level] != @InstanceCompatibilityLevel
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
			CheckId					= @CheckId ,
			Title					= N'Databases not in the Same Compatibility Level as the Instance' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 2 ,	-- Medium
			RecommendationEffort	= 2 ,	-- Medium
			RecommendationRisk		= 3 ,	-- Medium
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


-- Check #7 - Databases with Auto-Close Enabled

SET @DeadlockRetry = 0;
SET @CheckId = 7;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = [name]
				FROM
					sys.databases
				WHERE
					is_auto_close_on = 1
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
			CheckId					= @CheckId ,
			Title					= N'Databases with Auto-Close Enabled' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 1 ,	-- Low
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


-- Check #8 - Databases with Auto-Shrink Enabled

SET @DeadlockRetry = 0;
SET @CheckId = 8;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = [name]
				FROM
					sys.databases
				WHERE
					is_auto_shrink_on = 1
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
			CheckId					= @CheckId ,
			Title					= N'Databases with Auto-Shrink Enabled' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 1 ,	-- Low
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


-- Check #9 - Max Memory Configuration Too High

SET @DeadlockRetry = 0;
SET @CheckId = 9;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

		SELECT
			@CurrentMaxMemorySetting_MB = CAST ([value] AS INT)
		FROM
			sys.configurations
		WHERE
			[name] = N'max server memory (MB)';

		SELECT
			@MaxWorkerThreads = max_workers_count
		FROM
			sys.dm_os_sys_info;

		SELECT
			@TotalPhysicalMemory_MB = total_physical_memory_kb / 1024
		FROM
			sys.dm_os_sys_memory;

		SET @RecommendedMaxMemorySetting_MB =
			CAST
			(
				(
					@TotalPhysicalMemory_MB -
					@MaxWorkerThreads *
						CASE
							WHEN @OperatingSystemArchitecture = N'X86' AND @SQLServerArchitecture = N'X86'
								THEN 512.0 / 1024.0
							WHEN @OperatingSystemArchitecture = N'X64' AND @SQLServerArchitecture = N'X86'
								THEN 768.0 / 1024.0
							WHEN @OperatingSystemArchitecture = N'X64' AND @SQLServerArchitecture = N'X64'
								THEN 2048.0 / 1024.0
							WHEN @OperatingSystemArchitecture = N'IA64' AND @SQLServerArchitecture = N'IA64'
								THEN 4096.0 / 1024.0
						END
				) * 0.75
				AS INT
			);

		SET @AdditionalInfo =
			(
				SELECT
					[Current]	= @CurrentMaxMemorySetting_MB ,
					Recommended	= @RecommendedMaxMemorySetting_MB
				FOR XML
					PATH (N'') ,
					ROOT (N'MaxMemoryConfiguration')
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
			CheckId					= @CheckId ,
			Title					= N'Max Memory Configuration Too High' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 2 ,	-- Medium
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


-- Check #10 - Query Plans with Index Spools or Table Spools

SET @DeadlockRetry = 0;
SET @CheckId = 10;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

		SET @AdditionalInfo = NULL;

		WITH
			XMLNAMESPACES (DEFAULT N'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
		SELECT TOP (1)
			@AdditionalInfo = N'Found Query Plans with Index Spools or Table Spools'
		FROM
			sys.dm_exec_cached_plans AS CachedPlans
		CROSS APPLY
			sys.dm_exec_query_plan (CachedPlans.[plan_handle]) AS QueryPlans
		WHERE
		(
			QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Index Spool"][1])') = 1
		OR
			QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Table Spool"][1])') = 1
		)
		AND
			QueryPlans.query_plan.query('.').exist('data(//Object[@Schema!="[sys]"][1])') = 1;

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
			CheckId					= @CheckId ,
			Title					= N'Query Plans with Index Spools or Table Spools' ,
			RequiresAttention		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			CurrentStateImpact		= 2 ,	-- Medium
			RecommendationEffort	= 3 ,	-- High
			RecommendationRisk		= 2 ,	-- Medium
			AdditionalInfo			= NULL;

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


-- View the results

SELECT
	InstanceScore = CAST (ROUND ((1.0 - CAST (SUM (CurrentStateImpact * CAST (RequiresAttention AS INT)) AS DECIMAL(19,2)) / CAST (SUM (CurrentStateImpact) AS DECIMAL(19,2))) * 100.0 , 0) AS TINYINT)
FROM
	#Checks;

SELECT
	CheckId					= CheckId ,
	Title					= Title ,
	RequiresAttention		= RequiresAttention ,
	CurrentStateImpact		=
		CASE CurrentStateImpact
			WHEN 1 THEN N'Low'
			WHEN 2 THEN N'Medium'
			WHEN 3 THEN N'High'
		END ,
	RecommendationEffort	= 
		CASE RecommendationEffort
			WHEN 1 THEN N'Low'
			WHEN 2 THEN N'Medium'
			WHEN 3 THEN N'High'
		END ,
	RecommendationRisk		=
		CASE RecommendationRisk
			WHEN 1 THEN N'Low'
			WHEN 2 THEN N'Medium'
			WHEN 3 THEN N'High'
		END ,
	AdditionalInfo			= AdditionalInfo
FROM
	#Checks
ORDER BY
	RequiresAttention				DESC ,
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

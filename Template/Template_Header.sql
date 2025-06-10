USE
	[master];
GO


:setvar ThresholdParam 10
GO


:on error exit
GO


DECLARE
	@SkipIntensiveChecks			AS BIT = 0;		-- Set this to 1 to skip intensive checks, 0 to include them (default)

SET NOCOUNT ON;
SET DEADLOCK_PRIORITY -10;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE
	@SQLcmd							AS NVARCHAR(MAX)	= N'',
	@OperatingSystemArchitecture	AS NVARCHAR(4) ,
	@SQLServerArchitecture			AS NVARCHAR(4),
	@EngineEdition					AS INT,
	@ProductVersion					AS DECIMAL(3,1),
	@TraceFlags						AS NVARCHAR(1000),
	@Dbname							AS NVARCHAR(128);

IF OBJECT_ID('tempdb.dbo.#Checks', 'U') IS NOT NULL
BEGIN
	DROP TABLE #Checks;
END

CREATE TABLE
	#Checks
(
	CheckId					INT				NOT NULL ,
	Title					NVARCHAR(100)	NOT NULL ,
	RequiresAttention		BIT				NOT NULL ,
	WorstCaseImpact			TINYINT			NOT NULL ,
	CurrentStateImpact		TINYINT			NOT NULL ,
	RecommendationEffort	TINYINT			NOT NULL ,
	RecommendationRisk		TINYINT			NOT NULL ,
	AdditionalInfo			XML				NULL,
	[Responsible DBA Team]	NVARCHAR(24)	NULL 
);

IF OBJECT_ID('tempdb.dbo.#Errors', 'U') IS NOT NULL
BEGIN
	DROP TABLE #Errors;
END

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

IF OBJECT_ID('tempdb.dbo.#sys_databases', 'U') IS NOT NULL
BEGIN
	DROP TABLE #sys_databases;
END

SELECT *
INTO
	#sys_databases
FROM
	sys.databases
WHERE
	[name] != 'model'
OPTION (RECOMPILE);

IF OBJECT_ID('tempdb.dbo.#OserOptionsResults', 'U') IS NOT NULL
BEGIN
	DROP TABLE #OserOptionsResults;
END
CREATE TABLE #OserOptionsResults 
				(
					[Database Name]				NVARCHAR(128), 
					[Net Transport]				NVARCHAR(128), 
					[Protocol Type]				NVARCHAR(128), 
					[Text Size]					NVARCHAR(128), 
					[Language]					NVARCHAR(128), 
					[Date Format]				NVARCHAR(128), 
					[Date First]				NVARCHAR(128), 
					[Lock Timeout]				NVARCHAR(128), 
					[Quoted Identifier]			NVARCHAR(128), 
					[Arithabort]				NVARCHAR(128), 
					[Ansi NULL dflt on]			NVARCHAR(128), 
					[Ansi Warnings]				NVARCHAR(128), 
					[Ansi Padding]				NVARCHAR(128), 
					[Ansi NULLs]				NVARCHAR(128), 
					[Concat NULL Yields NULL]	NVARCHAR(128), 
					[Isolation Level]			NVARCHAR(128)
				);

IF OBJECT_ID('tempdb.dbo.#WaitsStats', 'U') IS NOT NULL
BEGIN
	DROP TABLE #WaitsStats;
END
CREATE TABLE #WaitsStats (
	[WaitType]		NVARCHAR(60)	NULL,
	[Wait_S]		DECIMAL(16, 2)	NULL,
	[Resource_S]	DECIMAL(16, 2)	NULL,
	[Signal_S]		DECIMAL(16, 2)	NULL,
	[WaitCount]		BIGINT			NULL,
	[Percentage]	DECIMAL(5, 2)	NULL,
	[AvgWait_S]		DECIMAL(16, 4)	NULL,
	[AvgRes_S]		DECIMAL(16, 4)	NULL,
	[AvgSig_S]		DECIMAL(16, 4)	NULL
) 

IF OBJECT_ID('tempdb.dbo.#Plans2Check', 'U') IS NOT NULL
BEGIN
	DROP TABLE #Plans2Check;
END
DROP TABLE IF EXISTS #Plans2Check;


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

SET @EngineEdition		= CAST (SERVERPROPERTY('EngineEdition') AS NVARCHAR(128));
SET @ProductVersion		= SUBSTRING(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)), 0, CHARINDEX('.', CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)), 4));

SET @SQLcmd = N'

-- Host properties
SELECT
	'

IF	(
		@EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
		AND @ProductVersion >= '13'			-- Major version 2016 (13.x)
	)
	OR @EngineEdition IN (5, 8)			-- Azure SQL Database;  Azure SQL Managed Instance
BEGIN
	SET @SQLcmd = @SQLcmd + N'	HostName				= HOST_NAME () ,													-- Applies to: SQL Server 2016 (13.x) and later; Azure SQL Database;  Azure SQL Managed Instance
'
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
	AND @ProductVersion >= '14'			-- Major version 2017 (14.x)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	HostPlatform				= (SELECT host_distribution FROM sys.dm_os_host_info) ,			-- Applies to: SQL Server 2017 (14.x) and later
	HostRelease				= (SELECT host_release FROM sys.dm_os_host_info) ,			-- Applies to: SQL Server 2017 (14.x) and later
'
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	OperatingSystemArchitecture	= ''' + @OperatingSystemArchitecture + N''' ,
'
END

IF @EngineEdition = 5					-- Azure SQL Database only
BEGIN
	SET @SQLcmd = @SQLcmd + N'	[Service Tier]	= DATABASEPROPERTYEX (DB_NAME(DB_ID()), ''Edition'') ,
	[Hardware Generation]		= DATABASEPROPERTYEX (DB_NAME(DB_ID()), ''ServiceObjective'') ,
'
END

IF @EngineEdition = 8					-- Azure SQL MI only
BEGIN
	SET @SQLcmd = @SQLcmd + N'	[Service Tier]	= (SELECT TOP (1) sku FROM sys.server_resource_stats WITH (NOLOCK)) ,
	[Hardware Generation]		= (SELECT TOP (1) hardware_generation FROM sys.server_resource_stats WITH (NOLOCK)) ,
'
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
	AND @ProductVersion >= '10.5'		-- Major version 2008 R2
BEGIN
	SET @SQLcmd = @SQLcmd + N'	VirtualizationType			= SystemInfo.virtual_machine_type_desc ,										-- Applies to: SQL Server 2008 R2 and later
'
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
	AND @ProductVersion > '13'			-- Major version 2016 SP2
BEGIN
	SET @SQLcmd = @SQLcmd + N'	NumOfSockets				= SystemInfo.socket_count ,
	CoresPerSokes				= SystemInfo.cores_per_socket ,	
	HostNumOfCores				= SystemInfo.cpu_count ,

'
END	

IF @EngineEdition = 8					-- Azure SQL MI only
BEGIN
	SET @SQLcmd = @SQLcmd + N'	NumOfCores				= (SELECT cpu_count FROM sys.dm_os_nodes WITH (NOLOCK) WHERE node_state_desc <> N''ONLINE DAC'') ,
'
END	

IF @EngineEdition = 5					-- Azure SQL Database only
BEGIN
	SET @SQLcmd = @SQLcmd + N'	[CPU/DTU limit]				= (SELECT TOP (1) ISNULL(cpu_limit, dtu_limit) from sys.dm_db_resource_stats ORDER BY end_time DESC) ,
'
END	

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server 
	AND @ProductVersion > '13'			-- Major version 2016 SP2
BEGIN
	SET @SQLcmd = @SQLcmd + N'	NumOfNUMAs				= SystemInfo.numa_node_count , 
'
END

IF (
	@EngineEdition BETWEEN 1 AND 4		-- SQL Server 
	AND @ProductVersion >= '11'			-- Major version 2012 (11.x) and later
	)
	OR @EngineEdition IN (5, 8)			-- Azure SQL Database/MI
BEGIN
	SET @SQLcmd = @SQLcmd + N'	PhysicalMemory_GB			= CAST (ROUND (SystemInfo.physical_memory_kb / 1024.0 / 1024.0 , 0) AS INT) 	-- Applies to: SQL Server 2012 (11.x) and later
'
END
	
SET @SQLcmd = @SQLcmd + N'
FROM
	sys.dm_os_sys_info AS SystemInfo
OPTION (RECOMPILE);

'


SET @SQLcmd = @SQLcmd + N'
-- SQL Instance properties
SELECT
	SQLServerName				= SERVERPROPERTY (''ServerName'') ,
	InstanceVersion				=
									CASE	
										WHEN @EngineEdition BETWEEN 1 AND 4	THEN SUBSTRING(@@VERSION, 0, CHARINDEX('' ('', @@VERSION, 0))
										WHEN @EngineEdition = 5				THEN ''Azure SQL Database''			
										WHEN @EngineEdition = 8				THEN ''Azure SQL Managed Instance''
									END ,
'

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
	AND @ProductVersion >= '10.0'		-- Major version 2008 (10.x)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	ProductLevel				= SERVERPROPERTY (''ProductLevel'') , 
'
END

IF 
	(
		@EngineEdition BETWEEN 1 AND 4	-- SQL Server only (Not Azure SQL Database/MI)
		OR @EngineEdition = 8			-- Azure SQL MI only
	)
	AND @ProductVersion >= '11'			-- Major version 2012 (11.x)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	UpdateLevel			= SERVERPROPERTY (''ProductUpdateLevel'') ,										-- Applies to: SQL Server 2012 (11.x) through current version in updates beginning in late 2015 
'
END

SET @SQLcmd = @SQLcmd + N'	BuildNum			= SERVERPROPERTY (''ProductVersion'') ,
	ProductBuildType	= SERVERPROPERTY(''ProductBuildType''),
	ServerCollation			= SERVERPROPERTY(''Collation''),
'

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	InstanceEdition				= SERVERPROPERTY (''Edition'') ,
'
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	SQLNumOfCores = (SELECT COUNT(*)	FROM sys.dm_os_schedulers WHERE	[status] = N''VISIBLE ONLINE'' AND is_online = 1) ,

'
END

IF @EngineEdition = 5					-- Azure SQL Database only
BEGIN
	SET @SQLcmd = @SQLcmd + N'	[IsPartOfElasticPool]	= (SELECT ISNULL(elastic_pool_name, ''No'') FROM sys.database_service_objectives WHERE database_id = DB_ID()) , 
'
END
	
SET @SQLcmd = @SQLcmd + N'
	ServiceName					= @@SERVICENAME,
	InstallDate					= (SELECT TOP 1 create_date FROM sys.server_principals WITH (NOLOCK) WHERE name = N''NT AUTHORITY\SYSTEM'' OR name = N''NT AUTHORITY\NETWORK SERVICE'' ORDER BY create_date ASC),
	LastServiceRestartDateTime	= SQLInfo.sqlserver_start_time
FROM
	sys.dm_os_sys_info AS SQLInfo
OPTION (RECOMPILE);

'

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
BEGIN

	DECLARE @TFs TABLE (TraceFlag INT, [Status] TINYINT, [Global] TINYINT, [Session] TINYINT)

	INSERT INTO @TFs
	EXEC ('DBCC TRACESTATUS (-1) WITH NO_INFOMSGS;')

	IF EXISTS (SELECT 1 FROM @TFs)
	BEGIN
		SELECT @TraceFlags = LTRIM(STUFF((SELECT ', ' + CONCAT(TraceFlag, '-', CASE WHEN [Global] = 1 THEN 'Global' ELSE 'Session' END)
		FROM @TFs
		WHERE [Status] = 1
		FOR XML PATH('')), 1, 1, ''))
		OPTION (RECOMPILE);
	END

	SET @SQLcmd = @SQLcmd + N'SELECT	IsPartOfFCI					= SERVERPROPERTY (''IsClustered'') ,
 '
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
	AND @ProductVersion >= '11'			-- Major version 2012 (11.x)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	IsHadrEnabled				= SERVERPROPERTY (''IsHadrEnabled'') ,											-- Applies to: SQL Server 2012 (11.x) and later
	HadrManagerStatus				= SERVERPROPERTY(''HadrManagerStatus''),
'
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	TraceFlags	= @TraceFlags,
	IsIntegratedSecurityOnly	= SERVERPROPERTY(''IsIntegratedSecurityOnly''),
	FilestreamConfiguredLevel	= SERVERPROPERTY(''FilestreamConfiguredLevel''),
	IsXTPSupported	= SERVERPROPERTY(''IsXTPSupported''),
	IsFullTextInstalled	= SERVERPROPERTY(''IsFullTextInstalled''),
	IsPolybaseInstalled	= SERVERPROPERTY(''IsPolybaseInstalled''),			
	IsRServicesInstalled	= SERVERPROPERTY(''IsAdvancedAnalyticsInstalled''),
	[Build CLR Version]	= SERVERPROPERTY(''BuildClrVersion'') '
END

EXECUTE sys.sp_executesql
					@SQLcmd, 
					N'@EngineEdition	INT,
					@TraceFlags	NVARCHAR(1000)', 
					@EngineEdition,
					@TraceFlags;

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
BEGIN

	DECLARE
		@ErrorLog2Read		INT = 0,
		@ErrorLogsNum		INT;

	DECLARE @ErrorLogs TABLE (ArchiveNumber INT, LogDate DATETIME, LogSize BIGINT);

	INSERT INTO @ErrorLogs
	EXEC sp_enumerrorlogs;

	SELECT @ErrorLogsNum = @@ROWCOUNT;

	DECLARE @socketCheck TABLE (LogDate NVARCHAR(32), ProcessInfo NVARCHAR(32), [Text]	NVARCHAR(4000))

	WHILE @ErrorLog2Read < @ErrorLogsNum+1
	BEGIN
		INSERT INTO @socketCheck
		EXEC sys.sp_readerrorlog @ErrorLog2Read, 1, N'detected', N'socket';

		IF EXISTS (SELECT 1 FROM @socketCheck)
		BEGIN
			SELECT
				REPLACE([Text], 'This is an informational message; no user action is required.', '')	AS [SQL Server Licensing Information]
			FROM
				@socketCheck;

			BREAK;
		END
		ELSE
		BEGIN
			PRINT CONCAT('SQL Server Error Log file ', @ErrorLog2Read, 'has no licensing information! Checking next file.');
			SET @ErrorLog2Read = @ErrorLog2Read + 1
		END
	END

END

SET @SQLcmd = N''

DECLARE db_cursor CURSOR FAST_FORWARD FOR

SELECT
	[name]
FROM
	#sys_databases
WHERE
	state_desc = 'ONLINE'
ORDER BY
	database_id ASC;

OPEN db_cursor  
FETCH NEXT FROM db_cursor INTO @Dbname  

WHILE @@FETCH_STATUS = 0  
BEGIN

SET @SQLcmd = CONCAT(N'USE [', @Dbname, N'];

DECLARE @tbl TABLE ([Set Option] NVARCHAR(128), [Value] NVARCHAR(128));

INSERT INTO @tbl ([Set Option], [Value])
EXEC (''DBCC useroptions'')

INSERT INTO #OserOptionsResults
SELECT 
	DB_NAME(), [net_transport], [protocol_type],
	[textsize], [language], [dateformat], [datefirst], [lock_timeout], 
	[quoted_identifier], [arithabort], [ansi_null_dflt_on], [ansi_warnings], 
	[ansi_padding], [ansi_nulls], [concat_null_yields_null], [isolation level]
FROM (
    SELECT [Set Option], [Value]
    FROM @tbl
) src
PIVOT (
    MAX([Value]) 
    FOR [Set Option] IN ([textsize], [language], [dateformat], [datefirst], [lock_timeout], [quoted_identifier], [arithabort], [ansi_null_dflt_on], [ansi_warnings], [ansi_padding], [ansi_nulls], [concat_null_yields_null], [isolation level])
) pvt
OUTER APPLY
	(
		SELECT TOP (1)
			[net_transport],
			[protocol_type]
		FROM
			sys.dm_exec_connections
		WHERE
			[session_id] = @@SPID
	) as c; ')

EXEC sp_executesql @SQLcmd;

	FETCH NEXT FROM db_cursor INTO @Dbname 
END

CLOSE db_cursor  
DEALLOCATE db_cursor

SELECT 
	[Database Name],
	[Isolation Level],	
	[Quoted Identifier],
	[Arithabort],
	[Ansi NULL dflt on],
	[Ansi Warnings],
	[Ansi Padding],
	[Ansi NULLs],
	[Concat NULL Yields NULL],
	[Net Transport],
	[Protocol Type],
	[Text Size],
	[Language],
	[Date Format],
	[Date First],
	[Lock Timeout]
FROM
	#OserOptionsResults;


DECLARE @WaitsSQL NVARCHAR(MAX) = N'

-- Last updated October 1, 2021
WITH [Waits] AS
    (SELECT
        [wait_type],
        [wait_time_ms] / 1000.0 AS [WaitS],
        ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
        [signal_wait_time_ms] / 1000.0 AS [SignalS],
        [waiting_tasks_count] AS [WaitCount],
        100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
        -- These wait types are almost 100% never a problem and so they are
        -- filtered out to avoid them skewing the results. Click on the URL
        -- for more information.
        N''BROKER_EVENTHANDLER'', -- https://www.sqlskills.com/help/waits/BROKER_EVENTHANDLER
        N''BROKER_RECEIVE_WAITFOR'', -- https://www.sqlskills.com/help/waits/BROKER_RECEIVE_WAITFOR
        N''BROKER_TASK_STOP'', -- https://www.sqlskills.com/help/waits/BROKER_TASK_STOP
        N''BROKER_TO_FLUSH'', -- https://www.sqlskills.com/help/waits/BROKER_TO_FLUSH
        N''BROKER_TRANSMITTER'', -- https://www.sqlskills.com/help/waits/BROKER_TRANSMITTER
        N''CHECKPOINT_QUEUE'', -- https://www.sqlskills.com/help/waits/CHECKPOINT_QUEUE
        N''CHKPT'', -- https://www.sqlskills.com/help/waits/CHKPT
        N''CLR_AUTO_EVENT'', -- https://www.sqlskills.com/help/waits/CLR_AUTO_EVENT
        N''CLR_MANUAL_EVENT'', -- https://www.sqlskills.com/help/waits/CLR_MANUAL_EVENT
        N''CLR_SEMAPHORE'', -- https://www.sqlskills.com/help/waits/CLR_SEMAPHORE
 
        -- Maybe comment this out if you have parallelism issues
        N''CXCONSUMER'', -- https://www.sqlskills.com/help/waits/CXCONSUMER
 
        -- Maybe comment these four out if you have mirroring issues
        N''DBMIRROR_DBM_EVENT'', -- https://www.sqlskills.com/help/waits/DBMIRROR_DBM_EVENT
        N''DBMIRROR_EVENTS_QUEUE'', -- https://www.sqlskills.com/help/waits/DBMIRROR_EVENTS_QUEUE
        N''DBMIRROR_WORKER_QUEUE'', -- https://www.sqlskills.com/help/waits/DBMIRROR_WORKER_QUEUE
        N''DBMIRRORING_CMD'', -- https://www.sqlskills.com/help/waits/DBMIRRORING_CMD
        N''DIRTY_PAGE_POLL'', -- https://www.sqlskills.com/help/waits/DIRTY_PAGE_POLL
        N''DISPATCHER_QUEUE_SEMAPHORE'', -- https://www.sqlskills.com/help/waits/DISPATCHER_QUEUE_SEMAPHORE
        N''EXECSYNC'', -- https://www.sqlskills.com/help/waits/EXECSYNC
        N''FSAGENT'', -- https://www.sqlskills.com/help/waits/FSAGENT
        N''FT_IFTS_SCHEDULER_IDLE_WAIT'', -- https://www.sqlskills.com/help/waits/FT_IFTS_SCHEDULER_IDLE_WAIT
        N''FT_IFTSHC_MUTEX'', -- https://www.sqlskills.com/help/waits/FT_IFTSHC_MUTEX
  
       -- Maybe comment these six out if you have AG issues
        N''HADR_CLUSAPI_CALL'', -- https://www.sqlskills.com/help/waits/HADR_CLUSAPI_CALL
        N''HADR_FILESTREAM_IOMGR_IOCOMPLETION'', -- https://www.sqlskills.com/help/waits/HADR_FILESTREAM_IOMGR_IOCOMPLETION
        N''HADR_LOGCAPTURE_WAIT'', -- https://www.sqlskills.com/help/waits/HADR_LOGCAPTURE_WAIT
        N''HADR_NOTIFICATION_DEQUEUE'', -- https://www.sqlskills.com/help/waits/HADR_NOTIFICATION_DEQUEUE
        N''HADR_TIMER_TASK'', -- https://www.sqlskills.com/help/waits/HADR_TIMER_TASK
        N''HADR_WORK_QUEUE'', -- https://www.sqlskills.com/help/waits/HADR_WORK_QUEUE
 
        N''KSOURCE_WAKEUP'', -- https://www.sqlskills.com/help/waits/KSOURCE_WAKEUP
        N''LAZYWRITER_SLEEP'', -- https://www.sqlskills.com/help/waits/LAZYWRITER_SLEEP
        N''LOGMGR_QUEUE'', -- https://www.sqlskills.com/help/waits/LOGMGR_QUEUE
        N''MEMORY_ALLOCATION_EXT'', -- https://www.sqlskills.com/help/waits/MEMORY_ALLOCATION_EXT
        N''ONDEMAND_TASK_QUEUE'', -- https://www.sqlskills.com/help/waits/ONDEMAND_TASK_QUEUE
        N''PARALLEL_REDO_DRAIN_WORKER'', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_DRAIN_WORKER
        N''PARALLEL_REDO_LOG_CACHE'', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_LOG_CACHE
        N''PARALLEL_REDO_TRAN_LIST'', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_TRAN_LIST
        N''PARALLEL_REDO_WORKER_SYNC'', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_SYNC
        N''PARALLEL_REDO_WORKER_WAIT_WORK'', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_WAIT_WORK
        N''PREEMPTIVE_OS_FLUSHFILEBUFFERS'', -- https://www.sqlskills.com/help/waits/PREEMPTIVE_OS_FLUSHFILEBUFFERS
        N''PREEMPTIVE_XE_GETTARGETSTATE'', -- https://www.sqlskills.com/help/waits/PREEMPTIVE_XE_GETTARGETSTATE
        N''PVS_PREALLOCATE'', -- https://www.sqlskills.com/help/waits/PVS_PREALLOCATE
        N''PWAIT_ALL_COMPONENTS_INITIALIZED'', -- https://www.sqlskills.com/help/waits/PWAIT_ALL_COMPONENTS_INITIALIZED
        N''PWAIT_DIRECTLOGCONSUMER_GETNEXT'', -- https://www.sqlskills.com/help/waits/PWAIT_DIRECTLOGCONSUMER_GETNEXT
        N''PWAIT_EXTENSIBILITY_CLEANUP_TASK'', -- https://www.sqlskills.com/help/waits/PWAIT_EXTENSIBILITY_CLEANUP_TASK
        N''QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'', -- https://www.sqlskills.com/help/waits/QDS_PERSIST_TASK_MAIN_LOOP_SLEEP
        N''QDS_ASYNC_QUEUE'', -- https://www.sqlskills.com/help/waits/QDS_ASYNC_QUEUE
        N''QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'',
            -- https://www.sqlskills.com/help/waits/QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP
        N''QDS_SHUTDOWN_QUEUE'', -- https://www.sqlskills.com/help/waits/QDS_SHUTDOWN_QUEUE
        N''REDO_THREAD_PENDING_WORK'', -- https://www.sqlskills.com/help/waits/REDO_THREAD_PENDING_WORK
        N''REQUEST_FOR_DEADLOCK_SEARCH'', -- https://www.sqlskills.com/help/waits/REQUEST_FOR_DEADLOCK_SEARCH
        N''RESOURCE_QUEUE'', -- https://www.sqlskills.com/help/waits/RESOURCE_QUEUE
        N''SERVER_IDLE_CHECK'', -- https://www.sqlskills.com/help/waits/SERVER_IDLE_CHECK
        N''SLEEP_BPOOL_FLUSH'', -- https://www.sqlskills.com/help/waits/SLEEP_BPOOL_FLUSH
        N''SLEEP_DBSTARTUP'', -- https://www.sqlskills.com/help/waits/SLEEP_DBSTARTUP
        N''SLEEP_DCOMSTARTUP'', -- https://www.sqlskills.com/help/waits/SLEEP_DCOMSTARTUP
        N''SLEEP_MASTERDBREADY'', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERDBREADY
        N''SLEEP_MASTERMDREADY'', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERMDREADY
        N''SLEEP_MASTERUPGRADED'', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERUPGRADED
        N''SLEEP_MSDBSTARTUP'', -- https://www.sqlskills.com/help/waits/SLEEP_MSDBSTARTUP
        N''SLEEP_SYSTEMTASK'', -- https://www.sqlskills.com/help/waits/SLEEP_SYSTEMTASK
        N''SLEEP_TASK'', -- https://www.sqlskills.com/help/waits/SLEEP_TASK
        N''SLEEP_TEMPDBSTARTUP'', -- https://www.sqlskills.com/help/waits/SLEEP_TEMPDBSTARTUP
        N''SNI_HTTP_ACCEPT'', -- https://www.sqlskills.com/help/waits/SNI_HTTP_ACCEPT
        N''SOS_WORK_DISPATCHER'', -- https://www.sqlskills.com/help/waits/SOS_WORK_DISPATCHER
        N''SP_SERVER_DIAGNOSTICS_SLEEP'', -- https://www.sqlskills.com/help/waits/SP_SERVER_DIAGNOSTICS_SLEEP
        N''SQLTRACE_BUFFER_FLUSH'', -- https://www.sqlskills.com/help/waits/SQLTRACE_BUFFER_FLUSH
        N''SQLTRACE_INCREMENTAL_FLUSH_SLEEP'', -- https://www.sqlskills.com/help/waits/SQLTRACE_INCREMENTAL_FLUSH_SLEEP
        N''SQLTRACE_WAIT_ENTRIES'', -- https://www.sqlskills.com/help/waits/SQLTRACE_WAIT_ENTRIES
        N''VDI_CLIENT_OTHER'', -- https://www.sqlskills.com/help/waits/VDI_CLIENT_OTHER
        N''WAIT_FOR_RESULTS'', -- https://www.sqlskills.com/help/waits/WAIT_FOR_RESULTS
        N''WAITFOR'', -- https://www.sqlskills.com/help/waits/WAITFOR
        N''WAITFOR_TASKSHUTDOWN'', -- https://www.sqlskills.com/help/waits/WAITFOR_TASKSHUTDOWN
        N''WAIT_XTP_RECOVERY'', -- https://www.sqlskills.com/help/waits/WAIT_XTP_RECOVERY
        N''WAIT_XTP_HOST_WAIT'', -- https://www.sqlskills.com/help/waits/WAIT_XTP_HOST_WAIT
        N''WAIT_XTP_OFFLINE_CKPT_NEW_LOG'', -- https://www.sqlskills.com/help/waits/WAIT_XTP_OFFLINE_CKPT_NEW_LOG
        N''WAIT_XTP_CKPT_CLOSE'', -- https://www.sqlskills.com/help/waits/WAIT_XTP_CKPT_CLOSE
        N''XE_DISPATCHER_JOIN'', -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_JOIN
        N''XE_DISPATCHER_WAIT'', -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_WAIT
        N''XE_TIMER_EVENT'' -- https://www.sqlskills.com/help/waits/XE_TIMER_EVENT
        )
    AND [waiting_tasks_count] > 0
    )
SELECT
    MAX ([W1].[wait_type]) AS [WaitType],
    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,2)) AS [Wait_S],
    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,2)) AS [Resource_S],
    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,2)) AS [Signal_S],
    MAX ([W1].[WaitCount]) AS [WaitCount],
    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgWait_S],
    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgRes_S],
    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgSig_S]
FROM [Waits] AS [W1]
INNER JOIN [Waits] AS [W2] ON [W2].[RowNum] <= [W1].[RowNum]
GROUP BY [W1].[RowNum]
HAVING SUM ([W2].[Percentage]) - MAX( [W1].[Percentage] ) < 95 -- percentage threshold
OPTION (RECOMPILE);

'
IF CAST (SERVERPROPERTY('EngineEdition') AS NVARCHAR(128)) = 5					-- Azure SQL Database only
BEGIN
	SET @WaitsSQL = REPLACE(@WaitsSQL, N'dm_os_wait_stats', N'dm_db_wait_stats')
END

INSERT INTO #WaitsStats
EXEC (@WaitsSQL);


--WITH
--	XMLNAMESPACES (DEFAULT N'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
--SELECT
--	QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Clustered Index Scan"][1])')											AS ClusteredIndexScan,
--	QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Index Scan"][1])')													AS IndexScan,
--	QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Table Scan"][1])')													AS TableScan,
--	QueryPlans.query_plan.query('.').exist('data(//IndexScan[@Lookup="1"][1])')																AS [Lookup],
--	QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="RID Lookup"][1])')													AS RIDLookup,
--	QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Table Spool"][1])')													AS TableSpool,
--	QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Index Spool"][1])')													AS IndexSpool,
--	QueryPlans.query_plan.query('.').exist('data(//MissingIndexes[1])')																		AS MissingIndexes,
--	QueryPlans.query_plan.query('.').exist('data(//RelOp[(@PhysicalOp[.="Sort"])])')														AS SortOperator,
--	QueryPlans.query_plan.query('.').exist('data(//PlanAffectingConvert[1])')																AS ImplicitConversion,
--	QueryPlans.query_plan.query('.').exist('data(//RelOp/Filter/Predicate/ScalarOperator/Compare/ScalarOperator/UserDefinedFunction[1])')	AS UserFunctionFilter,
--	QueryPlans.query_plan.query('.').exist('data(//RelOp[(@PhysicalOp[contains(., "Remote")])])')											AS RemoteQuery,
--	QueryPlans.query_plan.query('.').exist('data(//StmtSimple/@StatementOptmEarlyAbortReason[.="MemoryLimitExceeded"])')					AS CompileMemoryLimitExceeded,
--	--QueryPlans.query_plan.exist('//Object[substring(@Table, 1, 2) = "[@"]')							AS TableVariable,
--	CASE
--		WHEN
--			(	-- Table Variable
--				QueryPlans.query_plan.exist('//Object[substring(@Table, 1, 2) = "[@"]') = 1
--				AND
--					(
--					-- include all specific column references (seek predicates) 
--					QueryPlans.query_plan.exist('//Object[substring(@Table,1,2) = "[@"]/../SeekPredicates/SeekPredicateNew/SeekKeys/Prefix/RangeColumns/ColumnReference') = 1
--					--include all joins with table varibles by checking that no specific columns are referenced in the execution plan
--					OR QueryPlans.query_plan.exist('//ColumnReference[substring(@Table,1,1) = "@"]') = 1
--					)
--			)		THEN 1
--			ELSE 0
--	END																																		AS TableVariable,	
--	CASE
--		WHEN EXISTS
--					(
--						SELECT TOP 1 1
--						FROM 
--							QueryPlans.query_plan.nodes('//Warnings/*') AS W(node_xml)
--					)	THEN 1
--		ELSE 0
--	END																																		AS HasWarning,
--	CASE
--		WHEN EXISTS
--					(
--						SELECT TOP 1 1
--						FROM 
--							QueryPlans.query_plan.nodes('//RelOp/IndexScan/Predicate/ScalarOperator/Compare/ScalarOperator') AS ca(x)
--						WHERE
--							(
--								ca.x.query('.').exist('//ScalarOperator/Intrinsic/@FunctionName') = 1
--								OR ca.x.query('.').exist('//ScalarOperator/IF') = 1
--							)
--					)	THEN 1
--		ELSE 0
--	END																																		AS NonSargeableScalarFunction,
--	CASE
--		WHEN EXISTS
--					(
						
--						SELECT TOP 1 1
--						FROM
--							QueryPlans.query_plan.nodes('//RelOp//ScalarOperator') AS ca(x)
--						WHERE
--							QueryPlans.query_plan.query('.').exist('data(//RelOp[contains(@LogicalOp, "Join")])') = 1
--							AND ca.x.query('.').exist('//ScalarOperator[contains(@ScalarString, "Expr")]') = 1
--					)	THEN 1
--		ELSE 0
--	END																																		AS NonSargeableExpressionWithJoin,
--	CASE
--		WHEN EXISTS
--					(
						
--						SELECT TOP 1 1
--						FROM
--							QueryPlans.query_plan.nodes('//RelOp/IndexScan/Predicate/ScalarOperator') AS ca(x)
--							CROSS APPLY  ca.x.nodes('//Const') AS co(x)
--						WHERE
--							ca.x.query('.').exist('//ScalarOperator/Intrinsic/@FunctionName[.="like"]') = 1
--							AND
--								(
--									(
--										co.x.value('substring(@ConstValue, 1, 1)', 'VARCHAR(100)') <> 'N'
--										AND co.x.value('substring(@ConstValue, 2, 1)', 'VARCHAR(100)') = '%'
--									)
--								OR
--									(
--										co.x.value('substring(@ConstValue, 1, 1)', 'VARCHAR(100)') = 'N'
--										AND co.x.value('substring(@ConstValue, 3, 1)', 'VARCHAR(100)') = '%'
--									)
--								)
--					)	THEN 1
--		ELSE 0
--	END																																		AS NonSargeableLIKE
--INTO
--	#Plans2Check
--FROM
--	sys.dm_exec_cached_plans AS CachedPlans
--	CROSS APPLY sys.dm_exec_query_plan (CachedPlans.[plan_handle]) AS QueryPlans
--WHERE
--	QueryPlans.query_plan IS NOT NULL
--	AND CachedPlans.cacheobjtype IN ('Compiled Plan', 'Compiled Plan Stub')
--	AND CachedPlans.objtype IN ('Adhoc', 'Prepared', 'Proc')
--	AND QueryPlans.query_plan.query('.').exist('data(//Object[@Schema!="[sys]"][1])') = 1
--	AND
--		(
--			QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Clustered Index Scan"][1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Index Scan"][1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Table Scan"][1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//IndexScan[@Lookup="1"][1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="RID Lookup"][1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Table Spool"][1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//RelOp[@PhysicalOp="Index Spool"][1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//MissingIndexes[1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//RelOp[(@PhysicalOp[.="Sort"])])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//PlanAffectingConvert[1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//RelOp/Filter/Predicate/ScalarOperator/Compare/ScalarOperator/UserDefinedFunction[1])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//RelOp[(@PhysicalOp[contains(., "Remote")])])') = 1
--			OR QueryPlans.query_plan.query('.').exist('data(//StmtSimple/@StatementOptmEarlyAbortReason[.="MemoryLimitExceeded"])') = 1
--			OR 
--				(	-- Table Variable
--					QueryPlans.query_plan.exist('//Object[substring(@Table, 1, 2) = "[@"]') = 1
--					AND
--						(
--						-- include all specific column references (seek predicates) 
--						QueryPlans.query_plan.exist('//Object[substring(@Table,1,2) = "[@"]/../SeekPredicates/SeekPredicateNew/SeekKeys/Prefix/RangeColumns/ColumnReference') = 1
--						--include all joins with table varibles by checking that no specific columns are referenced in the execution plan
--						OR QueryPlans.query_plan.exist('//ColumnReference[substring(@Table,1,1) = "@"]') = 1
--						)
--				)
--			OR EXISTS
--					(
--						SELECT TOP 1 1
--						FROM 
--							QueryPlans.query_plan.nodes('//Warnings/*') AS W(node_xml)
--					)
--			OR EXISTS
--					(
						
--						SELECT TOP 1 1
--						FROM 
--							QueryPlans.query_plan.nodes('//RelOp/IndexScan/Predicate/ScalarOperator/Compare/ScalarOperator') AS ca(x)
--						WHERE
--							(
--								ca.x.query('.').exist('//ScalarOperator/Intrinsic/@FunctionName') = 1
--								OR ca.x.query('.').exist('//ScalarOperator/IF') = 1
--							)
--					)
--			OR EXISTS
--					(
						
--						SELECT TOP 1 1
--						FROM
--							QueryPlans.query_plan.nodes('//RelOp//ScalarOperator') AS ca(x)
--						WHERE
--							QueryPlans.query_plan.query('.').exist('data(//RelOp[contains(@LogicalOp, "Join")])') = 1
--							AND ca.x.query('.').exist('//ScalarOperator[contains(@ScalarString, "Expr")]') = 1
--					)
--			OR EXISTS
--					(
						
--						SELECT TOP 1 1
--						FROM
--							QueryPlans.query_plan.nodes('//RelOp/IndexScan/Predicate/ScalarOperator') AS ca(x)
--							CROSS APPLY  ca.x.nodes('//Const') AS co(x)
--						WHERE
--							ca.x.query('.').exist('//ScalarOperator/Intrinsic/@FunctionName[.="like"]') = 1
--							AND
--								(
--									(
--										co.x.value('substring(@ConstValue, 1, 1)', 'VARCHAR(100)') <> 'N'
--										AND co.x.value('substring(@ConstValue, 2, 1)', 'VARCHAR(100)') = '%'
--									)
--								OR
--									(
--										co.x.value('substring(@ConstValue, 1, 1)', 'VARCHAR(100)') = 'N'
--										AND co.x.value('substring(@ConstValue, 3, 1)', 'VARCHAR(100)') = '%'
--									)
--								)
--					)
--		)
--OPTION (RECOMPILE);

WITH XMLNAMESPACES (DEFAULT N'http://schemas.microsoft.com/sqlserver/2004/07/showplan'),
PlansCTE AS
(
	SELECT
		QueryPlans.query_plan.exist('//RelOp[@PhysicalOp="Clustered Index Scan"]')							AS ClusteredIndexScan,
		QueryPlans.query_plan.exist('//RelOp[@PhysicalOp="Index Scan"]')									AS IndexScan,
		QueryPlans.query_plan.exist('//RelOp[@PhysicalOp="Table Scan"]')									AS TableScan,
		QueryPlans.query_plan.exist('//IndexScan[@Lookup="1"]')												AS [Lookup],
		QueryPlans.query_plan.exist('//RelOp[@PhysicalOp="RID Lookup"]')									AS RIDLookup,
		QueryPlans.query_plan.exist('//RelOp[@PhysicalOp="Table Spool"]')									AS TableSpool,
		QueryPlans.query_plan.exist('//RelOp[@PhysicalOp="Index Spool"]')									AS IndexSpool,
		QueryPlans.query_plan.exist('//MissingIndexes')														AS MissingIndexes,
		QueryPlans.query_plan.exist('//RelOp[@PhysicalOp="Sort"]')											AS SortOperator,
		QueryPlans.query_plan.exist('//PlanAffectingConvert')												AS ImplicitConversion,
		QueryPlans.query_plan.exist('//UserDefinedFunction')												AS UserFunctionFilter,
		QueryPlans.query_plan.exist('//RelOp[contains(@PhysicalOp, "Remote")]')								AS RemoteQuery,
		QueryPlans.query_plan.exist('//StmtSimple[@StatementOptmEarlyAbortReason="MemoryLimitExceeded"]')	AS CompileMemoryLimitExceeded,
		CASE
			WHEN 
				(	-- table variable
					QueryPlans.query_plan.exist('//Object[contains(@Table, "@")]') = 1 
					AND
						(
						-- include all specific column references (seek predicates) 
						QueryPlans.query_plan.exist('//Object[substring(@Table,1,2) = "[@"]/../SeekPredicates/SeekPredicateNew/SeekKeys/Prefix/RangeColumns/ColumnReference') = 1
						--include all joins with table varibles by checking that no specific columns are referenced in the execution plan
						OR QueryPlans.query_plan.exist('//ColumnReference[substring(@Table,1,1) = "@"]') = 1
						)
				)
				THEN 1 
			ELSE 0
		END																									AS TableVariable,
		CASE
			WHEN QueryPlans.query_plan.exist('//Warnings/*') = 1 THEN 1 
			ELSE 0
		END																									AS HasWarning,
		CASE
			WHEN
				(
					SELECT TOP 1 1
					FROM 
						QueryPlans.query_plan.nodes('//RelOp/IndexScan/Predicate/ScalarOperator/Compare/ScalarOperator') AS ca(x)
					WHERE
						(
							ca.x.query('.').exist('//ScalarOperator/Intrinsic/@FunctionName') = 1
							OR ca.x.query('.').exist('//ScalarOperator/IF') = 1
						)
				) = 1	
				THEN 1
			ELSE 0
		END																									AS NonSargeableScalarFunction,
		CASE
			WHEN
				(
						
					SELECT TOP 1 1
					FROM
						QueryPlans.query_plan.nodes('//RelOp//ScalarOperator') AS ca(x)
					WHERE
						QueryPlans.query_plan.query('.').exist('data(//RelOp[contains(@LogicalOp, "Join")])') = 1
						AND ca.x.query('.').exist('//ScalarOperator[contains(@ScalarString, "Expr")]') = 1
				) = 1
				THEN 1
			ELSE 0
		END																									AS NonSargeableExpressionWithJoin,
		CASE
			WHEN
				(
						
					SELECT TOP 1 1
					FROM
						QueryPlans.query_plan.nodes('//RelOp/IndexScan/Predicate/ScalarOperator') AS ca(x)
						CROSS APPLY  ca.x.nodes('//Const') AS co(x)
					WHERE
						ca.x.query('.').exist('//ScalarOperator/Intrinsic/@FunctionName[.="like"]') = 1
						AND
							(
								(
									co.x.value('substring(@ConstValue, 1, 1)', 'VARCHAR(100)') <> 'N'
									AND co.x.value('substring(@ConstValue, 2, 1)', 'VARCHAR(100)') = '%'
								)
							OR
								(
									co.x.value('substring(@ConstValue, 1, 1)', 'VARCHAR(100)') = 'N'
									AND co.x.value('substring(@ConstValue, 3, 1)', 'VARCHAR(100)') = '%'
								)
							)
				) = 1
				THEN 1
			ELSE 0
		END																									AS NonSargeableLIKE
	FROM
		sys.dm_exec_cached_plans AS CachedPlans
		CROSS APPLY sys.dm_exec_query_plan(CachedPlans.plan_handle) AS QueryPlans
	WHERE
		QueryPlans.query_plan IS NOT NULL
		AND CachedPlans.cacheobjtype IN ('Compiled Plan', 'Compiled Plan Stub')
		AND CachedPlans.objtype IN ('Adhoc', 'Prepared', 'Proc')
		AND QueryPlans.query_plan.exist('//Object[@Schema!="[sys]"]') = 1
)
SELECT *
INTO
	#Plans2Check
FROM
	PlansCTE
WHERE
	ClusteredIndexScan = 1
	OR IndexScan = 1
	OR TableScan = 1
	OR [Lookup] = 1
	OR RIDLookup = 1
	OR TableSpool = 1
	OR IndexSpool = 1
	OR MissingIndexes = 1
	OR SortOperator = 1
	OR ImplicitConversion = 1
	OR UserFunctionFilter = 1
	OR RemoteQuery = 1
	OR CompileMemoryLimitExceeded = 1
	OR TableVariable = 1
	OR HasWarning = 1
	OR NonSargeableScalarFunction = 1
	OR NonSargeableExpressionWithJoin = 1
	OR NonSargeableLIKE = 1
OPTION (RECOMPILE)



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
	@ProductVersion					AS DECIMAL(3, 1);

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
	AdditionalInfo			XML				NULL
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
	sys.databases;


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

--SELECT
--	ServerName					= SERVERPROPERTY ('ServerName') ,
--	InstanceVersion				=
--		CASE
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '8%'	THEN N'2000'
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '9%'	THEN N'2005'
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '10.0%'	THEN N'2008'
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '10.5%'	THEN N'2008 R2'
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '11%'	THEN N'2012'
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '12%'	THEN N'2014'
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '13%'	THEN N'2016'
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '14%'	THEN N'2017'
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '15%'	THEN N'2019'
--			WHEN CAST (SERVERPROPERTY ('ProductVersion') AS NVARCHAR(128)) LIKE '16%'	THEN N'2022'
--		END ,
--	ProductLevel				= SERVERPROPERTY ('ProductLevel') ,
--	ProductUpdateLevel			= SERVERPROPERTY ('ProductUpdateLevel') ,										-- Applies to: SQL Server 2012 (11.x) through current version in updates beginning in late 2015
--	ProductBuildNumber			= SERVERPROPERTY ('ProductVersion') ,
--	InstanceEdition				= SERVERPROPERTY ('Edition') ,
--	IsPartOfFCI					= SERVERPROPERTY ('IsClustered') ,
--	IsEnabledForAG				= SERVERPROPERTY ('IsHadrEnabled') ,											-- Applies to: SQL Server 2012 (11.x) and later
--	HostPlatform				= HostInfo.host_distribution ,													-- Applies to: SQL Server 2017 (14.x) and later
--	OperatingSystemArchitecture	= @OperatingSystemArchitecture ,
--	SQLServerArchitecture		= @SQLServerArchitecture ,
--	VirtualizationType			= SystemInfo.virtual_machine_type_desc ,										-- Applies to: SQL Server 2008 R2 and later
--	NumberOfCores				= SystemInfo.cpu_count ,
--	PhysicalMemory_GB			= CAST (ROUND (SystemInfo.physical_memory_kb / 1024.0 / 1024.0 , 0) AS INT) ,	-- Applies to: SQL Server 2012 (11.x) and later
--	LastServiceRestartDateTime	= SystemInfo.sqlserver_start_time
--FROM
--	sys.dm_os_host_info AS HostInfo
--CROSS JOIN
--	sys.dm_os_sys_info AS SystemInfo;


SET @SQLcmd = N'
SELECT
	ServerName					= SERVERPROPERTY (''ServerName'') ,
	InstanceVersion				=
									CASE	
										WHEN @EngineEdition BETWEEN 1 AND 4	THEN REPLACE(SUBSTRING(@@VERSION, 0, CHARINDEX('' ('', @@VERSION, 0)), ''Microsoft SQL Server '', '''')
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
	SET @SQLcmd = @SQLcmd + N'	ProductUpdateLevel			= SERVERPROPERTY (''ProductUpdateLevel'') ,										-- Applies to: SQL Server 2012 (11.x) through current version in updates beginning in late 2015 
'
END

SET @SQLcmd = @SQLcmd + N'	ProductBuildNumber			= SERVERPROPERTY (''ProductVersion'') ,
'

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	InstanceEdition				= SERVERPROPERTY (''Edition'') ,
	IsPartOfFCI					= SERVERPROPERTY (''IsClustered'') ,
'
END


IF @EngineEdition = 5					-- Azure SQL Database only
BEGIN
	SET @SQLcmd = @SQLcmd + N'	[IsPartOfElasticPool]	= (SELECT ISNULL(elastic_pool_name, ''No'') FROM sys.database_service_objectives WHERE database_id = DB_ID()) , 
'
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
	AND @ProductVersion >= '11'			-- Major version 2012 (11.x)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	IsEnabledForAG				= SERVERPROPERTY (''IsHadrEnabled'') ,											-- Applies to: SQL Server 2012 (11.x) and later
'
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
	AND @ProductVersion >= '14'			-- Major version 2017 (14.x)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	HostPlatform				= (SELECT host_distribution FROM sys.dm_os_host_info) ,													-- Applies to: SQL Server 2017 (14.x) and later
'
END

IF @EngineEdition BETWEEN 1 AND 4		-- SQL Server only (Not Azure SQL Database/MI)
BEGIN
	SET @SQLcmd = @SQLcmd + N'	OperatingSystemArchitecture	= ''' + @OperatingSystemArchitecture + N''' ,
	SQLServerArchitecture		= ''' + @SQLServerArchitecture + N''' ,
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
BEGIN
	SET @SQLcmd = @SQLcmd + N'	NumberOfCores				= SystemInfo.cpu_count ,
'
END
	
IF @EngineEdition = 8					-- Azure SQL MI only
BEGIN
	SET @SQLcmd = @SQLcmd + N'	NumberOfCores				= (SELECT cpu_count FROM sys.dm_os_nodes WITH (NOLOCK) WHERE node_state_desc <> N''ONLINE DAC'') ,
'
END	

IF @EngineEdition = 5					-- Azure SQL Database only
BEGIN
	SET @SQLcmd = @SQLcmd + N'	[CPU/DTU limit]				= (SELECT TOP (1) ISNULL(cpu_limit, dtu_limit) from sys.dm_db_resource_stats ORDER BY end_time DESC) ,
'
END	

IF (
	@EngineEdition BETWEEN 1 AND 4		-- SQL Server 
	AND @ProductVersion >= '11'			-- Major version 2012 (11.x) and later
	)
	OR @EngineEdition IN (5, 8)		-- Azure SQL Database/MI
BEGIN
	SET @SQLcmd = @SQLcmd + N'	PhysicalMemory_GB			= CAST (ROUND (SystemInfo.physical_memory_kb / 1024.0 / 1024.0 , 0) AS INT) ,	-- Applies to: SQL Server 2012 (11.x) and later
'
END
	
SET @SQLcmd = @SQLcmd + N'
	LastServiceRestartDateTime	= SystemInfo.sqlserver_start_time
FROM
	sys.dm_os_sys_info AS SystemInfo;

'
EXECUTE sys.sp_executesql
					@SQLcmd, 
					N'@EngineEdition INT', 
					@EngineEdition;

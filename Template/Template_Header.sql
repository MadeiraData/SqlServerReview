USE
	[master];
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


DECLARE
	@OperatingSystemArchitecture	AS NVARCHAR(4) ,
	@SQLServerArchitecture			AS NVARCHAR(4);

DROP TABLE IF EXISTS
	#Checks;

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

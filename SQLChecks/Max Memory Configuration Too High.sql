
		DECLARE
			@OperatingSystemArchitecture	AS NVARCHAR(4) ,
			@SQLServerArchitecture			AS NVARCHAR(4) ,
			@CurrentMaxMemorySetting_MB		AS INT ,
			@MaxWorkerThreads				AS INT ,
			@TotalPhysicalMemory_MB			AS INT ,
			@RecommendedMaxMemorySetting_MB	AS INT;

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
			CheckId					= {CheckId} ,
			Title					= N'{CheckTitle}' ,
			RequiresAttention		=
				CASE
					WHEN @CurrentMaxMemorySetting_MB > @RecommendedMaxMemorySetting_MB
						THEN 1
					ELSE
						0
				END ,
			CurrentStateImpact		= 2 ,	-- Medium
			RecommendationEffort	= 1 ,	-- Low
			RecommendationRisk		= 1 ,	-- Low
			AdditionalInfo			= @AdditionalInfo;

		BREAK;

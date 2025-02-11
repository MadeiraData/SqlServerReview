/*
	DESCRIPTION:
		Check if any of the database is not online or Read-only, or  not Multi-user
		
			* Not part of DR secondary solution

*/

		SET @AdditionalInfo =
			(
				SELECT
					DatabaseName = [name]
				FROM
					#sys_databases db
					INNER JOIN sys.database_mirroring dm ON db.database_id = dm.database_id
				WHERE
					is_in_standby = 0 
					AND is_read_only = 0
					AND ISNULL(dm.mirroring_role,1) <> 2
					AND state_desc NOT IN ('ONLINE', 'RESTORING')
					AND NOT EXISTS (SELECT * FROM sys.dm_exec_requests r WHERE r.database_id = db.database_id AND r.blocking_session_id IN (0,r.session_id))
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
			WorstCaseImpact ,
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
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1
				END ,
			WorstCaseImpact			= 3 ,	-- High
			CurrentStateImpact		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- High
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- High
				END ,
			RecommendationRisk		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END ,
			AdditionalInfo			= @AdditionalInfo;


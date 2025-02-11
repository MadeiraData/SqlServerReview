/*

	DESCRIPTION:
		This script outputs data about the current load on each NUMA node.
		Output Resultset:
			memory_node_id - the identifier of the NUMA node
			memory_node_percent - the percentage of the NUMA node based on the total number of nodes
			cpu_nodes_count - number of CPU sockets belonging to the NUMA node
			load_type - Type of load on the NUMA node:
				- Active Worker Threads (sys.dm_os_nodes) - Number of workers that are active on all schedulers managed by this node.
				- Average Load Balance (sys.dm_os_nodes) - Average number of tasks per scheduler on this node.
				- Total Number of Connections (sys.dm_exec_connections) - Number of connections with an affinity to this node.
				- Load Factor (sys.dm_os_schedulers) - Reflects the total perceived load on this node. When a task is enqueued, the load factor is increased. When a task is completed, the load factor is decreased.
				- Online Schedulers (sys.dm_os_nodes) - Number of online schedulers that are managed by this node.
			load_value - The corresponding value (based on load_type)
			total_load_value - The total load at the server level across all NUMA nodes.
			load_percent - Relative load on this node (load_value * 100.0 / total_load_value)
			balanced_utilization_percentage - Load utilization of this node relative to its relative percent (load_percent * 100.0 / memory_node_percent)
			imbalance_factor - The difference between the NUMA node with the lowest and the highest balanced_utilization_percentage at the server level. The higher this value is, the more un-balanced the server is.

		Additional Resources:
			https://www.sqlpassion.at/archive/2019/09/23/troubleshooting-numa-node-inbalance-problems/
			https://glennsqlperformance.com/2020/06/25/how-to-balance-sql-server-core-licenses-across-numa-nodes/
*/

;WITH nodes AS
(
	SELECT	
		'connections'	AS load_type,
		node_affinity	AS node_id,
		COUNT(*)		AS load_value
	FROM
		sys.dm_exec_connections WITH (NOLOCK) 
	GROUP BY
		node_affinity

UNION ALL

	SELECT
		'load factor'			AS load_type,
		parent_node_id			AS node_id,
		SUM(load_factor)		AS load_value
	FROM
		sys.dm_os_schedulers WITH (NOLOCK) 
	WHERE
		[status] = 'VISIBLE ONLINE' 
		AND is_online = 1
	GROUP BY
		parent_node_id

UNION ALL

	SELECT
		load_type,
		node_id,
		load_value
	FROM
		sys.dm_os_nodes WITH (NOLOCK)
		CROSS APPLY
					(
						VALUES
							('online schedulers',online_scheduler_count),
							('active workers', active_worker_count),
							('avg load balance', avg_load_balance)
					)
						AS t(load_type, load_value)
	WHERE
		node_state_desc <> N'ONLINE DAC'
), memory_nodes AS
(
	SELECT
		n.memory_node_id
		,CONVERT(FLOAT, ROUND(100.0 / COUNT(*) OVER(PARTITION BY load_type), 2))								AS memory_node_percent
		,COUNT(*)																								AS cpu_nodes_count
		,load_type, SUM(nodes.load_value) AS load_value, SUM(SUM(load_value)) OVER(PARTITION BY load_type)		AS total_load_value
		,CONVERT(FLOAT, ROUND(SUM(load_value) * 100.0 / SUM(SUM(load_value)) OVER(PARTITION BY load_type), 2))	AS load_percent
	FROM 
		nodes
		INNER JOIN sys.dm_os_nodes AS n WITH(NOLOCK) ON nodes.node_id = n.node_id
	WHERE
		n.node_state_desc <> N'ONLINE DAC'
	GROUP BY
		n.memory_node_id, load_type
), Result AS
(
SELECT
	memory_node_id,
	CONCAT(memory_node_percent,	'%')											AS memory_node_percent,
	cpu_nodes_count,
	load_type,
	load_value,
	total_load_value,
	CONCAT(load_percent,	'%')												AS load_percent,
	CONCAT(CONVERT(FLOAT, load_percent * 100.0 / memory_node_percent),	'%')	AS balanced_utilization_percentage,
	MAX(load_percent * 100.0 / memory_node_percent) OVER(PARTITION BY load_type) - MIN(load_percent * 100.0 / memory_node_percent) OVER (PARTITION BY load_type) AS imbalance_factor
FROM
	memory_nodes
), AdditionalInfo (AdditionalInfoXML) AS
(
SELECT
	memory_node_id,
	memory_node_percent,
	cpu_nodes_count,
	load_type,
	load_value,
	total_load_value,
	load_percent,
	balanced_utilization_percentage
FROM
	Result
WHERE
	imbalance_factor != 0
ORDER BY
	load_type,
	memory_node_id
FOR XML
	AUTO,
	ROOT (N'Details')
)
SELECT
	@AdditionalInfo = AdditionalInfoXML
FROM
	AdditionalInfo;

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
						3	-- High
				END ,
			RecommendationEffort	=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						3	-- High
				END ,
			RecommendationRisk		=
				CASE
					WHEN @AdditionalInfo IS NULL
						THEN 0
					ELSE
						1	-- Low
				END ,
			AdditionalInfo			= @AdditionalInfo;
	

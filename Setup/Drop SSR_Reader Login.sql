USE
	[master];
GO


DECLARE
	@DatabaseName	AS SYSNAME ,
	@Command		AS NVARCHAR(MAX);

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
			sys.databases
		WHERE
			database_id NOT IN (2,3)	-- Not tempdb and model
		AND
			[state] = 0;	-- Online

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

			DROP USER
				SSR_Reader;
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
GO


DROP LOGIN
	SSR_Reader;
GO

USE
	[master];
GO


CREATE LOGIN
	SSR_Reader
WITH
	PASSWORD = 'StrongPassword';
GO


GRANT
	VIEW SERVER STATE
TO
	SSR_Reader;
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

			CREATE USER
				SSR_Reader
			FOR LOGIN
				SSR_Reader;

			GRANT
				VIEW DEFINITION
			TO
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

EXEC sys.sp_configure N'show advanced options', N'1';
GO
RECONFIGURE
GO
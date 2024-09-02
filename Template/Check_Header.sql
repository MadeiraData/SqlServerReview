DECLARE
	  @CheckId			AS INT = {CheckId}
	, @DeadlockRetry	AS BIT = 0


-- Check #{CheckId} : {CheckTitle}

WHILE
	1 = 1
BEGIN

	BEGIN TRY

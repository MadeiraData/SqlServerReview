

-- Check #{CheckId} : {CheckTitle}

DECLARE
	@CheckId		AS INT	= {CheckId} ,
	@DeadlockRetry	AS BIT	= 0 ,
	@AdditionalInfo	AS XML;

WHILE
	1 = 1
BEGIN

	BEGIN TRY

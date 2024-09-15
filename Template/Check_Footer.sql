
		BREAK;

	END TRY
	BEGIN CATCH

		INSERT INTO
			#Errors
		(
			CheckId ,
			ErrorNumber ,
			ErrorMessage ,
			ErrorSeverity ,
			ErrorState ,
			IsDeadlockRetry
		)
		SELECT
			CheckId			= {CheckId} ,
			ErrorNumber		= ERROR_NUMBER () ,
			ErrorMessage	= ERROR_MESSAGE () ,
			ErrorSeverity	= ERROR_SEVERITY () ,
			ErrorState		= ERROR_STATE () ,
			IsDeadlockRetry	= @DeadlockRetry;

		IF
			ERROR_NUMBER () = 1205	-- Deadlock
		AND
			@DeadlockRetry = 0
		BEGIN
			SET @DeadlockRetry = 1
		END
		ELSE
		BEGIN
			BREAK;
		END;

	END CATCH;

END;
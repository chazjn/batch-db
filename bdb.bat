@ECHO OFF
SETLOCAL enableextensions enabledelayedexpansion
IF [%1]==[/?] (GOTO HELP & GOTO EOF)

SET DB=.
SET HEADER=
SET TABLEOK=

:: Get input
:INPUT
SET INPUT=
CALL :BUILD_PROMPT RETURN
SET /P "INPUT=%RETURN% "

:: read tokens in input
FOR /F "usebackq tokens=1,2,3,4,5,6,7,8,9,* delims=:" %%A IN ('%INPUT%') DO (

	IF /I [%%~A]==[CLEAR] (
		CLS
		GOTO INPUT
	)
	
	IF /I [%%~A]==[LIST] (
		CALL :FUNC_LIST
		GOTO INPUT
	)
	
	IF /I [%%~A]==[USE] (
		CALL :FUNC_USE RESULT %%B
		GOTO INPUT
	)

	IF /I [%%~A]==[DROP] (
		CALL :FUNC_DROP RESULT %%B %%C
		GOTO INPUT
	) 	
	
	IF /I [%%~A]==[SELECT] (
		CALL :FUNC_SELECT RESULT %%B "%%~C" "%%~D" "%%~E"
		GOTO INPUT
	)
	
	IF /I [%%~A]==[QUIT] (
		CALL :WRITE "Qutting"
		GOTO QUIT
	) 
	
	REM Else the first token is something else...
	CALL :WRITE "%%~A: Unexpected token"
)
GOTO INPUT

::::::::::::::::::::::::::::::::::::::
:: FUCTIONS
::::::::::::::::::::::::::::::::::::::
:FUNC_USE <result> <db>
IF [%2]==[] (CALL :WRITE "USE: Expected database name" & GOTO EOF)
IF /I EXIST "%~2" (
	SET DB=%~2
	CALL :WRITE "Database '%~2' ready"
	SET %1=TRUE
) ELSE (
	CALL :WRITE "Cannot find database '%~2'"
	SET %1=FALSE
)
GOTO EOF

:FUNC_LIST
DIR "%DB%\" /B
GOTO EOF

:FUNC_DROP <result> <type> <name>
IF /I NOT [%2]==[DATABASE] (IF /I NOT [%2]==[TABLE] (CALL :WRITE "DROP: Expected type 'database' or 'table'" & GOTO EOF))
IF [%3]==[] (CALL :WRITE "DROP %2: Expected object name" & GOTO EOF)

IF /I [%2]==[DATABASE] (
	CALL :DOES_DATABASE_EXIST RESULT %3
	IF [%RESULT%]==[FALSE] (
		CALL :WRITE "Cannot find database '%3'"
		GOTO EOF
	) 
	RMDIR /S /Q "%DB%\%~3"
	CALL :WRITE "Dropped database '%3'"
)
IF /I [%2]==[TABLE] (
	CALL :DOES_TABLE_EXIST RESULT %3
	IF [%RESULT%]==[FALSE] (
		CALL :WRITE "Cannot find table '%3'"
		GOTO EOF
	)
	ERASE "%DB%\%~3"
	CALL :WRITE "Dropped table '%3'"
)

SET %1=TRUE
GOTO EOF

:FUNC_SELECT <result> <table> <columns> <clauses>
SET TABLE=%~2
SET COLUMNS=%~3
SET CLAUSES=%~4

echo Clauses:%CLAUSES%


IF ["%TABLE%"]==[""] (
	CALL :WRITE "SELECT: Expected table:columns:[where]" 
	GOTO EOF
)

IF ["%COLUMNS%"]==[""] (
	CALL :WRITE "SELECT:TABLE: Expected columns:[where]" 
	GOTO EOF
)

CALL :DOES_TABLE_EXIST RESULT "%TABLE%"
IF [%RESULT%]==[FALSE] (
	CALL :WRITE "Cannot find table '%TABLE%'"
	GOTO EOF
)

:: Get column header of table
CALL :GET_COL_HEADER HEADER "%TABLE%"

IF NOT DEFINED HEADER (
	CALL :WRITE "Cannot determine column headers in table '%TABLE%'"
	GOTO EOF
)

:: Replace any wildcard '$' with the header
SET COLUMNS=%COLUMNS:$=!HEADER!%

SET INDEXES=
SET COLCOUNT=0
FOR %%C IN (%COLUMNS%) DO (

	SET /A COLCOUNT=!COLCOUNT!+1

	CALL :GET_COL_INDEX INDEX "%HEADER%" %%C
	IF [!INDEX!]==[-1] (
		CALL :WRITE "SELECT: Failed to find index for column '%%C'"
		GOTO EOF
	)

	IF NOT DEFINED INDEXES (
		SET INDEXES=!INDEX!
	) ELSE (
		SET INDEXES=!INDEXES!;!INDEX!
	)	
)

:: start a row counter
:: row starts from -1 so the header is row 0
SET ROWCOUNTER=-1
SET COLCOUNTER=0

:: for each row in file
FOR /F %%R IN (%DB%\%TABLE%) DO (
	
	SET ROW=%%R
	SET /A ROWCOUNTER=!ROWCOUNTER!+1
	
	FOR /L %%I IN (1, 1, %COLCOUNT%) DO (
	
		SET INDEX=%%I
		
		REM Get the index of the column
		CALL :GET_FIELD_DATA RESULT "%INDEXES%" !INDEX! ";"
		
		REM Now get the actual data from the index
		CALL :GET_FIELD_DATA RESULT "!ROW!" !RESULT! ";"
		
		REM now perform some where clauses
		
		REM SET the field value
		SET "R[!ROWCOUNTER!]C[!INDEX!]=!RESULT!"
	)
)




CALL :DISPLAY RESULT %ROWCOUNTER% %COLCOUNT%
ECHO/
ECHO %ROWCOUNTER% rows selected

GOTO EOF

::::::::::::::::::::::::::::::::::::::


::::::::::::::::::::::::::::::::::::::
:: OUTPUT
::::::::::::::::::::::::::::::::::::::
:WRITE <text>
ECHO %~1
GOTO EOF

:BUILD_PROMPT <return>
SET %1=%DB%\
GOTO EOF

:DISPLAY <return> <rowcount> <colcount>
SET ROWCOUNT=%2
SET COLCOUNT=%3

FOR /L %%R IN (0, 1, %ROWCOUNT%) DO (
	
	SET ROW=
	SET DATA=
	FOR /L %%C IN (1, 1 %COLCOUNT%) DO (
		
		IF %%R EQU 0 (
			SET DATA=[!R[%%R]C[%%C]!]
		) ELSE (
			SET DATA=!R[%%R]C[%%C]!
		)
		
		SET ROW=!ROW!!DATA!;
	)
	ECHO !ROW!
)
GOTO EOF

::::::::::::::::::::::::::::::::::::::



:: %1 = result (index of column or -1 if not found)
:: %2 = list of columns
:: %3 = column name to search
:GET_COL_INDEX <result> <columns> <find>
SET VAR=1
FOR %%A IN (%~2) DO (
	IF [%%A]==[%3] (
		SET "%1=!VAR!" 
		GOTO EOF
	) ELSE (
		SET /A VAR=!VAR!+1
	)
)
SET %1=-1
GOTO EOF

:GET_FIELD_DATA <result> <row> <index> <delims>
FOR /F "tokens=%3 delims=%~4" %%I IN (%2) DO (
  SET %1=%%~I
)
GOTO EOF

:GET_COL_HEADER <result> <tableFile>
SET %1=
SET /P %1=< "%DB%\%~2"
GOTO EOF

:DOES_DATABASE_EXIST <result> <database>
IF [%2]==[.] (SET %1=TRUE & GOTO EOF)
IF EXIST "%~2" (SET %1=TRUE) ELSE (SET %1=FALSE)
GOTO EOF

:DOES_TABLE_EXIST <result> <table>
IF EXIST "%DB%\%~2" (SET %1=TRUE) ELSE (SET %1=FALSE)
GOTO EOF

:MAKE_ROWS <result> <table> <clauses>

GOTO EOF


::::::::::::::::::::::::::::::::::::::::::
:: True-ys and False-ys
::::::::::::::::::::::::::::::::::::::::::
:AND_TRUE <result> <values>
SET VAR=
FOR /F "tokens=* USEBACKQ" %%F IN (`ECHO "%~2" ^| FINDSTR /I "FALSE"`) DO (
	SET VAR=%%F
)
IF DEFINED VAR (SET %1=FALSE) ELSE (SET %1=TRUE)
GOTO EOF

:OR_TRUE <result> <values>
SET VAR=
FOR /F "tokens=* USEBACKQ" %%F IN (`ECHO "%~2" ^| FINDSTR /I "TRUE"`) DO (
	SET VAR=%%F
)
IF DEFINED VAR (SET %1=TRUE) ELSE (SET %1=FALSE)
GOTO EOF

:AND_FALSE <result> <values>
SET VAR=
FOR /F "tokens=* USEBACKQ" %%F IN (`ECHO "%~2" ^| FINDSTR /I "TRUE"`) DO (
	SET VAR=%%F
)
IF DEFINED VAR (SET %1=FALSE) ELSE (SET %1=TRUE)
GOTO EOF

:OR_FALSE <result> <values>
SET VAR=
FOR /F "tokens=* USEBACKQ" %%F IN (`ECHO "%~2" ^| FINDSTR /I "FALSE"`) DO (
	SET VAR=%%F
)
IF DEFINED VAR (SET %1=TRUE) ELSE (SET %1=FALSE)
GOTO EOF
::::::::::::::::::::::::::::::::::::::::::




:HELP
ECHO this is the help
GOTO EOF

:QUIT
EXIT /B

:EOF
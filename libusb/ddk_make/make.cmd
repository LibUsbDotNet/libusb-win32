@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
:: oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
:: LIBUSB-WIN32 WINDDK MAKE UTILITY
:: Travis Robinson [libusbdotnet@gmail.com]
::
:: NOTE: param/values passed into make.cmd will override make.cfg
:: NOTE: destination directories are automatically created
:: oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo

CALL :ToAbsoluteDirs DIR_LIBUSB_DDK "%~0" DIR_LIBUSB_WORKING "!CD!"
IF /I "!DIR_LIBUSB_DDK!" NEQ "!DIR_LIBUSB_WORKING!" (
	PUSHD !CD!
	CD /D "!DIR_LIBUSB_DDK!"
)

IF /I "%~1" EQU "" GOTO ShowHelp
IF /I "%~1" EQU "?" GOTO ShowHelp
IF /I "%~1" EQU "/?" GOTO ShowHelp
IF /I "%~1" EQU "--help" GOTO ShowHelp
IF /I "%~1" EQU "help" GOTO ShowHelp

:BEGIN
CALL :ClearError

ECHO Libusb-Win32 ddk directory = !DIR_LIBUSB_DDK!

SET MAKE_CFG=!DIR_LIBUSB_DDK!make.cfg
IF NOT EXIST "!MAKE_CFG!" (
	ECHO !MAKE_CFG! configuration file not found.
	GOTO CMDERROR
)
CALL :LoadConfig

IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR

SET _PACKAGE_TYPE_=%~1

:: oooooooooooooooooooooooooooooooooooo
:: Package build section [if any]
:: 
IF /I "!_PACKAGE_TYPE_!" EQU "clean" (
	CALL :Package_Clean %*
	GOTO CMDEXIT
)
IF /I "!_PACKAGE_TYPE_!" EQU "all" (
	CALL :Build_Binaries %*
	IF "!BUILD_ERRORLEVEL!" NEQ 0 GOTO CMDERROR
	GOTO CMDEXIT
)
IF /I "!_PACKAGE_TYPE_!" EQU "bin" (
	CALL :Build_Binaries %*
	IF "!BUILD_ERRORLEVEL!" NEQ 0 GOTO CMDERROR
	GOTO CMDEXIT
)

IF /I "!_PACKAGE_TYPE_!" EQU "dist" (
	CALL :Package_Distributables %*
	IF "!BUILD_ERRORLEVEL!" NEQ 0 GOTO CMDERROR
	GOTO CMDEXIT
)

IF /I "!_PACKAGE_TYPE_!" EQU "snapshot" (
	CALL :Package_Distributables %*
	IF "!BUILD_ERRORLEVEL!" NEQ 0 GOTO CMDERROR
	GOTO CMDEXIT
)

IF /I "!_PACKAGE_TYPE_!" EQU "makever" (
	CALL :TokenizeLibusbVersionH %*
	IF "!BUILD_ERRORLEVEL!" NEQ 0 GOTO CMDERROR
	GOTO CMDEXIT
)

IF /I "%~1" EQU "packagebin" (
	CALL :PrepForPackaging %*
	CALL :CheckOrBuildBinaries
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR

	CALL :Package_Bin
	IF "!BUILD_ERRORLEVEL!" NEQ 0 GOTO CMDERROR
	GOTO CMDEXIT
)

IF /I "%~1" EQU "packagesrc" (
	CALL :PrepForPackaging %*
	CALL :CheckOrBuildBinaries
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR

	CALL :Package_Src
	IF "!BUILD_ERRORLEVEL!" NEQ 0 GOTO CMDERROR
	GOTO CMDEXIT
)

IF /I "%~1" EQU "packagesetup" (
	CALL :PrepForPackaging %*
	CALL :CheckOrBuildBinaries
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
	
	CALL :Package_Setup
	IF "!BUILD_ERRORLEVEL!" NEQ 0 GOTO CMDERROR
	GOTO CMDEXIT
)

IF /I "%~1" EQU "signfile" (
	CALL :SignFile %2
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
	GOTO CMDEXIT
)

IF /I "%~1" EQU "launchdevenv" (
	"%VS90COMNTOOLS%..\IDE\devenv.exe" %2
	GOTO CMDEXIT
)

:: 
:: End of Package build section
:: oooooooooooooooooooooooooooooooooooo

:: oooooooooooooooooooooooooooooooooooo
:: WinDDK build section (not a package)
:: 
SET _PACKAGE_TYPE_=
CALL :LoadArguments 0 %*
	
IF NOT DEFINED CMDVAR_ARCH (
	ECHO The architecture must be specified. Example: CMD /C make.cmd "arch=x86"
	GOTO CMDERROR
)

CALL :CheckWinDDK pre
IF "!BUILD_ERRORLEVEL!" NEQ "0" GOTO CMDERROR

SET _FRE_OR_CHECK_=fre
IF /I "!CMDVAR_DEBUGMODE!" equ "true" SET _FRE_OR_CHECK_=chk

IF /I "!CMDVAR_ARCH!" EQU "x86" (
	CALL :SetDDK "!CMDVAR_WINDDK_DIR!" normal !_FRE_OR_CHECK_! WXP
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
) ELSE IF /I "!CMDVAR_ARCH!" EQU "x64" (
	CALL :SetDDK "!CMDVAR_WINDDK_DIR!" normal !_FRE_OR_CHECK_! x64 WNET
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
) ELSE IF /I "!CMDVAR_ARCH!" EQU "i64" (
	CALL :SetDDK "!CMDVAR_WINDDK_DIR!" normal !_FRE_OR_CHECK_! 64 WNET
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
) ELSE IF /I "!CMDVAR_ARCH!" EQU "w2k" (
	CALL :SetDDK "!CMDVAR_WINDDK_W2K_DIR!" forceoacr !_FRE_OR_CHECK_! W2K 
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
) ELSE (
	ECHO Invalid argument. arch=!CMDVAR_ARCH!
	GOTO CMDERROR
)
CALL :CheckWinDDK post
IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR

call make_clean.bat
CALL :ClearError

SET _LIBUSB_APP=!CMDVAR_APP!
IF EXIST "build!BUILD_ALT_DIR!.err" DEL /Q "build!BUILD_ALT_DIR!.err"
CALL :Build
IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
IF EXIST "build!BUILD_ALT_DIR!.err" GOTO CMDERROR

:: 
:: Copy binaries to the output directory
:: 
CALL  :SafeCreateDir "!CMDVAR_OUTDIR!"
IF !ERRORLEVEL! NEQ 0 (
	Unable to re-create output directory !CNDVAR_OUTPUT!
	GOTO CMDERROR
)

IF EXIST *.sys MOVE /Y *.sys "!CMDVAR_OUTDIR!" >NUL
IF EXIST *.dll MOVE /Y *.dll "!CMDVAR_OUTDIR!" >NUL
IF EXIST *.exe MOVE /Y *.exe "!CMDVAR_OUTDIR!" >NUL
IF EXIST *.lib COPY /Y *.lib "!CMDVAR_OUTDIR!" >NUL

CALL :DestroyErrorMarker

GOTO CMDEXIT

:: 
:: End of WinDDK build section
:: oooooooooooooooooooooooooooooooooooo

:: oooooooooooooooooooooooooooooooooooo
:: building functions 
:: 
:Build
	CALL :TokenizeLibusbVersionH true
	SET _title=Building libusb-win32 !_LIBUSB_APP! (!BUILD_ALT_DIR!)
	title !_title!
	CALL make_clean.bat
	
	SET CMDVAR_BUILDARCH=!_BUILDARCH!
	CALL make_!_LIBUSB_APP!.bat

	IF !ERRORLEVEL! NEQ 0 SET BUILD_ERRORLEVEL=!ERRORLEVEL!
	IF !BUILD_ERRORLEVEL! NEQ 0 (
		SET BUILD_ERRORLEVEL=!ERRORLEVEL!
		IF !BUILD_ERRORLEVEL! EQU 0 SET BUILD_ERRORLEVEL=1
		GOTO :EOF
	)
	IF /I "!CMDVAR_DIR_INTERMEDIATE!" NEQ "" (
		CALL :SafeCopyDir "!DIR_LIBUSB_DDK!obj!BUILD_ALT_DIR!\*" "!CMDVAR_DIR_INTERMEDIATE!"
	)

	IF /I "!CMDVAR_NOCLEAN" NEQ "true" CALL make_clean.bat %1
	
	IF /I "!CMDVAR_TESTSIGNING!" EQU "on" (
		IF EXIST libusb0.sys CALL :SignFile libusb0.sys
		IF EXIST libusb0.dll CALL :SignFile libusb0.dll
	)

	CALL :ClearError
	IF EXIST libusb0.lib move libusb0.lib libusb.lib %~1
GOTO :EOF

:Build_Binaries
	CALL :PrepForPackaging %*
	CALL :CheckPackaging
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR

	CALL :SafeCleanDir "!PACKAGE_BIN_DIR!"
	IF !ERRORLEVEL! NEQ 0 GOTO :EOF
	
	CALL :Build_PackageBinaries w2k msvc
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR

	CALL :Build_PackageBinaries x86 msvc
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
	
	PUSHD !CD!
	CD /D !_OUTDIR_!
	
	:: 
	:: build gcc lib 
	:: 
	CALL :BuildLib_GCC libusb_gcc.a libusb0.dll "!DIR_LIBUSB!libusb0.def"
	CALL :SafeMove libusb_gcc.a "!PACKAGE_LIB_DIR!gcc\libusb.a"
	
	:: 
	:: build bcc lib 
	:: 
	CALL :BuildLib_BCC libusb_bcc.lib libusb0.dll
	CALL :SafeMove libusb_bcc.lib "!PACKAGE_LIB_DIR!bcc\libusb.lib"
	
	POPD	
	
	CALL :Build_PackageBinaries x64 msvc_x64
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR

	CALL :Build_PackageBinaries i64 msvc_i64
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR

	CALL :SafeCopy "..\src\libusb_dyn.c" "!PACKAGE_LIB_DIR!dynamic\"
	
	CALL :SafeCopy "!PACKAGE_ROOT_DIR!gcc\libusb.a" "!PACKAGE_LIB_DIR!gcc\libusb.a" false
	CALL :SafeCopy "!PACKAGE_ROOT_DIR!bcc\libusb.lib" "!PACKAGE_LIB_DIR!bcc\libusb.lib" false

GOTO :EOF

:: oooooooooooooooooooooooooooooooooooo
:: Packaging functions 
:: 
:Build_PackageBinaries
	SET _OUTDIR_=!PACKAGE_BIN_DIR!%1\
	CALL :SafeCreateDir "!_OUTDIR_!"
	CALL :CmdExe make.cmd !_ARG_LINE! "arch=%1" "app=all" "outdir=!_OUTDIR_!"
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO :EOF
	
	CALL :SafeCreateDir "!PACKAGE_LIB_DIR!%2\"
	CALL :SafeMove "!_OUTDIR_!\libusb.lib" "!PACKAGE_LIB_DIR!%2\"
GOTO :EOF


:PackageText
	CALL :TagEnv "..\README.in" "%~1\README.txt"
	COPY /Y "..\*.txt" "%~1"
GOTO :EOF

:PrepForPackaging
	CALL :LoadArguments 1 %*
	CALL :TryCopyGccBinaries
	CALL make_super_clean.bat
GOTO :EOF

:SetPackage
	IF /I "!_PACKAGE_TYPE_!" EQU "snapshot" (
		SET CMDVAR_PCKGNAME=%~1-!CMDVAR_SNAPSHOT_ID!
	) ELSE (
		SET CMDVAR_PCKGNAME=%~1-!CMDVAR_VERSION!
	)
GOTO :EOF

:Package_Distributables
(
	CALL :PrepForPackaging %*
	CALL :CheckPackaging
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
	
	CALL :CheckOrBuildBinaries
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
	
	CALL :Package_Bin
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
	
	CALL :Package_Src
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
	
	CALL :Package_Setup
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR

	GOTO :EOF
)
GOTO :EOF

:Package_Bin
	CALL :SetPackage "!PACKAGE_BIN_NAME!"
	SET _WORKING_DIR=!PACKAGE_WORKING!!CMDVAR_PCKGNAME!\
	
	CALL :SafeReCreateDir "!_WORKING_DIR!"
		
	CALL :SafeCopyDir "!PACKAGE_BIN_DIR!*" "!_WORKING_DIR!bin\"
	CALL :SafeCopyDir "!PACKAGE_LIB_DIR!*" "!_WORKING_DIR!lib\"
	
	CALL :SafeCopyDir "..\examples\*" "!_WORKING_DIR!examples\"
	
	CALL :SafeCopy "..\src\usb.h" "!_WORKING_DIR!include\"

	CALL :SafeCopy "!PACKAGE_ROOT_DIR!gcc\*" "!_WORKING_DIR!lib\gcc\"
	CALL :SafeCopy "!PACKAGE_ROOT_DIR!bcc\*" "!_WORKING_DIR!lib\bcc\"

	CALL :PackageText "!_WORKING_DIR!"
	
	PUSHD "!CD!"
	CD /D "!PACKAGE_WORKING!"
	
	CALL :DeleteAllDirectories ".svn"

	"!ZIP!" -tzip a -r "!PACKAGE_SAVE_DIR!!CMDVAR_PCKGNAME!.zip" ".\!CMDVAR_PCKGNAME!"
	CALL :SafeDeleteDir ".\!CMDVAR_PCKGNAME!"
	POPD
	
GOTO :EOF

:Package_Src
	CALL make_super_clean.bat
	CALL :SetPackage "!PACKAGE_SRC_NAME!"
	SET _WORKING_DIR=!PACKAGE_WORKING!!CMDVAR_PCKGNAME!\
	CALL :SafeReCreateDir "!_WORKING_DIR!"

	CALL :SafeCopyDir "..\*" "!_WORKING_DIR!"
	
	CALL :PackageText "!_WORKING_DIR!"

	PUSHD "!CD!"
	CD /D "!PACKAGE_WORKING!"
	CALL :DeleteAllDirectories ".svn"
	"!ZIP!" -tzip a -r "!PACKAGE_SAVE_DIR!!CMDVAR_PCKGNAME!.zip" ".\!CMDVAR_PCKGNAME!"
	CALL :SafeDeleteDir ".\!CMDVAR_PCKGNAME!\"
	POPD
GOTO :EOF

:Package_Setup
	CALL :SetPackage "!PACKAGE_SETUP_NAME!"
	SET _WORKING_DIR=!PACKAGE_WORKING!!PACKAGE_SETUP_NAME!\
	CALL :SafeReCreateDir "!_WORKING_DIR!"

	CALL :PackageText "!_WORKING_DIR!"
	
	IF /I "!CMDVAR_TESTSIGNING!" EQU "on" (
		CALL :SafeCopy "!PACKAGE_ROOT_DIR!cert\!CERT_FILE!" "!_WORKING_DIR!"
	)
	
	CALL :TagEnv "filter-bin-setup.iss.in" "!_WORKING_DIR!filter-bin-setup.iss"
	
	PUSHD "!CD!"
	CD /D "!_WORKING_DIR!"
	CALL :DeleteAllDirectories ".svn"
	"!ISCC!" "filter-bin-setup.iss"
	IF !ERRORLEVEL! NEQ 0 GOTO CMDERROR

	CALL :SafeMove "!CMDVAR_PCKGNAME!.exe" "!PACKAGE_SAVE_DIR!"
	DEL /Q "!_WORKING_DIR!*"
	POPD
GOTO :EOF

:Package_Clean
	CALL :LoadArguments 1 %*
	CALL :SafeCleanDir "!PACKAGE_BIN_DIR!"
	CALL :SafeCleanDir "!PACKAGE_LIB_DIR!"
	CALL :SafeCleanDir "!PACKAGE_WORKING!"
	CALL :SafeCleanDir "!PACKAGE_SAVE_DIR!"
	CALL make_super_clean.bat
GOTO :EOF

:: oooooooooooooooooooooooooooooooooooo
:: Internal functions 
:: 
:SafeCleanDir
	IF EXIST "%~1" (
		ECHO [SafeCleanDir] %~1
		RMDIR /S /Q "%~1"
		GOTO :EOF
	)
	ECHO [SafeCleanDir] nothing to do.
GOTO :EOF

:SafeCopyDir
	IF NOT EXIST "%~1" (
		ECHO [SafeCopyDir] %~1 does not exists.
		GOTO :EOF
	)
	CALL :SafeCreateDir "%~dp2"
	ECHO [SafeCopyDir] %~1 %~p2
	XCOPY /I /S /Y "%~1" "%~p2" 2>NUL>NUL
	IF !ERRORLEVEL! NEQ 0 (
		ECHO Error copying "%~1" "%~p2"
		SET BUILD_ERRORLEVEL=!ERRORLEVEL!
	)
GOTO :EOF

:SafeReCreateDir
	CALL :SafeCleanDir "%~1"
	CALL :SafeCreateDir "%~1"
GOTO :EOF

:SafeCreateDir
	IF NOT EXIST "%~1" (
		ECHO [SafeCreateDir] %~1
		MKDIR "%~1"
		GOTO :EOF
	)
	ECHO [SafeCreateDir] nothing to do.
GOTO :EOF

:SafeDeleteDir
	IF EXIST "%~1" (
		ECHO [SafeDeleteDir] %~1
		RMDIR /S /Q "%~1"
		GOTO :EOF
	)
	ECHO [SafeDeleteDir] nothing to do.
GOTO :EOF


:SafeDelete
	IF EXIST "%~1" (
		ECHO [SafeDelete] %~1
		DEL /Q "%~1"
		GOTO :EOF
	)
	ECHO [SafeDelete] nothing to do.
GOTO :EOF

:SafeCopy
	IF /I "%3" EQU "false" (
		ECHO [SafeCopy] %~2 already exists. skipping..
		IF EXIST "%~2" GOTO :EOF
	)
	IF EXIST "%~1" (
		ECHO [SafeCopy] %~1 %~2
		CALL :SafeCreateDir "%~dp2"
		COPY /Y "%~1" "%~2" 2>NUL>NUL
		GOTO :EOF
	)
	ECHO [SafeCopy] nothing to do.
GOTO :EOF

:SafeMove
	IF EXIST "%~1" (
		ECHO [SafeMove] %~1 %~2
		CALL :SafeCreateDir "%~dp2"
		MOVE /Y "%~1" "%~2"
		GOTO :EOF
	)
	ECHO [SafeMove] nothing to do.
GOTO :EOF

:DeleteAllDirectories
	CALL :CreateTempFile CLEAN_SVN_TMP
	
	DIR /B /S "%~1">!CLEAN_SVN_TMP!
	FOR /F "eol=; tokens=1* usebackq delims=" %%I IN (!CLEAN_SVN_TMP!) DO (
		CALL :SafeDeleteDir "%%I"
	)

	CALL :DestroyTempFile CLEAN_SVN_TMP

GOTO :EOF

:: 
:: params = outlibfile indllfile indeffile
::
:BuildLib_GCC
	IF NOT EXIST "!CMDVAR_DLLTOOL!" (
		ECHO [WARNING] gcc dlltool not found. Skipping gcc lib build..
		SET BUILD_ERRORLEVEL=1
		GOTO :EOF
	)

	"!CMDVAR_DLLTOOL!" --output-lib "%~1" --dllname "%~2" --input-def "%~3"
	IF !ERRORLEVEL! NEQ 0 ECHO [WARNING] gcc dlltool tool failed.
GOTO :EOF

:: 
:: params = outlibfile indllfile
::
:BuildLib_BCC
	IF NOT EXIST "!CMDVAR_IMPLIB!" (
		ECHO [WARNING] bcc implib tool not found. Skipping bcc lib build..
		SET BUILD_ERRORLEVEL=1
		GOTO :EOF
	)

	"!CMDVAR_IMPLIB!" -a %~1 %~2
	IF !ERRORLEVEL! NEQ 0 ECHO [WARNING] bcc implib tool failed.
GOTO :EOF

:TryCopyGccBinaries
	CALL :SafeCopy ..\libusb.a "!PACKAGE_ROOT_DIR!gcc\"
GOTO :EOF

:SetDDK
	PUSHD !CD!
	SET SELECTED_DDK=%~1
	SHIFT /1
	IF /I "%~1" EQU "forceoacr" SET WINDDK_AUTOCODEREVIEW=
	SHIFT /1
	CALL "!SELECTED_DDK!\bin\setenv.bat" !SELECTED_DDK! %1 %2 %3 %4 !WINDDK_AUTOCODEREVIEW!
	SET BUILD_ERRORLEVEL=!ERRORLEVEL!
	POPD
	IF NOT !BUILD_ERRORLEVEL!==0 (
		ECHO Failed setting DDK environment
	)
GOTO :EOF

:CheckOrBuildBinaries
	IF NOT EXIST "!PACKAGE_BIN_DIR!x86\*.dll" GOTO BinariesNotBuilt
	IF NOT EXIST "!PACKAGE_BIN_DIR!x86\*.sys" GOTO BinariesNotBuilt
	IF NOT EXIST "!PACKAGE_BIN_DIR!x86\*.exe" GOTO BinariesNotBuilt
	IF NOT EXIST "!PACKAGE_BIN_DIR!x64\*.dll" GOTO BinariesNotBuilt
	IF NOT EXIST "!PACKAGE_BIN_DIR!x64\*.sys" GOTO BinariesNotBuilt
	IF NOT EXIST "!PACKAGE_BIN_DIR!x64\*.exe" GOTO BinariesNotBuilt
	GOTO :EOF
	
	:BinariesNotBuilt
	ECHO Binaries not found.  Building binaries first..
	CALL :CmdExe make.cmd bin
	IF !BUILD_ERRORLEVEL! NEQ 0 GOTO CMDERROR
	
GOTO :EOF

:CheckPackaging
	CALL :ToAbsolutePaths ZIP "!ZIP!" ISCC "!ISCC!"
	IF NOT EXIST "!ZIP!" (
		ECHO [CheckPackaging] Failed locating zip utility: !ZIP!
		ECHO [CheckPackaging] See !MAKE_CFG!
		GOTO CMDERROR
	)
	IF NOT EXIST "!ISCC!" (
		ECHO [CheckPackaging] Failed locating inno setup compiler: !ISCC!
		ECHO [CheckPackaging] See !MAKE_CFG!
		GOTO CMDERROR
	)
GOTO :EOF

:CheckWinDDK
	SET BUILD_ERRORLEVEL=1

	IF /I "%1" EQU "pre" (
		IF NOT EXIST "!CMDVAR_WINDDK_DIR!" GOTO WINDDK_NOTFOUND
		IF NOT EXIST "!CMDVAR_WINDDK_W2K_DIR!" GOTO WINDDK_W2K_NOTFOUND
		SET BUILD_ERRORLEVEL=0
		GOTO :EOF
		:WINDDK_NOTFOUND
			ECHO Invalid WinDDK Directory !CMDVAR_WINDDK_DIR!
			GOTO :EOF

		:WINDDK_W2K_NOTFOUND
			ECHO Invalid WinDDK W2K Directory !CMDVAR_WINDDK_W2K_DIR!
			GOTO :EOF
	) ELSE (
		IF DEFINED _NT_TARGET_VERSION (
			ECHO WinDDK ok. Target version = !_NT_TARGET_VERSION!
			SET BUILD_ERRORLEVEL=0
		) ELSE (
			ECHO Unable to configure WinDDK.
			GOTO :EOF
		)
	)
GOTO :EOF

:LoadConfig
	IF NOT EXIST "!MAKE_CFG!" (
		ECHO Config file not found "!MAKE_CFG!".
		SET BUILD_ERRORLEVEL=1
		GOTO :EOF
	)
	FOR /F "eol=; tokens=1,2* usebackq delims==" %%I IN (!MAKE_CFG!) DO (
		IF NOT "%%~I" EQU "" (
			SET _PNAME=%%~I
			SET _PNAME=!_PNAME: =!
			SET _PVALUE=%%J
			SET CMDVAR_!_PNAME!=!_PVALUE!
			SET !_PNAME!=!_PVALUE!
		)
	)
	
	IF /I "!WINDDK_AUTOCODEREVIEW!" EQU "false" (
		SET WINDDK_AUTOCODEREVIEW=no_oacr
	) ELSE (
		SET WINDDK_AUTOCODEREVIEW=
	)
GOTO :EOF

:LoadArguments
	CALL :ParamValsToEnv :LoadArgumentsCallback %*
	
	IF NOT EXIST "!DIR_LIBUSB_DDK!" (
		ECHO Invalid !MAKE_CFG!.
		GOTO CMDERROR
	)
	CALL :ToAbsolutePaths DIR_LIBUSB_DDK "!DIR_LIBUSB_DDK!"
	CALL :ToAbsolutePaths DIR_LIBUSB "!DIR_LIBUSB_DDK!..\"
	
	IF "!CMDVAR_WINDDK!" NEQ "" SET CMDVAR_WINDDK_DIR=!CMDVAR_WINDDK!
	IF "!CMDVAR_WIN2KDDK!" NEQ "" SET CMDVAR_WINDDK_W2K_DIR=!CMDVAR_WIN2KDDK!
	IF "!CMDVAR_WINDDK_W2K_DIR!" EQU "" SET CMDVAR_WINDDK_W2K_DIR=!CMDVAR_WINDDK_DIR!
	IF "!CMDVAR_OUTDIR!" EQU "" SET CMDVAR_OUTDIR=.\!CMDVAR_ARCH!
	IF "!CMDVAR_APP!" EQU "" SET CMDVAR_APP=all
GOTO :EOF

:: params = no_overwrite
:TokenizeLibusbVersionH
	CALL :ToAbsolutePaths _H_IN  "!DIR_LIBUSB_DDK!..\src\libusb_version_h.in"
	CALL :ToAbsolutePaths _H_OUT "!DIR_LIBUSB_DDK!..\src\libusb_version.h"
	IF /I "%~1" EQU "true" IF EXIST "!_H_OUT!" GOTO :EOF
	CALL :SafeDelete "!_H_OUT!"
	CALL :TagEnv "!_H_IN!" "!_H_OUT!"
GOTO :EOF

:LoadArgumentsCallback
	SET CMDVAR_%~1=%~2
GOTO :EOF

::
:: Parses param/value pairs.
:: Params = CallbackFunction ArgSkipCount "param1=value1" "param2=value2" ..
:: 
:ParamValsToEnv
	SET _SKIP_ARG_LINE=
	SET _ARG_LINE=
	
	SET _CALLBACK_FN=%~1
	SET _ARG_SKIP_COUNT=%~2
	SHIFT /1

	:ParamValsToEnv_Next
	SHIFT /1
	IF "%~1" EQU "" GOTO :EOF
	IF !_ARG_SKIP_COUNT! GTR 0 (
		SET _SKIP_ARG_LINE=!_SKIP_ARG_LINE! "%~1"
		SET /A _ARG_SKIP_COUNT=_ARG_SKIP_COUNT-1
		GOTO ParamValsToEnv_Next
	)
	SET _ARG_LINE=!_ARG_LINE! %1
	SET _PARAM_VALUE_=%%~1
	FOR /F "usebackq tokens=1,2 delims==" %%H IN ('%%~1') DO (
		IF "%%~H" NEQ "" (
			CALL !_CALLBACK_FN! %%H %%I
		)
	)
	GOTO ParamValsToEnv_Next
GOTO :EOF

:ToAbsoluteDirs
	IF NOT "%~1" EQU "" (
		SET %~1=%~dp2
		SHIFT /1
		SHIFT /1
		GOTO ToAbsoluteDirs
	)
GOTO :EOF

:GetDDKToolPath
	CALL :FindInPath %1 "%~2"
	IF "!%1!" EQU "" CALL :ToAbsolutePaths %1 "!CMDVAR_WINDDK_DIR!bin\x86\%~2"
	IF NOT EXIST "!%1!" (
		ECHO %~2 was not found in the path or !CMDVAR_WINDDK_DIR!bin\x86
		SET BUILD_ERRORLEVEL=1
		GOTO :EOF
	)
GOTO :EOF


:SignFile
	CALL :GetDDKToolPath MAKE-CERT makecert.exe
	IF "!BUILD_ERRORLEVEL!" NEQ "0" GOTO :EOF
	
	CALL :GetDDKToolPath CERT-MGR certmgr.exe
	IF "!BUILD_ERRORLEVEL!" NEQ "0" GOTO :EOF
	
	CALL :GetDDKToolPath SIGN-TOOL signtool.exe
	IF "!BUILD_ERRORLEVEL!" NEQ "0" GOTO :EOF
	
	ECHO [SignFile] NOTE - remember to type 'bcdedit -set testsigning on' to use
	ECHO                   test certificates on x64 machines.
	ECHO.
	CALL :SafeCopy "!PACKAGE_ROOT_DIR!cert\!CMDVAR_CERT_FILE!" "!CD!"
	IF NOT EXIST "!CMDVAR_CERT_FILE!" (
	
		ECHO [SignFile] clearing LibusbCertStore
		"!CERT-MGR!" -del -all -s LibusbCertStore
		
		ECHO [SignFile] making !CMDVAR_CERT_FILE! test certificate
		"!MAKE-CERT!" -r -pe -ss LibusbCertStore -n "CN=Libusb-Win32 Testing" !CMDVAR_CERT_FILE!
		IF "!ERRORLEVEL!" NEQ "0" (
			SET BUILD_ERRORLEVEL=1
			ECHO [SignFile] failed creating certificate !CMDVAR_CERT_FILE!
			GOTO :EOF
		)
		
		CALL :SafeCopy !CMDVAR_CERT_FILE! "!PACKAGE_ROOT_DIR!cert\"
		
		ECHO [SignFile] adding !CMDVAR_CERT_FILE! to root
		"!CERT-MGR!" -add !CMDVAR_CERT_FILE! -s -r localMachine root
		IF "!ERRORLEVEL!" NEQ "0" (
			SET BUILD_ERRORLEVEL=1
			ECHO [SignFile] failed adding certificate to root
			GOTO :EOF
		)	
		
		ECHO [SignFile] adding !CMDVAR_CERT_FILE! to trustedpublisher
		"!CERT-MGR!" -add !CMDVAR_CERT_FILE! -s -r localMachine trustedpublisher
		IF "!ERRORLEVEL!" NEQ "0" (
			SET BUILD_ERRORLEVEL=1
			ECHO [SignFile] failed adding certificate to trustedpublisher
			GOTO :EOF
		)		
		
	)
	
	"!SIGN-TOOL!" sign /s LibusbCertStore %1
	IF "!ERRORLEVEL!" NEQ "0" (
		SET BUILD_ERRORLEVEL=1
		GOTO :EOF
	)
	DEL /Q !CMDVAR_CERT_FILE!
GOTO :EOF

:: searches the directories listed in the PATH
:: environment variable for %2 and expands to the
:: drive letter and path of the first one found.
:: 
:FindInPath
	SET %1=%~dp$PATH:2
	IF "!%~1!" NEQ "" (
		CALL :ToAbsolutePaths %1 "!%~1!%2"
		ECHO [FindInPath] found path for %1
	)
GOTO :EOF

:ToAbsolutePaths
	IF NOT "%~1" EQU "" (
		SET %~1=%~f2
		SHIFT /1
		SHIFT /1
		GOTO ToAbsolutePaths
	)
GOTO :EOF

:: 
:: Params = <infile> <outfile>
:: 
:TagEnv
	CALL :CreateTempFile TAG_ENV_TMP
	
	IF NOT DEFINED _LTAG_ SET _LTAG_=@
	IF NOT DEFINED _RTAG_ SET _RTAG_=@
	IF EXIST "%~2" DEL /Q "%~2"
	ECHO [Tokenizing] %~1..
	SET CMDVAR_>!TAG_ENV_TMP!
	FOR /F "tokens=1,* delims=]" %%A IN ('"type %1|find /n /v """') DO (
		SET "line=%%B"
		IF DEFINED line (
			FOR /F "tokens=1,* usebackq delims==" %%I IN (!TAG_ENV_TMP!) DO (
				SET _TOKEN_KEY_=%%I
				SET _TOKEN_KEY_=!_LTAG_!!_TOKEN_KEY_:~7!!_RTAG_!
				CALL SET "line=%%line:!_TOKEN_KEY_!=%%~J%%"
			)
			ECHO !line!>> "%~2"
		) ELSE ECHO.>> "%~2"
	)
	CALL :DestroyTempFile TAG_ENV_TMP

GOTO :EOF

:CreateTempFile
	SET %1=!DIR_LIBUSB_DDK!tf!RANDOM!.tmp
GOTO :EOF

:DestroyTempFile
	IF EXIST "!%1!" (
		DEL /Q "!%1!"
		IF EXIST "!%1!" ECHO [DestroyTempFile] !%1! access denied.
	) ELSE (
		ECHO [DestroyTempFile] !%1! not found.
	)
	SET %1=
GOTO :EOF

:CreateErrorMarker
	SET _EMARKER=1
	ECHO !_EMARKER!>"!DIR_LIBUSB_DDK!emarker.tmp"
GOTO :EOF

:DestroyErrorMarker
	SET _EMARKER=
	IF EXIST "!DIR_LIBUSB_DDK!emarker.tmp" (
		DEL /Q "!DIR_LIBUSB_DDK!emarker.tmp"
		SET _EMARKER=1
	)
GOTO :EOF

:CmdExe
	CALL :CreateErrorMarker
	CMD /C %*
	CALL :DestroyErrorMarker
	IF DEFINED _EMARKER GOTO CMDERROR
GOTO :EOF


:ClearError
	SET ERRORLEVEL=0
	SET BUILD_ERRORLEVEL=0
GOTO :EOF

:CMDERROR
	SET BUILD_ERRORLEVEL=1
	SET ERRORLEVEL=1
GOTO CMDEXIT

:CMDEXIT
IF /I "!DIR_LIBUSB_DDK!" NEQ "!DIR_LIBUSB_WORKING!" POPD
EXIT /B !BUILD_ERRORLEVEL!

:ShowHelp

ECHO.
ECHO LIBUSB-WIN32 WinDDK build utility/application packager
ECHO.
ECHO Summary: This batch script automates the libusb-win32 WinDDK build process and
ECHO          creates libusb-win32 redistributable packages.
ECHO.
ECHO.
ECHO BUILD USAGE: CMD /C make.cmd "Option=Value"
ECHO Options: 
ECHO [req] ARCH      w2k/x86/x64/i64
ECHO APP		  all/dll/driver/install_filter/inf_wizard/test/testwin
ECHO              [Default = all]
ECHO OUTDIR		  Directory that will contain the compiled binaries
ECHO              [Default = .\ARCH]
ECHO WINDDK		  WinDDK directory for WXP-WIN7 builds
ECHO              [Default = see make.cfg]
ECHO WIN2KDDK     WinDDK directory for Windows 2000 builds
ECHO              [Default = see make.cfg]
ECHO DEBUGMODE    Setting this option to 'true' makes chk builds instead of fre.
ECHO              This also enables kernel debug messages and sets all default
ECHO              log modes to the max verbosity.
ECHO              [Default = false]
ECHO TESTSIGNING  Setting this option to 'on' signs te dll and driver with a
ECHO              test certifcate.
ECHO              [Default = off]
ECHO.
ECHO [Note: See make.cfg for more options that can be used when building]
ECHO.
ECHO Examples:
ECHO CMD /C make.cmd "arch=x86" "app=all" "outdir=.\x86"
ECHO CMD /C make.cmd "arch=x64" "outdir=.\x64" "winddk=Z:\WinDDK\7600.16385.0\"
ECHO CMD /C make.cmd "arch=x64" "testsigning=on"
ECHO CMD /C make.cmd "arch=x86"
ECHO.
ECHO PACKAGE USAGE: make.cmd PackageCommand "Option=Value"
ECHO Package Commands:
ECHO ALL       Build binaries for all architectures.
ECHO DIST      Creates libusb-win32 dist packages.
ECHO SNAPSHOT  Creates libusb-win32 snapshot packages.
ECHO.
ECHO Additional Commands:
ECHO CLEAN     Cleans all temporary files and root package directory.
ECHO SIGNFILE  Signs a dll or sys file with a test certificate.
ECHO MAKEVER   Re/creates libusb_version.h from the template.
ECHO.
ECHO [Note: See make.cfg for options that can be used when packaging]
ECHO.
ECHO Example: make.cmd clean
ECHO Example: make.cmd all
ECHO Example: make.cmd dist
ECHO.
GOTO GOTO CMDERROR


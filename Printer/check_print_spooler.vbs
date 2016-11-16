' MSDN: http://msdn.microsoft.com/en-us/library/aa394370%28v=vs.85%29.aspx
' Required Variables
' Author: Oliver Skibbe oliskibbe (at) gmail.com
' Date: 2016-11-16
' Changelog:
' - fixed return code in case of library file missing

Const PROGNAME = "check_print_spooler"
Const VERSION = "1.3.0"

' automatically kill job?
killjob = false

Set wshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

'64bit NSClient/NSCP
strProgramFilesDir = wshShell.ExpandEnvironmentStrings("%PROGRAMFILES%")

' Nagios helper functions
strNagiosLib = strProgramFilesDir & "\NSClient++\scripts\lib\NagiosPlugins.vbs"
If Not fso.FileExists(strNagiosLib) Then
    WScript.Echo("NSCP/NSClient VBS Library File (" + strNagiosLib + ") does not exist, please check/adjust path!")
    Wscript.Quit(3)
Else
    Include strNagiosLib
End If  

' Arguments
strComputer = WScript.Arguments.Item(0)

' Default return, not so nice to assume OK..
return_code = 0
return_msg = "Everythings fine"

' Create WMI object
Set objWMIService = GetObject("winmgmts:\\" & strComputer & "\root\cimv2")

' Create the NagiosPlugin object
Set np = New NagiosPlugin

' Fetch all jobs with status error
Set Result = objWMIService.ExecQuery("Select * From Win32_PrintJob Where Status = 'Error'")

For Each instance In Result
	' automatic job kill
	If killjob = True Then
		instance.Delete_
	Else
		' JobId is attached to "caption, description and name" thus we want to split and accessible with printerName(1)
		printerName = Split(instance.Caption,",")
		' if job should not be automatically killed, print critical and printer name
		failedPrinterStr = failedPrinterStr & " " & Chr(34) & printerName(0) & Chr(34)
		return_code = 2
	End If
next

If return_code > 0 Then
	return_msg = "Job Errors on printer " & failedPrinterStr
End If

' Nice Exit with msg and exitcode
np.nagios_exit return_msg, return_code


Sub Include( cNameScript )
    Set oFile = fso.OpenTextFile( cNameScript )
    ExecuteGlobal oFile.ReadAll()
    oFile.Close
End Sub
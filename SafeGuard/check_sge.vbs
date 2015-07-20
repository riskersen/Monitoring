' COPYRIGHT:
'
' This software is Copyright (c) 2015 Oliver Skibbe
'                                <oliskibbe@gmail.com>
'      (Except where explicitly superseded by other copyright notices)
'
' LICENSE:
'
' This program is free software: you can redistribute it and/or modify
'    it under the terms of the GNU General Public License as published by
'    the Free Software Foundation, either version 3 of the License, or
'    (at your option) any later version.
'
'    This program is distributed in the hope that it will be useful,
'    but WITHOUT ANY WARRANTY; without even the implied warranty of
'    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
'    GNU General Public License for more details.
'
'    You should have received a copy of the GNU General Public License
'    along with this program.  If not, see <http://www.gnu.org/licenses/>.
'
'    Dieses Programm ist Freie Software: Sie können es unter den Bedingungen
'    der GNU General Public License, wie von der Free Software Foundation,
'    Version 3 der Lizenz oder (nach Ihrer Wahl) jeder neueren
'    veröffentlichten Version, weiterverbreiten und/oder modifizieren.
'
'    Dieses Programm wird in der Hoffnung, dass es nützlich sein wird, aber
'    OHNE JEDE GEWÄHRLEISTUNG, bereitgestellt; sogar ohne die implizite
'    Gewährleistung der MARKTFÄHIGKEIT oder EIGNUNG FÜR EINEN BESTIMMTEN ZWECK.
'    Siehe die GNU General Public License für weitere Details.
'
'    Sie sollten eine Kopie der GNU General Public License zusammen mit diesem
'    Programm erhalten haben. Wenn nicht, siehe <http://www.gnu.org/licenses/>.
'
' 
' PUPROSE: this plugin checks safeguard enterprise web service for overall state
' AUTHOR: Oliver Skibbe oliskibbe@gmail.com
' DATE: 2015-07-20


' Required Variables
Const PROGNAME = "check_sge"
Const VERSION = "1.0.0"

' Nagios helper functions
'' NagiosPlugins.vbs is included via wrapper.vbs
'nsclientDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
'Include nsclientDir & "\NagiosPlugins.vbs"

' Create the NagiosPlugin object
'' NagiosPlugins.vbs is included via wrapper.vbs
Set np = New NagiosPlugin
Set WshShell = WScript.CreateObject("WScript.Shell")
Set xmlDoc = CreateObject("Msxml2.DOMDocument")
Set objFSO = CreateObject("Scripting.FileSystemObject") 

' get xml
Set oXMLHTTP = CreateObject("Msxml2.ServerXMLHTTP.3.0")
oXMLHTTP.SetOption 2, oXMLHTTP.GetOption(2) - SXH_SERVER_CERT_IGNORE_ALL_SERVER_ERRORS
oXMLHTTP.Open "POST", "http://localhost/SGNSRV/Trans.asmx/CheckConnection", False
oXMLHTTP.setRequestHeader "Content-Type", "application/x-www-form-urlencoded"
oXMLHTTP.Send ""

' Ugly, but we have to build a Tempfile, cause SafeGuard Enterprise does not provide a valid xml file
' Sophos Support: might be fixed in 6.20
' Update 2015-07-20: still not fixed in 7.0.1 :-(

' temporary file, 
strWinDir = WshShell.ExpandEnvironmentStrings("%WinDir%")
TEMPFILE = strWinDir & "\Temp\nagios_sge.xml"

' load fetched xml file
Set myFile = objFSO.CreateTextFile(TEMPFILE, True)
bodyStr = oXMLHTTP.responseXML.xml
' this is the magic, replace broken html stuff with real ">" & "<"
bodyXML = Replace(bodyStr, "&lt;", "<")
bodyXML = Replace(bodyXML, "&gt;", ">")
' save file
myFile.write(bodyXML)

' Website is responding and returns OK
If oXMLHTTP.Status = 200 Then	
	' Parse XML
	xmlDoc.load(TEMPFILE)
	
	If isObject(xmlDoc) Then
		' prepare output
		For Each x In xmlDoc.documentElement.selectNodes("//string/Dataroot")
			WebService = x.selectSingleNode("WebService").Text
			DBAuth = x.selectSingleNode("DBAuth").Text
			Info = "Database: " & x.selectSingleNode("Info/Database").Text
			Info = Info & vbcrlf & "DBServer: " & x.selectSingleNode("Info/Server").Text
			Info = Info & vbcrlf & "DBVersion: " & x.selectSingleNode("Info/Version").Text
			Info = Info & vbcrlf & "DBOwner: " & x.selectSingleNode("Info/Owner").Text
			Info = Info & vbcrlf & "DBConnectionInfo: " & x.selectSingleNode("Info/ConnectionInfo").Text
		Next
		
		If WebService = "OK" And DBAuth = "OK" Then
			return_code = OK
			return_msg = "Everything's fine!"
		Else
			return_code = CRITICAL
			return_msg = "Something happened!"
		End If ' end if webserver and dbauth
		' prepare return msg
		return_msg = return_msg & " WebService: " & WebService & " DBAuth: " & DBAuth & vbcrlf & Info				
	Else
		' XML not loaded
		MsgBox("XML konnte nicht gelesen werden")
		return_code = CRITICAL
		return_msg = "XML konnte nicht gelesen werden"
	End If ' end if xml load
Else 
' Something broken
	MsgBox("Error: " & oXMLHTTP.Status)
	return_code = CRITICAL
	return_msg = "Webservice konnte nicht abgefragt werden, Status: " & oXMLHTTP.Status
End If ' end if Webservice status 200 (OK)

' exit
np.nagios_exit return_msg, return_code

' helper for including nagios lib
Sub Include( cNameScript )
    Set oFS = CreateObject("Scripting.FileSystemObject")		
    Set oFile = oFS.OpenTextFile( cNameScript )
    ExecuteGlobal oFile.ReadAll()
    oFile.Close
End Sub
' EOF

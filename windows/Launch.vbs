' Starts Convert.ps1 with no console window flashing up.
' Usage: Launch.vbs "<file>" ["<target format>"]
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
If WScript.Arguments.Count = 0 Then WScript.Quit
folder = fso.GetParentFolderName(WScript.ScriptFullName)
targetArg = ""
If WScript.Arguments.Count >= 2 Then targetArg = " -Target """ & WScript.Arguments(1) & """"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & folder & "\Convert.ps1""" & targetArg & " """ & WScript.Arguments(0) & """"
sh.Run cmd, 0, False

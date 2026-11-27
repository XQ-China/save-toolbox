Set fso = CreateObject("Scripting.FileSystemObject")
p = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -File """ & p & "\save-toolbox.ps1""", 0, False
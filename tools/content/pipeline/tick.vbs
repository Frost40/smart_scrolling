Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
shell.Run "cmd.exe /c """ & files.BuildPath(files.GetParentFolderName(WScript.ScriptFullName), "tick.cmd") & """", 0, True

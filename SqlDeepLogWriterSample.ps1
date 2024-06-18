Using module .\SqlDeepLogWriterEnums.psm1
Import-Module "$PSScriptRoot\SqlDeepLogWriter.psm1"

$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "Test" -LogToConsole -LogToFile -LogFilePath "U:\Audit\LogTest_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[Events]"
$myLogWriter.Write("Testing process started...", [LogType]::INF) 
$myLogWriter.Write("Testing process started...", [LogType]::WRN) 
$myLogWriter.Write("Testing process started...", [LogType]::ERR,$true) 
$myLogWriter.ArchiveLogFilesToZipFile($null,[ArchiveTimeScale]::ByMonth,2,5,$true) #   Archive all log files (except last 2 files) to a zip file (a zip file for each year) inside current log directoy and remove archived logs
$myLogWriter.DeleteArchiveFiles($null,[ArchiveTimeScale]::ByMonth,2) #  Remove archive yearly zipped files (except last 2 zip files)
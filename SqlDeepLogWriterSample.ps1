Using module .\SqlDeepLogWriterEnums.psm1
Import-Module "$PSScriptRoot\SqlDeepLogWriter.psm1"

$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "Test" -LogToConsole -LogToFile -LogFilePath "U:\Audit\LogTest_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[Events]"
$myLogWriter.Write("Testing process started...", [LogType]::INF) 
$myLogWriter.Write("Testing process started...", [LogType]::WRN) 
$myLogWriter.Write("Testing process started...", [LogType]::ERR,$true) 
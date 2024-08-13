Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepBackupShipping.psm1


$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "BackupShipping" -LogToConsole -LogToFile -LogFilePath "C:\Databases\Audit\BackupShipping_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[Events]"
<#
$myBackupShipping=New-BackupShipping -SourceInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -
# -CentralTempInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -CurrentInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=SqlDeep;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -AllowedUserConnectionsJson $myAllowedUserConnectionsJson -AllowedServiceConnectionsJson $myAllowedServiceConnectionsJson -LogWrite $myLogWriter -Verbose
#>
$myBackupShipping=[BackupShipping]::new()
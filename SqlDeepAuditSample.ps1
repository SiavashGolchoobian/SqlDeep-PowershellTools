Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepAudit.psm1

[string]$myAllowedServiceConnectionsJson='
[
    {
        "LoginName":"SqlDeep\\SQL_ServiceGMSA$",
        "PersonnelIdentification":"",
        "ClientNamePattern":"%"
    },
    {
        "LoginName":"SqlDeep\\SQL_AgentGMSA$",
        "PersonnelIdentification":"",
        "ClientNamePattern":"%"
    }
]
'
[string]$myAllowedUserConnectionsJson='
[
    {
        "LoginName":"SqlDeep\\Admin",
        "PersonnelIdentification":"450986",
        "ClientNamePattern":"DB-%",
        "ClientIpPattern":"172.20.7%"
    },
    {
        "LoginName":"SqlDeep\\Expert",
        "PersonnelIdentification":"467620",
        "ClientNamePattern":"DB-%",
        "ClientIpPattern":"172.20.7%"
    }
]
'
#SqlSysAdminAudit
$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "SqlSysAdminAudit" -LogToConsole -LogToFile -LogFilePath "U:\Audit\SqlSysAdminAudit_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[Events]"
$mySqlSysAdminAudit=New-SqlSysAdminAuditByJsonConnSpec -LimitEventLogScanToRecentMinutes 5 -CentralTempInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -CurrentInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=SqlDeep;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -AllowedUserConnectionsJson $myAllowedUserConnectionsJson -AllowedServiceConnectionsJson $myAllowedServiceConnectionsJson -LogWrite $myLogWriter -Verbose
$mySqlSysAdminAudit.AnalyzeEvents()

#OsLoginAudit
$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "OsLoginAudit" -LogToConsole -LogToFile -LogFilePath "U:\Audit\OsLoginAudit_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[Events]"
$myOsLoginAudit=New-OsLoginAuditByJsonConnSpec -LimitEventLogScanToRecentMinutes 5 -CentralTempInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -CurrentInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=SqlDeep;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -AllowedUserConnectionsJson $myAllowedUserConnectionsJson -AllowedServiceConnectionsJson $myAllowedServiceConnectionsJson -LogWrite $myLogWriter -Verbose
$myOsLoginAudit.AnalyzeEvents()
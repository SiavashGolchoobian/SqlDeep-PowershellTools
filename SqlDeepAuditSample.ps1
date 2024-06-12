Import-Module "$PSScriptRoot\SqlDeepAudit.psm1"
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

$mySqlSysAdminAudit=New-SqlSysAdminAuditByJsonConnSpec -LimitEventLogScanToRecentMinutes 5 -CentralTempInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -CurrentInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=SqlDeep;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -AllowedUserConnectionsJson $myAllowedUserConnectionsJson -AllowedServiceConnectionsJson $myAllowedServiceConnectionsJson -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogFilePath "U:\Install\Scripts\Ocasions\SqlDeep-Tools\Test_{Date}.txt" -Verbose
$mySqlSysAdminAudit.AnalyzeEvents()

$myOsLoginAudit=New-OsLoginAuditByJsonConnSpec -LimitEventLogScanToRecentMinutes 5 -CentralTempInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -CurrentInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=SqlDeep;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -AllowedUserConnectionsJson $myAllowedUserConnectionsJson -AllowedServiceConnectionsJson $myAllowedServiceConnectionsJson -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SqlDeep.local\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogFilePath "U:\Install\Scripts\Ocasions\SqlDeep-Tools\Test_{Date}.txt" -Verbose
$myOsLoginAudit.AnalyzeEvents()
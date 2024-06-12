Using module .\SqlDeepLogWriterEnums.psm1
Import-Module "$PSScriptRoot\SqlDeepLogWriter.psm1"

Class ConnectionSpecification{
    [string]$LoginName
    [string]$PersonnelIdentification
    [string]$ClientNamePattern
    [string]$ClientIpPattern

    ConnectionSpecification ([string]$LoginName){
        $this.Init($LoginName,$null,"%","%")
    }
    ConnectionSpecification ([string]$LoginName,[string]$PersonnelIdentification,[string]$ClientNamePattern){
        $this.Init($LoginName,$PersonnelIdentification,$ClientNamePattern,"%")
    }
    ConnectionSpecification ([string]$LoginName,[string]$PersonnelIdentification,[string]$ClientNamePattern,[string]$ClientIpPattern){
        $this.Init($LoginName,$PersonnelIdentification,$ClientNamePattern,$ClientIpPattern)
    }
    hidden Init([string]$LoginName,[string]$PersonnelIdentification,[string]$ClientNamePattern,[string]$ClientIpPattern){
        [string]$myPersonnelIdentification=""
        [string]$myClientNamePattern="%"
        [string]$myClientIpPattern="%"
        
        if ($null -ne $PersonnelIdentification -and $PersonnelIdentification.Trim().Length -eq 0){$myPersonnelIdentification=""}else{$myPersonnelIdentification=$PersonnelIdentification.Trim().ToUpper()}
        if ($null -ne $ClientNamePattern -and $ClientNamePattern.Trim().Length -eq 0){$myClientNamePattern="%"}else{$myClientNamePattern=$ClientNamePattern.Trim().ToUpper()}
        if ($null -ne $ClientIpPattern -and $ClientIpPattern.Trim().Length -eq 0){$myClientIpPattern="%"}else{$myClientIpPattern=$ClientIpPattern.Trim().ToUpper()}
        $this.LoginName=$LoginName.Trim().ToUpper()
        $this.PersonnelIdentification=$myPersonnelIdentification
        $this.ClientNamePattern=$myClientNamePattern
        $this.ClientIpPattern=$myClientIpPattern
    }
    #region Functions
    [string] ToSqlSysAdminAuditString(){
        [string]$myAnswer=$null
        $myAnswer="(N'" + $this.LoginName + "',N'"+ $this.PersonnelIdentification +"',N'"+ $this.ClientNamePattern +"')"
        return $myAnswer
    }
    [string] ToOsLoginAuditString(){
        [string]$myAnswer=$null
        $myAnswer="(N'" + $this.LoginName + "',N'" + $this.PersonnelIdentification + "',N'" + $this.ClientNamePattern + "',N'" + $this.ClientIpPattern + "')"
        return $myAnswer
    }
    #endregion
}
Class SecurityEvent{
    [string]$DateTime
    [string]$LoginName
    [string]$Instance
    [string]$ClientName
    [string]$ClientIp
    [string]$DomainName
    [string]$LoginType
    [string]$ImpersonationLevel

    SecurityEvent([string]$DateTime,[string]$LoginName,[string]$Instance,[string]$ClientName){
        $this.Init($DateTime,$LoginName,$Instance,$ClientName,$null,$null,$null,$null)
    }
    SecurityEvent([string]$DateTime,[string]$LoginName,[string]$Instance,[string]$ClientName,[string]$ClientIp,[string]$DomainName,[string]$LoginType,[string]$ImpersonationLevel){
        $this.Init($DateTime,$LoginName,$Instance,$ClientName,$ClientIp,$DomainName,$LoginType,$ImpersonationLevel)
    }
    hidden Init ([string]$DateTime,[string]$LoginName,[string]$Instance,[string]$ClientName,[string]$ClientIp,[string]$DomainName,[string]$LoginType,[string]$ImpersonationLevel){
        $this.DateTime=$DateTime
        $this.LoginName=$LoginName.Trim().ToUpper()
        $this.Instance=$Instance.Trim().ToUpper()
        $this.ClientName=$ClientName.Trim().ToUpper()
        $this.ClientIp=$ClientIp.Trim()
        $this.DomainName=$DomainName.Trim().ToUpper()
        $this.LoginType=$LoginType.Trim().ToUpper()
        $this.ImpersonationLevel=$ImpersonationLevel.Trim().ToUpper()
    }
}
Class SqlSysAdminAudit{
    [int]$LimitEventLogScanToRecentMinutes
    [string]$CentralTempInstanceConnectionString
    [string]$CurrentInstanceConnectionString
    [string]$LogInstanceConnectionString
    [string]$LogTableName="[dbo].[Events]"
    [string]$LogFilePath
    [ConnectionSpecification[]]$AllowedUserConnections
    [ConnectionSpecification[]]$AllowedServiceConnections
    hidden [SecurityEvent[]]$SecurityEvents
    hidden [datetime]$ScanStartTime
    hidden [System.Object]$LogWriter

    SqlSysAdminAudit([string]$CentralTempInstanceConnectionString,[string]$CurrentInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[string]$LogInstanceConnectionString,[string]$LogTableName,[string]$LogFilePath){
        $this.Init(10,$CentralTempInstanceConnectionString,$CurrentInstanceConnectionString,$AllowedUserConnections,$AllowedServiceConnections,$LogInstanceConnectionString,$LogTableName,$LogFilePath)
    }
    SqlSysAdminAudit([int]$LimitEventLogScanToRecentMinutes,[string]$CentralTempInstanceConnectionString,[string]$CurrentInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[string]$LogInstanceConnectionString,[string]$LogTableName,[string]$LogFilePath){
        $this.Init($LimitEventLogScanToRecentMinutes,$CentralTempInstanceConnectionString,$CurrentInstanceConnectionString,$AllowedUserConnections,$AllowedServiceConnections,$LogInstanceConnectionString,$LogTableName,$LogFilePath)
    }
    hidden Init([int]$LimitEventLogScanToRecentMinutes,[string]$CentralTempInstanceConnectionString,[string]$CurrentInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[string]$LogInstanceConnectionString,[string]$LogTableName,[string]$LogFilePath){
        $this.LimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
        $this.CentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
        $this.CurrentInstanceConnectionString=$CurrentInstanceConnectionString
        $this.AllowedUserConnections=$AllowedUserConnections
        $this.AllowedServiceConnections=$AllowedServiceConnections
        $this.LogInstanceConnectionString=$LogInstanceConnectionString
        $this.LogTableName=$LogTableName
        $this.LogFilePath=$LogFilePath
        $this.SecurityEvents=$null
    }

    #region Functions
    hidden [void]CollectEvents(){
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [string]$myNonAdminLoginsQuery = "
            --Get Windows Group Logins/members
            SET NOCOUNT ON;
            DECLARE @myGroupName sysname
            CREATE TABLE #myDomainGroupMembers ([account_name] sysname, [type] Char(8), [privilege] Char(9), [mapped login name] sysname, [permission path] sysname)
            DECLARE myDomainGroups CURSOR FOR 
            SELECT
                UPPER([myLogins].[name]) AS GroupName
            FROM
                master.sys.server_principals AS myLogins
            WHERE
                IS_SRVROLEMEMBER('sysadmin',[myLogins].[name]) = 0
                AND [myLogins].[type] IN ('G')
        
            OPEN myDomainGroups
            FETCH NEXT FROM myDomainGroups 
            INTO @myGroupName
            WHILE @@FETCH_STATUS = 0
            BEGIN
                INSERT INTO #myDomainGroupMembers EXEC master..xp_logininfo @acctname =@myGroupName, @option = 'members'
                FETCH NEXT FROM myDomainGroups 
                INTO @myGroupName
            END 
            CLOSE myDomainGroups;
            DEALLOCATE myDomainGroups;
        
            --Get Regular Logins
            SELECT
                UPPER([myLogins].[name]) AS LoginName
            FROM
                master.sys.server_principals AS myLogins
            WHERE
                IS_SRVROLEMEMBER('sysadmin',[myLogins].[name]) = 0
                AND [myLogins].[type] NOT IN ('C','R','G')
            UNION
            --Get Group Logins
            SELECT
                UPPER([myGroupMembers].[account_name]) AS LoginName
            FROM
                master.sys.server_principals AS myGroups
                INNER JOIN #myDomainGroupMembers AS myGroupMembers ON UPPER([myGroups].[name])=UPPER([myGroupMembers].[permission path])
            WHERE
                IS_SRVROLEMEMBER('sysadmin',[myGroups].[name]) = 0
                AND [myGroups].[type] IN ('G')
                AND ISNULL([myGroupMembers].[privilege],'') <> 'admin'
            DROP TABLE #myDomainGroupMembers 
        "
        try{
            $this.LogWriter.Write("Extract relative Windows Events.",[LogType]::INF)
            $this.ScanStartTime=(Get-Date).AddMinutes((-1*[Math]::Abs($this.LimitEventLogScanToRecentMinutes)));
            [System.Data.DataRow[]]$myNonAdmins=$null
            [System.Collections.ArrayList]$mySecurityEventCollection=$null
            $mySecurityEventCollection=[System.Collections.ArrayList]::new()
            $this.LogWriter.Write("Specify sql server non-admin logins.",[LogType]::INF)
            $myNonAdmins = Invoke-Sqlcmd -ConnectionString ($this.CurrentInstanceConnectionString) -Query $myNonAdminLoginsQuery -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            $this.LogWriter.Write(("Retrive only admin logins from Windows Events from " + $this.ScanStartTime.ToString() + " through " + (Get-Date).ToString()),[LogType]::INF)
            $myEvents = (Get-WinEvent -FilterHashtable @{
                LogName='Application'
                ProviderName='MSSQL$NODE'
                StartTime=$this.ScanStartTime
                Id=33205} `
                | Where-Object {$_.Message -ilike "*action_id:LGIS*server_principal_name:*server_instance_name:*host_name:*" } `
                | Where-Object {$_.Message -match "(\nserver_principal_name:(?<login>.+))+(.|\n)*(\nserver_instance_name:(?<instance>.+))+(.|\n)*(\nhost_name:(?<client>.+))" } `
                | Where-Object {$matches['login'].Trim().ToUpper() -notin $this.AllowedServiceConnections.LoginName } `
                | Where-Object {$matches['login'].Trim().ToUpper() -notin $myNonAdmins.LoginName } `
                | ForEach-Object {$mySecurityEventCollection.Add([SecurityEvent]::New($_.TimeCreated,$matches['login'],$matches['instance'],$matches['client']))}
                )
            if ($null -ne $myEvents) {
                $this.SecurityEvents=$mySecurityEventCollection.ToArray([SecurityEvent])
                $this.LogWriter.Write("There is "+ $this.SecurityEvents.Count.ToString()+" Admin login events found in Windows Events.",[LogType]::INF)
            } else {
                $this.LogWriter.Write("There is no Admin login event found in Windows Events.",[LogType]::INF)
            }
            $this.LogWriter.Write("Admin logins retrived from Windows Events.",[LogType]::INF)
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            $this.SecurityEvents.Clear()
        }
    }
    hidden [void]SaveEvents(){
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write("Insert Security Events into SQL table.",[LogType]::INF)
            ForEach ($myEvent in $this.SecurityEvents) {
                [string]$myInserEventCommand="
                USE [Tempdb];
                DECLARE @BatchInsertTime DateTime;
                DECLARE @myTime DateTime;
                DECLARE @myLogin sysname;
                DECLARE @myInstance nvarchar(256);
                DECLARE @myClientName nvarchar(256);
        
                SET @BatchInsertTime=CAST(N'"+$this.ScanStartTime.ToString()+"' AS DATETIME);
                SET @myTime=CAST(N'"+$myEvent.DateTime+"' AS DATETIME);
                SET @myLogin=N'"+$myEvent.LoginName+"';
                SET @myInstance=N'"+$myEvent.Instance+"';
                SET @myClientName=N'"+$myEvent.ClientName+"';
        
                IF OBJECT_ID('SqlLoginRecords') IS NULL
                BEGIN
                    CREATE TABLE [dbo].[SqlLoginRecords] ([Id] bigint identity Primary Key, [BatchInsertTime] DateTime NOT NULL, [Time] DateTime NOT NULL, [Login] nvarchar(128) NOT NULL, [Instance] nvarchar(256) NOT NULL, [ClientName] nvarchar(256));
                    CREATE INDEX NCIX_dbo_SqlLoginRecords_Instance ON [dbo].[SqlLoginRecords] ([Instance],[BatchInsertTime]) WITH (DATA_COMPRESSION=PAGE,FILLFACTOR=85);
                    CREATE INDEX NCIX_dbo_SqlLoginRecords_LoginTime ON [dbo].[SqlLoginRecords] ([Login],[Time]) WITH (DATA_COMPRESSION=PAGE,FILLFACTOR=85);
                END
        
                INSERT INTO [dbo].[SqlLoginRecords] ([BatchInsertTime],[Time],[Login],[Instance],[ClientName]) VALUES (@BatchInsertTime,@myTime,@myLogin,@myInstance,@myClientName);
                "
                try{
                    Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myInserEventCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
                }Catch{
                    $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
                }
            }
        }else{
            $this.LogWriter.Write("Insert Security Events into SQL table: there is nothing",[LogType]::INF)
        }
    }
    hidden [void]CleanEvents(){
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write("Clean old events from temporary table.",[LogType]::INF)
            [string]$myValidateEventCommand="
                DECLARE @BatchInsertTime DateTime;
                DECLARE @myInstance nvarchar(256);
                SET @BatchInsertTime=CAST(N'"+$this.ScanStartTime.ToString()+"' AS DATETIME);
                SET @myInstance=N'"+$this.SecurityEvents[0].Instance+"';
        
                DELETE [dbo].[SqlLoginRecords] WHERE [Instance]=@myInstance AND [BatchInsertTime] < @BatchInsertTime;
                "
            Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myValidateEventCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
            $this.LogWriter.Write("Events cleaned.",[LogType]::INF)
        }else{
            $this.LogWriter.Write("Clean old events from temporary table: There is nothing",[LogType]::INF)
        }
    }
    hidden [void]AnalyzeSavedEvents(){
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write("Analyze saved security events", [LogType]::INF)
            [string]$myKnownListCommand=""
            [string]$myAnalyzeEventCommand=""
            [string]$myEventSource=$this.SecurityEvents[0].Instance
            
            $this.LogWriter.Write(("Detected event source is " + $myEventSource),[LogType]::INF)
            if($null -ne $this.AllowedUserConnections -and $this.AllowedUserConnections.Count -gt 0){
                $this.LogWriter.Write(("There is " + $this.AllowedUserConnections.Count.ToString() + " AllowedUsers specified."),[LogType]::INF)
                $myKnownListCommand="INSERT INTO @myKnownList ([Login],[PersonelID],[ClientName]) VALUES "
                foreach ($myConnection in $this.AllowedUserConnections){
                    $myKnownListCommand+=$myConnection.ToSqlSysAdminAuditString()+","
                }
                if ($myKnownListCommand[-1] -eq ","){$myKnownListCommand=$myKnownListCommand.Substring(0,$myKnownListCommand.Length-1)} else {$myKnownListCommand=""}
            }else{
                $this.LogWriter.Write(("There is not any AllowedUsers specified."),[LogType]::INF)
            }

            $myAnalyzeEventCommand="
                DECLARE @myInstance nvarchar(256)
                DECLARE @myCurrent DATETIME;
                DECLARE @myDummeyDate DATETIME;
                DECLARE @myKnownList TABLE ([Login] nvarchar(128), [PersonelID] bigint, [ClientName] nvarchar(256))
                DECLARE @myLoginStat TABLE ([Login] nvarchar(128), [ClientName] nvarchar(256), [StartDateTime] DateTime, [FinishDateTime] DateTime, [StartTime] Time(0), [FinishTime] Time(0), [StartDateJalali] nvarchar(10), [FinishDateJalali] nvarchar(10), [PersonelID] bigint, [LoginAttempts] bigint);
        
                SET @myInstance=N'"+$myEventSource+"';
                SET @myCurrent=GETDATE();
                SET @myDummeyDate=CAST(@myCurrent AS DATE)
                IF OBJECT_ID('SqlLoginRecords') IS NOT NULL
                BEGIN
                    " + $myKnownListCommand + "
                    INSERT INTO @myLoginStat ([Login],[ClientName],[StartDateTime],[FinishDateTime],[StartTime],[FinishTime],[StartDateJalali],[FinishDateJalali],[LoginAttempts],[PersonelID])
                    SELECT
                        [myLogs].[Login],
                        [myLogs].[ClientName],
                        [myLogs].[StartTime],
                        [myLogs].[FinishTime],
                        CAST([myLogs].[StartTime] AS Time(0)),
                        CAST([myLogs].[FinishTime] AS Time(0)),
                        [SqlDeep].[dbo].[dbafn_miladi2shamsi]([myLogs].[StartTime],'/'),
                        [SqlDeep].[dbo].[dbafn_miladi2shamsi]([myLogs].[FinishTime],'/'),
                        [myLogs].[LoginAttempts],
                        [myKnownList].[PersonelID]
                    FROM
                        (
                            SELECT 
                                [myRawLog].[Login],
                                [myRawLog].[ClientName],
                                MIN([myRawLog].[Time]) AS StartTime,
                                MAX([myRawLog].[Time]) AS FinishTime,
                                Count(1) AS LoginAttempts
                            FROM 
                                [dbo].[SqlLoginRecords] AS myRawLog WITH (READPAST)
                            WHERE
                                [myRawLog].[Instance]=@myInstance
                            GROUP BY
                                [myRawLog].[Login],
                                [myRawLog].[ClientName]
                        ) AS myLogs
                        LEFT OUTER JOIN @myKnownList AS myKnownList ON [myLogs].[Login]=[myKnownList].[Login] AND [myLogs].[ClientName] LIKE [myKnownList].[ClientName]
        
                    SELECT 
                        [myLoginStat].[StartDateTime] AS [EventTimeStamp],
                        N'Unexpected Login as sysadmin from '+ [myLoginStat].[ClientName] +N' client with ' + [myLoginStat].[Login] + N' login between ' + CAST([myLoginStat].[StartTime] AS nvarchar(10)) + N' and ' + CAST([myLoginStat].[FinishTime] AS nvarchar(10)) + N' for ' + CAST([myLoginStat].[LoginAttempts] AS nvarchar(10)) + N' times.' AS [Description]
                    FROM 
                        @myLoginStat AS myLoginStat
                        OUTER APPLY (
                            SELECT
                                [myKasraStat].[Date],
                                [myKasraStat].[InTime],
                                CASE WHEN [myKasraStat].[InTime]=[myKasraStat].[OutTime] THEN CAST(@myCurrent AS TIME(0)) ELSE [myKasraStat].[OutTime] END AS OutTime
                            FROM
                                (
                                SELECT
                                    [Date],
                                    MIN(CAST(DATEADD(MINUTE,[Time],@myDummeyDate) AS TIME(0))) AS [InTime],
                                    MAX(CAST(DATEADD(MINUTE,[Time],@myDummeyDate) AS TIME(0))) AS [OutTime]
                                FROM 
                                    [LSNRKASRA].[framework].[Att].[Attendance]
                                WHERE
                                    PersonelID=[myLoginStat].[PersonelID] AND [DATE] BETWEEN [myLoginStat].[StartDateJalali] COLLATE Arabic_CI_AS AND [myLoginStat].[FinishDateJalali] COLLATE Arabic_CI_AS
                                GROUP BY
                                    [Date]
                                ) AS myKasraStat
                        ) AS myKasraSummery
                    WHERE
                        [myLoginStat].[PersonelID] IS NULL			--From unknown Admins or known admins from unknown clients
                        OR											--Known Admins
                        (
                            [myLoginStat].[PersonelID] IS NOT NULL
                            AND 
                                (
                                NOT ([myLoginStat].[StartTime] BETWEEN [myKasraSummery].[InTime] AND [myKasraSummery].[OutTime])
                                OR
                                NOT ([myLoginStat].[FinishTime] BETWEEN [myKasraSummery].[InTime] AND [myKasraSummery].[OutTime])
                                OR
                                [myKasraSummery].[Date] IS NULL		--Off day
                                )
                        )
                 END
                "
            try{
                [System.Data.DataRow[]]$myRecords=$null
                $this.LogWriter.Write("Executing query to detect login attemts in unusual times.",[LogType]::INF)
                $myRecords=Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myAnalyzeEventCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
                $this.LogWriter.Write("Query to detect login attemts in unusual times executed.",[LogType]::INF)
                if ($null -ne $myRecords){
                    $this.LogWriter.Write("There is "+ $myRecords.Count.ToString()+" Alarms found.",[LogType]::INF)
                    $myAlarmWriter=New-LogWriter -EventSource ($myEventSource) -Module "SqlSysAdminLogin" -LogToConsole -LogToFile -LogFilePath ($this.LogFilePath) -LogToTable -LogInstanceConnectionString ($this.LogInstanceConnectionString) -LogTableName ($this.LogTableName)
                    foreach ($myRecord in $myRecords){
                        $myAlarmWriter.Write($myRecord.Description, [LogType]::WRN, $false, $true, $myRecord.EventTimeStamp.ToString())
                    }
                }else{
                    $this.LogWriter.Write("There is no Alarms found.",[LogType]::INF)
                }
            }catch{
                $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            }
        } ELSE {
            Write-Host "Analyze Event Logs: There is nothing"
        }
    }
    [void] EnableSqlLoginAudit(){
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [string]$myCommand="
        USE [master];
        CREATE SERVER AUDIT [SqlDeep_TrackLogins] TO APPLICATION_LOG WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
        CREATE SERVER AUDIT SPECIFICATION SqlDeep_TrackAllLogins
        FOR SERVER AUDIT SqlDeep_TrackLogins
            ADD (FAILED_LOGIN_GROUP),
            ADD (SUCCESSFUL_LOGIN_GROUP),
            ADD (AUDIT_CHANGE_GROUP),
            ADD (DATABASE_PERMISSION_CHANGE_GROUP),
            ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
            ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
            ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP)
        WITH (STATE = ON);
        ALTER SERVER AUDIT SqlDeep_TrackLogins WITH (STATE = ON);
        "
        try{
            $this.LogWriter.Write("Enabling SqlDeep_TrackLogins extended event on SQL Server instance.",[LogType]::INF)
            Invoke-Sqlcmd -ConnectionString $this.CurrentInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
            $this.LogWriter.Write("SqlDeep_TrackLogins extended event enabled.",[LogType]::INF)
        }catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
    }
    [void] AnalyzeEvents(){
        try {
            #--=======================Initial Log Modules
            Write-Verbose ("===== SqlSysAdminAudit process started. =====")
            $this.LogWriter=New-LogWriter -EventSource ($env:computername) -Module "SqlSysAdminAudit" -LogToConsole -LogToFile -LogFilePath ($this.LogFilePath) -LogToTable -LogInstanceConnectionString ($this.LogInstanceConnectionString) -LogTableName ($this.LogTableName)
            $this.LogWriter.Write("===== SqlSysAdminAudit process started... ===== ", [LogType]::INF) 
            $this.CollectEvents()       #-----Retrive Successful Logins
            $this.SaveEvents()          #-----Insert Event Logs to a table
            $this.CleanEvents()         #-----Clean Event old Logs
            $this.AnalyzeSavedEvents()  #-----Analyze Event Logs and send alert
        }catch{
            Write-Error ($_.ToString())
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }finally{
            Write-Verbose ("===== SqlSysAdminAudit finished. =====")
        }
        $this.LogWriter.Write("===== SqlSysAdminAudit process finished. ===== ", [LogType]::INF) 
    }
    #endregion
}

Class OsLoginAudit{
    [int]$LimitEventLogScanToRecentMinutes
    [string]$CentralTempInstanceConnectionString
    [string]$LogInstanceConnectionString
    [string]$LogTableName="[dbo].[Events]"
    [string]$LogFilePath
    [ConnectionSpecification[]]$AllowedUserConnections
    [ConnectionSpecification[]]$AllowedServiceConnections
    hidden [SecurityEvent[]]$SecurityEvents
    hidden [datetime]$ScanStartTime
    hidden [System.Object]$LogWriter

    OsLoginAudit([string]$CentralTempInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[string]$LogInstanceConnectionString,[string]$LogTableName,[string]$LogFilePath){
        $this.Init(10,$CentralTempInstanceConnectionString,$AllowedUserConnections,$AllowedServiceConnections,$LogInstanceConnectionString,$LogTableName,$LogFilePath)
    }
    OsLoginAudit([int]$LimitEventLogScanToRecentMinutes,[string]$CentralTempInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[string]$LogInstanceConnectionString,[string]$LogTableName,[string]$LogFilePath){
        $this.Init($LimitEventLogScanToRecentMinutes,$CentralTempInstanceConnectionString,$AllowedUserConnections,$AllowedServiceConnections,$LogInstanceConnectionString,$LogTableName,$LogFilePath)
    }
    hidden Init([int]$LimitEventLogScanToRecentMinutes,[string]$CentralTempInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[string]$LogInstanceConnectionString,[string]$LogTableName,[string]$LogFilePath){
        $this.LimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
        $this.CentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
        $this.AllowedUserConnections=$AllowedUserConnections
        $this.AllowedServiceConnections=$AllowedServiceConnections
        $this.LogInstanceConnectionString=$LogInstanceConnectionString
        $this.LogTableName=$LogTableName
        $this.LogFilePath=$LogFilePath
        $this.SecurityEvents=$null
    }
    #region Functions
    hidden [void]CollectEvents(){
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        try{
            $this.LogWriter.Write("Extract OS login Windows Events.",[LogType]::INF)
            $this.ScanStartTime=(Get-Date).AddMinutes((-1*[Math]::Abs($this.LimitEventLogScanToRecentMinutes)));
            [System.Collections.ArrayList]$mySecurityEventCollection=$null
            $mySecurityEventCollection=[System.Collections.ArrayList]::new()
            $this.LogWriter.Write(("Retrive only OS logins from Windows Events from " + $this.ScanStartTime.ToString() + " through " + (Get-Date).ToString()),[LogType]::INF)
            $myEvents = (Get-WinEvent -FilterHashtable @{
                LogName='Security'
                ProviderName='Microsoft-Windows-Security-Auditing'
                StartTime=$this.ScanStartTime
                Id=4624} `
                | Where-Object {$_.Message -match "(\n`tLogon\sType:\s`t(?<type>.+))+(.|\n)*(\nImpersonation\sLevel:\s`t(?<impersonation_level>.+))+(.|\n)*(\n`tAccount\sName:\s`t(?<login>.+))" } `
                | ForEach-Object {$mySecurityEventCollection.Add([SecurityEvent]::New($_.TimeCreated,$matches['login'].Trim().ToUpper(),$_.MachineName.Trim().ToUpper(),$_.Properties.Value[11].Trim().ToUpper(),$_.Properties.Value[18].Trim().ToUpper(),$_.Properties.Value[6].Trim().ToUpper(),$matches['type'].Trim().ToUpper(),$matches['impersonation_level'].Trim().ToUpper()))}
                )
            if ($null -ne $myEvents) {
                $this.SecurityEvents=$mySecurityEventCollection.ToArray([SecurityEvent]) | Where-Object {($_.DomainName.LastIndexOf(".") -ne -1 -and ($_.DomainName.Substring(0,$_.DomainName.LastIndexOf(".")) +"\"+$_.LoginName) -notin $this.AllowedServiceConnections) -or ($_.DomainName.LastIndexOf(".") -eq -1 -and ($_.DomainName+"\"+$_.LoginName) -notin $this.AllowedServiceConnections)}
                $this.LogWriter.Write("There is "+ $this.SecurityEvents.Count.ToString()+" disallowed OS login events found in Windows Events.",[LogType]::INF)
            } else {
                $this.LogWriter.Write("There is no OS login event found in Windows Events.",[LogType]::INF)
            }
            $this.LogWriter.Write("OS logins retrived from Windows Events.",[LogType]::INF)
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            $this.SecurityEvents.Clear()
        }
    
    }
    hidden [void]SaveEvents(){
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write("Insert Security Events into SQL table.",[LogType]::INF)
            ForEach ($myEvent in $this.SecurityEvents) {
                [string]$myInserEventCommand="
                USE [Tempdb];
                DECLARE @BatchInsertTime DateTime;
                DECLARE @myTime DateTime;
                DECLARE @myLogin sysname;
                DECLARE @myInstance nvarchar(256);
                DECLARE @myClientName nvarchar(256);
                DECLARE @myClientIp nvarchar(128);
                DECLARE @myDomain nvarchar(128);
                DECLARE @myLoginType nvarchar(128);
                DECLARE @myImpersonationLevel nvarchar(128);
        
                SET @BatchInsertTime=CAST(N'"+$this.ScanStartTime.ToString()+"' AS DATETIME);
                SET @myTime=CAST(N'"+$myEvent.DateTime+"' AS DATETIME);
                SET @myLogin=N'"+$myEvent.LoginName+"';
                SET @myInstance=N'"+$myEvent.Instance+"';
                SET @myClientName=N'"+$myEvent.ClientName+"';
                SET @myClientIp=N'"+$myEvent.ClientIp+"';
                SET @myDomain=N'"+$myEvent.DomainName+"';
                SET @myLoginType=N'"+$myEvent.LoginType+"';
                SET @myImpersonationLevel=N'"+$myEvent.ImpersonationLevel+"';
        
                IF OBJECT_ID('WinLoginRecords') IS NULL
                BEGIN
                    CREATE TABLE [dbo].[WinLoginRecords] ([Id] bigint identity Primary Key, [BatchInsertTime] DateTime NOT NULL, [Time] DateTime NOT NULL, [Login] nvarchar(128) NOT NULL, [Instance] nvarchar(256) NOT NULL, [ClientName] nvarchar(256), [ClientIp] nvarchar(128), [DomainName] nvarchar(128), [LoginType] nvarchar(128) NOT NULL, [ImpersonationLevel] nvarchar(128));
                    CREATE INDEX NCIX_dbo_WinLoginRecords_Instance ON [dbo].[WinLoginRecords] ([Instance],[BatchInsertTime]) WITH (DATA_COMPRESSION=PAGE,FILLFACTOR=85);
                    CREATE INDEX NCIX_dbo_WinLoginRecords_LoginTime ON [dbo].[WinLoginRecords] ([Login],[Time]) WITH (DATA_COMPRESSION=PAGE,FILLFACTOR=85);
                END
        
                INSERT INTO [dbo].[WinLoginRecords] ([BatchInsertTime],[Time],[Login],[Instance],[ClientName],[ClientIp],[DomainName],[LoginType],[ImpersonationLevel]) VALUES (@BatchInsertTime,@myTime,@myDomain+'\'+@myLogin,@myInstance,@myClientName,@myClientIp,@myDomain,@myLoginType,@myImpersonationLevel);
                "
                try{
                    Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myInserEventCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
                }Catch{
                    $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
                }
            }
        }else{
            $this.LogWriter.Write("Insert Security Events into SQL table: there is nothing",[LogType]::INF)
        }
    }
    hidden [void]CleanEvents(){
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write("Clean old events from temporary table.",[LogType]::INF)
            [string]$myValidateEventCommand="
                DECLARE @BatchInsertTime DateTime;
                DECLARE @myInstance nvarchar(256);
                SET @BatchInsertTime=CAST(N'"+$this.ScanStartTime.ToString()+"' AS DATETIME);
                SET @myInstance=N'"+$this.SecurityEvents[0].Instance+"';
        
                DELETE [dbo].[WinLoginRecords] WHERE [Instance]=@myInstance AND [BatchInsertTime] < @BatchInsertTime;
                "
            Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myValidateEventCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
            $this.LogWriter.Write("Events cleaned.",[LogType]::INF)
        }else{
            $this.LogWriter.Write("Clean old events from temporary table: There is nothing",[LogType]::INF)
        }
    }
    hidden [void]AnalyzeSavedEvents(){
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write("Analyze saved security events", [LogType]::INF)
            [string]$myKnownListCommand=""
            [string]$myAnalyzeEventCommand=""
            [string]$myEventSource=$this.SecurityEvents[0].Instance
            
            $this.LogWriter.Write(("Detected event source is " + $myEventSource),[LogType]::INF)
            if($null -ne $this.AllowedUserConnections -and $this.AllowedUserConnections.Count -gt 0){
                $this.LogWriter.Write(("There is " + $this.AllowedUserConnections.Count.ToString() + " AllowedUsers specified."),[LogType]::INF)
                $myKnownListCommand="INSERT INTO @myKnownList ([Login],[PersonelID],[ClientName],[ClientIp]) VALUES "
                foreach ($myConnection in $this.AllowedUserConnections){
                    $myKnownListCommand+=$myConnection.ToOsLoginAuditString()+","
                }
                if ($myKnownListCommand[-1] -eq ","){$myKnownListCommand=$myKnownListCommand.Substring(0,$myKnownListCommand.Length-1)} else {$myKnownListCommand=""}
            }else{
                $this.LogWriter.Write(("There is not any AllowedUsers specified."),[LogType]::INF)
            }

            $myAnalyzeEventCommand="
                DECLARE @myInstance nvarchar(256)
                DECLARE @myCurrent DATETIME;
                DECLARE @myDummeyDate DATETIME;
                DECLARE @myKnownList TABLE ([Login] nvarchar(128), [PersonelID] bigint, [ClientName] nvarchar(256), [ClientIp] nvarchar(128))
                DECLARE @myLoginStat TABLE ([Login] nvarchar(128), [ClientName] nvarchar(256), [LoginType] nvarchar(128), [ImpersonationLevel] nvarchar(128), [StartDateTime] DateTime, [FinishDateTime] DateTime, [StartTime] Time(0), [FinishTime] Time(0), [StartDateJalali] nvarchar(10), [FinishDateJalali] nvarchar(10), [PersonelID] bigint, [LoginAttempts] bigint);
        
                SET @myInstance=N'"+$myEventSource+"';
                SET @myCurrent=GETDATE();
                SET @myDummeyDate=CAST(@myCurrent AS DATE)
                IF OBJECT_ID('WinLoginRecords') IS NOT NULL
                BEGIN
                    " + $myKnownListCommand + "
                    INSERT INTO @myLoginStat ([Login],[ClientName],[LoginType],[ImpersonationLevel],[StartDateTime],[FinishDateTime],[StartTime],[FinishTime],[StartDateJalali],[FinishDateJalali],[LoginAttempts],[PersonelID])
                    SELECT
                        [myLogs].[Login],
                        [myLogs].[ClientName]+'('+[myLogs].[ClientIp]+')',
                        [myLogs].[LoginType],
                        [myLogs].[ImpersonationLevel],
                        [myLogs].[StartTime],
                        [myLogs].[FinishTime],
                        CAST([myLogs].[StartTime] AS Time(0)),
                        CAST([myLogs].[FinishTime] AS Time(0)),
                        [SqlDeep].[dbo].[dbafn_miladi2shamsi]([myLogs].[StartTime],'/'),
                        [SqlDeep].[dbo].[dbafn_miladi2shamsi]([myLogs].[FinishTime],'/'),
                        [myLogs].[LoginAttempts],
                        [myKnownList].[PersonelID]
                    FROM
                        (
                            SELECT 
                                [myRawLog].[Login],
                                [myRawLog].[ClientName],
                                [myRawLog].[ClientIp],
                                [myRawLog].[LoginType],
                                [myRawLog].[ImpersonationLevel],
                                MIN([myRawLog].[Time]) AS StartTime,
                                MAX([myRawLog].[Time]) AS FinishTime,
                                Count(1) AS LoginAttempts
                            FROM 
                                [dbo].[WinLoginRecords] AS myRawLog WITH (READPAST)
                            WHERE
                                [myRawLog].[Instance]=@myInstance
                            GROUP BY
                                [myRawLog].[Login],
                                [myRawLog].[ClientName],
                                [myRawLog].[ClientIp],
                                [myRawLog].[LoginType],
                                [myRawLog].[ImpersonationLevel]
                        ) AS myLogs
                        LEFT OUTER JOIN @myKnownList AS myKnownList ON [myLogs].[Login]=[myKnownList].[Login] AND ([myLogs].[ClientName] LIKE [myKnownList].[ClientName] OR [myLogs].[ClientIp] LIKE [myKnownList].[ClientIp])
        
                    SELECT 
                        [myLoginStat].[StartDateTime] AS [EventTimeStamp],
                        N'Unexpected Windows Login from '+ [myLoginStat].[ClientName] +N' client with ' + [myLoginStat].[Login] + N' login between ' + CAST([myLoginStat].[StartTime] AS nvarchar(10)) + N' and ' + CAST([myLoginStat].[FinishTime] AS nvarchar(10)) + N' for ' + CAST([myLoginStat].[LoginAttempts] AS nvarchar(10)) + N' times. Impersonation is ' + [myLoginStat].[ImpersonationLevel] + ' and LogonType is ' + CAST([myLoginStat].[LoginType] AS NVARCHAR(10)) + '.' AS [Description]
                    FROM 
                        @myLoginStat AS myLoginStat
                        OUTER APPLY (
                            SELECT
                                [myKasraStat].[Date],
                                [myKasraStat].[InTime],
                                CASE WHEN [myKasraStat].[InTime]=[myKasraStat].[OutTime] THEN CAST(@myCurrent AS TIME(0)) ELSE [myKasraStat].[OutTime] END AS OutTime
                            FROM
                                (
                                SELECT
                                    [Date],
                                    MIN(CAST(DATEADD(MINUTE,[Time],@myDummeyDate) AS TIME(0))) AS [InTime],
                                    MAX(CAST(DATEADD(MINUTE,[Time],@myDummeyDate) AS TIME(0))) AS [OutTime]
                                FROM 
                                    [LSNRKASRA].[framework].[Att].[Attendance]
                                WHERE
                                    PersonelID=[myLoginStat].[PersonelID] AND [DATE] BETWEEN [myLoginStat].[StartDateJalali] COLLATE Arabic_CI_AS AND [myLoginStat].[FinishDateJalali] COLLATE Arabic_CI_AS
                                GROUP BY
                                    [Date]
                                ) AS myKasraStat
                        ) AS myKasraSummery
                    WHERE
                        [myLoginStat].[PersonelID] IS NULL			--From unknown Admins or known admins from unknown clients
                        OR											--Known Admins
                        (
                            [myLoginStat].[PersonelID] IS NOT NULL
                            AND 
                                (
                                NOT ([myLoginStat].[StartTime] BETWEEN [myKasraSummery].[InTime] AND [myKasraSummery].[OutTime])
                                OR
                                NOT ([myLoginStat].[FinishTime] BETWEEN [myKasraSummery].[InTime] AND [myKasraSummery].[OutTime])
                                OR
                                [myKasraSummery].[Date] IS NULL		--Off day
                                )
                        )
                 END
                "
            try{
                [System.Data.DataRow[]]$myRecords=$null
                $this.LogWriter.Write("Executing query to detect login attemts in unusual times.",[LogType]::INF)
                $myRecords=Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myAnalyzeEventCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
                $this.LogWriter.Write("Query to detect login attemts in unusual times executed.",[LogType]::INF)
                if ($null -ne $myRecords){
                    $this.LogWriter.Write("There is "+ $myRecords.Count.ToString()+" Alarms found.",[LogType]::INF)
                    $myAlarmWriter=New-LogWriter -EventSource ($myEventSource) -Module "OsLogin" -LogToConsole -LogToFile -LogFilePath ($this.LogFilePath) -LogToTable -LogInstanceConnectionString ($this.LogInstanceConnectionString) -LogTableName ($this.LogTableName)
                    foreach ($myRecord in $myRecords){
                        $myAlarmWriter.Write($myRecord.Description, [LogType]::WRN, $false, $true, $myRecord.EventTimeStamp.ToString())
                    }
                }else{
                    $this.LogWriter.Write("There is no Alarms found.",[LogType]::INF)
                }
            }catch{
                $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            }
        } ELSE {
            Write-Host "Analyze Event Logs: There is nothing"
        }
    }
    [void] AnalyzeEvents(){
        try {
            #--=======================Initial Log Modules
            Write-Verbose ("===== OsLoginAudit process started. =====")
            $this.LogWriter=New-LogWriter -EventSource ($env:computername) -Module "OsLoginAudit" -LogToConsole -LogToFile -LogFilePath ($this.LogFilePath) -LogToTable -LogInstanceConnectionString ($this.LogInstanceConnectionString) -LogTableName ($this.LogTableName)
            $this.LogWriter.Write("===== OsLoginAudit process started... ===== ", [LogType]::INF) 
            $this.CollectEvents()       #-----Retrive Successful Logins
            $this.SaveEvents()          #-----Insert Event Logs to a table
            $this.CleanEvents()         #-----Clean Event old Logs
            $this.AnalyzeSavedEvents()  #-----Analyze Event Logs and send alert
        }catch{
            Write-Error ($_.ToString())
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }finally{
            Write-Verbose ("===== OsLoginAudit finished. =====")
        }
        $this.LogWriter.Write("===== OsLoginAudit process finished. ===== ", [LogType]::INF) 
    }
    #endregion
}
#region Functions
Function New-SqlSysAdminAudit {
    Param(
        [Parameter(Mandatory=$false)][int]$LimitEventLogScanToRecentMinutes=10,
        [Parameter(Mandatory=$true)][string]$CentralTempInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$CurrentInstanceConnectionString,
        [Parameter(Mandatory=$true)][ConnectionSpecification[]]$AllowedUserConnections,
        [Parameter(Mandatory=$true)][ConnectionSpecification[]]$AllowedServiceConnections,
        [Parameter(Mandatory=$true)][string]$LogInstanceConnectionString,
        [Parameter(Mandatory=$false)][string]$LogTableName="[dbo].[Events]",
        [Parameter(Mandatory=$true)][string]$LogFilePath
    )
    Write-Verbose "Creating New-SqlSysAdminAudit"
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [string]$myCurrentInstanceConnectionString=$CurrentInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$AllowedUserConnections
    [ConnectionSpecification[]]$myAllowedServiceConnections=$AllowedServiceConnections
    [string]$myLogInstanceConnectionString=$LogInstanceConnectionString
    [string]$myLogTableName=$LogTableName
    [string]$myLogFilePath=$LogFilePath
    [SqlSysAdminAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myCurrentInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogInstanceConnectionString,$myLogTableName,$myLogFilePath)
    Write-Verbose "New-SqlSysAdminAudit Created"
}
Function New-SqlSysAdminAuditByJsonConnSpec {
    Param(
        [Parameter(Mandatory=$false)][int]$LimitEventLogScanToRecentMinutes=10,
        [Parameter(Mandatory=$true)][string]$CentralTempInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$CurrentInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$AllowedUserConnectionsJson,
        [Parameter(Mandatory=$true)][string]$AllowedServiceConnectionsJson,
        [Parameter(Mandatory=$true)][string]$LogInstanceConnectionString,
        [Parameter(Mandatory=$false)][string]$LogTableName="[dbo].[Events]",
        [Parameter(Mandatory=$true)][string]$LogFilePath
    )
    Write-Verbose "Creating New-SqlSysAdminAuditByJsonConnSpec"
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [string]$myCurrentInstanceConnectionString=$CurrentInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$null
    [ConnectionSpecification[]]$myAllowedServiceConnections=$null
    [string]$myLogInstanceConnectionString=$LogInstanceConnectionString
    [string]$myLogTableName=$LogTableName
    [string]$myLogFilePath=$LogFilePath
    [SqlSysAdminAudit]$myAnswer=$null

    try {
        $Null=@(
            [System.Collections.ArrayList]$myAllowedUserConnectionCollection=[System.Collections.ArrayList]::new()
            $myJsonOfAllowedUsers=ConvertFrom-Json -InputObject $AllowedUserConnectionsJson
            foreach($myJsonOfAllowedUser in $myJsonOfAllowedUsers) {
                $myAllowedUserConnectionCollection.Add([ConnectionSpecification]::New($myJsonOfAllowedUser.LoginName,$myJsonOfAllowedUser.PersonnelIdentification,$myJsonOfAllowedUser.ClientNamePattern))
            }
            $myAllowedUserConnections=$myAllowedUserConnectionCollection.ToArray([ConnectionSpecification])
        
            [System.Collections.ArrayList]$myAllowedServiceConnectionCollection=[System.Collections.ArrayList]::new()
            $myJsonOfAllowedServices=ConvertFrom-Json -InputObject $AllowedServiceConnectionsJson
            foreach($myJsonOfAllowedService in $myJsonOfAllowedServices) {
                $myAllowedServiceConnectionCollection.Add([ConnectionSpecification]::New($myJsonOfAllowedService.LoginName,$myJsonOfAllowedService.PersonnelIdentification,$myJsonOfAllowedService.ClientNamePattern))
            }
            $myAllowedServiceConnections=$myAllowedServiceConnectionCollection.ToArray([ConnectionSpecification])
        )
        $myAnswer=[SqlSysAdminAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myCurrentInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogInstanceConnectionString,$myLogTableName,$myLogFilePath)    
    }
    catch {
        Write-Verbose ($_.ToString())
    }
    Write-Verbose "New-SqlSysAdminAuditByJsonConnSpec Created"
    return $myAnswer
}
Function New-OsLoginAudit {
    Param(
        [Parameter(Mandatory=$false)][int]$LimitEventLogScanToRecentMinutes=10,
        [Parameter(Mandatory=$true)][string]$CentralTempInstanceConnectionString,
        [Parameter(Mandatory=$true)][ConnectionSpecification[]]$AllowedUserConnections,
        [Parameter(Mandatory=$true)][ConnectionSpecification[]]$AllowedServiceConnections,
        [Parameter(Mandatory=$true)][string]$LogInstanceConnectionString,
        [Parameter(Mandatory=$false)][string]$LogTableName="[dbo].[Events]",
        [Parameter(Mandatory=$true)][string]$LogFilePath
    )
    Write-Verbose "Creating New-OsLoginAudit"
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$AllowedUserConnections
    [ConnectionSpecification[]]$myAllowedServiceConnections=$AllowedServiceConnections
    [string]$myLogInstanceConnectionString=$LogInstanceConnectionString
    [string]$myLogTableName=$LogTableName
    [string]$myLogFilePath=$LogFilePath
    [OsLoginAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogInstanceConnectionString,$myLogTableName,$myLogFilePath)
    Write-Verbose "New-OsLoginAudit Created"
}
Function New-OsLoginAuditByJsonConnSpec {
    Param(
        [Parameter(Mandatory=$false)][int]$LimitEventLogScanToRecentMinutes=10,
        [Parameter(Mandatory=$true)][string]$CentralTempInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$AllowedUserConnectionsJson,
        [Parameter(Mandatory=$true)][string]$AllowedServiceConnectionsJson,
        [Parameter(Mandatory=$true)][string]$LogInstanceConnectionString,
        [Parameter(Mandatory=$false)][string]$LogTableName="[dbo].[Events]",
        [Parameter(Mandatory=$true)][string]$LogFilePath
    )
    Write-Verbose "Creating New-OsLoginAuditByJsonConnSpec"
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$null
    [ConnectionSpecification[]]$myAllowedServiceConnections=$null
    [string]$myLogInstanceConnectionString=$LogInstanceConnectionString
    [string]$myLogTableName=$LogTableName
    [string]$myLogFilePath=$LogFilePath
    [OsLoginAudit]$myAnswer=$null

    try {
        $Null=@(
            [System.Collections.ArrayList]$myAllowedUserConnectionCollection=[System.Collections.ArrayList]::new()
            $myJsonOfAllowedUsers=ConvertFrom-Json -InputObject $AllowedUserConnectionsJson
            foreach($myJsonOfAllowedUser in $myJsonOfAllowedUsers) {
                $myAllowedUserConnectionCollection.Add([ConnectionSpecification]::New($myJsonOfAllowedUser.LoginName,$myJsonOfAllowedUser.PersonnelIdentification,$myJsonOfAllowedUser.ClientNamePattern,$myJsonOfAllowedUser.ClientIpPattern))
            }
            $myAllowedUserConnections=$myAllowedUserConnectionCollection.ToArray([ConnectionSpecification])
        
            [System.Collections.ArrayList]$myAllowedServiceConnectionCollection=[System.Collections.ArrayList]::new()
            $myJsonOfAllowedServices=ConvertFrom-Json -InputObject $AllowedServiceConnectionsJson
            foreach($myJsonOfAllowedService in $myJsonOfAllowedServices) {
                $myAllowedServiceConnectionCollection.Add([ConnectionSpecification]::New($myJsonOfAllowedService.LoginName,$myJsonOfAllowedService.PersonnelIdentification,$myJsonOfAllowedService.ClientNamePattern,$myJsonOfAllowedService.ClientIpPattern))
            }
            $myAllowedServiceConnections=$myAllowedServiceConnectionCollection.ToArray([ConnectionSpecification])
        )
        $myAnswer=[OsLoginAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogInstanceConnectionString,$myLogTableName,$myLogFilePath)    
    }
    catch {
        Write-Verbose ($_.ToString())
    }
    Write-Verbose "New-OsLoginAuditByJsonConnSpec Created"
    return $myAnswer
}
#endregion

#region Export
Export-ModuleMember -Function New-SqlSysAdminAudit,New-SqlSysAdminAuditByJsonConnSpec,New-OsLoginAudit,New-OsLoginAuditByJsonConnSpec
#endregion
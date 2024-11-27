Using module .\SqlDeepLogWriter.psm1

Class ConnectionSpecification{
    [string]$LoginName
    [string]$PersonnelIdentification
    [string]$ClientNamePattern
    [string]$ClientIpPattern

    ConnectionSpecification ([string]$LoginName){
        $this.Init($LoginName,$null,'%','%')
    }
    ConnectionSpecification ([string]$LoginName,[string]$PersonnelIdentification,[string]$ClientNamePattern){
        $this.Init($LoginName,$PersonnelIdentification,$ClientNamePattern,'%')
    }
    ConnectionSpecification ([string]$LoginName,[string]$PersonnelIdentification,[string]$ClientNamePattern,[string]$ClientIpPattern){
        $this.Init($LoginName,$PersonnelIdentification,$ClientNamePattern,$ClientIpPattern)
    }
    hidden Init([string]$LoginName,[string]$PersonnelIdentification,[string]$ClientNamePattern,[string]$ClientIpPattern){
        [string]$myPersonnelIdentification=''
        [string]$myClientNamePattern='%'
        [string]$myClientIpPattern='%'
        
        if ($null -ne $PersonnelIdentification -and $PersonnelIdentification.Trim().Length -eq 0){$myPersonnelIdentification=''}else{$myPersonnelIdentification=$PersonnelIdentification.Trim().ToUpper()}
        if ($null -ne $ClientNamePattern -and $ClientNamePattern.Trim().Length -eq 0){$myClientNamePattern='%'}else{$myClientNamePattern=$ClientNamePattern.Trim().ToUpper()}
        if ($null -ne $ClientIpPattern -and $ClientIpPattern.Trim().Length -eq 0){$myClientIpPattern='%'}else{$myClientIpPattern=$ClientIpPattern.Trim().ToUpper()}
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
    [ConnectionSpecification[]]$AllowedUserConnections
    [ConnectionSpecification[]]$AllowedServiceConnections
    hidden [SecurityEvent[]]$SecurityEvents
    hidden [datetime]$ScanStartTime
    hidden [LogWriter]$LogWriter

    SqlSysAdminAudit([string]$CentralTempInstanceConnectionString,[string]$CurrentInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[LogWriter]$LogWriter){
        $this.Init(10,$CentralTempInstanceConnectionString,$CurrentInstanceConnectionString,$AllowedUserConnections,$AllowedServiceConnections,$LogWriter)
    }
    SqlSysAdminAudit([int]$LimitEventLogScanToRecentMinutes,[string]$CentralTempInstanceConnectionString,[string]$CurrentInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[LogWriter]$LogWriter){
        $this.Init($LimitEventLogScanToRecentMinutes,$CentralTempInstanceConnectionString,$CurrentInstanceConnectionString,$AllowedUserConnections,$AllowedServiceConnections,$LogWriter)
    }
    hidden Init([int]$LimitEventLogScanToRecentMinutes,[string]$CentralTempInstanceConnectionString,[string]$CurrentInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[LogWriter]$LogWriter){
        $this.LimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
        $this.CentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
        $this.CurrentInstanceConnectionString=$CurrentInstanceConnectionString
        $this.AllowedUserConnections=$AllowedUserConnections
        $this.AllowedServiceConnections=$AllowedServiceConnections
        $this.LogWriter=$LogWriter
        $this.SecurityEvents=$null
    }

    #region Functions
    hidden [void]CollectEvents(){
        $this.LogWriter.Write('Processing Started.', [LogType]::INF)
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
            $this.LogWriter.Write('Extract relative Windows Events.',[LogType]::INF)
            $this.ScanStartTime=(Get-Date).AddMinutes((-1*[Math]::Abs($this.LimitEventLogScanToRecentMinutes)));
            [System.Data.DataRow[]]$myNonAdmins=$null
            [System.Collections.ArrayList]$mySecurityEventCollection=$null
            $mySecurityEventCollection=[System.Collections.ArrayList]::new()
            $this.LogWriter.Write('Specify sql server non-admin logins.',[LogType]::INF)
            $myNonAdmins = Invoke-Sqlcmd -ConnectionString ($this.CurrentInstanceConnectionString) -Query $myNonAdminLoginsQuery -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            $this.LogWriter.Write(('Retrive only admin logins from Windows Events from ' + $this.ScanStartTime.ToString() + ' through ' + (Get-Date).ToString()),[LogType]::INF)
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
                $this.LogWriter.Write('There is '+ $this.SecurityEvents.Count.ToString()+' Admin login events found in Windows Events.',[LogType]::INF)
            } else {
                $this.LogWriter.Write('There is no Admin login event found in Windows Events.',[LogType]::INF)
            }
            $this.LogWriter.Write('Admin logins retrived from Windows Events.',[LogType]::INF)
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            $this.SecurityEvents.Clear()
        }
    }
    hidden [void]SaveEvents(){
        $this.LogWriter.Write('Processing Started.', [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write('Insert Security Events into SQL table.',[LogType]::INF)
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
            $this.LogWriter.Write('Insert Security Events into SQL table: there is nothing',[LogType]::INF)
        }
    }
    hidden [void]CleanEvents(){
        $this.LogWriter.Write('Processing Started.', [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write('Clean old events from temporary table.',[LogType]::INF)
            [string]$myValidateEventCommand="
                DECLARE @BatchInsertTime DateTime;
                DECLARE @myInstance nvarchar(256);
                SET @BatchInsertTime=CAST(N'"+$this.ScanStartTime.ToString()+"' AS DATETIME);
                SET @myInstance=N'"+$this.SecurityEvents[0].Instance+"';
        
                DELETE [dbo].[SqlLoginRecords] WHERE [Instance]=@myInstance AND [BatchInsertTime] < @BatchInsertTime;
                "
            Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myValidateEventCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
            $this.LogWriter.Write('Events cleaned.',[LogType]::INF)
        }else{
            $this.LogWriter.Write('Clean old events from temporary table: There is nothing',[LogType]::INF)
        }
    }
    hidden [void]AnalyzeSavedEvents(){
        $this.LogWriter.Write('Processing Started.', [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write('Analyze saved security events', [LogType]::INF)
            [string]$myKnownListCommand=''
            [string]$myAnalyzeEventCommand=''
            [string]$myEventSource=$this.SecurityEvents[0].Instance
            
            $this.LogWriter.Write(('Detected event source is ' + $myEventSource),[LogType]::INF)
            if($null -ne $this.AllowedUserConnections -and $this.AllowedUserConnections.Count -gt 0){
                $this.LogWriter.Write(('There is ' + $this.AllowedUserConnections.Count.ToString() + ' AllowedUsers specified.'),[LogType]::INF)
                $myKnownListCommand='INSERT INTO @myKnownList ([Login],[PersonelID],[ClientName]) VALUES '
                foreach ($myConnection in $this.AllowedUserConnections){
                    $myKnownListCommand+=$myConnection.ToSqlSysAdminAuditString()+','
                }
                if ($myKnownListCommand[-1] -eq ','){$myKnownListCommand=$myKnownListCommand.Substring(0,$myKnownListCommand.Length-1)} else {$myKnownListCommand=''}
            }else{
                $this.LogWriter.Write(('There is not any AllowedUsers specified.'),[LogType]::INF)
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
                $this.LogWriter.Write('Executing query to detect login attemts in unusual times.',[LogType]::INF)
                $myRecords=Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myAnalyzeEventCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
                $this.LogWriter.Write('Query to detect login attemts in unusual times executed.',[LogType]::INF)
                if ($null -ne $myRecords){
                    $this.LogWriter.Write('There is '+ $myRecords.Count.ToString()+' Alarms found.',[LogType]::INF)
                    $myAlarmWriter=New-LogWriter -EventSource ($myEventSource) -Module ($this.LogWriter.Module + ':LoginAlarm') -LogToConsole ($this.LogWriter.LogToConsole) -LogToFile ($this.LogWriter.LogToFile) -LogFilePath ($this.LogWriter.LogFilePath) -LogToTable ($this.LogWriter.LogToTable) -LogInstanceConnectionString ($this.LogInstanceConnectionString) -LogTableName (($this.LogWriter.LogTableName))
                    foreach ($myRecord in $myRecords){
                        $myAlarmWriter.Write($myRecord.Description, [LogType]::WRN, $false, $true, $myRecord.EventTimeStamp.ToString())
                    }
                }else{
                    $this.LogWriter.Write('There is no Alarms found.',[LogType]::INF)
                }
            }catch{
                $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            }
        } ELSE {
            Write-Host 'Analyze Event Logs: There is nothing'
        }
    }
    [void] EnableSqlLoginAudit(){
        $this.LogWriter.Write('Processing Started.', [LogType]::INF)
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
            $this.LogWriter.Write('Enabling SqlDeep_TrackLogins extended event on SQL Server instance.',[LogType]::INF)
            Invoke-Sqlcmd -ConnectionString $this.CurrentInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
            $this.LogWriter.Write('SqlDeep_TrackLogins extended event enabled.',[LogType]::INF)
        }catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
    }
    [void] AnalyzeEvents(){
        try {
            #--=======================Initial Log Modules
            Write-Verbose ('===== SqlSysAdminAudit process started. =====')
            $this.LogWriter.Write('===== SqlSysAdminAudit process started... ===== ', [LogType]::INF) 
            $this.CollectEvents()       #-----Retrive Successful Logins
            $this.SaveEvents()          #-----Insert Event Logs to a table
            $this.CleanEvents()         #-----Clean Event old Logs
            $this.AnalyzeSavedEvents()  #-----Analyze Event Logs and send alert
        }catch{
            Write-Error ($_.ToString())
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }finally{
            Write-Verbose ('===== SqlSysAdminAudit finished. =====')
        }
        $this.LogWriter.Write('===== SqlSysAdminAudit process finished. ===== ', [LogType]::INF) 
    }
    #endregion
}
Class OsLoginAudit{
    [int]$LimitEventLogScanToRecentMinutes
    [string]$CentralTempInstanceConnectionString
    [ConnectionSpecification[]]$AllowedUserConnections
    [ConnectionSpecification[]]$AllowedServiceConnections
    hidden [SecurityEvent[]]$SecurityEvents
    hidden [datetime]$ScanStartTime
    hidden [LogWriter]$LogWriter

    OsLoginAudit([string]$CentralTempInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[LogWriter]$LogWriter){
        $this.Init(10,$CentralTempInstanceConnectionString,$AllowedUserConnections,$AllowedServiceConnections,$LogWriter)
    }
    OsLoginAudit([int]$LimitEventLogScanToRecentMinutes,[string]$CentralTempInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[LogWriter]$LogWriter){
        $this.Init($LimitEventLogScanToRecentMinutes,$CentralTempInstanceConnectionString,$AllowedUserConnections,$AllowedServiceConnections,$LogWriter)
    }
    hidden Init([int]$LimitEventLogScanToRecentMinutes,[string]$CentralTempInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[LogWriter]$LogWriter){
        $this.LimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
        $this.CentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
        $this.AllowedUserConnections=$AllowedUserConnections
        $this.AllowedServiceConnections=$AllowedServiceConnections
        $this.LogWriter=$LogWriter
        $this.SecurityEvents=$null
    }
    #region Functions
    hidden [void]CollectEvents(){
        $this.LogWriter.Write('Processing Started.', [LogType]::INF)
        try{
            $this.LogWriter.Write('Extract OS login Windows Events.',[LogType]::INF)
            $this.ScanStartTime=(Get-Date).AddMinutes((-1*[Math]::Abs($this.LimitEventLogScanToRecentMinutes)));
            [System.Collections.ArrayList]$mySecurityEventCollection=$null
            $mySecurityEventCollection=[System.Collections.ArrayList]::new()
            $this.LogWriter.Write(('Retrive only OS logins from Windows Events from ' + $this.ScanStartTime.ToString() + ' through ' + (Get-Date).ToString()),[LogType]::INF)
            $myEvents = (Get-WinEvent -FilterHashtable @{
                LogName='Security'
                ProviderName='Microsoft-Windows-Security-Auditing'
                StartTime=$this.ScanStartTime
                Id=4624} `
                | Where-Object {$_.Message -match "(\n`tLogon\sType:\s`t(?<type>.+))+(.|\n)*(\nImpersonation\sLevel:\s`t(?<impersonation_level>.+))+(.|\n)*(\n`tAccount\sName:\s`t(?<login>.+))" } `
                | ForEach-Object {$mySecurityEventCollection.Add([SecurityEvent]::New($_.TimeCreated,$matches['login'].Trim().ToUpper(),$_.MachineName.Trim().ToUpper(),$_.Properties.Value[11].Trim().ToUpper(),$_.Properties.Value[18].Trim().ToUpper(),$_.Properties.Value[6].Trim().ToUpper(),$matches['type'].Trim().ToUpper(),$matches['impersonation_level'].Trim().ToUpper()))}
                )
            if ($null -ne $myEvents) {
                $this.SecurityEvents=$mySecurityEventCollection.ToArray([SecurityEvent]) | Where-Object {($_.DomainName.LastIndexOf('.') -ne -1 -and ($_.DomainName.Substring(0,$_.DomainName.LastIndexOf('.')) +'\'+$_.LoginName) -notin $this.AllowedServiceConnections) -or ($_.DomainName.LastIndexOf('.') -eq -1 -and ($_.DomainName+'\'+$_.LoginName) -notin $this.AllowedServiceConnections)}
                $this.LogWriter.Write('There is '+ $this.SecurityEvents.Count.ToString()+' disallowed OS login events found in Windows Events.',[LogType]::INF)
            } else {
                $this.LogWriter.Write('There is no OS login event found in Windows Events.',[LogType]::INF)
            }
            $this.LogWriter.Write('OS logins retrived from Windows Events.',[LogType]::INF)
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            $this.SecurityEvents.Clear()
        }
    
    }
    hidden [void]SaveEvents(){
        $this.LogWriter.Write('Processing Started.', [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write('Insert Security Events into SQL table.',[LogType]::INF)
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
            $this.LogWriter.Write('Insert Security Events into SQL table: there is nothing',[LogType]::INF)
        }
    }
    hidden [void]CleanEvents(){
        $this.LogWriter.Write('Processing Started.', [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write('Clean old events from temporary table.',[LogType]::INF)
            [string]$myValidateEventCommand="
                DECLARE @BatchInsertTime DateTime;
                DECLARE @myInstance nvarchar(256);
                SET @BatchInsertTime=CAST(N'"+$this.ScanStartTime.ToString()+"' AS DATETIME);
                SET @myInstance=N'"+$this.SecurityEvents[0].Instance+"';
        
                DELETE [dbo].[WinLoginRecords] WHERE [Instance]=@myInstance AND [BatchInsertTime] < @BatchInsertTime;
                "
            Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myValidateEventCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
            $this.LogWriter.Write('Events cleaned.',[LogType]::INF)
        }else{
            $this.LogWriter.Write('Clean old events from temporary table: There is nothing',[LogType]::INF)
        }
    }
    hidden [void]AnalyzeSavedEvents(){
        $this.LogWriter.Write('Processing Started.', [LogType]::INF)
        if ($null -ne $this.SecurityEvents -and $this.SecurityEvents.Count -gt 0) {
            $this.LogWriter.Write('Analyze saved security events', [LogType]::INF)
            [string]$myKnownListCommand=''
            [string]$myAnalyzeEventCommand=''
            [string]$myEventSource=$this.SecurityEvents[0].Instance
            
            $this.LogWriter.Write(('Detected event source is ' + $myEventSource),[LogType]::INF)
            if($null -ne $this.AllowedUserConnections -and $this.AllowedUserConnections.Count -gt 0){
                $this.LogWriter.Write(('There is ' + $this.AllowedUserConnections.Count.ToString() + ' AllowedUsers specified.'),[LogType]::INF)
                $myKnownListCommand='INSERT INTO @myKnownList ([Login],[PersonelID],[ClientName],[ClientIp]) VALUES '
                foreach ($myConnection in $this.AllowedUserConnections){
                    $myKnownListCommand+=$myConnection.ToOsLoginAuditString()+','
                }
                if ($myKnownListCommand[-1] -eq ','){$myKnownListCommand=$myKnownListCommand.Substring(0,$myKnownListCommand.Length-1)} else {$myKnownListCommand=''}
            }else{
                $this.LogWriter.Write(('There is not any AllowedUsers specified.'),[LogType]::INF)
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
                $this.LogWriter.Write('Executing query to detect login attemts in unusual times.',[LogType]::INF)
                $myRecords=Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myAnalyzeEventCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
                $this.LogWriter.Write('Query to detect login attemts in unusual times executed.',[LogType]::INF)
                if ($null -ne $myRecords){
                    $this.LogWriter.Write('There is '+ $myRecords.Count.ToString()+' Alarms found.',[LogType]::INF)
                    $myAlarmWriter=New-LogWriter -EventSource ($myEventSource) -Module ($this.LogWriter.Module + ':LoginAlarm') -LogToConsole ($this.LogWriter.LogToConsole) -LogToFile ($this.LogWriter.LogToFile) -LogFilePath ($this.LogWriter.LogFilePath) -LogToTable ($this.LogWriter.LogToTable) -LogInstanceConnectionString ($this.LogInstanceConnectionString) -LogTableName (($this.LogWriter.LogTableName))
                    foreach ($myRecord in $myRecords){
                        $myAlarmWriter.Write($myRecord.Description, [LogType]::WRN, $false, $true, $myRecord.EventTimeStamp.ToString())
                    }
                }else{
                    $this.LogWriter.Write('There is no Alarms found.',[LogType]::INF)
                }
            }catch{
                $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            }
        } ELSE {
            Write-Host 'Analyze Event Logs: There is nothing'
        }
    }
    [void] AnalyzeEvents(){
        try {
            #--=======================Initial Log Modules
            Write-Verbose ('===== OsLoginAudit process started. =====')
            $this.LogWriter.Write('===== OsLoginAudit process started... ===== ', [LogType]::INF) 
            $this.CollectEvents()       #-----Retrive Successful Logins
            $this.SaveEvents()          #-----Insert Event Logs to a table
            $this.CleanEvents()         #-----Clean Event old Logs
            $this.AnalyzeSavedEvents()  #-----Analyze Event Logs and send alert
        }catch{
            Write-Error ($_.ToString())
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }finally{
            Write-Verbose ('===== OsLoginAudit finished. =====')
        }
        $this.LogWriter.Write('===== OsLoginAudit process finished. ===== ', [LogType]::INF) 
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
        [Parameter(Mandatory=$true)][LogWriter]$LogWriter
    )
    Write-Verbose 'Creating New-SqlSysAdminAudit'
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [string]$myCurrentInstanceConnectionString=$CurrentInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$AllowedUserConnections
    [ConnectionSpecification[]]$myAllowedServiceConnections=$AllowedServiceConnections
    [LogWriter]$myLogWriter=$LogWriter
    [SqlSysAdminAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myCurrentInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogWriter)
    Write-Verbose 'New-SqlSysAdminAudit Created'
}
Function New-SqlSysAdminAuditByJsonConnSpec {
    Param(
        [Parameter(Mandatory=$false)][int]$LimitEventLogScanToRecentMinutes=10,
        [Parameter(Mandatory=$true)][string]$CentralTempInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$CurrentInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$AllowedUserConnectionsJson,
        [Parameter(Mandatory=$true)][string]$AllowedServiceConnectionsJson,
        [Parameter(Mandatory=$true)][LogWriter]$LogWriter
    )
    Write-Verbose 'Creating New-SqlSysAdminAuditByJsonConnSpec'
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [string]$myCurrentInstanceConnectionString=$CurrentInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$null
    [ConnectionSpecification[]]$myAllowedServiceConnections=$null
    [LogWriter]$myLogWriter=$LogWriter
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
        $myAnswer=[SqlSysAdminAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myCurrentInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogWriter)    
    }
    catch {
        Write-Verbose ($_.ToString())
    }
    Write-Verbose 'New-SqlSysAdminAuditByJsonConnSpec Created'
    return $myAnswer
}
Function New-OsLoginAudit {
    Param(
        [Parameter(Mandatory=$false)][int]$LimitEventLogScanToRecentMinutes=10,
        [Parameter(Mandatory=$true)][string]$CentralTempInstanceConnectionString,
        [Parameter(Mandatory=$true)][ConnectionSpecification[]]$AllowedUserConnections,
        [Parameter(Mandatory=$true)][ConnectionSpecification[]]$AllowedServiceConnections,
        [Parameter(Mandatory=$true)][LogWriter]$LogWriter
    )
    Write-Verbose 'Creating New-OsLoginAudit'
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$AllowedUserConnections
    [ConnectionSpecification[]]$myAllowedServiceConnections=$AllowedServiceConnections
    [LogWriter]$myLogWriter=$LogWriter
    [OsLoginAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogWriter)
    Write-Verbose 'New-OsLoginAudit Created'
}
Function New-OsLoginAuditByJsonConnSpec {
    Param(
        [Parameter(Mandatory=$false)][int]$LimitEventLogScanToRecentMinutes=10,
        [Parameter(Mandatory=$true)][string]$CentralTempInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$AllowedUserConnectionsJson,
        [Parameter(Mandatory=$true)][string]$AllowedServiceConnectionsJson,
        [Parameter(Mandatory=$true)][LogWriter]$LogWriter
    )
    Write-Verbose 'Creating New-OsLoginAuditByJsonConnSpec'
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$null
    [ConnectionSpecification[]]$myAllowedServiceConnections=$null
    [LogWriter]$myLogWriter=$LogWriter
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
        $myAnswer=[OsLoginAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogWriter)    
    }
    catch {
        Write-Verbose ($_.ToString())
    }
    Write-Verbose 'New-OsLoginAuditByJsonConnSpec Created'
    return $myAnswer
}
#endregion

#region Export
Export-ModuleMember -Function New-SqlSysAdminAudit,New-SqlSysAdminAuditByJsonConnSpec,New-OsLoginAudit,New-OsLoginAuditByJsonConnSpec
#endregion
# SIG # Begin signature block
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAD3oxA4fA9ktcn
# AQiH3KUPC2H8gvhUiEuDLlq/wGcdUqCCFhswggMUMIIB/KADAgECAhAT2c9S4U98
# jEh2eqrtOGKiMA0GCSqGSIb3DQEBBQUAMBYxFDASBgNVBAMMC3NxbGRlZXAuY29t
# MB4XDTI0MTAyMzEyMjAwMloXDTI2MTAyMzEyMzAwMlowFjEUMBIGA1UEAwwLc3Fs
# ZGVlcC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDivSzgGDqW
# woiD7OBa8twT0nzHGNakwZtEzvq3HcL8bCgfDdp/0kpzoS6IKpjt2pyr0xGcXnTL
# SvEtJ70XOgn179a1TlaRUly+ibuUfO15inrwPf1a6fqgvPMoXV6bMxpsbmx9vS6C
# UBYO14GUN10GtlQgpUYY1N0czabC7yXfo8EwkO1ZTGoXADinHBF0poKffnR0EX5B
# iL7/WGRfT3JgFZ8twYMoKOc4hJ+GZbudtAptvnWzAdiWM8UfwQwcH8SJQ7n5whPO
# PV8e+aICbmgf9j8NcVAKUKqBiGLmEhKKjGKaUow53cTsshtGCndv5dnMgE2ppkxh
# aWNn8qRqYdQFAgMBAAGjXjBcMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggr
# BgEFBQcDAzAWBgNVHREEDzANggtzcWxkZWVwLmNvbTAdBgNVHQ4EFgQUwoHZNhYd
# VvtzY5g9WlOViG86b8EwDQYJKoZIhvcNAQEFBQADggEBAAvLzZ9wWrupREYXkcex
# oLBwbxjIHueaxluMmJs4MSvfyLG7mzjvkskf2AxfaMnWr//W+0KLhxZ0+itc/B4F
# Ep4cLCZynBWa+iSCc8iCF0DczTjU1exG0mUff82e7c5mXs3oi6aOPRyy3XBjZqZd
# YE1HWl9GYhboC5kY65Z42ZsbNyPOM8nhJNzBKq9V6eyNE2JnxlrQ1v19lxXOm6WW
# Hgnh++tUf9k8DI1D7Da3bQqsj8O+ACHjhjMVzWKqAtnDxydaOOjRhKWIlHUQ7fLW
# GYFZW2JXnogqxFR2tzdpZxsNgD4vHFzt1CspiHzhIsMwfQFxIg44Ny/U96l2aVpR
# 6lUwggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUA
# MGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsT
# EHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQg
# Um9vdCBDQTAeFw0yMjA4MDEwMDAwMDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNV
# BAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdp
# Y2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqcl
# LskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YF
# PFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQRBAu34LzB4TmdDttceIt
# DBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nPzaw0QF+xembud8hIqGZX
# V59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1
# ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2Tox
# RJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdp
# ekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF
# 30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9
# t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQ
# UOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXk
# aS+YHS312amyHeUbAgMBAAGjggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1Ud
# DgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEt
# UYunpyGd823IDzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAw
# DQYJKoZIhvcNAQEMBQADggEBAHCgv0NcVec4X6CjdBs9thbX979XB72arKGHLOyF
# XqkauyL4hxppVCLtpIh3bb0aFPQTSnovLbc47/T/gLn4offyct4kvFIDyE7QKt76
# LVbP+fT3rDB6mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8L
# punyNDzs9wPHh6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2
# CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si
# /xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQwggauMIIElqADAgEC
# AhAHNje3JFR82Ees/ShmKl5bMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMjAzMjMw
# MDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0
# MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQDGhjUGSbPBPXJJUVXHJQPE8pE3qZdRodbSg9GeTKJtoLDMg/la
# 9hGhRBVCX6SI82j6ffOciQt/nR+eDzMfUBMLJnOWbfhXqAJ9/UO0hNoR8XOxs+4r
# gISKIhjf69o9xBd/qxkrPkLcZ47qUT3w1lbU5ygt69OxtXXnHwZljZQp09nsad/Z
# kIdGAHvbREGJ3HxqV3rwN3mfXazL6IRktFLydkf3YYMZ3V+0VAshaG43IbtArF+y
# 3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYbqMFkdECnwHLFuk4fsbVYTXn+149zk6ws
# OeKlSNbwsDETqVcplicu9Yemj052FVUmcJgmf6AaRyBD40NjgHt1biclkJg6OBGz
# 9vae5jtb7IHeIhTZgirHkr+g3uM+onP65x9abJTyUpURK1h0QCirc0PO30qhHGs4
# xSnzyqqWc0Jon7ZGs506o9UD4L/wojzKQtwYSH8UNM/STKvvmz3+DrhkKvp1KCRB
# 7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo80VgvCONWPfcYd6T/jnA+bIwpUzX6ZhK
# WD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjBJgj5FBASA31fI7tk42PgpuE+9sJ0sj8e
# CXbsq11GdeJgo1gJASgADoRU7s7pXcheMBK9Rp6103a50g5rmQzSM7TNsQIDAQAB
# o4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUuhbZbU2FL3Mp
# dpovdYxqII+eyG8wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYD
# VR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGsw
# aTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUF
# BzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# Um9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeB
# DAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBAH1ZjsCTtm+YqUQi
# AX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd4ksp+3CKDaopafxpwc8dB+k+YMjYC+Vc
# W9dth/qEICU0MWfNthKWb8RQTGIdDAiCqBa9qVbPFXONASIlzpVpP0d3+3J0FNf/
# q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl/Yy8ZCaHbJK9nXzQcAp876i8dU+6Wvep
# ELJd6f8oVInw1YpxdmXazPByoyP6wCeCRK6ZJxurJB4mwbfeKuv2nrF5mYGjVoar
# CkXJ38SNoOeY+/umnXKvxMfBwWpx2cYTgAnEtp/Nh4cku0+jSbl3ZpHxcpzpSwJS
# pzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/a6fxZsNBzU+2QJshIUDQtxMkzdwdeDrk
# nq3lNHGS1yZr5Dhzq6YBT70/O3itTK37xJV77QpfMzmHQXh6OOmc4d0j/R0o08f5
# 6PGYX/sr2H7yRp11LB4nLCbbbxV7HhmLNriT1ObyF5lZynDwN7+YAN8gFk8n+2Bn
# FqFmut1VwDophrCYoCvtlUG3OtUVmDG0YgkPCr2B2RP+v6TR81fZvAT6gt4y3wSJ
# 8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJRyvmfxqkhQ/8mJb2VVQrH4D6wPIOK+XW
# +6kvRBVK5xMOHds3OBqhK/bt1nz8MIIGvDCCBKSgAwIBAgIQC65mvFq6f5WHxvnp
# BOMzBDANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGln
# aUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5
# NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTI0MDkyNjAwMDAwMFoXDTM1MTEy
# NTIzNTk1OVowQjELMAkGA1UEBhMCVVMxETAPBgNVBAoTCERpZ2lDZXJ0MSAwHgYD
# VQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyNDCCAiIwDQYJKoZIhvcNAQEBBQAD
# ggIPADCCAgoCggIBAL5qc5/2lSGrljC6W23mWaO16P2RHxjEiDtqmeOlwf0KMCBD
# Er4IxHRGd7+L660x5XltSVhhK64zi9CeC9B6lUdXM0s71EOcRe8+CEJp+3R2O8oo
# 76EO7o5tLuslxdr9Qq82aKcpA9O//X6QE+AcaU/byaCagLD/GLoUb35SfWHh43rO
# H3bpLEx7pZ7avVnpUVmPvkxT8c2a2yC0WMp8hMu60tZR0ChaV76Nhnj37DEYTX9R
# eNZ8hIOYe4jl7/r419CvEYVIrH6sN00yx49boUuumF9i2T8UuKGn9966fR5X6kgX
# j3o5WHhHVO+NBikDO0mlUh902wS/Eeh8F/UFaRp1z5SnROHwSJ+QQRZ1fisD8UTV
# DSupWJNstVkiqLq+ISTdEjJKGjVfIcsgA4l9cbk8Smlzddh4EfvFrpVNnes4c16J
# idj5XiPVdsn5n10jxmGpxoMc6iPkoaDhi6JjHd5ibfdp5uzIXp4P0wXkgNs+CO/C
# acBqU0R4k+8h6gYldp4FCMgrXdKWfM4N0u25OEAuEa3JyidxW48jwBqIJqImd93N
# Rxvd1aepSeNeREXAu2xUDEW8aqzFQDYmr9ZONuc2MhTMizchNULpUEoA6Vva7b1X
# CB+1rxvbKmLqfY/M/SdV6mwWTyeVy5Z/JkvMFpnQy5wR14GJcv6dQ4aEKOX5AgMB
# AAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNVHSUB
# Af8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1s
# BwEwHwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxqII+eyG8wHQYDVR0OBBYEFJ9X
# LAN3DigVkGalY17uT5IfdqBbMFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1l
# U3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGDMIGAMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYBBQUHMAKGTGh0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZU
# aW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggIBAD2tHh92mVvjOIQS
# R9lDkfYR25tOCB3RKE/P09x7gUsmXqt40ouRl3lj+8QioVYq3igpwrPvBmZdrlWB
# b0HvqT00nFSXgmUrDKNSQqGTdpjHsPy+LaalTW0qVjvUBhcHzBMutB6HzeledbDC
# zFzUy34VarPnvIWrqVogK0qM8gJhh/+qDEAIdO/KkYesLyTVOoJ4eTq7gj9UFAL1
# UruJKlTnCVaM2UeUUW/8z3fvjxhN6hdT98Vr2FYlCS7Mbb4Hv5swO+aAXxWUm3Wp
# ByXtgVQxiBlTVYzqfLDbe9PpBKDBfk+rabTFDZXoUke7zPgtd7/fvWTlCs30VAGE
# sshJmLbJ6ZbQ/xll/HjO9JbNVekBv2Tgem+mLptR7yIrpaidRJXrI+UzB6vAlk/8
# a1u7cIqV0yef4uaZFORNekUgQHTqddmsPCEIYQP7xGxZBIhdmm4bhYsVA6G2WgNF
# YagLDBzpmk9104WQzYuVNsxyoVLObhx3RugaEGru+SojW4dHPoWrUhftNpFC5H7Q
# EY7MhKRyrBe7ucykW7eaCuWBsBb4HOKRFVDcrZgdwaSIqMDiCLg4D+TPVgKx2EgE
# deoHNHT9l3ZDBD+XgbF+23/zBjeCtxz+dL/9NWR6P2eZRi7zcEO1xwcdcqJsyz/J
# ceENc2Sg8h3KeFUCS7tpFk7CrDqkMYIFADCCBPwCAQEwKjAWMRQwEgYDVQQDDAtz
# cWxkZWVwLmNvbQIQE9nPUuFPfIxIdnqq7ThiojANBglghkgBZQMEAgEFAKCBhDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEi
# BCBOsKU3DVf4pc0FL/S5dVpzvfgU209LrlmBDl4eUhrSCzANBgkqhkiG9w0BAQEF
# AASCAQC1BgMfiF/WUMMi/RFwnPPaNUJcKJNiY5Mco+uVU1s6sqa7a5NevvAOWgj4
# sOZ0NdzhxGfTB14toPi9B/PHQ6KZutVol3UnpKS8tG3RFjCqhA0U63ykro17iulo
# stNN24VqCEcTU/jxuZgBCwmdEKxClhxZ9WgRsXdoEhsSwjm35mshsUANERguzAX2
# HBethmRcMVaSHta7r4jrnzKe2GaNkQdS4xseNPc6Ax04jYShKEIbPS6bAsD2v996
# 4/vvYPLAuwvHCU0Cl1aqj6+3qe1hOxfrpUwB2vbkOl2DATWYAlrMUaaWg4mpTLR4
# eW98dX0KPnb9FRXWYgFV2gdiBBUDoYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTEyNzA1
# MDUxMVowLwYJKoZIhvcNAQkEMSIEIHwtFjOh7gnvBLODF4o31cnWL2U2xhx17CUc
# ihR4BNcGMA0GCSqGSIb3DQEBAQUABIICAC/q3RFsW3hlBiE+kOO9i2mNtQrPpWWP
# GIjVp6l+TELHJCCKWdMGAZ7AkIOfOy3lz5byH8X1CtlJ9gK+ZQ/+HQKp+0KTAvHe
# weOzWr7XPUoHE87i3IWR6AFgx93jef9Iztg5Z9XcmpIohHsNbKBinUgtc9w/fkC+
# 97ShQ3Xe8nEXBqdCupdITQfv/ivNdEMEUIwj1PrxMmtAOcS+1AHyc9vFEX5DOIlg
# uMSmL+NKcXdKZz3HWtDvoFbEPph5X9FLXY+Y8yA7trH1MdrOuCoQzXNfgV5LR9o+
# KZH9CulVz6a0SrJghUI/tQ9LGlaKeq3Mm+JnySFRKNtVXfN2gthI0LFCoW6XdZoq
# m034k0miUC9bo8we13nKcMLwIVdh3AHk1RlV/aQ9Pk+Oy+/46NLgIPIHlqJBZcWF
# wMdPzfM6aIWW+dRNIuZTxs2Kz+i+/85+5MmrXFbQJTkh73h3lGyXAs2Eh2hUFZMc
# kQGfsZUNQIrrl+PcIRpcDCnuss69p1GtH9NhmSTo++rdtZsoDSr5KTnE/GF0BA/n
# Urm9zq4qutIeXz6C737efKRHzt4yryeRUIBwiMkBZTVlr1mNrLwJW8h8xkCPpBnD
# XvnCHSQslSuiN2snGoFnSBoaH6XVGpQQl5DGuZKqHJArYfXDAunJyn3Cvb4lozoq
# hxFZoAiY6uYS
# SIG # End signature block

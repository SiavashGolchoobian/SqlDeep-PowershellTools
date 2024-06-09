Using module .\SqlDeepLogWriterEnums.psm1
Import-Module "$PSScriptRoot\SqlDeepLogWriter.psm1"

Class ConnectionSpecification{
    [string]$LoginName
    [string]$PersonnelIdentification
    [string]$ClientNamePattern

    ConnectionSpecification ([string]$LoginName){
        $this.Init($LoginName,$null,"%")
    }
    ConnectionSpecification ([string]$LoginName,[string]$PersonnelIdentification,[string]$ClientNamePattern){
        $this.Init($LoginName,$PersonnelIdentification,$ClientNamePattern)
    }
    hidden Init([string]$LoginName,[string]$PersonnelIdentification,[string]$ClientNamePattern){
        $this.LoginName=$LoginName.Trim().ToUpper()
        $this.PersonnelIdentification=$PersonnelIdentification.Trim().ToUpper()
        $this.ClientNamePattern=$ClientNamePattern.Trim().ToUpper()
    }
    #region Functions
    [string] ToString(){
        [string]$myAnswer=$null
        $myAnswer="(N'" + $this.LoginName + "',N'"+ $this.PersonnelIdentification +"',N'"+ $this.ClientNamePattern +"')"
        return $myAnswer
    }
    #endregion
}
Class SecurityEvent{
    [string]$DateTime
    [string]$LoginName
    [string]$Instance
    [string]$Client

    SecurityEvent([string]$DateTime,[string]$LoginName,[string]$Instance,[string]$Client){
        $this.DateTime=$DateTime
        $this.LoginName=$LoginName.Trim().ToUpper()
        $this.Instance=$Instance.Trim().ToUpper()
        $this.Client=$Client.Trim().ToUpper()
    }
}
Class SysAdminAudit{
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

    SysAdminAudit([string]$CentralTempInstanceConnectionString,[string]$CurrentInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[string]$LogInstanceConnectionString,[string]$LogTableName,[string]$LogFilePath){
        $this.Init(10,$CentralTempInstanceConnectionString,$CurrentInstanceConnectionString,$AllowedUserConnections,$AllowedServiceConnections,$LogInstanceConnectionString,$LogTableName,$LogFilePath)
    }
    SysAdminAudit([int]$LimitEventLogScanToRecentMinutes,[string]$CentralTempInstanceConnectionString,[string]$CurrentInstanceConnectionString,[ConnectionSpecification[]]$AllowedUserConnections,[ConnectionSpecification[]]$AllowedServiceConnections,[string]$LogInstanceConnectionString,[string]$LogTableName,[string]$LogFilePath){
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
            [System.Data.DataRow[]]$myNonAdmins=$null
            [System.Collections.ArrayList]$mySecurityEventCollection=$null
            $mySecurityEventCollection=[System.Collections.ArrayList]::new()
            $myNonAdmins = Invoke-Sqlcmd -ConnectionString ($this.CurrentInstanceConnectionString) -Query $myNonAdminLoginsQuery -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            $this.SecurityEvents = (Get-WinEvent -FilterHashtable @{
                LogName='Application'
                ProviderName='MSSQL$NODE'
                StartTime=$this.ScanStartTime
                Id=33205} `
                | Where-Object {$_.Message -ilike "*action_id:LGIS*server_principal_name:*server_instance_name:*host_name:*" } `
                | Where-Object {$_.Message -match "(\nserver_principal_name:(?<login>.+))+(.|\n)*(\nserver_instance_name:(?<instance>.+))+(.|\n)*(\nhost_name:(?<client>.+))" } `
                | Where-Object {$matches['login'].Trim().ToUpper() -notin $this.AllowedServiceConnections.LoginName } `
                | Where-Object {$matches['login'].Trim().ToUpper() -notin $myNonAdmins.LoginName } `
                | ForEach-Object {$mySecurityEventCollection.Add([SecurityEvent]::New($_.TimeCreated,$matches['login'],$matches['instance'],$matches['client']))}
                ).ToArray([SecurityEvent])
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
                DECLARE @myClient nvarchar(256);
        
                SET @BatchInsertTime=CAST(N'"+$this.ScanStartTime.ToString()+"' AS DATETIME);
                SET @myTime=CAST(N'"+$myEvent.DateTime+"' AS DATETIME);
                SET @myLogin=N'"+$myEvent.LoginName+"';
                SET @myInstance=N'"+$myEvent.Instance+"';
                SET @myClient=N'"+$myEvent.Client+"';
        
                IF OBJECT_ID('SqlLoginRecords') IS NULL
                BEGIN
                    CREATE TABLE [dbo].[SqlLoginRecords] ([Id] bigint identity Primary Key, [BatchInsertTime] DateTime NOT NULL, [Time] DateTime NOT NULL, [Login] nvarchar(128) NOT NULL, [Instance] nvarchar(256) NOT NULL, [Client] nvarchar(256));
                    CREATE INDEX NCIX_dbo_SqlLoginRecords_Instance ON [dbo].[SqlLoginRecords] ([Instance],[BatchInsertTime]) WITH (DATA_COMPRESSION=PAGE,FILLFACTOR=85);
                    CREATE INDEX NCIX_dbo_SqlLoginRecords_LoginTime ON [dbo].[SqlLoginRecords] ([Login],[Time]) WITH (DATA_COMPRESSION=PAGE,FILLFACTOR=85);
                END
        
                INSERT INTO [dbo].[SqlLoginRecords] ([BatchInsertTime],[Time],[Login],[Instance],[Client]) VALUES (@BatchInsertTime,@myTime,@myLogin,@myInstance,@myClient);
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
            [string]$myEventSource=$this.SecurityEvent[0].Instance

            if($null -ne $this.AllowedUserConnections -and $this.AllowedUserConnections.Count -gt 0){
                $myKnownListCommand="INSERT INTO @myKnownList ([Login],[PersonelID],[Client]) VALUES "
                foreach ($myConnection in $this.AllowedUserConnections){
                    $myKnownListCommand+=$myConnection.ToString()+","
                }
                if ($myKnownListCommand[-1] -eq ","){$myKnownListCommand=$myKnownListCommand.Substring(0,$myKnownListCommand.Length-1)} else {$myKnownListCommand=""}
            }
            $myAnalyzeEventCommand="
                DECLARE @myInstance nvarchar(256)
                DECLARE @myCurrent DATETIME;
                DECLARE @myDummeyDate DATETIME;
                DECLARE @myKnownList TABLE ([Login] nvarchar(128), [PersonelID] bigint, [Client] nvarchar(256))
                DECLARE @myLogonStat TABLE ([Login] nvarchar(128), [Client] nvarchar(256), [StartDateTime] DateTime, [FinishDateTime] DateTime, [StartTime] Time(0), [FinishTime] Time(0), [StartDateJalali] nvarchar(10), [FinishDateJalali] nvarchar(10), [PersonelID] bigint, [LoginAttempts] bigint);
        
                SET @myInstance=N'"+$myEventSource+"';
                SET @myCurrent=GETDATE();
                SET @myDummeyDate=CAST(@myCurrent AS DATE)
                IF OBJECT_ID('SqlLoginRecords') IS NOT NULL
                BEGIN
                    " + $myKnownListCommand + "
                    INSERT INTO @myLogonStat ([Login],[Client],[StartDateTime],[FinishDateTime],[StartTime],[FinishTime],[StartDateJalali],[FinishDateJalali],[LoginAttempts],[PersonelID])
                    SELECT
                        [myLogs].[Login],
                        [myLogs].[Client],
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
                                [myRawLog].[Client],
                                MIN([myRawLog].[Time]) AS StartTime,
                                MAX([myRawLog].[Time]) AS FinishTime,
                                Count(1) AS LoginAttempts
                            FROM 
                                [dbo].[SqlLoginRecords] AS myRawLog WITH (READPAST)
                            WHERE
                                [myRawLog].[Instance]=@myInstance
                            GROUP BY
                                [myRawLog].[Login],
                                [myRawLog].[Client]
                        ) AS myLogs
                        LEFT OUTER JOIN @myKnownList AS myKnownList ON [myLogs].[Login]=[myKnownList].[Login] AND [myLogs].[Client] LIKE [myKnownList].[Client]
        
                    SELECT 
                        [myLogonStat].[StartDateTime] AS [EventTimeStamp],
                        N'Unexpected Login as sysadmin from '+ [myLogonStat].[Client] +N' client with ' + [myLogonStat].[Login] + N' login between ' + CAST([myLogonStat].[StartTime] AS nvarchar(10)) + N' and ' + CAST([myLogonStat].[FinishTime] AS nvarchar(10)) + N' for ' + CAST([myLogonStat].[LoginAttempts] AS nvarchar(10)) + N' times.' AS [Description]
                    FROM 
                        @myLogonStat AS myLogonStat
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
                                    PersonelID=[myLogonStat].[PersonelID] AND [DATE] BETWEEN [myLogonStat].[StartDateJalali] COLLATE Arabic_CI_AS AND [myLogonStat].[FinishDateJalali] COLLATE Arabic_CI_AS
                                GROUP BY
                                    [Date]
                                ) AS myKasraStat
                        ) AS myKasraSummery
                    WHERE
                        [myLogonStat].[PersonelID] IS NULL			--From unknown Admins or known admins from unknown clients
                        OR											--Known Admins
                        (
                            [myLogonStat].[PersonelID] IS NOT NULL
                            AND 
                                (
                                NOT ([myLogonStat].[StartTime] BETWEEN [myKasraSummery].[InTime] AND [myKasraSummery].[OutTime])
                                OR
                                NOT ([myLogonStat].[FinishTime] BETWEEN [myKasraSummery].[InTime] AND [myKasraSummery].[OutTime])
                                OR
                                [myKasraSummery].[Date] IS NULL		--Off day
                                )
                        )
                 END
                "
            try{
                [System.Data.DataRow[]]$myRecords=$null
                $myRecords=Invoke-Sqlcmd -ConnectionString $this.CentralTempInstanceConnectionString -Query $myAnalyzeEventCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
                if ($null -ne $myRecords){
                    $myAlarmWriter=New-LogWriter -EventSource ($myEventSource) -Module "AdminLogins" -LogToConsole -LogToFile -LogFilePath ($this.LogFilePath) -LogToTable -LogInstanceConnectionString ($this.LogInstanceConnectionString) -LogTableName ($this.LogTableName)
                    foreach ($myRecord in $myRecords){
                        $myAlarmWriter.LogWriter($myRecords.Description, [LogType]::WRN, $false, $true, $myRecord.EventTimeStamp.ToString())
                    }
                }
            }catch{
                $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            }
        } ELSE {
            Write-Host "Analyze Event Logs: There is nothing"
        }
    }
    [void] Analyze(){
        try {
            #--=======================Initial Log Modules
            Write-Verbose ("===== SysAdminAudit process started. =====")
            $this.LogWriter=New-LogWriter -EventSource ($env:computername) -Module "SysAdminAudit" -LogToConsole -LogToFile -LogFilePath ($this.LogFilePath) -LogToTable -LogInstanceConnectionString ($this.LogInstanceConnectionString) -LogTableName ($this.LogTableName)
            $this.LogWriter.Write("===== SysAdminAudit process started... ===== ", [LogType]::INF) 
            $this.CollectEvents()       #-----Retrive Successful Logins
            $this.SaveEvents()          #-----Insert Event Logs to a table
            $this.CleanEvents()         #-----Clean Event old Logs
            $this.AnalyzeSavedEvents()  #-----Analyze Event Logs and send alert
        }catch{
            Write-Error ($_.ToString())
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }finally{
            Write-Verbose ("===== SysAdminAudit finished. =====")
        }
        $this.LogWriter.Write("===== SysAdminAudit process finished. ===== ", [LogType]::INF) 
    }
    #endregion
}

#region Functions
Function New-SysAdminAudit {
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
    Write-Verbose "Creating New-SysAdminAudit"
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [string]$myCurrentInstanceConnectionString=$CurrentInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$AllowedUserConnections
    [ConnectionSpecification[]]$myAllowedServiceConnections=$AllowedServiceConnections
    [string]$myLogInstanceConnectionString=$LogInstanceConnectionString
    [string]$myLogTableName=$LogTableName
    [string]$myLogFilePath=$LogFilePath
    [SysAdminAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myCurrentInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogInstanceConnectionString,$myLogTableName,$myLogFilePath)
    Write-Verbose "New-SysAdminAudit Created"
}
Function New-SysAdminAuditByJsonConnSpec {
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
    Write-Verbose "Creating New-SysAdminAuditByJsonConnSpec"
    [int]$myLimitEventLogScanToRecentMinutes=$LimitEventLogScanToRecentMinutes
    [string]$myCentralTempInstanceConnectionString=$CentralTempInstanceConnectionString
    [string]$myCurrentInstanceConnectionString=$CurrentInstanceConnectionString
    [ConnectionSpecification[]]$myAllowedUserConnections=$null
    [ConnectionSpecification[]]$myAllowedServiceConnections=$null
    [string]$myLogInstanceConnectionString=$LogInstanceConnectionString
    [string]$myLogTableName=$LogTableName
    [string]$myLogFilePath=$LogFilePath
    [SysAdminAudit]$myAnswer=$null

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
        $myAnswer=[SysAdminAudit]::New($myLimitEventLogScanToRecentMinutes,$myCentralTempInstanceConnectionString,$myCurrentInstanceConnectionString,$myAllowedUserConnections,$myAllowedServiceConnections,$myLogInstanceConnectionString,$myLogTableName,$myLogFilePath)    
    }
    catch {
        Write-Verbose ($_.ToString())
    }
    Write-Verbose "New-SysAdminAuditByJsonConnSpec Created"
    return $myAnswer
}
#endregion

#region Export
Export-ModuleMember -Function New-SysAdminAudit,New-SysAdminAuditByJsonConnSpec
#endregion
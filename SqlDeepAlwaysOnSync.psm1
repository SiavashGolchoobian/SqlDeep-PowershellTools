Using module .\SqlDeepLogWriter.psm1
Import-Module SqlServer

Class AvailabilityGroupInfo{
    [string]$AvailabilityGroupName;
    [bool]$IsPrimaryAvailabilityGroup;
    [string]$ReplicaInstanceName;
    [bool]$IsReadOnlyAllowedReplica;
    [bool]$IsPrimaryReplica;
    [string]$DatabaseName;

    AvailabilityGroupInfo([string]$AvailabilityGroupName,[bool]$IsPrimaryAvailabilityGroup,[string]$ReplicaInstanceName,[bool]$IsReadOnlyAllowedReplica,[bool]$IsPrimaryReplica,[string]$DatabaseName){
        Write-Verbose 'AvailabilityGroupInfo object initializing started.'
        $this.AvailabilityGroupName=$AvailabilityGroupName;
        $this.IsPrimaryAvailabilityGroup=$IsPrimaryAvailabilityGroup;
        $this.ReplicaInstanceName=$ReplicaInstanceName;
        $this.IsReadOnlyAllowedReplica=$IsReadOnlyAllowedReplica;
        $this.IsPrimaryReplica=$IsPrimaryReplica;
        $this.DatabaseName=$DatabaseName;
        Write-Verbose 'AvailabilityGroupInfo object initialized.'
    }
}
Class DatabaseCommand{
    [int]$Id;
    [string]$DatabaseName;
    [string]$Command;
    [string]$CommandType;

    DatabaseCommand([int]$Id,[string]$DatabaseName,[string]$Command,[string]$CommandType){
        Write-Verbose 'DatabaseCommand object initializing started.'
        $this.Id=$Id;
        $this.DatabaseName=$DatabaseName;
        $this.Command=$Command;
        $this.CommandType=$CommandType;
        Write-Verbose 'DatabaseCommand object initialized.'
    }
}
Class DatabaseJob{
    [int]$JobId;
    [string]$JobName;
    [bool]$JobIsEnabled;
    [bool]$JobIsEnabledOnPrimary;
    [bool]$JobIsEnabledOnSecondary;
    [string]$CreateScript;

    DatabaseJob([int]$JobId,[string]$JobName,[bool]$JobIsEnabled,[bool]$JobIsEnabledOnPrimary,[bool]$JobIsEnabledOnSecondary,[string]$CreateScript){
        Write-Verbose 'Job object initializing started'
        $this.JobId=$JobId;
        $this.JobName=$JobName;
        $this.JobIsEnabled=$JobIsEnabled;
        $this.JobIsEnabledOnPrimary=$JobIsEnabledOnPrimary;
        $this.JobIsEnabledOnSecondary=$JobIsEnabledOnSecondary;
        $this.CreateScript=$CreateScript;
        Write-Verbose 'Job object initialized'
    }
    [string] DropScript(){
        [string]$myAnswer=$null;
        $myAnswer="IF EXISTS(SELECT 1 FROM [msdb].[dbo].[sysjobs] AS myJobs WITH (READPAST) WHERE [myJobs].[name]=N'" + ($This.JobName) + "') `nEXEC [msdb].[dbo].[sp_delete_job] @job_name=N'" + ($this.JobName) + "', @delete_unused_schedule=1"
        return $myAnswer
    }
}
Class DatabaseLinkedServer{
    [string]$LinkedServerName;
    [string]$CreateScript;

    DatabaseLinkedServer([string]$LinkedServerName,[string]$CreateScript){
        Write-Verbose 'LinkedServer object initializing started'
        $this.LinkedServerName=$LinkedServerName;
        $this.CreateScript=$CreateScript;
        Write-Verbose 'LinkedServer object initialized'
    }
}
Class AlwaysOnSync {
    [string]$SourceInstanceConnectionString;
    hidden [LogWriter]$LogWriter;
    hidden [string]$LogStaticMessage='';

    AlwaysOnSync(){}
    AlwaysOnSync([string]$SourceInstanceConnectionString,[LogWriter]$LogWriter){
        $this.Init($SourceInstanceConnectionString,$LogWriter);
    }
    hidden Init([string]$SourceInstanceConnectionString,[LogWriter]$LogWriter){
        $this.SourceInstanceConnectionString=$SourceInstanceConnectionString;
        $this.LogWriter=$LogWriter;
    }
#region Functions
hidden [AvailabilityGroupInfo[]] Get_AvailabilityGroupInfoCollection([string]$ConnectionString){      #Get list of databases with primary role and having readable secondaries
    $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
    [AvailabilityGroupInfo[]]$myAnswer=$null;
    [string]$myCommand=$null;

    $myCommand="
        SELECT 
            [myAvailabilityGroups].[name] AS AvailabilityGroupName,
            CASE [myAvailabilityGroupsStatus].[primary_recovery_health] WHEN 1 THEN 1 ELSE 0 END AS IsPrimaryAvailabilityGroup,
            [myAvailabilityReplicas].[replica_server_name] AS ReplicaInstanceName,
            CASE [myAvailabilityReplicas].[secondary_role_allow_connections] WHEN 2 THEN 1 ELSE 0 END AS IsReadOnlyAllowedReplica,
            CASE [myReplicaDatabaseState].[is_primary_replica] WHEN 1 THEN 1 ELSE 0 END AS IsPrimaryReplica,
            [myDatabases].[name] AS DatabaseName
        FROM 
            [master].[sys].[availability_groups] AS myAvailabilityGroups WITH (READPAST)
            INNER JOIN [master].[sys].[dm_hadr_availability_group_states] AS myAvailabilityGroupsStatus WITH (READPAST) ON [myAvailabilityGroupsStatus].[group_id]=[myAvailabilityGroups].[group_id]
            INNER JOIN [master].[sys].[availability_replicas] AS myAvailabilityReplicas WITH (READPAST) ON [myAvailabilityReplicas].[group_id]=[myAvailabilityGroups].[group_id]
            INNER JOIN [master].[sys].[dm_hadr_database_replica_states] AS myReplicaDatabaseState WITH (READPAST) ON [myReplicaDatabaseState].[replica_id]=[myAvailabilityReplicas].[replica_id]
            INNER JOIN [master].[sys].[databases] AS myDatabases WITH (READPAST) ON [myReplicaDatabaseState].[database_id]=[myDatabases].[database_id]
        WHERE
            [myAvailabilityGroupsStatus].[primary_recovery_health]=1	--Filter AG's are primary in current site
    "

    try{
        Write-Verbose $myCommand
        #$this.LogWriter.Write($this.LogStaticMessage+$myCommand,[LogType]::INF)
        $this.LogWriter.Write($this.LogStaticMessage+'Retrive list of primary mode availability groups replicas and databases.',[LogType]::INF)
        [System.Data.DataRow[]]$myRecords=$null
        $myRecords=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
        if ($null -ne $myRecords){
            [System.Collections.ArrayList]$myCollection=$null
            $myCollection=[System.Collections.ArrayList]::new()
            $myRecords|ForEach-Object{$myCollection.Add([AvailabilityGroupInfo]::New($_.AvailabilityGroupName,$_.IsPrimaryAvailabilityGroup,$_.ReplicaInstanceName,$_.IsReadOnlyAllowedReplica,$_.IsPrimaryReplica,$_.DatabaseName))}
            $myAnswer=$myCollection.ToArray([AvailabilityGroupInfo])
        }
    }Catch{
        $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        $myAnswer.Clear()
    }
    return $myAnswer
}
hidden [DatabaseCommand[]] Get_Logins([string]$ConnectionString,[string]$DatabaseName){     #Get list of Logins related to a database
    $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
    [string]$myCommand=$null;
    [DatabaseCommand[]]$myAnswer=$null;
    $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign

    $myCommand="
        SET NOCOUNT ON
        CREATE TABLE #myAnswer (Id INT IDENTITY PRIMARY KEY, DatabaseName sysname, Command NVARCHAR(MAX))
        DECLARE @myLoginCursor CURSOR
        DECLARE @myLoginName sysname
        DECLARE @mySidString VARCHAR(514)
        DECLARE @myLoginType CHAR(1)
        DECLARE @myIsDisabled BIT
        DECLARE @myDefaultDatabaseName sysname
        DECLARE @myDefaultLanguageName sysname
        DECLARE @myIsPolicyChecked BIT
        DECLARE @myIsExperationChecked BIT
        DECLARE @myHashedPasswordString NVARCHAR(514)
        DECLARE @myStatement NVARCHAR(MAX)
        DECLARE @myTemplateOfCreateSqlLogin NVARCHAR(MAX)
        DECLARE @myTemplateOfCreateWinLogin NVARCHAR(MAX)
        DECLARE @myTemplateOfAlterSqlLogin NVARCHAR(MAX)
        DECLARE @myTemplateOfAlterWinLogin NVARCHAR(MAX)
        DECLARE @myTemplateOfDefaultDatabase NVARCHAR(MAX)
        DECLARE @myTemplateOfDisableLogin NVARCHAR(MAX)
        DECLARE @myNewLine NVARCHAR(10)

        SET @myStatement=NULL
        SET @myNewLine=CHAR(13)+CHAR(10)
        SET @myTemplateOfCreateSqlLogin=N'CREATE LOGIN [<@myLoginName>] WITH Password=<@myHashedPasswordString> HASHED, SID=<@mySidString>, DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[<@myDefaultLanguageName>], CHECK_EXPIRATION=<@myIsExperationChecked>, CHECK_POLICY=<@myIsPolicyChecked>;'
        SET @myTemplateOfCreateWinLogin=N'CREATE LOGIN [<@myLoginName>] FROM WINDOWS WITH DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[<@myDefaultLanguageName>];'
        SET @myTemplateOfAlterSqlLogin=N'
        IF EXISTS (SELECT 1 FROM [master].[sys].[sql_logins] WHERE [name]=''<@myLoginName>'' AND [master].[sys].[fn_varbintohexstr](CAST([password_hash] AS VARBINARY(MAX)))=N''<@myHashedPasswordString>'')
        BEGIN
            ALTER LOGIN [<@myLoginName>] WITH DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[<@myDefaultLanguageName>], CHECK_EXPIRATION=<@myIsExperationChecked>, CHECK_POLICY=<@myIsPolicyChecked>;
        END
        ELSE
        BEGIN
            ALTER LOGIN [<@myLoginName>] WITH Password=<@myHashedPasswordString> HASHED, DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[<@myDefaultLanguageName>], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF;
            ALTER LOGIN [<@myLoginName>] WITH CHECK_EXPIRATION=<@myIsExperationChecked>, CHECK_POLICY=<@myIsPolicyChecked>;
        END'
        SET @myTemplateOfAlterWinLogin=N'ALTER LOGIN [<@myLoginName>] WITH DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[<@myDefaultLanguageName>];'
        SET @myTemplateOfDefaultDatabase=N'IF(SELECT [state] FROM [master].[sys].[databases] WITH (READPAST) WHERE [name]=''<@myDefaultDatabaseName>'')=0
            ALTER LOGIN [<@myLoginName>] WITH DEFAULT_DATABASE=[<@myDefaultDatabaseName>];'
        SET @myTemplateOfDisableLogin=N'ALTER LOGIN [<@myLoginName>] <@myIsDisabled>;'
        SET @myLoginCursor = CURSOR FOR

        SELECT
            [myLogins].[name] AS LoginName,
            CAST([master].[sys].[fn_varbintohexstr]([myLogins].[sid]) AS VARCHAR(514)) AS [SidString],
            [myLogins].[type] AS LoginType,
            [myLogins].[is_disabled] AS IsDisabled,
            [myLogins].[default_database_name] AS DefaultDatabaseName,
            [myLogins].[default_language_name] AS DefaultLanguageName,
            [mySqlLogins].[is_policy_checked] AS IsPolicyChecked,
            [mySqlLogins].[is_expiration_checked] AS IsExperationChecked,
            CASE WHEN [mySqlLogins].[password_hash] IS NOT NULL THEN [master].[sys].[fn_varbintohexstr](CAST([mySqlLogins].[password_hash] AS VARBINARY(MAX))) ELSE NULL END AS HashedPasswordString
        FROM
            ["+$DatabaseName+"].[sys].[database_principals] AS myUsers WITH (READPAST)
            INNER JOIN [master].[sys].[server_principals] AS myLogins WITH (READPAST) ON [myUsers].[sid]=[myLogins].[sid]
            LEFT OUTER JOIN [master].[sys].[sql_logins] AS mySqlLogins WITH (READPAST) ON [myLogins].[sid]=[mySqlLogins].[sid]
        WHERE
            [myLogins].[type] IN ('S', 'G', 'U') 
            AND [myLogins].[sid] <> 0x01	--sa
            AND [myLogins].[name] NOT LIKE '##%'
        ORDER BY
            [myLogins].[name]

        --Generate CREATE/ALTER login script
        OPEN @myLoginCursor
        FETCH NEXT FROM @myLoginCursor INTO @myLoginName,@mySidString,@myLoginType,@myIsDisabled,@myDefaultDatabaseName,@myDefaultLanguageName,@myIsPolicyChecked,@myIsExperationChecked,@myHashedPasswordString
        WHILE @@Fetch_Status = 0
        BEGIN
            SET @myStatement=CAST('' AS NVARCHAR(MAX))
            SET @myStatement=@myStatement +
            CAST(
            @myNewLine+ '--Login: ' + CAST(@myLoginName AS NVARCHAR(MAX))+
            @myNewLine+ N'USE [master];'+
            @myNewLine+ N'IF NOT EXISTS (SELECT 1 FROM [master].[sys].[server_principals] AS myLogins WITH (READPAST) WHERE [myLogins].[name]=''<@myLoginName>'')'+
            @myNewLine+ N'BEGIN'+
            @myNewLine+ CASE @myLoginType
                    WHEN 'S' THEN @myTemplateOfCreateSqlLogin
                    WHEN 'G' THEN @myTemplateOfCreateWinLogin
                    WHEN 'U' THEN @myTemplateOfCreateWinLogin
                END+
            @myNewLine+ N'END'+
            @myNewLine+ N'ELSE'+
            @myNewLine+ N'BEGIN'+
            @myNewLine+ CASE @myLoginType
                    WHEN 'S' THEN @myTemplateOfAlterSqlLogin
                    WHEN 'G' THEN @myTemplateOfAlterWinLogin
                    WHEN 'U' THEN @myTemplateOfAlterWinLogin
                END+
            @myNewLine+ N'END'+
            @myNewLine+ @myTemplateOfDefaultDatabase+
            @myNewLine+ @myTemplateOfDisableLogin
            AS NVARCHAR(MAX))
            SET @myStatement=REPLACE(@myStatement,'<@myLoginName>',@myLoginName)
            SET @myStatement=REPLACE(@myStatement,'<@mySidString>',@mySidString)
            SET @myStatement=REPLACE(@myStatement,'<@myIsDisabled>',CASE WHEN @myIsDisabled=1 THEN 'DISABLE' ELSE 'ENABLE' END)
            SET @myStatement=REPLACE(@myStatement,'<@myDefaultDatabaseName>',@myDefaultDatabaseName)
            SET @myStatement=REPLACE(@myStatement,'<@myDefaultLanguageName>',@myDefaultLanguageName)
            SET @myStatement=REPLACE(@myStatement,'<@myIsPolicyChecked>',CASE @myIsPolicyChecked WHEN 1 THEN 'ON' ELSE 'OFF' END)
            SET @myStatement=REPLACE(@myStatement,'<@myIsExperationChecked>',CASE @myIsExperationChecked WHEN 1 THEN 'ON' ELSE 'OFF' END)
            SET @myStatement=REPLACE(@myStatement,'<@myHashedPasswordString>',@myHashedPasswordString)
            INSERT INTO [#myAnswer]([DatabaseName],[Command]) VALUES (N'"+$DatabaseName+"',@myStatement)
            FETCH NEXT FROM @myLoginCursor INTO @myLoginName,@mySidString,@myLoginType,@myIsDisabled,@myDefaultDatabaseName,@myDefaultLanguageName,@myIsPolicyChecked,@myIsExperationChecked,@myHashedPasswordString
        END
        CLOSE @myLoginCursor;
        DEALLOCATE @myLoginCursor;
        SELECT [Id],[DatabaseName],[Command] FROM #myAnswer
        DROP TABLE [#myAnswer]
    "

    try{
        Write-Verbose $myCommand
        #$this.LogWriter.Write($this.LogStaticMessage+$myCommand,[LogType]::INF)
        $this.LogWriter.Write($this.LogStaticMessage+'Retrive list of logins script related to database with primary role.',[LogType]::INF)
        [System.Data.DataRow[]]$myRecords=$null
        $myRecords=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
        if ($null -ne $myRecords){
            [System.Collections.ArrayList]$myCollection=$null
            $myCollection=[System.Collections.ArrayList]::new()
            $myRecords|ForEach-Object{$myCollection.Add([DatabaseCommand]::New($_.Id,$_.DatabaseName,$_.Command,'LOGIN'))}
            $myAnswer=$myCollection.ToArray([DatabaseCommand])
        }
    }Catch{
        $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        $myAnswer.Clear()
    }
    return $myAnswer
}
hidden [DatabaseJob[]] Get_Jobs([string]$ConnectionString,[string]$DatabaseName){       #Get list of Jobs related to a database
    $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
    [string]$myCommand=$null;
    [DatabaseJob[]]$myAnswer=$null;
    [Microsoft.SqlServer.Management.Smo.SqlSmoObject]$mySqlServer=$null;

    $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign

    $myCommand="
        DECLARE @myJobs XML
        SET @myJobs=
            (
            SELECT 
                CAST(CAST([myProperty].[value] AS NVARCHAR(MAX)) AS XML)
            FROM 
                [" + $DatabaseName + "].[sys].[extended_properties] AS myProperty WITH (READPAST)
            WHERE 
                [myProperty].[class]=0
                AND [myProperty].[name]=N'_AlwaysOnJobs'
            )

        SELECT 
            [myJobs].[job_id] AS JobId,
            [myXML].[Jobs].value('@name','nvarchar(255)') AS JobName,
            CAST([myJobs].[enabled] AS BIT) AS JobIsEnabled,
            [myXML].[Jobs].value('@enabled_on_primary','bit') AS JobIsEnabledOnPrimary,
            [myXML].[Jobs].value('@enabled_on_secondary','bit') AS JobIsEnabledOnSecondary
        FROM
            @myJobs.nodes('/jobs/job') myXML(Jobs)
            INNER JOIN [msdb].[dbo].[sysjobs] AS myJobs WITH (READPAST) ON [myJobs].[name]=[myXML].[Jobs].value('@name','nvarchar(255)')
    "
    try{
        Write-Verbose $myCommand
        #$this.LogWriter.Write($this.LogStaticMessage+$myCommand,[LogType]::INF)
        $this.LogWriter.Write($this.LogStaticMessage+'Retrive list of job(s) related to database with primary role.',[LogType]::INF)
        [System.Data.DataRow[]]$myRecords=$null
        $myRecords=Invoke-Sqlcmd -ConnectionString $this.SourceInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
        if ($null -ne $myRecords){
            $mySqlServer=New-Object ('Microsoft.SqlServer.Management.Smo.Server')
            $mySqlServer.ConnectionContext.ConnectionString=$ConnectionString
            $myScriptOption = New-Object ('Microsoft.SqlServer.Management.Smo.ScriptingOptions')
            $myScriptOption.IncludeDatabaseContext = $true
            $myScriptOption.ScriptOwner = $true
            $myScriptOption.PrimaryObject = $true
            $myScriptOption.ScriptSchema = $true
            $myScriptOption.ScriptData = $false
            $myScriptOption.ScriptDrops = $false
            [System.Collections.ArrayList]$myCollection=$null
            $myCollection=[System.Collections.ArrayList]::new()
            $myRecords|ForEach-Object{
                $myCreateScript=$mySqlServer.JobServer.GetJobByID($_.JobId).Script($myJobScriptOption)
                $myCollection.Add([DatabaseJob]::New($_.JobId,$_.JobName,$_.JobIsEnabled,$_.JobIsEnabledOnPrimary,$_.JobIsEnabledOnSecondary,$myCreateScript))
            }
            $myAnswer=$myCollection.ToArray([DatabaseJob])
        }
    }Catch{
        $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        $myAnswer.Clear()
    }
    return $myAnswer
}
hidden [DatabaseLinkedServer[]] Get_LinkedServers([string]$ConnectionString,[string]$DatabaseName){       #Get list of LinkedServes related to a database
    $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
    [string]$myCommand=$null;
    [DatabaseLinkedServer[]]$myAnswer=$null;
    [Microsoft.SqlServer.Management.Smo.SqlSmoObject]$mySqlServer=$null;

    $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign

    $myCommand="
        DECLARE @myLinkedServers XML
        SET @myLinkedServers=
        (
        SELECT TOP 1
            CAST(CAST([myProperty].[value] AS NVARCHAR(MAX)) AS XML)
        FROM 
            ["+$DatabaseName+"].[sys].[extended_properties] AS myProperty WITH (READPAST)
        WHERE 
            [myProperty].[class]=0
            AND [myProperty].[name]=N'_AlwaysOnLinkedServers'
        )
        
        SELECT 
            [myXML].[Links].value('@name','nvarchar(255)') AS LinkedServerName
        FROM
            @myLinkedServers.nodes('/linkedservers/linkedserver') myXML(Links)
            INNER JOIN [master].[sys].[sysservers] AS [myLinkedServer] WITH (READPAST) ON [myLinkedServer].[srvname]=[myXML].[Links].value('@name','nvarchar(255)')
    "
    try{
        Write-Verbose $myCommand
        #$this.LogWriter.Write($this.LogStaticMessage+$myCommand,[LogType]::INF)
        $this.LogWriter.Write($this.LogStaticMessage+'Retrive list of LinkedServer(s) related to database ['+$DatabaseName+'] with primary role.',[LogType]::INF)
        [System.Data.DataRow[]]$myRecords=$null
        $myRecords=Invoke-Sqlcmd -ConnectionString $this.SourceInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
        if ($null -ne $myRecords){
            $mySqlServer=New-Object ('Microsoft.SqlServer.Management.Smo.Server')
            $mySqlServer.ConnectionContext.ConnectionString=$ConnectionString
            $myScriptOption = New-Object ('Microsoft.SqlServer.Management.Smo.ScriptingOptions')
            $myScriptOption.IncludeDatabaseContext = $true
            $myScriptOption.ScriptOwner = $true
            $myScriptOption.PrimaryObject = $true
            [System.Collections.ArrayList]$myCollection=$null
            $myCollection=[System.Collections.ArrayList]::new()
            $myRecords|ForEach-Object{
                $myCreateScript=$mySqlServer.LinkedServers.Item($_.LinkedServerName).Script($myScriptOption)
                $myCreateScript="IF NOT EXISTS (SELECT 1 FROM [master].[sys].[sysservers] AS [myLinkedServer] WITH (READPAST) WHERE [myLinkedServer].[srvname]=N'"+($_.LinkedServerName)+"' `nBEGIN "+$myCreateScript+"`nEND"
                $myCollection.Add([DatabaseLinkedServer]::New($_.LinkedServerName,$myCreateScript))
            }
            $myAnswer=$myCollection.ToArray([DatabaseLinkedServer])
        }
    }Catch{
        $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        $myAnswer.Clear()
    }
    return $myAnswer
}
[void] Sync(){
    try {
        [AvailabilityGroupInfo[]]$myAvailabilityGroupInfoCollection=$null;
        [DatabaseCommand[]]$myLogins=$null;
        [DatabaseJob[]]$myJobs=$null;

        $myAvailabilityGroupInfoCollection=$this.Get_AvailabilityGroupInfoCollection($this.SourceInstanceConnectionString)
        $myLogins=$this.Get_Logins($this.SourceInstanceConnectionString,'SqlDeep')
        $myJobs=$this.Get_Jobs($this.SourceInstanceConnectionString,'SqlDeep')
    }
    catch {
        $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
    }
}
#endregion
}

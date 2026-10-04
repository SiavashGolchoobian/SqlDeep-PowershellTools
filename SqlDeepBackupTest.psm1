Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepDatabaseShipping.psm1
Using module .\SqlDeepCommon.psm1

enum TestResult {
    RestoreSuccseed = 1
    RestoreFailed = -1
    CheckDbSuccseed = 2
    CheckDbFailed = -2
    }
Class BackupTestCatalogItem {
    [bigint]$Id
    [string]$InstanceName
    [string]$DatabaseName
    [int]$TestResult
    [datetime]$BackupRestoredTime
    [datetime]$BackupStartTime
    [datetime]$SysRowVersion
    [string]$TestResultDescription
    [bigint]$HashValue
    [datetime]$FinishTime
   
    BackupTestCatalogItem([bigint]$Id,[string]$InstanceName,[string]$DatabaseName,[int]$TestResult,[datetime]$BackupRestoredTime,[datetime]$BackupStartTime,[datetime]$SysRowVersion,[string]$TestResultDescription,[bigint]$HashValue,[datetime]$FinishTime){
        Write-Verbose 'BackupCatalogItem object initializing started'
        $this.Id=$Id
        $this.InstanceName=$InstanceName
        $this.DatabaseName=$DatabaseName
        $this.TestResult=$TestResult
        $this.BackupRestoredTime=$BackupRestoredTime
        $this.BackupStartTime=$BackupStartTime
        $this.SysRowVersion=$SysRowVersion
        $this.TestResultDescription=$TestResultDescription
        $this.HashValue=$HashValue
        $this.FinishTime=$FinishTime
        Write-Verbose 'BackupCatalogItem object initialized'
    }
}
Class BackupTest:DatabaseShipping {
    [string]$BackupTestCatalogTableName;
    [nullable[datetime]]$StartDate ;
    [nullable[datetime]]$EndDate ;
     
BackupTest():base() {
    $this.Init($null)
}
BackupTest([string]$BackupTestCatalogTableName) : base() {
    $this.Init($BackupTestCatalogTableName)
}
hidden Init ([string]$BackupTestCatalogTableName)
{  
    $this.BackupTestCatalogTableName=$BackupTestCatalogTableName
    if($null -eq $this.BackupTestCatalogTableName -or $this.BackupTestCatalogTableName.Trim().Length -eq 0){$this.BackupTestCatalogTableName='BackupTest'}
}

#region Functions
    hidden [datetime] GenerateRandomDate([nullable[DateTime]]$StartDate, [nullable[DateTime]]$EndDate) {
        [nullable[DateTime]]$myStartDate = $StartDate
        [nullable[DateTime]]$myEndDate = $EndDate
        
        if($null -eq $myStartDate -and $null -eq $myEndDate)
        {
            $this.LogWriter.Write($this.LogStaticMessage+'StartDate and EndDate is empty . set random date between 5 days ago.', [LogType]::INF)
            $myStartDate =  (Get-Date).AddDays(-5) 
            $myEndDate = Get-Date
        }
        elseif ($null -eq $myStartDate -and $null -ne $myEndDate) {  
            $this.LogWriter.Write($this.LogStaticMessage + ' StartDate is empty. Setting StartDate to EndDate - 5 days.', [LogType]::INF)  
            $myStartDate = $myEndDate.AddDays(-5)  
        }  
        # Check if only EndDate is null  
        elseif ($null -ne $myStartDate -and $null -eq $myEndDate) {  
            $this.LogWriter.Write($this.LogStaticMessage + ' EndDate is empty. Setting EndDate to StartDate + 5 days.', [LogType]::INF)  
            $myEndDate = $myStartDate.AddDays(5)  
        }  
        elseif ($myStartDate -gt $myEndDate) {  
            $this.LogWriter.Write($this.LogStaticMessage+'StartDate must be less than or equal to EndDate .', [LogType]::INF)
            $myStartDate=$EndDate
            $myEndDate=$StartDate
        }  
        $myRandomDate = Get-Random -Minimum $myStartDate.Ticks -Maximum $myEndDate.Ticks
     return $myRandomDate =[datetime]($myRandomDate)
    }
    hidden [bool] CreateBackupTestCatalog() {   #Create Log Table to Write Logs of transfered files in a table, if not exists
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [bool]$myAnswer=[bool]$true
        [string]$myCommand=$null
    
        $this.BackupTestCatalogTableName=Clear-SqlParameter -ParameterValue $this.BackupTestCatalogTableName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        $myCommand="
        DECLARE @myTableName nvarchar(255)
        SET @myTableName=N'"+ $this.BackupTestCatalogTableName +"'
        
        IF NOT EXISTS (
            SELECT 
                1
            FROM 
                [sys].[all_objects] AS myTable
                INNER JOIN [sys].[schemas] AS mySchema ON [myTable].[schema_id]=[mySchema].[schema_id]
            WHERE 
                [mySchema].[name] + '.' + [myTable].[name] = [mySchema].[name] + '.' + REPLACE(REPLACE(@myTableName,'[',''),']','')
        ) BEGIN
         CREATE TABLE [dbo].[" + $this.BackupTestCatalogTableName + "](
       
            [Id] [BIGINT] IDENTITY(1,1) NOT NULL,
            [InstanceName] [NVARCHAR](128) NOT NULL,
            [DatabaseName] [NVARCHAR](128) NOT NULL,
            [TestResult] [INT] NOT NULL,
            [BackupRestoredTime] [DATETIME] NOT NULL,
            [BackupStartTime] [DATETIME] NULL,
            [SysRowVersion] [TIMESTAMP] NOT NULL,
            [TestResultDescription] [NCHAR](50) NULL,
            [HashValue]  AS (BINARY_CHECKSUM([InstanceName],[DatabaseName])),
            [FinishTime] [DATETIME] NULL
         CONSTRAINT [PK_dbo_"+$this.BackupTestCatalogTableName+"] PRIMARY KEY CLUSTERED 
        (
            [Id] ASC
        )WITH (PAD_INDEX = ON, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
        ) ON [PRIMARY];
        
    
        ALTER TABLE [dbo].["+$this.BackupTestCatalogTableName+"] ADD  CONSTRAINT [DF_"+$this.BackupTestCatalogTableName+"_FinishDate]  DEFAULT (GETDATE()) FOR [FinishTime];
		END
        "
        try{
            Write-Verbose $myCommand
            Invoke-Sqlcmd -ConnectionString ($this.LogWriter.LogInstanceConnectionString) -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myAnswer=[bool]$false
        }
        return $myAnswer
    }
    hidden [bool] IsTested([string]$SourceInstanceName, [datetime]$RecoveryDateTime, [string]$DatabaseName) {
        $this.LogWriter.Write($this.LogStaticMessage+'Processing check is tested Database name in backup test cataloge Started.', [LogType]::INF)
        $this.BackupTestCatalogTableName=Clear-SqlParameter -ParameterValue $this.BackupTestCatalogTableName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        $SourceInstanceName=Clear-SqlParameter -ParameterValue $SourceInstanceName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        [bool]$myResult=$false
        [string]$myQuery = 
        "
        DECLARE @myHashValue AS INT
        DECLARE @myRecoveryDateTime AS DateTime
        DECLARE @myDBName AS NVARCHAR(50)

        SET @myHashValue = BINARY_CHECKSUM('"+ $DatabaseName + "','"+ $SourceInstanceName + "')
        SET @myRecoveryDateTime = CAST('" + $RecoveryDateTime.ToString() + "' AS DATETIME)

        SELECT COUNT(1) As myResult
        FROM [dbo].["+$this.BackupTestCatalogTableName+"]
        Where [HashValue] = @myHashValue 
        AND @myRecoveryDateTime BETWEEN [BackupStartTime] AND [BackupRestoredTime]
        "
        try{
            $myResultCheckDate = Invoke-Sqlcmd -ConnectionString ($this.LogWriter.LogInstanceConnectionString) -Query $myQuery -OutputSqlErrors $true -OutputAs DataRows
            if ($null -ne $myResultCheckDate) {
                $myResult = $false
            } else {
                if ($myResultCheckDate[0] -eq 0 ) {
                    $myResult = $false
                }
                else {
                    $myResult = $true
                }
            }
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myResult=$false
        }
    return $myResult
    }
    hidden [bool] TestDatabaseIntegrity([string]$DestinationDatabaseName) {
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Test Database Integrity Started.', [LogType]::INF)
        [bool]$myResult = $false
        $myCommand = "
        DECLARE @myDBName AS sysname
        SET @myDBName = CAST(N'"+$DestinationDatabaseName+"' AS sysname);
        
        DBCC CHECKDB (@myDBName) WITH NO_INFOMSGS;
        "
        try{
            $myResult = Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString  -Query $myCommand -OutputSqlErrors $true -OutputAs DataTables -ErrorAction Stop 
            if ($null -eq $myResult) {$myResult=$true}
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myResult=$false
        }
    return $myResult
    }
    hidden [void] SaveResultToBackupTestCatalog([string]$DatabaseName,[TestResult]$TestResult,[datetime]$RecoveryDateTime,[nullable[datetime]]$BackupStartDate) {
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Save Result To Backup Test Catalog Started.', [LogType]::INF)
        [string]$myCommand=$null;
        [string]$myBackupStartDateCommand=$null;

        $mySourceInstanceInstanceInfo=Get-InstanceInformation -ConnectionString $this.SourceInstanceConnectionString -ShowRelatedInstanceOnly
        $mySourceInstanceName=$mySourceInstanceInstanceInfo.MachineNameDomainNameInstanceNamePortNumber

        if ($null -eq $BackupStartDate) {$myBackupStartDateCommand='NULL'} else {$myBackupStartDateCommand="CAST('" + $BackupStartDate.ToString() + "' AS DATETIME)"}
        $myCommand = "
        DECLARE @myRecoveryDateTime AS DateTime
        DECLARE @myBackupStartTime AS DateTime
        SET @myRecoveryDateTime = CAST('" + ($RecoveryDateTime.ToString()) + "' AS DATETIME)
        SET @myBackupStartTime = " + $myBackupStartDateCommand + "
  
        INSERT INTO [dbo].["+$this.BackupTestCatalogTableName+"] ([InstanceName], [DatabaseName], [TestResult], [TestResultDescription], [BackupRestoredTime],[BackupStartTime])
        VALUES (N'"+ $mySourceInstanceName +"', N'"+ $DatabaseName +"', "+($TestResult.value__).ToString() +", N'"+ $TestResult +"', @myRecoveryDateTime ,@myBackupStartTime)
        "
        try{
            Write-Verbose $myCommand
            Invoke-Sqlcmd -ConnectionString ($this.LogWriter.LogInstanceConnectionString) -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
    }
    hidden [void] DropDatabase ([string]$DatabaseName){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing drop database Started.', [LogType]::INF)
        [string]$myCommand=
        "
        DECLARE @myDatabaseName sysname
        SET @myDatabaseName = N'" + $DatabaseName + "'
        IF EXISTS (SELECT 1 FROM sys.databases WHERE [name] = @myDatabaseName)
            BEGIN
                DROP DATABASE [" + $DatabaseName + "]
            END
        "
        try{
            Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
    }
    [void] TestAllDatabases([string[]]$ExcludedDatabaseList){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        $myDatabaseList=Get-DatabaseList -ConnectionString $this.SourceInstanceConnectionString -ExcludedList $ExcludedDatabaseList
        foreach($myDatabase in $myDatabaseList){
            $this.TestDatabase($myDatabase.DatabaseName)
        }
    }
    [void] TestFromRegisterServer([string[]]$ExcludedInstanceList,[string[]]$ExcludedDatabaseList,[string]$RegisteryCategoryName){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        $myServerList = Get-InfoFromSqlRegisteredServers -MonitoringConnectionString $this.SourceInstanceConnectionString -ExcludedList $ExcludedInstanceList -FilterGroup $RegisteryCategoryName # Get Server list from MSX
        
        foreach ($myServer in $myServerList){
            $this.SourceInstanceConnectionString=$myServer.EncryptConnectionString
            $this.TestAllDatabases($ExcludedDatabaseList)
        }
    }
    [void] TestFromQueryResult([string]$ConnectionStringQuery,[string[]]$ExcludedDatabaseList){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [System.Data.DataRow[]]$myServerList=$null
        $myServerList=Invoke-Sqlcmd -ConnectionString $this.SourceInstanceConnectionString -Query $ConnectionStringQuery -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
        if ($null -ne $myServerList) {
            foreach ($myServer in $myServerList){
                $this.SourceInstanceConnectionString=$myServer.ConnectionString
                $this.TestAllDatabases($ExcludedDatabaseList)
            }
        }
    }
    [void] TestDatabase([string]$DatabaseName){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        #Set Constr
        [int]$myExecutionId=1;
        [string]$myDestinationDatabaseName=$null;
        [int]$myOriginalLimitMsdbScanToRecentHours=0;
        [string]$myOriginalLogFilePath=$null;
        [bool]$myIsDatabaseRestored=$false;
        [bool]$myDatabaseIsValid=$false;
        [string]$myCommand=$null;
        [nullable[DateTime]]$myBackupStartDate=$null

        try{
            $myOriginalLogFilePath=$this.LogWriter.LogFilePath
            $this.LogWriter.LogFilePath=$this.LogWriter.LogFilePath.Replace('{Database}',$DatabaseName)
            $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
            $myExecutionId=Get-Random -Minimum 1 -Maximum 1000
            $myDestinationDatabaseName=$DatabaseName+$myExecutionId
            $this.LogWriter.Write($this.LogStaticMessage+'Destinarion Database name: '+$myDestinationDatabaseName,[LogType]::INF)

            #Determine candidate server(s)
            $this.LogWriter.Write($this.LogStaticMessage+'Get Source instance server name: '+$this.SourceInstanceConnectionString,[LogType]::INF)
            $mySourceInstanceInfo=Get-InstanceInformation -ConnectionString $this.SourceInstanceConnectionString -ShowRelatedInstanceOnly
            if ($mySourceInstanceInfo.PsObject.Properties.Name -eq 'MachineName') {  
                $mySourceServerName=$mySourceInstanceInfo.MachineName
                $mySourceInstanceName=$mySourceInstanceInfo.MachineNameDomainNameInstanceNamePortNumber
                $this.LogWriter.Write($this.LogStaticMessage+'Source server name is ' + $mySourceServerName + ' and Instance name is ' + $mySourceInstanceName,[LogType]::INF)
            } else {
                $this.LogWriter.Write($this.LogStaticMessage+'Get-InstanceInformation failure.', [LogType]::ERR) 
                throw ('Get-InstanceInformation failure.')
            }
            if ($null -eq $mySourceServerName -or $mySourceServerName.Length -eq 0) {
                $this.LogWriter.Write($this.LogStaticMessage+'Source server name is empty.',[LogType]::ERR)
                throw 'Source server name is empty.'
            }

            #Determine database is not in simple recovery model
            $this.LogWriter.Write($this.LogStaticMessage+'Validate Source database recovery model.',[LogType]::INF)
            $myCommand = "
            SELECT CAST(
                CASE WHEN EXISTS (
                    SELECT 1
                    FROM master.sys.databases
                    WHERE recovery_model <> 3
                    AND name = N'"+$DatabaseName+"'
                ) THEN 1 ELSE 0 END
            AS BIT) AS IsValid;
            ";
            $myDatabaseIsValid = (Invoke-Sqlcmd -ConnectionString $this.SourceInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop).IsValid
            if ($myDatabaseIsValid -eq $false) {
                $this.LogWriter.Write($this.LogStaticMessage+'Source server database is in simple recovery model.',[LogType]::ERR)
                throw 'Source server database is in simple recovery model.'
            }else{
                $this.LogWriter.Write($this.LogStaticMessage+'Source server database is not in simple recovery model.',[LogType]::INF)
            }

            #Determine restoresd server
            $this.LogWriter.Write($this.LogStaticMessage+'Get Destination instance server name: ' + $this.DestinationInstanceConnectionString,[LogType]::INF)
            $myDestinationInstanceInfo=Get-InstanceInformation -ConnectionString $this.DestinationInstanceConnectionString -ShowRelatedInstanceOnly
            $myDestinationInstanceName=$myDestinationInstanceInfo.MachineNameDomainNameInstanceNamePortNumber

            #Initial Log Modules
            Write-Verbose ('===== Testbackup database  ' + $DatabaseName + ' on ' + $mySourceInstanceName + ' started. =====')
            $this.LogStaticMessage= '{"SourceDB":"' + $DatabaseName+ '","SourceInstance":"' + $mySourceInstanceName+'"} : '
        # $this.LogWriter.LogFilePath=$this.LogWriter.LogFilePath.Replace('{Database}',$myDestinationDatabaseName)
            $this.LogWriter.Reinitialize()
            $this.LogWriter.Write($this.LogStaticMessage+'===== BackupTest process started... ===== ', [LogType]::INF) 
            $this.LogWriter.Write($this.LogStaticMessage+('TestDatabase ' + $DatabaseName + ' on ' + $mySourceInstanceName), [LogType]::INF) 
            $this.LogWriter.Write($this.LogStaticMessage+'Initializing EventsTable.Create.', [LogType]::INF) 
        # $this.RestoreTo=Clear-SqlParameter -ParameterValue $this.RestoreTo -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
            if($null -eq $this.RestoreTo)
            {
                $this.RestoreTo=$this.GenerateRandomDate($this.StartDate,$this.EndDate)
                $this.LogWriter.Write($this.LogStaticMessage+('RestoreTo is :' + $this.RestoreTo),[LogType]::INF);
            }
            
            $myOriginalLimitMsdbScanToRecentHours=$this.LimitMsdbScanToRecentHours;
            $this.LogWriter.Write($this.LogStaticMessage+('Origina lLimit Msdb Scan To Recent Hours is :' + $myOriginalLimitMsdbScanToRecentHours), [LogType]::INF) 
            if ($this.RestoreTo -lt (Get-Date).AddHours(-1*$this.LimitMsdbScanToRecentHours)) {
                $this.LimitMsdbScanToRecentHours= ((Get-Date)-($this.RestoreTo)).Hour;
            }
            #--=======================Check shipped files catalog table connectivity
            $this.LogWriter.Write($this.LogStaticMessage+'Test catalog table connectivity.', [LogType]::INF) 
            if ((Test-DatabaseConnection -ConnectionString ($this.LogWriter.LogInstanceConnectionString) -DatabaseName 'master') -eq $false) {
                $this.LogWriter.Write($this.LogStaticMessage+'Can not connect to sql instance on ' + $this.LogWriter.LogInstanceConnectionString, [LogType]::ERR) 
                throw ($this.LogStaticMessage+'Can not connect to sql instance.')
            }
            $this.LogWriter.Write($this.LogStaticMessage+'Initializing  catalog table.', [LogType]::INF)
            if ($this.CreateBackupTestCatalog() -eq $false)  {
                $this.LogWriter.Write($this.LogStaticMessage+'Can not initialize table to save catalog on ' + $this.LogWriter.LogInstanceConnectionString + ' to ' + $this.BackupShippingCatalogTableName + ' table.', [LogType]::ERR) 
                throw ($this.LogStaticMessage+' catalog initialization failed.')
            }
            #Has this database been tested on this date?
            $this.LogWriter.Write($this.LogStaticMessage+('in time :' + $this.RestoreTo+' does not have any test record'),[LogType]::INF);
            Write-Host $mySourceInstanceName,$this.RestoreTo.DateTime,$DatabaseName
            if($this.IsTested($mySourceInstanceName,($this.RestoreTo.DateTime),$DatabaseName) -eq $false){

               if ($myDestinationInstanceName -ne $mySourceInstanceName) { #Do not restore any database when Source instance is equal to Destination instance (Because of operational database replacement)
                    #Restore database to destination
                    try {
                        $this.LogWriter.Write($this.LogStaticMessage+('restored database with name:' + $myDestinationDatabaseName),[LogType]::INF);
                        $this.DestinationRestoreMode=[DatabaseRecoveryMode]::RECOVERY
                        $this.PreferredStrategies=[RestoreStrategy]::FullDiffLog,[RestoreStrategy]::FullLog,[RestoreStrategy]::DiffLog,[RestoreStrategy]::Log
                        $this.RestoreFilesToIndividualFolders = $false
                        $this.ShipDatabase($DatabaseName,$myDestinationDatabaseName)
                        $this.LogWriter.Write($this.LogStaticMessage+('ShipDatabase ' + $DatabaseName + ' on ' + $mySourceInstanceName + ' with new name ' + $myDestinationDatabaseName), [LogType]::INF) 
                        $myIsDatabaseRestored=Test-DatabaseConnection -ConnectionString $this.DestinationInstanceConnectionString -DatabaseName $myDestinationDatabaseName -AccesibilityCheck
                        $this.LogWriter.Write($this.LogStaticMessage+('Test database Connection '+ $myDestinationDatabaseName + ' on ' + $myDestinationInstanceName ), [LogType]::INF) 
                        if ($myIsDatabaseRestored -eq $true) {
                            $myTestResult = [TestResult]::RestoreSuccseed
                            $this.LogWriter.Write($this.LogStaticMessage+('Result of restored database is  ' + $myTestResult), [LogType]::INF) 
                            $myBackupStartDate = ($this.BackupFileList | Where-Object -Property DatabaseName -EQ $DatabaseName | Sort-Object -Property BackupStartTime |Select-Object -Property BackupStartTime -First 1).BackupStartTime
                            $this.LogWriter.Write($this.LogStaticMessage+('Backup start time is  ' + $myBackupStartDate), [LogType]::INF) 
                        } else {
                            $this.LogWriter.Write($this.LogStaticMessage+('Failed to restore database ' + $myDestinationDatabaseName + ' to destination.'),[LogType]::ERR);
                            $myTestResult = [TestResult]::RestoreFailed
                        }
                    } catch {
                        $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
                        $myTestResult = [TestResult]::RestoreFailed
                    } finally {
                        #Save Restore Result
                        $myIsDatabaseRestored=Test-DatabaseConnection -ConnectionString $this.DestinationInstanceConnectionString -DatabaseName $myDestinationDatabaseName
                        $this.LogWriter.Write($this.LogStaticMessage+('Save Restore Result ' + $myTestResult + ' for ' + $myDestinationDatabaseName + ' into tabale  ' +  $this.BackupTestCatalogTableName ), [LogType]::INF) 
                        $this.SaveResultToBackupTestCatalog($DatabaseName,$myTestResult,($this.RestoreTo.DateTime),$myBackupStartDate)
                        #$this.BackupFileList |  Select-Object -Unique -Property RemoteRepositoryUncFilePath | ForEach-Object{Remove-Item -Path ($_.RemoteRepositoryUncFilePath); $this.LogWriter.Write($this.LogStaticMessage+('Remove file ' + $_.RemoteRepositoryUncFilePath),[LogType]::INF)}
                        foreach ($myFile in ($this.BackupFileList | Select-Object -Unique -Property RemoteRepositoryUncFilePath)){ 
                            if(Test-Path $myFile.RemoteRepositoryUncFilePath){
                                Remove-Item -Path ($myFile.RemoteRepositoryUncFilePath); 
                                $this.LogWriter.Write($this.LogStaticMessage+('Remove file ' + $myFile.RemoteRepositoryUncFilePath),[LogType]::INF)
                            }
                            else {
                                $this.LogWriter.Write($this.LogStaticMessage+('File dose not exist ' + $myFile.RemoteRepositoryUncFilePath),[LogType]::WRN)
                            }
                        }
                    }
                    
                    #Checkdb
                    if ($myTestResult -eq [TestResult]::RestoreSuccseed) {
                        try {
                            $this.LogWriter.Write($this.LogStaticMessage+('checkdb on database:' + $myDestinationDatabaseName),[LogType]::INF); 
                            $this.TestDatabaseIntegrity($myDestinationDatabaseName)
                            $myTestResult = [TestResult]::CheckDbSuccseed
                            $this.LogWriter.Write($this.LogStaticMessage+('checkdb on database:' + $myDestinationDatabaseName + ' has Succseed'),[LogType]::INF); 
                        } catch {
                            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
                            $myTestResult = [TestResult]::CheckDbFailed
                            $this.LogWriter.Write($this.LogStaticMessage+('checkdb on database:' + $myDestinationDatabaseName + ' has Failed'),[LogType]::INF); 
                        } finally {
                            $this.SaveResultToBackupTestCatalog($DatabaseName,$myTestResult,($this.RestoreTo.DateTime),$myBackupStartDate)
                            $this.LogWriter.Write($this.LogStaticMessage+('Save Checkdb Result ' + $myTestResult + ' for ' + $myDestinationDatabaseName + ' into tabale  ' +  $this.BackupTestCatalogTableName ), [LogType]::INF) 
                        }
                    }
                    #Remove database
                    if ($myIsDatabaseRestored) {
                        try {
                            $this.LogWriter.Write($this.LogStaticMessage+('remove database:' + $myDestinationDatabaseName),[LogType]::INF); 
                            $this.DropDatabase($myDestinationDatabaseName)
                            $this.LogWriter.Write($this.LogStaticMessage+('remove database:' + $myDestinationDatabaseName + ' is Succsesfully. '),[LogType]::INF); 
                        }
                        catch {
                            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
                        }
                    }
                } else {
                    $this.LogWriter.Write($this.LogStaticMessage+('Destination instance is same as Source instance.'),[LogType]::ERR); 
                }
            }
        } catch {
            Write-Error ($_.ToString())
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        } finally {
            #Re-assign original value
            $this.LimitMsdbScanToRecentHours=$myOriginalLimitMsdbScanToRecentHours;
            $this.LogWriter.LogFilePath=$myOriginalLogFilePath;
        }
    }
 
#endregion
}
#region Functions
Function New-DatabaseTest {
    Param(
        [Parameter(Mandatory=$true)][string]$SourceInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$DestinationInstanceConnectionString,
        [Parameter(Mandatory=$false)][string]$BackupTestCatalogTableName,
        [Parameter(Mandatory=$true)][string]$FileRepositoryUncPath,
        [Parameter(Mandatory=$true)][LogWriter]$LogWriter
    )
    Write-Verbose 'Creating New-DatabaseTest'
    [BackupTest]$myAnswer=$null
    [string]$mySourceInstanceConnectionString=$SourceInstanceConnectionString
    [string]$myDestinationInstanceConnectionString=$DestinationInstanceConnectionString
    [string]$myBackupTestCatalogTableName=$BackupTestCatalogTableName
    [LogWriter]$myLogWriter=$LogWriter
    $myAnswer=[BackupTest]::New($myBackupTestCatalogTableName)
    $myAnswer.SourceInstanceConnectionString=$mySourceInstanceConnectionString
    $myAnswer.DestinationInstanceConnectionString=$myDestinationInstanceConnectionString
    $myAnswer.FileRepositoryUncPath = $FileRepositoryUncPath
    $myAnswer.LogWriter=$myLogWriter
    Write-Verbose 'New-DatabaseTest Created'
    Return $myAnswer
}
#endregion

#region Export
Export-ModuleMember -Function New-DatabaseTest
#endregion   
    

# SIG # Begin signature block
# MIIb6gYJKoZIhvcNAQcCoIIb2zCCG9cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBPdgOOE5jnojHt
# 54QaCZnBma2GLl52CIBh6gM/gBBLdqCCFjowggL8MIIB5KADAgECAhBuGGiP9rFT
# sEjfxjEo89WdMA0GCSqGSIb3DQEBCwUAMBYxFDASBgNVBAMMC3NxbGRlZXAuY29t
# MB4XDTI2MDcyODEyMjQ1MVoXDTI3MDcyODEyNDQ1MVowFjEUMBIGA1UEAwwLc3Fs
# ZGVlcC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDNOXX1vdSL
# U0u489johy9jEFIcvpJoJx0CWOasotOkoW0AJKh8abBNWcGUMbz+BONVSvr9lEMV
# 8HaWBUpnst/7Y7di49A/sVJgljT26H2K7jJ0Ot5342TKYp5NlMZWS+yLugHXXpQ8
# pAHwjeU0E6IIqDZUMc3aXcz13lxH2Lmomifx7h80JdjTnKg3VEGSt9Nk7Bt3kTHW
# AHZo6a/uVQuTNRVpFHg5baZs6pW4rmcyF2GrZYC1bbuwS3RfI442GB67oqS+EZv5
# lGRn0ZGKisoJ5sVHzsZrZnDKtATEY7j93diosWk4Ylh/isl56RFBVSp0q5Wh3Y7u
# TlBepciv+YhhAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggr
# BgEFBQcDAzAdBgNVHQ4EFgQUpj47586JqBg2vR/KExFCqFUrEgMwDQYJKoZIhvcN
# AQELBQADggEBAEynF/H5ccJzVOfxmFmOaK/sPCFaJeAoU0kfACVVkjVcfzvYoJSu
# LIio+7fihza5JI6UcrK67NPU6DKLM3mGrdh0XFG7lAVGQ8u0f22+PC8liPib9G2V
# g6QDM04Y5/jdJolxmV4lyAO5rRaU5GQ9Nv9wQP0bpKOtVu2BC+synzlqSSRp23wD
# x3dgi06D+j2OIjGP50bJhdrPagmtT2+UeOWTDHBkvRtAh3hwwbPM7kl0oxRZsJnM
# AjPgc7CxptFxtyylL9noP/48/HW/gm6AN4HWfJglprZFrEUX31BaROBcG65zTt0a
# ZxvHT7NkSYvZ+pawSBBfrc0NXUhK5IPBJLcwggWNMIIEdaADAgECAhAOmxiO+dAt
# 5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBa
# Fw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3E
# MB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKy
# unWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsF
# xl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU1
# 5zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJB
# MtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObUR
# WBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6
# nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxB
# YKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5S
# UUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+x
# q4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIB
# NjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwP
# TzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMC
# AYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdp
# Y2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0
# aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0Nc
# Vec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnov
# Lbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65Zy
# oUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFW
# juyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPF
# mCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9z
# twGpn1eqXijiuZQwgga0MIIEnKADAgECAhANx6xXBf8hmS5AQyIMOkmGMA0GCSqG
# SIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRy
# dXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcwMDAwMDBaFw0zODAxMTQyMzU5NTlaMGkx
# CzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4
# RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYg
# MjAyNSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC0eDHTCphB
# cr48RsAcrHXbo0ZodLRRF51NrY0NlLWZloMsVO1DahGPNRcybEKq+RuwOnPhof6p
# vF4uGjwjqNjfEvUi6wuim5bap+0lgloM2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHe
# HYNnQxqXmRinvuNgxVBdJkf77S2uPoCj7GH8BLuxBG5AvftBdsOECS1UkxBvMgEd
# gkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQSku2Ws3IfDReb6e3mmdglTcaarps0wjU
# jsZvkgFkriK9tUKJm/s80FiocSk1VYLZlDwFt+cVFBURJg6zMUjZa/zbCclF83bR
# VFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeS
# LsJygoLPp66bkDX1ZlAeSpQl92QOMeRxykvq6gbylsXQskBBBnGy3tW/AMOMCZIV
# NSaz7BX8VtYGqLt9MmeOreGPRdtBx3yGOP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL
# 6s36czwzsucuoKs7Yk/ehb//Wx+5kMqIMRvUBDx6z1ev+7psNOdgJMoiwOrUG2Zd
# SoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFU
# eEY0qVjPKOWug/G6X5uAiynM7Bu2ayBjUwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/
# BAgwBgEB/wIBADAdBgNVHQ4EFgQU729TSunkBnx6yuKQVvYv1Ensy04wHwYDVR0j
# BBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0
# cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0
# cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8E
# PDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVz
# dGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEw
# DQYJKoZIhvcNAQELBQADggIBABfO+xaAHP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/
# T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQM2qEJPe36zwbSI/mS83afsl3YTj+IQhQ
# E7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9r
# EVKChHyfpzee5kH0F8HABBgr0UdqirZ7bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y
# 1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmSNq1UH410ANVko43+Cdmu4y81hjajV/gx
# dEkMx1NKU4uHQcKfZxAvBAKqMVuqte69M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3t
# y9qIijanrUR3anzEwlvzZiiyfTPjLbnFRsjsYg39OlV8cipDoq7+qNNjqFzeGxcy
# tL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmMThi0vw9vODRzW6AxnJll38F0cuJG7uEB
# YTptMSbhdhGQDpOXgpIUsWTjd6xpR6oaQf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud
# /v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx9yHbxtl5TPau1j/1MIDpMPx0LckTetiS
# uEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3/BAPvIXKUjPSxyZsq8WhbaM2tszWkPZP
# ubdcMIIG7TCCBNWgAwIBAgIQCE/cM09+RU7bww+P+ZIYNTANBgkqhkiG9w0BAQsF
# ADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNV
# BAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hB
# MjU2IDIwMjUgQ0ExMB4XDTI2MDgwNTAwMDAwMFoXDTM3MTEwNDIzNTk1OVowYzEL
# MAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJE
# aWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1lc3RhbXAgUmVzcG9uZGVyIDIwMjYg
# MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALZ7pvLJ/s1K+NSbTGWz
# /TjGMPh8CQ6RucZCLv5anHzWJjF/NWJrFIhy24fcpKXlgRiky4WAawDfU3YP0BMx
# t9l3Dm5oCG5Z69AqEN1kgHg2epx+l+lZBcmJCcN0ASURML5uFIS80sZsDwO3BSkU
# xDjLJhBI+qiZP3aixAC/qEGLjsBNlLol9VZ7pfGEXiMlneJIC5/YKuizVzNFKZZE
# eoy/0B8Zm+nzKBgSWG52lCO1w+nCg6XpCtklTJXeIg283hw7TmmsZXR+SMbjbrEO
# vZ3fP2VxIgeR28Y90ZStd3F9VuA5RVynb/whITPAo9b75Zr4Ta6Mj3URm26QZYMn
# /FnbuTegcoRcFEZ9FOqM5T6MTdtr/n74lIT/ug0eeOzmZ6QTFg33otX+bFRsIolv
# ykE1jive4PuESaT8zzVeFWDAMDtozNgLctkGD1ZjkEyZtJrLl5ya0m5doH/ScpaZ
# CZVl6pNUOCybMc/kxC6EAmSJY24L0yYKD1Nkddsnb/ItVKi/2nXpQNMu1PT5prW8
# 3vV8d67WowuUs0HdY4H8AMLGvdL/WHEj3ZnqMqAQQP9u3Ai9t+5eQ02GDwy0ODjd
# zi0xlp70W+ow63/0++YDEX1M0iwgUHwbrJvfpklkZQvw3+kv3vUPItdwroczk9ic
# flf55W1zOEKAcJVAIXpcMCU9AgMBAAGjggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0G
# A1UdDgQWBBQUyWOKMC7USvtulPPm40B+9ezN4jAfBgNVHSMEGDAWgBTvb1NK6eQG
# fHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQGCCsGAQUFBzABhhhodHRwOi8vb2Nz
# cC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEy
# NTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vY3JsMy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hB
# MjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcB
# MA0GCSqGSIb3DQEBCwUAA4ICAQCNxTphHp1SCt+ZrAmAfn0oQLFr0mLywSLaDXQI
# ENoyKqxrFbJblzCVP/pkXmwXOdrOpWygLzlT12os5ipDCy35RBCg2UMeApEtrfGh
# z45F4Wt4WGdNdIbRWt3YTYJmpR+b7lr4d7Uwn+H600u4D7RnOGf8Wj4UNgAdZkfH
# hHv1mx9EVh71SJelcEN/oORSjXzdjfw1iZH9d8Nh/thn6hH23d+VsPAr6GAYyzSA
# 02nXD1nYLI7Ijmiv+xLCiYC41DSFYL3GhTiy0PxpawPtGRyaBVGzq+UiTfM8pD7K
# VyF5aQyWP4KhVGUUTnmm/RlYJoW3TiXA/+t0YcT2oRVBm3JETjajHug2AL+v5jht
# KVnd3D0rbHXEu27o+Q8p4sEWPMqKDB+qbceb6T/6WcwTwXmQ9lOCLLYcsQeSWmvK
# qzpAec9etE14jOQAzLKWdE3w/TCaKtLRaRT7LCkRYVnhA2D73FLje1O5b3HR5eHs
# 0NzU/+xX7NbEdcofy0W3Wdwd1XOqtlpg/JgwtKfZM5dqO94lbUveOiJBI+xZEbGR
# sMNbXmMREUTgu+Oca7Y73MPWcslIx2VhkSKSXjDbD6rgg39H5Mh7QfieAIjWagkJ
# Nt68Yfim6cjEzVSiLSeZfdkr5dtFPTW6jATlWJdYeeDRGCyatf8R1hSjzSvdN8yW
# QPT9gzGCBQYwggUCAgEBMCowFjEUMBIGA1UEAwwLc3FsZGVlcC5jb20CEG4YaI/2
# sVOwSN/GMSjz1Z0wDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAig
# AoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgEL
# MQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgH8qQUxLBLybQAf1fj0G+
# ymEQcg3M13Ch5alMJahUSc0wDQYJKoZIhvcNAQEBBQAEggEAXpxgRK4M9KXVjw4R
# DxhrG3ta59IRohkgA7l/uK3Vjb1Xr2KjTSp+m9EVb9RrohoA8r9Yyrw0eB3W+Y1D
# yr5t/AlobOlDETzj7dkRIdBubo6kfOSTvJ1hfbBdkh4i3nVu7T10LC+RVw1k3c17
# j6CIOuAuGFA2jKpXnra6ozvCVMkpO5UEgiOnAfyWnaJs3vNAOATHPDJOXV9Irnt0
# ZJLhyiOJAVVDfMMJm7pjoJ7i08HyzNqg/O7r5hmpsMoeaHZgQpHR2NU1p4TtsagC
# jPk9zeahaykgN31DEPBnWFnRldtoj3D0mGfVYQZGxHjTsljCwLRyGePJUw7ZaT13
# Z2DawqGCAyYwggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYT
# AlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQg
# VHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEC
# EAhP3DNPfkVO28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMx
# CwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjEwMDQxMzQyNTRaMC8GCSqG
# SIb3DQEJBDEiBCAZy5WNmZUvotG08qHvJcL+yd0Psu3MOVmVKvlD7wk77DANBgkq
# hkiG9w0BAQEFAASCAgBOwEsS7qTMoeDii8P6xOnAlzszUAAphuU6enznWEOyf1oE
# KLNPOcx6cUVrjT0FEbOs2vhMcJhKd5Z4pwfBbihuyNqGnXt2p4AbMXHlicvsPeN0
# K8ZRoPNblVJ3Bj56qyTY6WHBNGZcsjgDvzRnIi2ShB+29PDKVgtNxCbA8J1lK6NJ
# 3gjxxPurc0uP8+mFXcaT7hCStCPgP9gf5rWXFNzUNWwD0Lk8zb0Jjx6oWR+ZgMBc
# PT0MTWkPkeS2tIzBaGegY6+Iqn7s+Y2+19H3XxhfRkFXDhLy81bawudpG6FNvW1d
# DXt0TwghjUj28MrjvTojV9l1zP1RZ7Hn0m1xd1qcYBB4ztes4swdCeK/usOlFVoO
# e3eI5wU1DybZ2BjGiWvy5wkqTIPHqkEzizAhRMhpePIO9Z0c+Czcxm1aiYjUmPod
# DjVRiO5KmQzPIo9noV7PCPliSRIvxb9r+1qwXjrLns6FII6lcqRGZtee8JY48Dk4
# wT2P0q9GHZi6gQL5RtAlptkAzvP9qABkWo9qhCDsHTZ1LmQmLDexccOyTYcQ+5hH
# 0qXZiAzYDNjUC3/WqIk3UqIhf7vLCfaOTtP0WtrPCxg2k5A8KTSEsn+DrHvZRzb6
# FZD4/Ms2AKZeXHK7zXJqIZ6dEssnm9h6+BTlK5aQK3T4qOxf/58C5Uhr4Zd8gg==
# SIG # End signature block

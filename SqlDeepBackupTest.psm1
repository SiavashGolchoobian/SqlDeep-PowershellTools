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
# MIIcAgYJKoZIhvcNAQcCoIIb8zCCG+8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAavC4kRFMX6hH4
# 6Qxin0Vil6JSGGzlK0we7b9uG66kUaCCFlIwggMUMIIB/KADAgECAhAT2c9S4U98
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
# /xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQwgga0MIIEnKADAgEC
# AhANx6xXBf8hmS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcw
# MDAwMDBaFw0zODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1l
# U3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZ
# loMsVO1DahGPNRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM
# 2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2uPoCj
# 7GH8BLuxBG5AvftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQ
# Sku2Ws3IfDReb6e3mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZ
# lDwFt+cVFBURJg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+
# 8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRx
# ykvq6gbylsXQskBBBnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yG
# OP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqI
# MRvUBDx6z1ev+7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm
# 1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2ayBj
# UwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729T
# SunkBnx6yuKQVvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4c
# D08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUF
# BwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEG
# CCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAX
# MAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaA
# HP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQ
# M2qEJPe36zwbSI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt
# 6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0UdqirZ7
# bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmS
# Nq1UH410ANVko43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69
# M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPjLbnF
# RsjsYg39OlV8cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmM
# Thi0vw9vODRzW6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oa
# Qf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx
# 9yHbxtl5TPau1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3
# /BAPvIXKUjPSxyZsq8WhbaM2tszWkPZPubdcMIIG7TCCBNWgAwIBAgIQCoDvGEuN
# 8QWC0cR2p5V0aDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQg
# VGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAw
# MDAwMFoXDTM2MDkwMzIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRp
# Z2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBU
# aW1lc3RhbXAgUmVzcG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBANBGrC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx
# +wvA69HFTBdwbHwBSOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvN
# Zh6wW2R6kSu9RJt/4QhguSssp3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlL
# nh00Cll8pjrUcCV3K3E0zz09ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmn
# cOOMA3CoB/iUSROUINDT98oksouTMYFOnHoRh6+86Ltc5zjPKHW5KqCvpSduSwhw
# UmotuQhcg9tw2YD3w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL
# 4Q1OpbybpMe46YceNA0LfNsnqcnpJeItK/DhKbPxTTuGoX7wJNdoRORVbPR1VVnD
# uSeHVZlc4seAO+6d2sC26/PQPdP51ho1zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCy
# FG1roSrgHjSHlq8xymLnjCbSLZ49kPmk8iyyizNDIXj//cOgrY7rlRyTlaCCfw7a
# SUROwnu7zER6EaJ+AliL7ojTdS5PWPsWeupWs7NpChUk555K096V1hE0yZIXe+gi
# AwW00aHzrDchIc2bQhpp0IoKRR7YufAkprxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGj
# ggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zyMe39/dfzkXFjGVBD
# z2GM6DAfBgNVHSMEGDAWgBTvb1NK6eQGfHrK4pBW9i/USezLTjAOBgNVHQ8BAf8E
# BAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGF
# MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXQYIKwYBBQUH
# MAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRH
# NFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBW
# MFSgUqBQhk5odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# RzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkw
# FzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3x
# HCcEua5gQezRCESeY0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh
# 8/YmRDfxT7C0k8FUFqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim8/9yJmZS
# e2F8AQ/UdKFOtj7YMTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu+WUqW4daIqToXFE/
# JQ/EABgfZXLWU0ziTN6R3ygQBHMUBaB5bdrPbF6MRYs03h4obEMnxYOX8VBRKe1u
# NnzQVTeLni2nHkX/QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq
# 8/gVutDojBIFeRlqAcuEVT0cKsb+zJNEsuEB7O7/cuvTQasnM9AWcIQfVjnzrvwi
# CZ85EE8LUkqRhoS3Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol/DJgddJ35XTxfUlQ
# +8Hggt8l2Yv7roancJIFcbojBcxlRcGG0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1
# R9xJgKf47CdxVRd/ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3ocCVccAvlKV9jEnstr
# niLvUxxVZE/rptb7IRE2lskKPIJgbaP5t2nGj/ULLi49xTcBZU8atufk+EMF/cWu
# iC7POGT75qaL6vdCvHlshtjdNXOCIUjsarfNZzGCBQYwggUCAgEBMCowFjEUMBIG
# A1UEAwwLc3FsZGVlcC5jb20CEBPZz1LhT3yMSHZ6qu04YqIwDQYJYIZIAWUDBAIB
# BQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYK
# KwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG
# 9w0BCQQxIgQgZ983bP6mb81VjpxIVlPjpR5zfPp7lsnCdPUEj/TjNGMwDQYJKoZI
# hvcNAQEBBQAEggEAP6+DzbvRsk/biOQ5YeBGeZZBJtKaJZLHkYcq8TVbfnCEQ4BX
# taQRtB4V+kOaIjwhswMcvNkLCW3GBExYBYN3GdKhZbVBrrs0IodtVgjHnekN0BhZ
# cKOotfLo1KaRk1l1KZHz7AlGGSXV8mIvUQdGFsNqEslZcNygkab4GQwrW9IzwreL
# 7hJ/GKMAKoUeKvRtPuJKWyiw6J6g7PAO7yetasSQ/S5LhIzoyffmnXh6UUCYKL7O
# 0suSZeMIOgFfcusxJmLiuLXwYQPYG0BnnNP1ldOCHYoWWxqZPmSoFvpLxTS7xxUC
# eSFTsYfDixxi6A35EXvA0axuGzHQqhE9KpfgOqGCAyYwggMiBgkqhkiG9w0BCQYx
# ggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcg
# UlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEFgtHEdqeVdGgwDQYJYIZI
# AWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJ
# BTEPFw0yNjA3MjgwNTUyMjRaMC8GCSqGSIb3DQEJBDEiBCBYj/h1MpyZKstWnjzf
# AvBUJxQS3Hk0p/dHlXx6yYgSgjANBgkqhkiG9w0BAQEFAASCAgB3fkfZ8eDY3Lal
# IFXrZR/Ns0raRSmh2Db+q8cZypMUk24E0pP7NU6NEtt8uE0EQIrPJBBxITLkPMGO
# fprhS9vpCEK0QNYTXJqPV3TfLohMWIyJTtUj/rgjzTOoMpg4UcYFelIekJL3UoUg
# yhB6yXWUoeFZ0sBBksRns0PTmYcEan+mVdgss9lBD0S6jdlVpU0KxcwDt0YDMOQA
# 3FT9jtqQAJzE/ja2D6yJKU7dfrmyOJRdZGfJTupeDQa98jytcLyU8aVPEDStohjp
# 1lEOUcDyR9DJoFYtnhdZKfNt5VA8e5SkxcbVxCVykT+L4UjtZ61Vrs4DhfWlPpbK
# oReWCDrr5py3OgLIr8N1/SI44AFgtBuwGL9BrWchaU4cJrEaGjt7ojopTNmYOAQc
# kdJ7sgwnp8HRuhJ2t0JTvHWnHDOZTMobVO05aCaVHp3HMqKlVMh7K8FryxnLWqtZ
# TAQMD4Ajjs35+CXYTnOV+dZTHd70i0OPsChUlGhkfb5KTaNBNO1dDa0ZU5zhdyvV
# j9dxJF8ZzmnqNCE+ei2D/zM+qqTAfQ8l2dt69pMCKkXaUOTbXX5iIfUggIVW61A/
# 52byXMROou2SLy4vgyp4zQlsmTfJnjT4oBC3QC+9qj7Rf/2MC8iy9PCki9LJnIYC
# iU/9KAGc8S6vifrEBsdnDzQuFuwwqQ==
# SIG # End signature block

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
                        foreach ($myFile in $this.BackupFileList | Select-Object -Unique -Property RemoteRepositoryUncFilePath){ 
                            if(Test-Path $myFile.RemoteRepositoryUncFilePath){
                                Remove-Item -Path ($_.RemoteRepositoryUncFilePath); $this.LogWriter.Write($this.LogStaticMessage+('Remove file ' + $_.RemoteRepositoryUncFilePath),[LogType]::INF)
                            }
                            else {
                                $this.LogWriter.Write($this.LogStaticMessage+('File dose not  ' + $_.RemoteRepositoryUncFilePath),[LogType]::WRN)
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
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAx/b4uhhz/bUvg
# iNSVIcMn7L9fgV1I+ouieAtiSQcRkaCCFhswggMUMIIB/KADAgECAhAT2c9S4U98
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
# BCC/g+znSjKnmQwqjxPzLKjuW+OSTlgdaAxhUjXSTpcF6jANBgkqhkiG9w0BAQEF
# AASCAQCA891huUx23A6myedC22ND+cinquvJEEAjpGlBP5YwoRmhQIMmbWxtug/X
# 8RX3al9TTHrQrbp8YGSlaeczKOXTFdktQMlq7TuRRl+nbNRuIwfO5XfagtIE0gRv
# T6+buV4uDIuwHhvjES6vYmehbq9ibEdKqRGLYl7qfQSmnUczHEUi388wrJ8xqZAf
# kIzaruAi2PChZNS4RNHHcSirSbRjKYzwV7SlEuOpeTD6w6HizHIrYIiT2QAEWvcO
# MjdipVQ41MMSKRFC7R8yqwdf2+31R8iiU8xyG08vqbWxirky8UrqzDgS5kJP7q0P
# 3kcuUouS+LvKIXH/khoEphqgzxWuoYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTAzMDE4
# NDAwN1owLwYJKoZIhvcNAQkEMSIEIBpKJeS9f6ND6M6FJnJF/pNSHj/A1nAhy/Xi
# K093FMFCMA0GCSqGSIb3DQEBAQUABIICAJ9wIJTTPtkgx9r5y+oTl7QKSQrt5aPc
# VK60Us9KsGj/fOy6/TIh080Xj4b2apYB1sOJHr3dv7gVeXvSXh864Fwe5UpLkQo+
# 7XpmwuWgY7gRjwSVGu30oSlSlRL8ZCStVpPkr4bRYV23G+d8Y5D/1str0CKMTXbD
# Y6k6RHMApDPjdpJzezFDNgbb0JKumC+nFj4wGTzEMxwmaQGWofLQqX6vIvnDsQus
# B7E7v3L1nu0KHmp3KUEMbr6DqD8KkdTKw6azfyQ4Vk1T7iyRf2p0n6meNWcvq0HS
# 8tVxglRyA1m2b0RM41mXYiP9DBVTmWt9SpQei55gf+Xr2Bxmh+cIKsS5D4bU76D2
# AUkbMUmFAJgxgB74TPKZTskcCW7reXFoOhCTBF9AMcES6bfUxEBCly8tVnCj0Ty3
# DMBOSNRyugR1MOHcnJd3EyyKqP4tKk+VK32p+tUX8xVkqgS3T/5cjD6Omky6lpXK
# VSrwYr1SBWhnSjKvui/JdEgcPdCWVFnBsgvITiasDcxfsWQegUIT13QKbdTdzqOn
# 7upqO7KL9sXDCVy1b62KsW4sQC7/WUN5TfJwPdxlRFKEQXHhmLuk7FGgrA/gxv2P
# YstbkdeazrfmtahSM8YSyWXrpBYIYLxgjH1gQaDp5mqqlj7bePGvKnFovUZZwHUo
# 9s3fLOZdwgqW
# SIG # End signature block

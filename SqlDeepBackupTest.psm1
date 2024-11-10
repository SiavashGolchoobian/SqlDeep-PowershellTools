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
# MIIboAYJKoZIhvcNAQcCoIIbkTCCG40CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUKWoigdxIAY+xcxmjFrQZMXsZ
# HwigghYbMIIDFDCCAfygAwIBAgIQE9nPUuFPfIxIdnqq7ThiojANBgkqhkiG9w0B
# AQUFADAWMRQwEgYDVQQDDAtzcWxkZWVwLmNvbTAeFw0yNDEwMjMxMjIwMDJaFw0y
# NjEwMjMxMjMwMDJaMBYxFDASBgNVBAMMC3NxbGRlZXAuY29tMIIBIjANBgkqhkiG
# 9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4r0s4Bg6lsKIg+zgWvLcE9J8xxjWpMGbRM76
# tx3C/GwoHw3af9JKc6EuiCqY7dqcq9MRnF50y0rxLSe9FzoJ9e/WtU5WkVJcvom7
# lHzteYp68D39Wun6oLzzKF1emzMabG5sfb0uglAWDteBlDddBrZUIKVGGNTdHM2m
# wu8l36PBMJDtWUxqFwA4pxwRdKaCn350dBF+QYi+/1hkX09yYBWfLcGDKCjnOISf
# hmW7nbQKbb51swHYljPFH8EMHB/EiUO5+cITzj1fHvmiAm5oH/Y/DXFQClCqgYhi
# 5hISioximlKMOd3E7LIbRgp3b+XZzIBNqaZMYWljZ/KkamHUBQIDAQABo14wXDAO
# BgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwFgYDVR0RBA8wDYIL
# c3FsZGVlcC5jb20wHQYDVR0OBBYEFMKB2TYWHVb7c2OYPVpTlYhvOm/BMA0GCSqG
# SIb3DQEBBQUAA4IBAQALy82fcFq7qURGF5HHsaCwcG8YyB7nmsZbjJibODEr38ix
# u5s475LJH9gMX2jJ1q//1vtCi4cWdPorXPweBRKeHCwmcpwVmvokgnPIghdA3M04
# 1NXsRtJlH3/Nnu3OZl7N6Iumjj0cst1wY2amXWBNR1pfRmIW6AuZGOuWeNmbGzcj
# zjPJ4STcwSqvVensjRNiZ8Za0Nb9fZcVzpullh4J4fvrVH/ZPAyNQ+w2t20KrI/D
# vgAh44YzFc1iqgLZw8cnWjjo0YSliJR1EO3y1hmBWVtiV56IKsRUdrc3aWcbDYA+
# Lxxc7dQrKYh84SLDMH0BcSIOODcv1PepdmlaUepVMIIFjTCCBHWgAwIBAgIQDpsY
# jvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
# IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAw
# MDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57
# G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9o
# k3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFh
# mzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463J
# T17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFw
# q1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yh
# Tzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU
# 75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LV
# jHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJ
# bOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8Qg
# UWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IB
# OjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6
# mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/
# BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4
# oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBw
# oL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0
# E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtD
# IeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlU
# sLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFig
# DkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwY
# w02fc7cBqZ9Xql4o4rmUMIIGrjCCBJagAwIBAgIQBzY3tyRUfNhHrP0oZipeWzAN
# BgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2Vy
# dCBUcnVzdGVkIFJvb3QgRzQwHhcNMjIwMzIzMDAwMDAwWhcNMzcwMzIyMjM1OTU5
# WjBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNV
# BAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1w
# aW5nIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAxoY1BkmzwT1y
# SVFVxyUDxPKRN6mXUaHW0oPRnkyibaCwzIP5WvYRoUQVQl+kiPNo+n3znIkLf50f
# ng8zH1ATCyZzlm34V6gCff1DtITaEfFzsbPuK4CEiiIY3+vaPcQXf6sZKz5C3GeO
# 6lE98NZW1OcoLevTsbV15x8GZY2UKdPZ7Gnf2ZCHRgB720RBidx8ald68Dd5n12s
# y+iEZLRS8nZH92GDGd1ftFQLIWhuNyG7QKxfst5Kfc71ORJn7w6lY2zkpsUdzTYN
# XNXmG6jBZHRAp8ByxbpOH7G1WE15/tePc5OsLDnipUjW8LAxE6lXKZYnLvWHpo9O
# dhVVJnCYJn+gGkcgQ+NDY4B7dW4nJZCYOjgRs/b2nuY7W+yB3iIU2YIqx5K/oN7j
# PqJz+ucfWmyU8lKVEStYdEAoq3NDzt9KoRxrOMUp88qqlnNCaJ+2RrOdOqPVA+C/
# 8KI8ykLcGEh/FDTP0kyr75s9/g64ZCr6dSgkQe1CvwWcZklSUPRR8zZJTYsg0ixX
# NXkrqPNFYLwjjVj33GHek/45wPmyMKVM1+mYSlg+0wOI/rOP015LdhJRk8mMDDtb
# iiKowSYI+RQQEgN9XyO7ZONj4KbhPvbCdLI/Hgl27KtdRnXiYKNYCQEoAA6EVO7O
# 6V3IXjASvUaetdN2udIOa5kM0jO0zbECAwEAAaOCAV0wggFZMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHQYDVR0OBBYEFLoW2W1NhS9zKXaaL3WMaiCPnshvMB8GA1UdIwQY
# MBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUE
# DDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6
# Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDww
# OjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3Rl
# ZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0G
# CSqGSIb3DQEBCwUAA4ICAQB9WY7Ak7ZvmKlEIgF+ZtbYIULhsBguEE0TzzBTzr8Y
# +8dQXeJLKftwig2qKWn8acHPHQfpPmDI2AvlXFvXbYf6hCAlNDFnzbYSlm/EUExi
# HQwIgqgWvalWzxVzjQEiJc6VaT9Hd/tydBTX/6tPiix6q4XNQ1/tYLaqT5Fmniye
# 4Iqs5f2MvGQmh2ySvZ180HAKfO+ovHVPulr3qRCyXen/KFSJ8NWKcXZl2szwcqMj
# +sAngkSumScbqyQeJsG33irr9p6xeZmBo1aGqwpFyd/EjaDnmPv7pp1yr8THwcFq
# cdnGE4AJxLafzYeHJLtPo0m5d2aR8XKc6UsCUqc3fpNTrDsdCEkPlM05et3/JWOZ
# Jyw9P2un8WbDQc1PtkCbISFA0LcTJM3cHXg65J6t5TRxktcma+Q4c6umAU+9Pzt4
# rUyt+8SVe+0KXzM5h0F4ejjpnOHdI/0dKNPH+ejxmF/7K9h+8kaddSweJywm228V
# ex4Ziza4k9Tm8heZWcpw8De/mADfIBZPJ/tgZxahZrrdVcA6KYawmKAr7ZVBtzrV
# FZgxtGIJDwq9gdkT/r+k0fNX2bwE+oLeMt8EifAAzV3C+dAjfwAL5HYCJtnwZXZC
# pimHCUcr5n8apIUP/JiW9lVUKx+A+sDyDivl1vupL0QVSucTDh3bNzgaoSv27dZ8
# /DCCBrwwggSkoAMCAQICEAuuZrxaun+Vh8b56QTjMwQwDQYJKoZIhvcNAQELBQAw
# YzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQD
# EzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGlu
# ZyBDQTAeFw0yNDA5MjYwMDAwMDBaFw0zNTExMjUyMzU5NTlaMEIxCzAJBgNVBAYT
# AlVTMREwDwYDVQQKEwhEaWdpQ2VydDEgMB4GA1UEAxMXRGlnaUNlcnQgVGltZXN0
# YW1wIDIwMjQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC+anOf9pUh
# q5Ywultt5lmjtej9kR8YxIg7apnjpcH9CjAgQxK+CMR0Rne/i+utMeV5bUlYYSuu
# M4vQngvQepVHVzNLO9RDnEXvPghCaft0djvKKO+hDu6ObS7rJcXa/UKvNminKQPT
# v/1+kBPgHGlP28mgmoCw/xi6FG9+Un1h4eN6zh926SxMe6We2r1Z6VFZj75MU/HN
# mtsgtFjKfITLutLWUdAoWle+jYZ49+wxGE1/UXjWfISDmHuI5e/6+NfQrxGFSKx+
# rDdNMsePW6FLrphfYtk/FLihp/feun0eV+pIF496OVh4R1TvjQYpAztJpVIfdNsE
# vxHofBf1BWkadc+Up0Th8EifkEEWdX4rA/FE1Q0rqViTbLVZIqi6viEk3RIySho1
# XyHLIAOJfXG5PEppc3XYeBH7xa6VTZ3rOHNeiYnY+V4j1XbJ+Z9dI8ZhqcaDHOoj
# 5KGg4YuiYx3eYm33aebsyF6eD9MF5IDbPgjvwmnAalNEeJPvIeoGJXaeBQjIK13S
# lnzODdLtuThALhGtyconcVuPI8AaiCaiJnfdzUcb3dWnqUnjXkRFwLtsVAxFvGqs
# xUA2Jq/WTjbnNjIUzIs3ITVC6VBKAOlb2u29Vwgfta8b2ypi6n2PzP0nVepsFk8n
# lcuWfyZLzBaZ0MucEdeBiXL+nUOGhCjl+QIDAQABo4IBizCCAYcwDgYDVR0PAQH/
# BAQDAgeAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwIAYD
# VR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMB8GA1UdIwQYMBaAFLoW2W1N
# hS9zKXaaL3WMaiCPnshvMB0GA1UdDgQWBBSfVywDdw4oFZBmpWNe7k+SH3agWzBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRUcnVzdGVkRzRSU0E0MDk2U0hBMjU2VGltZVN0YW1waW5nQ0EuY3JsMIGQBggr
# BgEFBQcBAQSBgzCBgDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQu
# Y29tMFgGCCsGAQUFBzAChkxodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGln
# aUNlcnRUcnVzdGVkRzRSU0E0MDk2U0hBMjU2VGltZVN0YW1waW5nQ0EuY3J0MA0G
# CSqGSIb3DQEBCwUAA4ICAQA9rR4fdplb4ziEEkfZQ5H2EdubTggd0ShPz9Pce4FL
# Jl6reNKLkZd5Y/vEIqFWKt4oKcKz7wZmXa5VgW9B76k9NJxUl4JlKwyjUkKhk3aY
# x7D8vi2mpU1tKlY71AYXB8wTLrQeh83pXnWwwsxc1Mt+FWqz57yFq6laICtKjPIC
# YYf/qgxACHTvypGHrC8k1TqCeHk6u4I/VBQC9VK7iSpU5wlWjNlHlFFv/M93748Y
# TeoXU/fFa9hWJQkuzG2+B7+bMDvmgF8VlJt1qQcl7YFUMYgZU1WM6nyw23vT6QSg
# wX5Pq2m0xQ2V6FJHu8z4LXe/371k5QrN9FQBhLLISZi2yemW0P8ZZfx4zvSWzVXp
# Ab9k4Hpvpi6bUe8iK6WonUSV6yPlMwerwJZP/Gtbu3CKldMnn+LmmRTkTXpFIEB0
# 6nXZrDwhCGED+8RsWQSIXZpuG4WLFQOhtloDRWGoCwwc6ZpPddOFkM2LlTbMcqFS
# zm4cd0boGhBq7vkqI1uHRz6Fq1IX7TaRQuR+0BGOzISkcqwXu7nMpFu3mgrlgbAW
# +BzikRVQ3K2YHcGkiKjA4gi4OA/kz1YCsdhIBHXqBzR0/Zd2QwQ/l4Gxftt/8wY3
# grcc/nS//TVkej9nmUYu83BDtccHHXKibMs/yXHhDXNkoPIdynhVAku7aRZOwqw6
# pDGCBO8wggTrAgEBMCowFjEUMBIGA1UEAwwLc3FsZGVlcC5jb20CEBPZz1LhT3yM
# SHZ6qu04YqIwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAw
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFJqI/a/pUTcrVrpou5oXawyb/WAtMA0G
# CSqGSIb3DQEBAQUABIIBADqffs3F4BHx4dNOOj2qo/KKzLSFjdtap1A6t6ehsLh6
# 3AoxdfRUFQx0a4AXVzGvbD69tEWo+CmfWv7l1qeiNGvN6fkQu65xsHBnqBVozb22
# b7Du+QMK4lD+zJdTQzdWwY2OFkImv3sfTDvwFPocKtbUFXNuSWv+Lgzx9fOnteLY
# R/8D+zH4gZo+qH5OScypVCC/embag8xdSLI7evlOJaoBaQnMYLfZAWqg1UkE8ElB
# qYLnI1eGLd2f2kUziiEvY0gFANDSBty8b59/ByrNnZ5F76XSKqdkKtSExcvb8xA4
# dxpv+kT2cXJSVjkP01+olbdZt/grRqzojnqcLNM/e9+hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhALrma8Wrp/lYfG+ekE4zMEMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjQxMTEwMDgzMDIxWjAvBgkqhkiG9w0BCQQxIgQgrR0uvwYDLoWqwJ6/AlBB
# j4ayZCn9fgYpZrtEyy1E9QAwDQYJKoZIhvcNAQEBBQAEggIAgjAJR4GjaTMNpi8C
# KSiUtLM5rmaCqZmQO1VXES+kIPCfmNJalhTQzsajc6prYIRDc2Fp9JbN+OLgTv8c
# k/7/uWg5yl1RbEalRp5tr8XB+ozqJ7h1FaAtNJSusd/GqdtkiNf6BrpRRCpQR/jC
# LXhx6S1xV5m3ySOB4G2JdcY30s01Mvpk6bmniDqxFgr9ALx71+tm9LhUQOKixj0K
# roZfKTXoCAi49Mxy01wcMHmgBLtY2JU1UCnQVGHyMSggRAOvhTKf3vZmhFj3NLZ4
# cZoshyIvqyLfAqeuAuOQKmXQT/apfQQ6NFX0D2ULdV7g5Dy/pqGnVH8PAWof+LFi
# kPfDSaPOLtH8p46lGFj1GPvpwMcABopq+HJ1awpRlJ4wfHCaJNIS12SmnF9DyhGB
# f/DRM8K3oa0KZ50TNUJ17YWcf4dyAlX+wxfyJRnwO1olws9yWp7KIpXPRJNATbQ1
# Mmt3ORq/pGsYZZAl4VNXizqDZeIey7yz4Qmc419UgFKXjVVH4/dLvH5ZM3MMLUQp
# voT/1WdwbBSUQwF9cm3w88O5pKVybHfINiMUcOSk+lOc4Bp7xSPaBUb4aE1PPkVw
# LYkLGNjPfYAObeAUISwaQauHGG7aTM2i8yZ9AWCzrsyQ37RbCkg/UwUmKpUyFSpz
# 9V16QkatMU0R43kWwcXp8y/VeD0=
# SIG # End signature block

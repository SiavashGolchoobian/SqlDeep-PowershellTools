#region Functions
    function IsNumeric {  #Check if input value is numeric
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input value to evaluate")][AllowEmptyString()][AllowNull()]$Value
        )
        begin{}
        process{
            return ($Value -match "^[\d\.]+$")
        }
        end{}
    }
    function Clear-Text {
        [OutputType([string])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][AllowEmptyString()][AllowNull()][string]$Text,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][AllowEmptyCollection()][AllowNull()][string[]]$ProhibitedPhrases
        )
        begin {}
        process {
            [string]$myAnswer=$null;
            try{
                $myAnswer=$Text;
                foreach ($ProhibitedPhrase in $ProhibitedPhrases){
                    $myAnswer=$myAnswer.Replace($ProhibitedPhrase,"");
                }
            }catch{
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end{}
    }
    function Clear-SqlParameter {
        [OutputType([string])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage='Input string to cleanup')][AllowEmptyString()][AllowNull()][string]$ParameterValue,
            [Parameter(Mandatory=$false,HelpMessage='Remove space( ) character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveSpace,
            [Parameter(Mandatory=$false,HelpMessage='Remove wildecard(%) character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveWildcard,
            [Parameter(Mandatory=$false,HelpMessage='Remove braces([]) character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveBraces,
            [Parameter(Mandatory=$false,HelpMessage='Remove single quote character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveSingleQuote,
            [Parameter(Mandatory=$false,HelpMessage='Remove double quote(") character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveDoubleQuote,
            [Parameter(Mandatory=$false,HelpMessage='Remove doller sign ($) character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveDollerSign
            )
        begin {
            [string[]]$myProhibitedPhrases=$null;
            $myProhibitedPhrases+=';';
            if ($RemoveSpace){$myProhibitedPhrases+=' '};
            if ($RemoveWildcard){$myProhibitedPhrases+='%'};
            if ($RemoveBraces){$myProhibitedPhrases+='[',']','{','}'};
            if ($RemoveSingleQuote){$myProhibitedPhrases+="'"};
            if ($RemoveDoubleQuote){$myProhibitedPhrases+='"'};
            if ($RemoveDollerSign){$myProhibitedPhrases+='$'};
        } 
        process {
            [string]$myAnswer=$null;

            try{
                $myAnswer = Clear-Text -Text $ParameterValue -ProhibitedPhrases $myProhibitedPhrases
            }catch{
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    function Export-DatabaseBlob {
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$CommandText,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$DestinationFilePath
        )
        begin {
            $mySqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $mySqlCommand = $mySqlConnection.CreateCommand();
            $mySqlConnection.Open(); 
        }
        process {
            [bool]$myAnswer=$false;
            try
            {
                $mySqlCommand.CommandText = $CommandText;                      
                # New Command and Reader
                $myReader = $mySqlCommand.ExecuteReader();
        
                # Create a byte array for the stream.
                $myBufferSize = 8192*8;
                $myOut = [array]::CreateInstance('Byte', $myBufferSize)

                # Looping through records
                While ($myReader.Read())
                {
                    #Create Directory if not exists and remove any Existing item
                    $myFolderPath=Split-Path $DestinationFilePath
                    IF (-not (Test-Path -Path $myFolderPath -PathType Container)) {
                        New-Item -Path $myFolderPath -ItemType Directory -Force
                        #$myDestinationFolderPath=$DestinationFilePath.Substring(0,($DestinationFilePath.Length-$DestinationFilePath.Split("\")[-1].Length))
                        #New-Item -ItemType Directory -Path $myDestinationFolderPath -Force
                    }
                    IF (Test-Path -Path $DestinationFilePath -PathType Leaf) {Move-Item -Path $DestinationFilePath -Force}
            
                    # New BinaryWriter, write content to specified file on (zero based) first column (FileContent)
                    $myFileStream = New-Object System.IO.FileStream $DestinationFilePath, Create, Write;
                    $myBinaryWriter = New-Object System.IO.BinaryWriter $myFileStream;

                    $myStart = 0;
                    # Read first byte stream from (zero based) first column (FileContent)
                    $myReceived = $myReader.GetBytes(0, $myStart, $myOut, 0, $myBufferSize - 1);
                    While ($myReceived -gt 0)
                    {
                        $myBinaryWriter.Write($myOut, 0, $myReceived);
                        $myBinaryWriter.Flush();
                        $myStart += $myReceived;
                        # Read next byte stream from (zero based) first column (FileContent)
                        $myReceived = $myReader.GetBytes(0, $myStart, $myOut, 0, $myBufferSize - 1);
                    }

                    $myBinaryWriter.Close();
                    $myFileStream.Close();
                    
                    if (-not (Test-Path -Path $DestinationFilePath) -or -not ($myFileStream)) {
                        $myAnswer=$false;
                    } else {
                        $myAnswer=$true;
                    }
                    
                    # Closing & Disposing all objects
                    if ($myFileStream) {$myFileStream.Dispose()};
                }
                $myReader.Close();
                return $myAnswer
            }
            catch
            {       
                $myAnswer=$false;
                Write-Error($_.ToString());
                Throw;
            }
            return $myAnswer;
        }
        end {
            $mySqlCommand.Dispose();
            $mySqlConnection.Close();
            $mySqlConnection.Dispose();
            #[System.Data.SqlClient.SqlConnection]::ClearAllPools();  
        }
    }
    function Read-SqlQuery {
        [OutputType([System.Data.DataTable])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$Query
        )
        begin {
            $mySqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $mySqlCommand = $mySqlConnection.CreateCommand();
            $mySqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter;
            $myDataTable = New-Object System.Data.DataTable;
            $mySqlConnection.Open(); 
        }
        process {
            try
            {
                [System.Data.DataTable]$myAnswer=$null;
                $mySqlCommand.CommandText = $Query;                      
                $mySqlDataAdapter.SelectCommand = $mySqlCommand;
                $null=$mySqlDataAdapter.Fill($myDataTable);
                $myAnswer=$myDataTable;
            }
            catch
            {       
                $myAnswer=$null;
                Write-Error($_.ToString());
                Throw;
            }
            return $myAnswer;
        }
        end {
            $mySqlCommand.Dispose();
            $mySqlConnection.Close();
            $mySqlConnection.Dispose();
            #[System.Data.SqlClient.SqlConnection]::ClearAllPools();  
        }
    }
    function Invoke-SqlCommand {
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$Command
        )
        begin {
            $mySqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $mySqlCommand = $mySqlConnection.CreateCommand();
            $mySqlConnection.Open(); 
        }
        process {
            [bool]$myAnswer=$false;
            try
            {
                $mySqlCommand.CommandText = $Command;                      
                $mySqlCommand.ExecuteNonQuery();
                $myAnswer=$true;
            }
            catch
            {       
                $myAnswer=$false;
                Write-Error($_.ToString());
                Throw;
            }
            return $myAnswer;
        }
        end {
            $mySqlCommand.Dispose();
            $mySqlConnection.Close();
            $mySqlConnection.Dispose();
            #[System.Data.SqlClient.SqlConnection]::ClearAllPools();  
        }
    }
    function Test-DatabaseConnection {
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$DatabaseName
        )
        begin {}
        process {
            [bool]$myAnswer=$false;
            [string]$myCommand=$null;
            
            $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveWildcard -RemoveBraces ;
            $myCommand="
                USE ["+$DatabaseName+"];
                SELECT [name] AS Result FROM [master].[sys].[databases] WHERE name = '" + $DatabaseName + "';
                ";
            try{
                $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop;
                if ($null -ne $myRecord) {$myAnswer=$true} else {$myAnswer=$false}
            }Catch{
                $myAnswer=$false;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer
        }
        end {}
    }
    function Test-InstanceConnection {
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString
        )
        begin {}
        process {
            [bool]$myAnswer=$false;
            try{
                $myAnswer=Test-DatabaseConnection -ConnectionString $ConnectionString -DatabaseName 'master';
            }Catch{
                $myAnswer=$false;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    function Get-InstanceInformationFromRegistery {
        [OutputType([PSCustomObject[]])]
        param ()
        begin {}
        process {
            [PSCustomObject[]]$myAnswer=$null;
            [string]$myMachineName=$null;
            [string]$myDomainName=$null;
            [string]$myRegInstanceFilter=$null;

            try {
                [System.Collections.ArrayList]$myInstanceCollection=$null;
                $myInstanceCollection=[System.Collections.ArrayList]::new();
                $myMachineName=($env:computername);
                $myDomainName=(Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem).Domain;
                $myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL';
                $myRegKey=Get-ItemProperty -Path $myRegInstanceFilter;
                $myRegKey.psobject.Properties | Where-Object -Property Name -NotIn ("PSPath","PSParentPath","SQL","PSChildName","PSDRIVE","PSProvider") | ForEach-Object{Write-Host ($myMachineName+","+$myDomainName+","+$_.Name+","+$_.Value);
                    $myInstanceObject=[PSCustomObject]@{
                        MachineName=$myMachineName
                        DomainName=$myDomainName
                        InstanceName=$_.Name
                        InstanceRegName=$_.Value
                        InstancePort="1433"
                        ForceEncryption=$false
                        DefaultDataPath=""
                        DefaultLogPath=""
                        DefaultBackupPath=""
                        Collation=""
                        PatchLevel=""
                    };
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name InstanceMajorVersion -Value {return [int]($this.PatchLevel.Split('.')[0])}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameInstanceName -Value {$myInstanceName="";if ($this.InstanceName -and $this.InstanceName.Trim().Length -gt 0) {$myInstanceName="\" + $this.InstanceName}; return $this.MachineName+$myInstanceName}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameDomainNameInstanceName -Value {$myInstanceName="";$myDomainName="";if ($this.InstanceName -and $this.InstanceName.Trim().Length -gt 0) {$myInstanceName="\" + $this.InstanceName};if ($this.DomainName -and $this.DomainName.Trim().Length -gt 0) {$myDomainName="." + $this.DomainName}; return $this.MachineName+$myDomainName+$myInstanceName}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameDomainNameInstanceNamePortNumber -Value {return $this.MachineNameDomainNameInstanceName+","+$this.InstancePort.Split(',')[0]}
                     $myInstanceCollection.Add($myInstanceObject)};
                #$myRegKey.psobject.Properties | Where-Object -Property Name -NotIn ("PSPath","PSParentPath","SQL","PSChildName","PSDRIVE","PSProvider") | ForEach-Object{Write-Host ($myMachineName+","+$myDomainName+","+$_.Name+","+$_.Value);$myInstanceCollection.Add([InstanceObject]::New($myMachineName,$myDomainName,$_.Name,$_.Value,'1433',$false,"","","","",""))};
                $myInstanceCollection | ForEach-Object{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$_.InstanceRegName+'\MSSQLServer\SuperSocketNetLib\Tcp\IPAll';$_.InstancePort=(Get-ItemProperty -Path $myRegInstanceFilter).TcpPort};
                $myInstanceCollection | ForEach-Object{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$_.InstanceRegName+'\MSSQLServer\SuperSocketNetLib';$_.ForceEncryption=(Get-ItemProperty -Path $myRegInstanceFilter).ForceEncryption};
                $myInstanceCollection | ForEach-Object{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$_.InstanceRegName+'\MSSQLServer';$_.DefaultDataPath=(Get-ItemProperty -Path $myRegInstanceFilter).DefaultData;$_.DefaultLogPath=(Get-ItemProperty -Path $myRegInstanceFilter).DefaultLog;$_.DefaultBackupPath=(Get-ItemProperty -Path $myRegInstanceFilter).BackupDirectory};
                $myInstanceCollection | ForEach-Object{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$_.InstanceRegName+'\Setup';$_.Collation=(Get-ItemProperty -Path $myRegInstanceFilter).Collation;$_.PatchLevel=(Get-ItemProperty -Path $myRegInstanceFilter).PatchLevel};
                $myAnswer=$myInstanceCollection.ToArray([PSCustomObject]);
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    function Get-InstanceInformationFromSql {
        [OutputType([PSCustomObject[]])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$false)][Switch]$ShowRelatedInstanceOnly
        )
        begin {
            [string]$myCommand=$null;
            [string]$myShowRelatedInstanceCommand="";
            if ($ShowRelatedInstanceOnly) {$myShowRelatedInstanceCommand=" WHERE [InstanceName]=@@ServiceName"}
            $myCommand="
                DECLARE @myMachineName NVARCHAR(255)
                DECLARE @myDomainName NVARCHAR(255)
                DECLARE @myInstanceName NVARCHAR(255)
                DECLARE @myInstanceRegName NVARCHAR(255)
                DECLARE @myInstancePort NVARCHAR(255)
                DECLARE @myForceEncryption BIT
                DECLARE @myDefaultDataPath NVARCHAR(255)
                DECLARE @myDefaultLogPath NVARCHAR(255)
                DECLARE @myDefaultBackupPath NVARCHAR(255)
                DECLARE @myCollation NVARCHAR(255)
                DECLARE @myPatchLevel NVARCHAR(255)
                DECLARE @myRegInstanceFilter NVARCHAR(255)
                CREATE TABLE #myInstance (InstanceName sysname,InstanceRegName NVARCHAR(255))
                CREATE TABLE #myInstanceInfo (MachineName NVARCHAR(255), DomainName NVARCHAR(255), InstanceName sysname,InstanceRegName NVARCHAR(255), InstancePort NVARCHAR(255), ForceEncryption BIT, DefaultDataPath NVARCHAR(255), DefaultLogPath NVARCHAR(255), DefaultBackupPath NVARCHAR(255), Collation NVARCHAR(255), PatchLevel NVARCHAR(255))

                SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
                INSERT INTO #myInstance EXECUTE master.dbo.xp_regenumvalues 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter
                DECLARE myCursor CURSOR FOR SELECT [InstanceName],[InstanceRegName] FROM [#myInstance] " + $myShowRelatedInstanceCommand + "
                OPEN myCursor
                FETCH NEXT FROM myCursor INTO @myInstanceName,@myInstanceRegName
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    INSERT INTO #myInstanceInfo ([InstanceName],[InstanceRegName]) VALUES (@myInstanceName,@myInstanceRegName)
                    SET @myRegInstanceFilter='SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'ComputerName',@myMachineName OUTPUT
                    SET @myRegInstanceFilter='SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'Domain',@myDomainName OUTPUT
                    SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\'+@myInstanceRegName+'\MSSQLServer\SuperSocketNetLib\Tcp\IPAll'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'TcpPort',@myInstancePort OUTPUT
                    SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\'+@myInstanceRegName+'\MSSQLServer\SuperSocketNetLib'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'ForceEncryption',@myForceEncryption OUTPUT
                    SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\'+@myInstanceRegName+'\MSSQLServer'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'DefaultData',@myDefaultDataPath OUTPUT
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'DefaultLog',@myDefaultLogPath OUTPUT
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'BackupDirectory',@myDefaultBackupPath OUTPUT
                    SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\'+@myInstanceRegName+'\Setup'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'Collation',@myCollation OUTPUT
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'PatchLevel',@myPatchLevel OUTPUT

                    UPDATE #myInstanceInfo SET 
                        [MachineName]=@myMachineName,
                        [DomainName]=@myDomainName,
                        [InstancePort]=@myInstancePort,
                        [ForceEncryption]=@myForceEncryption,
                        [DefaultDataPath]=@myDefaultDataPath,
                        [DefaultLogPath]=@myDefaultLogPath,
                        [DefaultBackupPath]=@myDefaultBackupPath,
                        [Collation]=@myCollation,
                        [PatchLevel]=@myPatchLevel
                    WHERE [InstanceName]=@myInstanceName
                    FETCH NEXT FROM myCursor INTO @myInstanceName,@myInstanceRegName
                END 
                CLOSE myCursor;
                DEALLOCATE myCursor;
                SELECT MachineName,DomainName,InstanceName,InstanceRegName,InstancePort,ForceEncryption,DefaultDataPath,DefaultLogPath,DefaultBackupPath,Collation,PatchLevel FROM [#myInstanceInfo]

                DROP TABLE [#myInstance]
                DROP TABLE [#myInstanceInfo]
            "
        }
        process {
            [PSCustomObject[]]$myAnswer=$null;
            try {
                [System.Collections.ArrayList]$myInstanceCollection=$null;
                $myInstanceCollection=[System.Collections.ArrayList]::new();
                $myResult=Read-SqlQuery -ConnectionString $ConnectionString -Query $myCommand
                $null=$myResult | ForEach-Object{
                    $myInstanceObject=[PSCustomObject]@{
                    MachineName=$_.MachineName
                    DomainName=$_.DomainName
                    InstanceName=$_.InstanceName
                    InstanceRegName=$_.InstanceRegName
                    InstancePort=$_.InstancePort
                    ForceEncryption=$_.ForceEncryption
                    DefaultDataPath=$_.DefaultDataPath
                    DefaultLogPath=$_.DefaultLogPath
                    DefaultBackupPath=$_.DefaultBackupPath
                    Collation=$_.Collation
                    PatchLevel=$_.PatchLevel}; 
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name InstanceMajorVersion -Value {return [int]($this.PatchLevel.Split('.')[0])}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameInstanceName -Value {$myInstanceName="";if ($this.InstanceName -and $this.InstanceName.Trim().Length -gt 0) {$myInstanceName="\" + $this.InstanceName}; return $this.MachineName+$myInstanceName}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameDomainNameInstanceName -Value {$myInstanceName="";$myDomainName="";if ($this.InstanceName -and $this.InstanceName.Trim().Length -gt 0) {$myInstanceName="\" + $this.InstanceName};if ($this.DomainName -and $this.DomainName.Trim().Length -gt 0) {$myDomainName="." + $this.DomainName}; return $this.MachineName+$myDomainName+$myInstanceName}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameDomainNameInstanceNamePortNumber -Value {return $this.MachineNameDomainNameInstanceName+","+$this.InstancePort.Split(',')[0]}
                    $myInstanceCollection.Add($myInstanceObject);
                };
                $myAnswer=($myInstanceCollection.ToArray([PSCustomObject]))
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    function Get-InstanceInformation {
        [OutputType([PSCustomObject[]])]
        param (
            [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][string]$ConnectionString,
            [Parameter(Mandatory=$false)][Switch]$ShowRelatedInstanceOnly
        )
        begin {}
        process {
            [PSCustomObject[]]$myAnswer=$null;
            try {
                if ($ConnectionString) {
                    if ($ShowRelatedInstanceOnly){
                        $myAnswer=Get-InstanceInformationFromSql -ConnectionString $ConnectionString -ShowRelatedInstanceOnly
                    }else{
                        $myAnswer=Get-InstanceInformationFromSql -ConnectionString $ConnectionString
                    }
                } else {
                    $myAnswer=Get-InstanceInformationFromRegistery
                }
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    unction Get-InfoFromSqlRegisteredServers {
        [OutputType([PSCustomObject[]])]
        Param (
            [parameter(Mandatory = $true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][string]$MonitoringConnectionString,
            [parameter(Mandatory = $false)][string[]]$ExcludedList,
            [parameter(Mandatory = $false)][string]$FilterGroup
        )
        begin{
            [PSCustomObject[]]$myAnswer=$null
            [string]$myQuery=$null
            [string]$myWhereCondition=''    
            [string]$myExludedString=''

            if ($null -ne $ExcludedList){
                foreach ($myExcludedItem in $ExcludedList){
                    $myExludedString+=",'" + $myExcludedItem.Trim() + "'"
                }
            }
    
            $myExludedString=Clear-SqlParameter -ParameterValue $myExludedString -RemoveWildcard -RemoveDoubleQuote -RemoveDollerSign -RemoveBraces
            $FilterGroup=Clear-SqlParameter -ParameterValue $FilterGroup -RemoveWildcard -RemoveDoubleQuote -RemoveDollerSign
    
            if($null -eq $myExludedString) {$myExludedString=''}
            if($null -ne $FilterGroup -and  $FilterGroup.Trim() -ne '') {$myWhereCondition="AND myGroups.name = '"+$FilterGroup+"'"}
        }
        process {
            $myMonitoringInstancInfo=Get-InstanceInformation -ConnectionString $MonitoringConnectionString -ShowRelatedInstanceOnly
            $myMonitoringInstanceName=$myMonitoringInstancInfo.MachineNameDomainNameInstanceNamePortNumber
            $myQuery = "
                SELECT Distinct
                    myGroups.name AS ServerGroupName,
                    myServer.server_name AS InstanceName,
                    'Data Source='+myServer.server_name+';Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;Integrated Security=True;' AS EncryptConnectionString,
                    'Data Source='+myServer.server_name+';Initial Catalog=master;Integrated Security=True;' AS ConnectionString
                FROM
                    msdb.dbo.sysmanagement_shared_server_groups_internal As myGroups WITH (READPAST)
                    INNER JOIN msdb.dbo.sysmanagement_shared_registered_servers_internal As myServer  WITH (READPAST) ON myGroups.server_group_id = myServer.server_group_id
                WHERE
                    myServer.server_name NOT IN('"+$myMonitoringInstanceName+"'"+$myExludedString+")
                    " + $myWhereCondition
            
            try {
                [System.Collections.ArrayList]$myServerCollection=$null;
                $myServerCollection=[System.Collections.ArrayList]::new();
        
                $myResult= Invoke-Sqlcmd -ConnectionString $MonitoringConnectionString -Query $myQuery -OutputSqlErrors $true
                $null=$myResult | ForEach-Object{
                    $myInstanceObject=[PSCustomObject]@{
                    ServerGroupName=$_.ServerGroupName
                    InstanceName=$_.InstanceName
                    EncryptConnectionString=$_.EncryptConnectionString
                    ConnectionString=$_.ConnectionString}; 
                    $myServerCollection.Add($myInstanceObject);
                };
                $myAnswer=($myServerCollection.ToArray([PSCustomObject]))
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer
        }
        end {}
    }
    function Get-DatabaseList {
        [OutputType([PSCustomObject[]])]
        Param (
            [parameter(Mandatory = $true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][string]$ConnectionString,
            [parameter(Mandatory = $false)][string[]]$ExcludedList
        )
    
        begin {
            $myAnswer=$null
            [string]$myQuery=$null
            [string]$myExludedDB=''
    
            if ($null -ne $ExcludedList){
                foreach ($myExceptedDB in $ExcludedList){
                    $myExludedDB+=",'" + $myExceptedDB.Trim() + "'"
                }
            }
            $myExludedDB=Clear-SqlParameter -ParameterValue $myExludedDB -RemoveWildcard -RemoveDoubleQuote -RemoveDollerSign -RemoveBraces
    
            $myQuery = 
            "
            SELECT 
                [myDatabase].[name]
            FROM 
                master.sys.databases myDatabase WITH (READPAST)
                LEFT OUTER JOIN master.sys.dm_hadr_availability_replica_states AS myHA WITH (READPAST) on myDatabase.replica_id=myHa.replica_id
            WHERE
                [myDatabase].[name] NOT IN ('master','msdb','model','tempdb'"+$myExludedDB+") 
                AND [myDatabase].[state] = 0
                AND [myDatabase].[source_database_id] IS NULL -- REAL DBS ONLY (Not Snapshots)
                AND [myDatabase].[is_read_only] = 0
                AND ([myHA].[role]=1 or [myHA].[role] is null)
            "
        }
        process {
            try {
                [System.Collections.ArrayList]$myDatabaseCollection=$null;
                $myDatabaseCollection=[System.Collections.ArrayList]::new();
        
                $myResult= Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myQuery -OutputSqlErrors $true
                $null=$myResult | ForEach-Object{
                    $myDatabaseObject=[PSCustomObject]@{
                    DatabaseName=$_.name}; 
                    $myDatabaseCollection.Add($myDatabaseObject);
                };
                $myAnswer=($myDatabaseCollection.ToArray([PSCustomObject]))
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer
        }
        end {}
    }
#endregion

#region Export
    Export-ModuleMember -Function IsNumeric,Clear-Text,Clear-SqlParameter,Export-DatabaseBlob,Read-SqlQuery,Invoke-SqlCommand,Test-DatabaseConnection,Test-InstanceConnection,Get-InstanceInformation ,Get-InfoFromSqlRegisteredServers,Get-DatabaseList
#endregion
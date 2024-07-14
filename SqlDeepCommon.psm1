Using module .\SqlDeepLogWriter.psm1
Class InstanceObject {  # Data structure for Instance Object
    [string]$MachineName
	[string]$DomainName
	[string]$InstanceName
    [string]$InstanceRegName
    [string]$InstancePort
    [bool]$ForceEncryption
    [string]$DefaultDataPath
    [string]$DefaultLogPath
    [string]$DefaultBackupPath
    [string]$Collation
    [string]$PatchLevel
	
	InstanceProperty([string]$MachineName,[string]$DomainName,[string]$InstanceName,[string]$InstanceRegName,[string]$InstancePort,[bool]$ForceEncryption,[string]$DefaultDataPath,[string]$DefaultLogPath,[string]$DefaultBackupPath,[string]$Collation,[string]$PatchLevel){
		$this.MachineName=$MachineName;
		$this.DomainName=$DomainName;
		$this.InstanceName=$InstanceName;
		$this.InstanceRegName=$InstanceRegName;
		$this.InstancePort=$InstancePort;
        $this.ForceEncryption=$ForceEncryption;
        $this.DefaultDataPath=$DefaultDataPath;
        $this.DefaultLogPath=$DefaultLogPath;
        $this.DefaultBackupPath=$DefaultBackupPath;
        $this.Collation=$Collation;
        $this.PatchLevel=$PatchLevel;
	}
}
Class Instance {    # Instance level common functions
    [bool]Test_InstanceConnectivity([string]$ConnectionString,[string]$DatabaseName) {  # Test Instance connectivity
        $this.LogWriter.Write($this.LogStaticMessage+"Processing Started.", [LogType]::INF)
        [bool]$myAnswer=$false
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$true} else {$myAnswer=$false}
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    [InstanceObject[]]Get_InstanceInfo() {  # Retrive current machine sql instance(s) and it's related info from windows registery
        [InstanceObject[]]$myAnswer=$null;
        [string]$myMachineName=$null;
        [string]$myDomainName=$null;
        [string]$myRegInstanceFilter=$null;

        try {
            [System.Collections.ArrayList]$myInstanceCollection=$null
            $myInstanceCollection=[System.Collections.ArrayList]::new()
            $myMachineName=($env:computername)
            $myDomainName=(Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem).Domain
            $myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
            $myRegKey=Get-ItemProperty -Path $myRegInstanceFilter
            $myRegKey.psobject.Properties | Where-Object -Property Name -NotIn ("PSPath","PSParentPath","SQL","PSChildName","PSDRIVE","PSProvider") | ForEach-Object{Write-Host ($myMachineName+","+$myDomainName+","+$_.Name+","+$_.Value);$myInstanceCollection.Add([InstanceObject]::New($myMachineName,$myDomainName,$_.Name,$_.Value,'1433',$false,"","","","",""))}
            $myInstanceCollection | %{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$myInstance.InstanceRegName+'\MSSQLServer\SuperSocketNetLib\Tcp\IPAll';$_.InstancePort=(Get-ItemProperty -Path $myRegInstanceFilter).TcpPort}
            $myInstanceCollection | %{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$myInstance.InstanceRegName+'\MSSQLServer\SuperSocketNetLib';$_.ForceEncryption=(Get-ItemProperty -Path $myRegInstanceFilter).ForceEncryption}
            $myInstanceCollection | %{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$myInstance.InstanceRegName+'\MSSQLServer';$_.DefaultDataPath=(Get-ItemProperty -Path $myRegInstanceFilter).DefaultData;$_.DefaultLogPath=(Get-ItemProperty -Path $myRegInstanceFilter).DefaultLog;$_.DefaultBackupPath=(Get-ItemProperty -Path $myRegInstanceFilter).BackupDirectory}
            $myInstanceCollection | %{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$myInstance.InstanceRegName+'\Setup';$_.Collation=(Get-ItemProperty -Path $myRegInstanceFilter).Collation;$_.PatchLevel=(Get-ItemProperty -Path $myRegInstanceFilter).PatchLevel}
            $myAnswer=$myInstanceCollection.ToArray([InstanceObject])
        }
        catch
        {
            Write-Log -Type WRN -Content ($_.ToString()).ToString()
        }
        return $myAnswer
    }
}
Class Database {    # Database level common functions
    [bool]Test_DatabaseConnectivity([string]$ConnectionString,[string]$DatabaseName) {  # Test Database connectivity
        $this.LogWriter.Write($this.LogStaticMessage+"Processing Started.", [LogType]::INF)
        [bool]$myAnswer=$false
        [string]$myCommand=$null
        
        $DatabaseName=$this.Clean_Parameters($DatabaseName)
        $myCommand="
            USE ["+$DatabaseName+"];
            SELECT TOP 1 1 AS Result FROM [master].[sys].[databases] WHERE name = '" + $DatabaseName + "';
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$true} else {$myAnswer=$false}
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    [bool]Execute_SqlCommand([string]$ConnectionString,[string]$CommandText)     # Execute SQL Command via ADO.NET
    {
        [bool]$myAnswer=$false
        try
        {
            $mySqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $mySqlCommand = $mySqlConnection.CreateCommand();
            $mySqlConnection.Open(); 
            $mySqlCommand.CommandText = $CommandText;                      
            $mySqlCommand.ExecuteNonQuery();
            $myAnswer=$true;
        }
        catch
        {       
            $myAnswer=$false;
            Write-Error($_.ToString());
            Throw;
        }
        finally
        {
            $mySqlCommand.Dispose();
            $mySqlConnection.Close();
            $mySqlConnection.Dispose();
            #[System.Data.SqlClient.SqlConnection]::ClearAllPools();  
        }
        return $myAnswer
    }
    [System.Data.DataSet]Execute_SqlQuery([string]$ConnectionString,[string]$CommandText)     # Execute SQL Query via ADO.NET
    {
        [System.Data.DataSet]$myAnswer=$null
        try
        {
            $mySqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $mySqlCommand = $mySqlConnection.CreateCommand();
            $mySqlConnection.Open(); 
            $mySqlCommand.CommandText = $CommandText;                      
            $myDataSet = New-Object System.Data.DataSet;
            $mySqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter;
            $mySqlDataAdapter.SelectCommand = $mySqlCommand;
            $mySqlDataAdapter.Fill($myDataSet);
            $myAnswer=$myDataSet;
        }
        catch
        {       
            $myAnswer=$null;
            Write-Error($_.ToString());
            Throw;
        }
        finally
        {
            $mySqlCommand.Dispose();
            $mySqlConnection.Close();
            $mySqlConnection.Dispose();
            #[System.Data.SqlClient.SqlConnection]::ClearAllPools();  
        }
        return $myAnswer
    }
}
Class Data {    # Data level common functions
    [string]Clean_Parameters([string]$ParameterValue,[bool]$RemoveWildcard){  # Remove injection like characters
        [string]$myAnswer=$null        
        [string[]]$myProhibitedPhrases=$null

        $myProhibitedPhrases.Add(";")
        if ($RemoveWildcard)    {$myProhibitedPhrases.Add("%")}
        $myAnswer=$this.Clean_String($ParameterValue,$myProhibitedPhrases)
        return $myAnswer
    }
    [string]Clean_String([string]$InputString,[string[]]$ProhibitedPhrases){  # Remove Prohibited Phrases from InputString
        [string]$myAnswer=$null
        $myAnswer=$InputString
        foreach ($ProhibitedPhrase in $ProhibitedPhrases){
            $myAnswer=$myAnswer.Replace($ProhibitedPhrase,"")
        }
        return $myAnswer
    }
}
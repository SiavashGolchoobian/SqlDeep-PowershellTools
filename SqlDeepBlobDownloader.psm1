<#
.SYNOPSIS
    A script module that provides some functionality.

.DESCRIPTION
    A detailed description of what the script module does.

.PARAMETER Input
    The input parameter for the Get-SomeData function.

.PARAMETER Output
    The output parameter for the Set-SomeData function.

.EXAMPLE
    Import-Module .\SqlDeepBlobDownloader.psm1
    
    Sample 1: Download single file
    $myConnectionString="Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True"
    $myDestinationFolderPath="C:\Repo"
    $myDestinationFileName="File1.txt"
    $myDestinationFilePath=$myDestinationFolderPath + "\" + $myDestinationFileName
    $myBlobQuery="SELECT TOP 1 [FileContent] FROM [SqlDeep].[dbo].[ScriptRepositoryGuest] WITH (READPAST) WHERE [IsEnabled]=1 AND [HostChecksum]=[GuestChecksum] AND [FileUniqueName]=N'"+$myDestinationFileName+"'"
    DownloadSingleFileFromDB -ConnectionString $myConnectionString -QueryToGetSpecificFile $myBlobQuery -DestinationFilePath $myDestinationFilePath

    Sample 2: Download list of files
    $myConnectionString="Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True"
    $myDestinationFolderPath="C:\Repo"
    $myFileQueryList=@{}
    $myFileQueryList.("file1.txt")="SELECT TOP 1 [FileContent] FROM [SqlDeep].[dbo].[ScriptRepositoryGuest] WITH (READPAST) WHERE [IsEnabled]=1 AND [HostChecksum]=[GuestChecksum] AND [FileUniqueName]=N'file1.txt'"
    $myFileQueryList.("file2.txt")="SELECT TOP 1 [FileContent] FROM [SqlDeep].[dbo].[ScriptRepositoryGuest] WITH (READPAST) WHERE [IsEnabled]=1 AND [HostChecksum]=[GuestChecksum] AND [FileUniqueName]=N'file2.txt'"
    $myFileQueryList.("file3.txt")="SELECT TOP 1 [FileContent] FROM [SqlDeep].[dbo].[ScriptRepositoryGuest] WITH (READPAST) WHERE [IsEnabled]=1 AND [HostChecksum]=[GuestChecksum] AND [FileUniqueName]=N'file3.txt'"
    DownloadSingleFileFromDB -ConnectionString $myConnectionString -FileQueryList $myFileQueryList -DestinationFolderPath $myDestinationFolderPath
    
#>
Import-Module -Name SqlServer
Function DownloadSingleFileFromDB #Export a BLOB file from anywhere to disk
{
    Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString,
        [Parameter(Mandatory=$true)][string]$QueryToGetSpecificFile,
        [Parameter(Mandatory=$true)][string]$DestinationFilePath
        )
    [bool]$myAnswer=$true;
	try {
        $myBufferSize = 8192*8;
        # Open ADO.NET Connection
        $myConnection = New-Object Data.SqlClient.SqlConnection;
        $myConnection.ConnectionString = $ConnectionString;
        $myConnection.Open();

        # New Command and Reader
        $myCmd = New-Object Data.SqlClient.SqlCommand ($QueryToGetSpecificFile, $myConnection);
        $myReader = $myCmd.ExecuteReader();
        
        # Create a byte array for the stream.
        $myOut = [array]::CreateInstance('Byte', $myBufferSize)

        # Looping through records
        While ($myReader.Read())
        {
            #Create Directory if not exists and remove any Existing item
            $myFolderPath=Split-Path $DestinationFilePath
            IF (-not (Test-Path -Path $myFolderPath -PathType Container)) {
                New-Item -Path $myFolderPath -ItemType Directory -Force
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
        }

        # Closing & Disposing all objects            
        if ($myFileStream) {$myFileStream.Dispose()} else {$myAnswer=$false};
        $myReader.Close();
        $myCmd.Dispose();
        $myConnection.Close();
    } catch {
        $myAnswer=$false
        Write-Error($_.ToString())
    }
    return $myAnswer
}
Function DownloadMultipleFilesFromDB
{
        Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString,
        [Parameter(Mandatory=$true)][hashtable]$FileQueryList,
        [Parameter(Mandatory=$true)][string]$DestinationFolderPath
        )
    [bool]$myAnswer=$false;
    try{
        [int]$myRequestCount=$FileQueryList.Count
        [int]$myDownloadedCount=0
        [bool]$myDownloadResult=$false
        foreach ($myKey in $FileQueryList) {
            $myFilePath=$DestinationFolderPath + "\" + $myKey
            $myBlobQuery=$FileQueryList[$myKey]
            $myDownloadResult=DownloadSingleFileFromDB -ConnectionString $ConnectionString -QueryToGetSpecificFile $myBlobQuery -DestinationFilePath $myFilePath
            if ($myDownloadResult) {$myDownloadedCount+=1}
        }
        if ($myDownloadedCount -eq $myRequestCount) {$myAnswer=$true}
    } catch {
        $myAnswer=$false
        Write-Error($_.ToString())
    }
    return $myAnswer
}
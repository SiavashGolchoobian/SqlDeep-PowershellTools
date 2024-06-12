Import-Module "$PSScriptRoot\SqlDeepBlobDownloader.psm1"
    
#Sample 1: Download single file
[bool]$myAnswer
[string]$myConnectionString="Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True"
[string]$myDestinationFolderPath="C:\Repo"
[string]$myDestinationFileName="File1.txt"
[string]$myDestinationFilePath=$myDestinationFolderPath + "\" + $myDestinationFileName
[string]$myBlobQuery="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'"+$myDestinationFileName+"'"
$myAnswer=DownloadSingleFileFromDB -ConnectionString $myConnectionString -QueryToGetSpecificFile $myBlobQuery -DestinationFilePath $myDestinationFilePath

#Sample 2: Download list of files
[bool]$myAnswer
[string]$myConnectionString="Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True"
[string]$myDestinationFolderPath="C:\Repo"
$myFileQueryList=@{}
$myFileQueryList.("file1.txt")="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'file1.txt'"
$myFileQueryList.("file2.txt")="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'file2.txt'"
$myFileQueryList.("file3.txt")="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'file3.txt'"
$myAnswer=DownloadMultipleFilesFromDB -ConnectionString $myConnectionString -FileQueryList $myFileQueryList -DestinationFolderPath $myDestinationFolderPath

#Sample 3: Download list of files via query
[bool]$myAnswer
[string]$myConnectionString="Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True"
[string]$myDestinationFolderPath="C:\Repo\DatabaseShipping"
[string]$myCommand="SELECT [myItems].[ItemName],[myItems].[SubscriberItemId] FROM [SqlDeep].[repository].[dbafn_get_subscriber_item_and_dependencies] ('Saipa_SqlDeepDatabaseShipping.ps1',Null,Null) AS myItems WHERE [myItems].[IsEnabled]=1"
$myFileQueryList=@{}
try{
    $myRecord=Invoke-Sqlcmd -ConnectionString $myConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
    $myRecord
    if ($null -ne $myRecord) {
        foreach ($myRow in $myRecord){
            $myFileQueryList.Add($myRow.ItemName.ToString(),"SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [SubscriberItemId]=" + $myRow.SubscriberItemId.ToString())
        }
    }
    $myAnswer=DownloadMultipleFilesFromDB -ConnectionString $myConnectionString -FileQueryList $myFileQueryList -DestinationFolderPath $myDestinationFolderPath
}Catch{
    Write-Output(($_.ToString()).ToString())
}
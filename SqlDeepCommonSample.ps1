Using module .\SqlDeepCommon.psm1

#Sample 1:  Clear input text from any ProhibitedPhrases
[string[]]$myBlackList=@(';','WHERE')
'SELECT name FROM sys.databases WHERE 1=1;','SELECT name FROM sys.databases WHERE 2=2;','Hello World' | ForEach-Object{Clear-Text -Text $_ -ProhibitedPhrases $myBlackList}

#Sample 2:  Clear parameter value from any bad characters
"SELECT name FROM sys.databases WHERE 1={1};","SELECT name FROM sys.databases WHERE name like '%';","Hello World" | ForEach-Object{Clear-SqlParameter -ParameterValue $_ -RemoveWildcard -RemoveBraces}

#Sample 3.1:  Download BLOB from database to a file
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Export-DatabaseBlob -ConnectionString $myConnectionString -CommandText "SELECT CAST('Hello World' AS VARBINARY(MAX)) AS BlobData" -DestinationFilePath "E:\Log\test.txt"
$mySqlQueryResult

#Sample 3.2:  Download multiple BLOB from database to a directory
[hashtable]$myFileListQuery;    #This Hashtable should have filename as hashtable item key and BLOB retrive query as hastable item value
[string]$myConnectionString="Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True";
[string]$myDestinationFolderPath="C:\Repo";
[bool]$myAnswer=$false;
$myFileQueryList=@{}
$myFileQueryList.("file1.txt")="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'file1.txt'"
$myFileQueryList.("file2.txt")="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'file2.txt'"
$myFileQueryList.("file3.txt")="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'file3.txt'"
<#
--OR to fill Hashtable via query you can use bellow statements
[string]$myCommand="SELECT [myItems].[ItemName],[myItems].[SubscriberItemId] FROM [SqlDeep].[repository].[dbafn_get_subscriber_item_and_dependencies] ('Saipa_SqlDeepDatabaseShipping.ps1',Null,Null) AS myItems WHERE [myItems].[IsEnabled]=1"
$myRecord=Invoke-Sqlcmd -ConnectionString $myConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
$myRecord
if ($null -ne $myRecord) {
    foreach ($myRow in $myRecord){
        $myFileQueryList.Add($myRow.ItemName.ToString(),"SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [SubscriberItemId]=" + $myRow.SubscriberItemId.ToString())
    }
}
#>
try{
    [int]$myRequestCount=$myFileQueryList.Count
    [int]$myDownloadedCount=0
    [bool]$myDownloadResult=$false
    if ($myDestinationFolderPath[-1] -ne "\") {$myDestinationFolderPath+="\"}
    foreach ($myItem in $myFileQueryList.GetEnumerator()) {
        [string]$myFile=$myItem.Key.ToString().Trim()
        [string]$myBlobQuery=$myItem.Value.ToString().Trim()
        $myFilePath=$myDestinationFolderPath + $myFile
        If ($myFile.Length -gt 0 -and $myDestinationFolderPath.Length -gt 0) {
            Write-Output ("Multiple file downloader: Downloading " + $myFilePath + " ...")
            $myDownloadResult=Export-DatabaseBlob -ConnectionString $myConnectionString -CommandText $myBlobQuery -DestinationFilePath $myFilePath
        } else {
            $myDownloadResult=$false
        }
        if ($myDownloadResult) {$myDownloadedCount+=1}
    }
    if ($myDownloadedCount -eq $myRequestCount) {$myAnswer=$true}
} catch {
    $myAnswer=$false
    Write-Error($_.ToString())
}
Write-Output $myAnswer

#Sample 4:  Query from database
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Read-SqlQuery -ConnectionString $myConnectionString -Query "SELECT database_id,name FROM sys.databases"
$mySqlQueryResultUnionAll="SELECT database_id,name FROM sys.databases","select 1 as database_id,name from sys.all_objects" | ForEach-Object{Read-SqlQuery -ConnectionString $myConnectionString -Query $_}
$mySqlQueryResultUnionAll

#Sample 5:  Invoke Sql Command
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Invoke-SqlCommand -ConnectionString $myConnectionString -Command "CREATE Database Test01"

#Sample 6:  Test Database Connection
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
Test-DatabaseConnection -ConnectionString $myConnectionString -DatabaseName 'Test'

#Sample 7:  Test Instance Connection
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
Test-InstanceConnection -ConnectionString $myConnectionString

#Sample 8:  Get Instance Info
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Get-InstanceInformation -ConnectionString $myConnectionString
$mySqlQueryResult=Get-InstanceInformation
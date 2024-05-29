Import-Module .\SqlDeepBlobDownloader.psm1
    
#Sample 1: Download single file
[bool]$myAnswer
[string]$myConnectionString="Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True"
[string]$myDestinationFolderPath="C:\Repo"
[string]$myDestinationFileName="File1.txt"
[string]$myDestinationFilePath=$myDestinationFolderPath + "\" + $myDestinationFileName
[string]$myBlobQuery="SELECT TOP 1 [FileContent] FROM [SqlDeep].[dbo].[ScriptRepositoryGuest] WITH (READPAST) WHERE [IsEnabled]=1 AND [HostChecksum]=[GuestChecksum] AND [FileUniqueName]=N'"+$myDestinationFileName+"'"
$myAnswer=DownloadSingleFileFromDB -ConnectionString $myConnectionString -QueryToGetSpecificFile $myBlobQuery -DestinationFilePath $myDestinationFilePath

#Sample 2: Download list of files
[bool]$myAnswer
[string]$myConnectionString="Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True"
[string]$myDestinationFolderPath="C:\Repo"
$myFileQueryList=@{}
$myFileQueryList.("file1.txt")="SELECT TOP 1 [FileContent] FROM [SqlDeep].[dbo].[ScriptRepositoryGuest] WITH (READPAST) WHERE [IsEnabled]=1 AND [HostChecksum]=[GuestChecksum] AND [FileUniqueName]=N'file1.txt'"
$myFileQueryList.("file2.txt")="SELECT TOP 1 [FileContent] FROM [SqlDeep].[dbo].[ScriptRepositoryGuest] WITH (READPAST) WHERE [IsEnabled]=1 AND [HostChecksum]=[GuestChecksum] AND [FileUniqueName]=N'file2.txt'"
$myFileQueryList.("file3.txt")="SELECT TOP 1 [FileContent] FROM [SqlDeep].[dbo].[ScriptRepositoryGuest] WITH (READPAST) WHERE [IsEnabled]=1 AND [HostChecksum]=[GuestChecksum] AND [FileUniqueName]=N'file3.txt'"
$myAnswer=DownloadSingleFileFromDB -ConnectionString $myConnectionString -FileQueryList $myFileQueryList -DestinationFolderPath $myDestinationFolderPath
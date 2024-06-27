Using module .\SqlDeepLogWriter.psm1

$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "Test" -LogToConsole -LogToFile -LogFilePath "U:\Audit\LogTest_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[Events]"
$myLogWriter.Write("Testing process started...", [LogType]::INF) 
$myLogWriter.Write("Testing process started...", [LogType]::WRN) 
$myLogWriter.Write("Testing process started...", [LogType]::ERR,$true) 

$myLogWriter.ArchiveLogFilesToZipFile([ArchiveTimeScale]::ByMonth,2,5,$true) #   Archive all log files (except last 2 files) to a zip file (a zip file for each month) inside current log directoy and remove source log files
$myLogWriter.ArchiveLogFilesToZipFile("ArchivedLogTest_",[ArchiveTimeScale]::ByMonth,2,5,$true) #   Archive all log files (except last 2 files) to a zip file (a zip file named ArchiveLogTest_xxx.zip for each month) inside current log directoy and remove source log files
$myLogWriter.ArchiveLogFilesToZipFile("U:\Databases\Audit\Archive","ArchivedLogTest_",[ArchiveTimeScale]::ByMonth,2,5,$true) #   Archive all log files (except last 2 files) to a zip file (a zip file named ArchiveLogTest_xxx.zip for each month) inside U:\Databases\Audit\Archive directoy and remove source log files
$myLogWriter.ArchiveLogFilesToZipFile("U:\Databases\Audit","LogTest_{Date}.txt","U:\Databases\Audit\Archive","ArchivedLogTest_",[ArchiveTimeScale]::ByDay,1,5,$true) #   Archive all log files (except last file) inside U:\Databases\Audit directory with LogTest_{Date}.txt file pattern names to a zip file (a zip file named ArchiveLogTest_xxx.zip for each month) inside U:\Databases\Audit\Archive directoy and remove source log files
$myLogWriter.ArchiveLogFilesToZipFile("U:\Databases\Audit","LogTest_.+_{Date}.txt","U:\Databases\Audit\Archive","ArchivedLogTest_",[ArchiveTimeScale]::ByDay,1,5,$true) #   Archive all log files (except last file) inside U:\Databases\Audit directory with file names likes "LogTest_*_2024_01_27.txt pattern to a zip file (a zip file named ArchiveLogTest_xxx.zip for each month) inside U:\Databases\Audit\Archive directoy and remove source log files

$myLogWriter.DeleteArchiveFiles([ArchiveTimeScale]::ByMonth,2) #  Remove archived monthy zipped files (except last 2 zip files)
$myLogWriter.DeleteArchiveFiles("U:\Databases\Audit\Archive",[ArchiveTimeScale]::ByMonth,2) #  Remove archived monthly zipped files (except last 2 zip files)
$myLogWriter.DeleteArchiveFiles("U:\Databases\Audit","ArchivedLogTest_",[ArchiveTimeScale]::ByDay,2) #  Remove archived daily zipped files (except last 2 zip files)
$myLogWriter.DeleteArchiveFiles("U:\Databases\Audit","Archived.+_",[ArchiveTimeScale]::ByDay,2) #  Remove archived daily zipped files (except last 2 zip files)
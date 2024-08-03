Using module .\SqlDeepCommon.psm1

#Sample 1:  Clear input text from any ProhibitedPhrases
[string[]]$myBlackList=@(';','WHERE')
'SELECT name FROM sys.databases WHERE 1=1;','SELECT name FROM sys.databases WHERE 2=2;','Hello World' | ForEach-Object{Clear-Text -Text $_ -ProhibitedPhrases $myBlackList}

#Sample 2:  Clear parameter value from any bad characters
"SELECT name FROM sys.databases WHERE 1={1};","SELECT name FROM sys.databases WHERE name like '%';","Hello World" | ForEach-Object{Clear-SqlParameter -ParameterValue $_ -RemoveWildcard -RemoveBraces}

#Sample 3:  Download BLOB from database to a file
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Export-DatabaseBlob -ConnectionString $myConnectionString -CommandText "SELECT CAST('Hello World' AS VARBINARY(MAX)) AS BlobData" -DestinationFilePath "E:\Log\test.txt"

#Sample 4:  Query from database
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Read-SqlQuery -ConnectionString $myConnectionString -Query "SELECT database_id,name FROM sys.databases"
$mySqlQueryResultUnionAll="SELECT database_id,name FROM sys.databases","select 1 as database_id,name from sys.all_objects" | ForEach-Object{Read-SqlQuery -ConnectionString $myConnectionString -Query $_}

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
[string]$Message
[string]$Algorithm
[int]$KeySize

$Message="Hello world"
$Algorithm="MD5"        #SHA,SHA1,System.Security.Cryptography.SHA1,System.Security.Cryptography.HashAlgorithm,MD5,System.Security.Cryptography.MD5,SHA256,SHA-256,System.Security.Cryptography.SHA256,SHA384,SHA-384,System.Security.Cryptography.SHA384,SHA512,SHA-512,System.Security.Cryptography.SHA512
$KeySize=3072           #128-bit security

[byte[]]$myMessageByte=$null
[byte[]]$myHashValue=$null
[byte[]]$mySignedHashValue=$null
[System.Security.Cryptography.HashAlgorithm]$myHashAlgorithm=$null
[System.Security.Cryptography.RSA]$myRSA=$null
[System.Security.Cryptography.RSAPKCS1SignatureFormatter]$myRSAFormatter=$null

$myMessageByte=[System.Text.Encoding]::UTF8.GetBytes($Message)
$myHashAlgorithm=[System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
$myHashValue=$myHashAlgorithm.ComputeHash($myMessageByte)

$myRSA=[System.Security.Cryptography.RSA]::Create($KeySize)
$myRSAFormatter=[System.Security.Cryptography.RSAPKCS1SignatureFormatter]::new($myRSA)
$myRSAFormatter.SetHashAlgorithm($Algorithm);
$mySignedHashValue = $myRSAFormatter.CreateSignature($myHashValue);
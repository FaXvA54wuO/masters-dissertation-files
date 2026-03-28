let ip = '192.168.1.251'

let ps = $"
$client = [System.Net.Sockets.TcpClient]::new\()
$client.Connect\(\"($ip)\", 4444)
Write-Host \"Connected to ($ip):4444\"
Read-Host \"Press Enter to close the connection\"
$client.Close\()
"
^powershell -NoProfile -Command $ps 
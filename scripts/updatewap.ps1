#Obtain ADFS Private IP Address
$ADFSIP = (Resolve-DnsName ADFS).IpAddress

#Create a backup file
New-Item -ItemType Directory -Force -Path C:\Temp
Copy-Item -Path "C:\Windows\System32\drivers\etc\hosts" -Destination "C:\temp\hosts" -Force

Set-HostEntry sts.swiftsolves.com $ADFSIP

# Restart Service
Restart-Service "appproxysvc"
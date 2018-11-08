<# 
    .DESCRIPTION 
        This will create a Public IP address, Network Security Group, and public DNS changes for the failed over VM(s). 
         
        Pre-requisites 
        All resources involved are based on Azure Resource Manager (NOT Azure Classic)

        The following AzureRm Modules are required
        - AzureRm.Profile
        - AzureRm.Resources
        - AzureRm.Compute
        - AzureRm.Network

        How to add the script? 
        Add the runbook as a post action in boot up group containing the VMs, where you want to assign a public IP.. 
 
    .NOTES 
        AUTHOR: naswif@microsoft.com 
        LASTEDIT: 2 November, 2018
#>

## Used for manual testing in PS ISE
#$RecoveryPlanContext = Get-Content 'C:\Users\naswif\Documents\val.json' | Out-String | ConvertFrom-Json


param ( 
        [Object]$RecoveryPlanContext 
      ) 

Write-Output $RecoveryPlanContext

# Authenticate
Try
 {
    "Logging in to Azure..."
    $Conn = Get-AutomationConnection -Name AzureRunAsConnection 
     Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint

    "Selecting Azure subscription..."
    Select-AzureRmSubscription -SubscriptionId $Conn.SubscriptionID -TenantId $Conn.tenantid 
 }
Catch
 {
      $ErrorMessage = 'Login to Azure subscription failed.'
      $ErrorMessage += " `n"
      $ErrorMessage += 'Error: '
      $ErrorMessage += $_
      Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
 }



# RecoveryVM Context and VMs
$VMinfo = $RecoveryPlanContext.VmMap | Get-Member | Where-Object MemberType -EQ NoteProperty | select -ExpandProperty Name
#Write-Output $VMinfo
$vmMap = $RecoveryPlanContext.VmMap
#Write-Output $vmMap
## NSG Rules
$rdpRule = New-AzureRmNetworkSecurityRuleConfig -Name Allow-RDP -Description "Allow RDP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
$ftpRule = New-AzureRmNetworkSecurityRuleConfig -Name Allow-FTP -Description "Allow FTP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 21
$passftpRule = New-AzureRmNetworkSecurityRuleConfig -Name Allow-PassFTP -Description "Allow Passive FTP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 1003 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5001-5010
$httpsRule = New-AzureRmNetworkSecurityRuleConfig -Name Allow-HTTPS -Description "Allow HTTPS" -Access Allow -Protocol Tcp -Direction Inbound -Priority 1004 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443
#Write-Output $rdpRule
#Write-Output $ftpRule
#Write-Output $passftpRule
#Write-Output $httpsRule

# Loop Through the VMs create PIP, NSG and Apply, Update Public DNS entries
 #Write-Output ("Starting Loop")
 
 foreach($VMID in $VMinfo)
 {
     $vmprop = $vmMap.$VMID
     #Write-Output $vmprop                
                #this check is to ensure that we skip when some data is not available else it will fail
                #Write-output "Resource group name: " , $vmprop.ResourceGroupName
                #Write-output "Rolename: " , $vmprop.RoleName
                
                #Capture ARM VM Object
                $VM = Get-AzureRmVM -ResourceGroupName $vmprop.ResourceGroupName -Name $vmprop.RoleName
                
                #Capture ARM NIC
                $ARMNic = Get-AzureRmResource -ResourceId $VM.NetworkProfile.NetworkInterfaces[0].id
                $NIC = Get-AzureRmNetworkInterface -Name $ARMNic.Name -ResourceGroupName $ARMNic.ResourceGroupName
                
                #Generate Public IP Address and apply to VM NIC
                New-AzureRmPublicIpAddress -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Location $VM.Location -AllocationMethod Static -Force
                #Write-Output ("Created PIP")
                $PIP = Get-AzureRmPublicIpAddress -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName
                #Write-Output $PIP
                #Write-Output "PIP IPv4 Address: " , $PIP.IpAddress
                #Write-Output "BEFORE PIP: " , $NIC.IpConfigurations[0]
                #DebugPreference="Continue"
                $NIC.IpConfigurations[0].PublicIpAddress = $PIP
                #Write-Output "AFTER PIP CHANGE-1: " , $NIC.IpConfigurations[0]
                #Write-Output "AFTER PIP CHANGE-2: " , $NIC.IpConfigurations[0].PublicIpAddress
                
                #Write-Output ("Running If Logic")
                #VM Check for WAP, Create NSG with Rules and Apply to VM NIC and Set Public A Host DNS entries
                if ($VM.Name -match "WAP" ) {
                    Write-Output ("WAP VM Found")

                    $nsgName = $VM.Name + "-NSG"
                    $nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $VM.ResourceGroupName -Location $VM.Location -Name $nsgName -SecurityRules $rdpRule,$httpsRule -Force
                    #$nicset = Get-AzureRmNetworkInterface -Name $NIC.name -ResourceGroupName $NIC.ResourceGroupName
                    $NIC.NetworkSecurityGroup = $nsg
                    #Set-AzureRmNetworkInterface -NetworkInterface $nicset

                    $rs = Get-AzureRmDnsRecordSet -name "sts" -RecordType A -ZoneName "swiftsolves.com" -ResourceGroupName "rgdns"
       
                    $rs.Records[0].Ipv4Address = $PIP.IpAddress
                    Set-AzureRmDnsRecordSet -RecordSet $rs
                
                    Write-Output ("WAP VM SET")

                }
     
                #VM Check for FTP, Create NSG with Rules and Apply to VM NIC and Set Public A Host DNS entries
                elseif ($VM.Name -match "FTP") {
                    Write-Output ("FTP VM Found")

                    $nsgName = $VM.Name + "-NSG"
                    $nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $VM.ResourceGroupName -Location $VM.Location -Name $nsgName -SecurityRules $rdpRule,$ftpRule,$passftpRule -Force 
                    #$nicset = Get-AzureRmNetworkInterface -Name $NIC.name -ResourceGroupName $NIC.ResourceGroupName
                    $NIC.NetworkSecurityGroup = $nsg
                    #$nicset | Set-AzureRmNetworkInterface

                    $rs = Get-AzureRmDnsRecordSet -name "ftp" -RecordType A -ZoneName "swiftsolves.com" -ResourceGroupName "rgdns"

                    $rs.Records[0].Ipv4Address = $PIP.IpAddress
                    Set-AzureRmDnsRecordSet -RecordSet $rs
            
                    Write-Output ("FTP VM SET")

                }
                Else {
                    Write-Output "WAP or FTP NOT FOUND!"
                }

                Set-AzureRmNetworkInterface -NetworkInterface $NIC
                Write-Output "Added public IP address to the following VM: " , $VM.Name
 }
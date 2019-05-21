function Invoke-VMCleanup
{
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'None')]
	param
	(
		[Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ServerDefinition')]
		[ValidateNotNullOrEmpty()]
		[GHI.EnvironmentOrchestration.ServerDefinition[]]
		$ServerDefinition,
		
		[Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'Name')]
		[ValidateNotNullOrEmpty()]
		[string]$Name,
		
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$DomainName,
		
		[Parameter(ValueFromPipelineByPropertyName)]
		[ValidateNotNullOrEmpty()]
		[string]$VMMServer = $VMMResources.VMMServer,
		
		[Parameter(ValueFromPipelineByPropertyName)]
		[AllowNull()]
		[pscredential]$Credential = $null,
		
		[Parameter()]
		[switch]$Force
	)
	
	begin
	{
		Set-StrictMode -Version Latest;
		Write-Log -Source $MyInvocation.MyCommand -Message ('{0}: Entering' -f $MyInvocation.MyCommand);
		$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop;
		
		$rejectAll = $false;
		$confirmAll = $false;
		
		$null = Get-SCVMMServer -ComputerName $VMMServer -Credential $Credential;
		$null = Add-AzureRmAccount -Credential (Get-KeystoreCredential -Name 'Azure svcOrchestrator')
	}
	
	process
	{
		#region Collect VMs, AD accounts and DNS records
		$vms = @()
		Write-Log -Source $MyInvocation.MyCommand -Message "Finding all VMs that match [$($Name)]";
		if ($PSCmdlet.ParameterSetName -eq 'ServerDefinition')
		{
			$Name = $ServerDefinition.ComputerName
		}

		$vms += Get-SCVirtualMachine | Where-Object { $_.Name -like $Name } | Select-Object Name, @{ 'Name' = 'Type'; Expression = { 'VMM' } }
		$vms += Get-AzureRmVM | Where-Object { $_.Name -like $Name } | Select-Object Name, @{ 'Name' = 'Type'; Expression = { 'Azure' } }
		
		if (@($vms).Count -gt 1)
		{
			$message = @"
You are about remove the following VMs:
$($vms.Name -join "`n")
Are you sure? (Y,N)
"@
			$response = Read-Host -Prompt $message
			if ($response -ne 'Y')
			{
				throw 'VM cleanup cancelled.'
			}
		}
		
		if ($PSBoundParameters.ContainsKey('DomainName')) {
			$getDnsServerRecordsParams = @{
				RRType = 'A';
				ErrorAction = 'SilentlyContinue';
				ComputerName = $DomainName
				ZoneName = $DomainName
			}
			$dnsRecords = Get-DnsServerResourceRecord @getDnsServerRecordsParams | Where-Object { ($_.HostName -like $Name) -and ($_.HostName -notlike '*.*') }
			
			$getADComputerParams = @{
				ErrorAction = 'SilentlyContinue';
				Properties = 'DistinguishedName';
				Server = $DomainName;
			}
			$adComputers = Get-ADComputer @getADComputerParams -Filter "Name -like '$Name'"
		}
		#endregion
		
		#region VM Cleanup
		if ($vms.Count -eq 0)
		{
			Write-Log -Source $MyInvocation.MyCommand -Message 'No VMs found matching input criteria';
		}
		else
		{
			foreach ($vm in $vms)
			{
				try
				{
					$shouldProcessCaption = 'Virtual machine: {0}' -f $vm.Name;
					if ($PSCmdlet.ShouldProcess($shouldProcessCaption, 'Remove'))
					{
						$shouldContinueCaption = 'Are you sure you want to remove the virtual machine {0}?' -f $vm.Name;
						if ($Force -or $PSCmdlet.ShouldContinue($shouldContinueCaption, 'Remove Virtual machine', [ref]$confirmAll, [ref]$rejectAll))
						{
							switch ($vm.Type)
							{
								'VMM' {
									$vm = Get-SCVirtualMachine -Name $vm.Name
									if ($vm.VirtualMachineState -eq 'Running')
									{
										Write-Log -Source $MyInvocation.MyCommand -Message "Powering down the VMM virtual machine [$($vm.Name)]";
										$null = Get-SCVirtualMachine -Name $vm.Name | Stop-SCVirtualMachine;
									}
									if ($vm.VirtualMachineState -eq 'PowerOff')
									{
										Write-Log -Source $MyInvocation.MyCommand -Message "Removing the VMMvirtual machine [$($vm.Name)]";
										$null = Get-SCVirtualMachine -Name $vm.Name | Remove-SCVirtualMachine;
									}
									else
									{
										throw "VMM VM [$($vm.Name)] could not be powered down to remove."
									}
								}
								'Azure' {
									Write-Log -Source $MyInvocation.MyCommand -Message "Removing Azure VM [$($vm.Name)]..."
									Get-AzureRmVM | Where-Object { $_.Name -eq $vm.Name } | Remove-AzrVirtualMachine -Wait
								}
								default
								{
									throw "Could not determine VM type: [$($_)]"
								}
							}
						}
					}
				}
				catch
				{
					Write-Log -Source $MyInvocation.MyCommand -EventId 1003 -EntryType Error -Message ($_ | Resolve-Error);
				}
			}
		}
		#endregion
		
		#region DNS Record Cleanup
		if (-not (Test-Path -Path Variable:\dnsRecords) -or (-not $dnsRecords))
		{
			Write-Log -Source $MyInvocation.MyCommand -Message 'No DNS records found matching input criteria';
		}
		else
		{
			foreach ($record in $dnsRecords)
			{
				try
				{
					$shouldProcessCaption = 'DNS record: {0}' -f $record.HostName;
					if ($PSCmdlet.ShouldProcess($shouldProcessCaption, 'Remove'))
					{
						$shouldContinueCaption = 'Are you sure you want to remove the DNS record {0}?' -f $record.HostName;
						if ($Force -or $PSCmdlet.ShouldContinue($shouldContinueCaption, 'Remove DNS record', [ref]$confirmAll, [ref]$rejectAll))
						{
							Write-Log -Source $MyInvocation.MyCommand -Message "Removing DNS A record [$($record.HostName)] from zone [$($DomainName)]";
							Remove-DnsServerResourceRecord -ZoneName $DomainName -ComputerName $DomainName -Name $record.HostName -RRType A -Force;
						}
					}
				}
				catch
				{
					Write-Log -Source $MyInvocation.MyCommand -EventId 1003 -EntryType Error -Message ($_ | Resolve-Error);
				}
			}
		}
		#endregion
		
		#region AD Account Cleanup
		if (-not (Test-Path -Path Variable:\adComputers) -or (-not $adComputers))
		{
			Write-Log -Source $MyInvocation.MyCommand -Message 'No AD computer accounts found matching input criteria or no domain specified.';
		}
		else
		{
			foreach ($adComputer in $adComputers)
			{
				$shouldProcessCaption = 'AD computer: {0}' -f $adComputer.DistinguishedName;
				if ($PSCmdlet.ShouldProcess($shouldProcessCaption, 'Remove'))
				{
					$shouldContinueCaption = 'Are you sure you want to remove the AD computer {0}?' -f $adComputer.DistinguishedName;
					if ($Force -or $PSCmdlet.ShouldContinue($shouldContinueCaption, 'Remove AD computer', [ref]$confirmAll, [ref]$rejectAll))
					{
						try
						{
							$leafObjects = Get-ADObject -SearchBase $adComputer -Filter "objectClass -ne 'computer'" -Server $DomainName;
							foreach ($leaf in $leafObjects)
							{
								try
								{
									Write-Log -Source $MyInvocation.MyCommand -Message "Removing the AD child object [$($leaf.Name)]";
									$leaf | Set-ADObject -ProtectedFromAccidentalDeletion $false;
									$leaf | Remove-ADObject -Confirm:$false;
								}
								catch
								{
									Write-Log -Source $MyInvocation.MyCommand -EventId 1003 -EntryType Error -Message ($_ | Resolve-Error);
								}
							}
							Write-Log -Source $MyInvocation.MyCommand -Message "Removing the AD object [$($adComputer.Name)]";
							$adComputer | Set-ADObject -ProtectedFromAccidentalDeletion $false;
							$adComputer | Remove-ADObject -Confirm:$false;
						}
						catch
						{
							Write-Log -Source $MyInvocation.MyCommand -EventId 1003 -EntryType Error -Message ($_ | Resolve-Error);
						}
					}
				}
			}
		}
		#endregion
	}
	
	end
	{
		if ($PSBoundParameters.ContainsKey('DomainName'))
		{
			Write-Log -Source $MyInvocation.MyCommand -Message 'Clearing local DNS client cache';
			Clear-DnsClientCache;
			## ADB There needs to be a step in here to also clear the client's DNS server. I can't do it though
			## because I don't have permission
			Write-Log -Source $MyInvocation.MyCommand -Message "Clearing the environment DNS server cache on server [$($DomainName)]";
			Clear-DnsServerCache -ComputerName $DomainName -Force;
			Write-Log -Source $MyInvocation.MyCommand -Message ('{0}: Exiting' -f $MyInvocation.MyCommand);
		}
	}
}
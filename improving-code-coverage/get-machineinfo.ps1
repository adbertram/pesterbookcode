function Get-MachineInfo {
	<# 
		.SYNOPSIS 
			Retrieves specific information about one or more computers, using WMI or CIM.
		
		.DESCRIPTION
			This command uses either WMI or CIM to retrieve specific information about 
			one or more computers. You must run this command as a user who has permission
			to query CIM or WMI remotely on the machines involved. You can specify a
			starting protocol (CIM by default), and specify that, in the event of a
			failure, the other protocol be used on a per-machine basis.

		.PARAMETER ComputerName
			One or more computer names. When using WMI, this can also be IP addresses.
			IP addresses may not work for CIM.

		.PARAMETER LogFailuresToPath
			A path and filename to which to write failed computer names. If omitted,
			no log will be written.

		.PARAMETER Protocol
			Valid values: Wsman (uses CIM) or Dcom (uses WMI). Will be used for all 
			machines. "Wsman" is the default.

		.PARAMETER ProtocolFallback
			Specify this to try the other protocol automatically if a machine fails.

		.EXAMPLE
			Get-MachineInfo -ComputerName ONE,TWO,THREE

			This example will query three machines.

		.EXAMPLE
			Get-ADComputer -filter * | Select -Expand Name | Get-MachineInfo

			This example will attempt to query all machines in AD.
	#> 
	[CmdletBinding()]
	param(
		[Parameter(ValueFromPipeline=$True, Mandatory=$True)]
		[Alias('CN', 'MachineName', 'Name')]
		[string[]]$ComputerName,
		
		[Parameter()]
		[string]$LogFailuresToPath,
		
		[Parameter()]
		[ValidateSet('Wsman', 'Dcom')]
		[string]$Protocol = "Wsman",
	
		[switch]$ProtocolFallback
	)
	
	BEGIN { }
	
	PROCESS {
		foreach ($computer in $ComputerName) {
			if ($Protocol -eq 'Dcom') {
				$option = New-CimSessionOption -Protocol Dcom
			} else {
				$option = New-CimSessionOption -Protocol Wsman
			}
	
			try {
				Write-Verbose "Connecting to $computer over $Protocol"
				$params = @{'ComputerName' =$computer
					'SessionOption'           =$option
					'ErrorAction'             ='Stop'
				}
	
				$session = New-CimSession @params
	
				Write-Verbose "Querying from $computer"
	
				$os_params = @{
					'ClassName'  ='Win32_OperatingSystem'
					'CimSession' =$session
				}
	
				$os = Get-CimInstance @os_params
	
				$cs_params = @{
					'ClassName'  ='Win32_ComputerSystem'
					'CimSession' =$session
				}
	
				$cs = Get-CimInstance @cs_params
	
				$sysdrive = $os.SystemDrive
				$drive_params = @{
					'ClassName'  ='Win32_LogicalDisk'
					'Filter'     ="DeviceId='$sysdrive'"
					'CimSession' =$session
				}
	
				$drive = Get-CimInstance @drive_params
	
				$proc_params = @{
					'ClassName'  ='Win32_Processor'
					'CimSession' =$session
				}
	
				$proc = Get-CimInstance @proc_params | Select-Object -first 1
	
				Write-Verbose "Closing session to $computer"
	
				$session | Remove-CimSession
	
				Write-Verbose "Outputting for $computer"
				$obj = [pscustomobject]@{
					'ComputerName'      =$computer
					'OSVersion'         =$os.Version
					'SPVersion'         =$os.ServicePackMajorVersion
					'OSBuild'           =$os.BuildNumber
					'Manufacturer'      =$cs.Manufacturer
					'Model'             =$cs.Model
					'Procs'             =$cs.NumberOfProcessors
					'Cores'             =$cs.NumberOfLogicalProcessors
					'RAM'               =($cs.TotalPhysicalMemory / 1GB)
					'Arch'              =$proc.AddressWidth
					'SysDriveFreeSpace' =$drive.FreeSpace
				}
	
				Write-Output $obj
	
			} catch {
		
				# Did I specify protocol fallback?
				# If so, try again. If I specified logging,
				# I won't log a problem here; we'll let
				# the logging occur if this fallback also
				# fails
		
				if ($ProtocolFallback) {
					if ($Protocol -eq 'Dcom') {
						$newprotocol = 'Wsman'
					} else {
						$newprotocol = 'Dcom'
					}
		
					Write-Verbose "Trying again with $newprotocol"
					$params = @{
						'ComputerName'     =$Computer
						'Protocol'         =$newprotocol
						'ProtocolFallback' =$False
					}
		
					if ($PSBoundParameters.ContainsKey('LogFailuresToPath')){
						$params += @{'LogFailuresToPath' =$LogFailuresToPath }
					}
		
					Get-MachineInfo @params
				}
		
				# if I didn't specify fallback, but we did specify logging, then log the error,
				# because I won't try again.
				if (-not $ProtocolFallback -and $PSBoundParameters.ContainsKey('LogFailuresToPath')){
					Write-Verbose "Logging to $LogFailuresToPath"
					$computer | Out-File $LogFailuresToPath -Append
				}
			}
		}	
	}		
}

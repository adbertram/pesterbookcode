$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '.Tests.', '.'
. "$here\$sut"

describe 'Get-MachineInfo' {
	mock 'New-CimSessionOption' {
		New-MockObject -Type 'Microsoft.Management.Infrastructure.Options.WSManSessionOptions'
	}

	mock 'New-CimSession' {
		New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession'
	}

	mock 'Get-CimInstance' {
		@{
			Manufacturer              = 'manhere'
			Model                     = 'modelhere' 
			NumberOfProcessors        = 'numberofprocshere'
			NumberOfLogicalProcessors = 'numlogprocshere'
			TotalPhysicalMemory       = '1000' 
		} 
	} -ParameterFilter { $PSBoundParameters.ClassName -eq 'Win32_ComputerSystem' }

	mock 'Get-CimInstance' {
		@{
			Freespace               = 'freespacehere'
			SystemDrive             = 'C:' 
			Version                 = 'ver' 
			ServicePackMajorVersion = 'spver' 
			BuildNumber             = 'buildnum'
		} 
	} -ParameterFilter { $PSBoundParameters.ClassName -eq 'Win32_OperatingSystem' }

	mock 'Get-CimInstance' {
		@{ 
			Freespace = 'freespacehere'
		} 
	} -ParameterFilter { $PSBoundParameters.ClassName -eq 'Win32_LogicalDisk' }

	mock 'Get-CimInstance' {
		@{ AddressWidth = 'Addrwidth' } 
		@{ AddressWidth = 'Addrwidth2' } 
	} -ParameterFilter { $PSBoundParameters.ClassName -eq 'Win32_Processor' }

	mock 'Remove-CimSession'
	mock 'Out-File'
	mock 'Write-Verbose'

	it 'allows multiple computer names to be passed to it' {
		{ $null = Get-MachineInfo -ComputerName FOO, FOO1, FOO2 } | should not throw
	}

	it 'only allows the strings "Wsman" and "Dcom" to be used for the Protocol parameter' {
		{ Get-MachineInfo -ComputerName FOO -Protocol 1 } | should throw
	}

	it 'should create a DCOM CIM session when the DCOM protocol is specified' {
		$result = Get-MachineInfo -ComputerName FOO -Protocol Dcom
		$assMParams = @{
			CommandName     = 'New-CimSessionOption'
			Times           = 1
			Exactly         = $true
			Scope           = 'It'
			ParameterFilter = { $PSBoundParameters.Protocol -eq 'Dcom' }
		}
		Assert-MockCalled @assMParams
	}

	it 'should create a WSMAN CIM session when the WSMAN protocol is specified' {
		$result = Get-MachineInfo -ComputerName FOO -Protocol Wsman
		$assMParams = @{
			CommandName     = 'New-CimSessionOption'
			Times           = 1
			Exactly         = $true
			Scope           = 'It'
			ParameterFilter = { $PSBoundParameters.Protocol -eq 'Wsman' }

		}
		Assert-MockCalled @assMParams
	}

	it 'should create a CIM session for each computer provided' {
		$computers = 'FOO1', 'FOO2'
		$result = Get-MachineInfo -ComputerName $computers
		foreach ($comp in $computers) {
			$assMParams = @{
				CommandName     = 'New-CimSession'
				Times           = 1
				Exactly         = $true
				Scope           = 'It'
				ParameterFilter = { $PSBoundParameters.ComputerName -eq $comp }
			}
			Assert-MockCalled @assMParams
		}
	}

	it 'should query the Win32_ComputerSystem CIM class on each computer provided' {
		$computers = 'FOO1', 'FOO2'
		$result = Get-MachineInfo -ComputerName $computers
		$assMParams = @{
			CommandName     = 'Get-CimInstance'
			Times           = @($computers).Count
			Exactly         = $true
			Scope           = 'It'
			ParameterFilter = { $PSBoundParameters.ClassName -eq 'Win32_ComputerSystem' }
		}
		Assert-MockCalled @assMParams
	}

	it 'should query the Win32_OperatingSystem CIM class on each computer provided' {
		$computers = 'FOO1', 'FOO2'
		$result = Get-MachineInfo -ComputerName $computers
		$assMParams = @{
			CommandName     = 'Get-CimInstance'
			Times           = @($computers).Count
			Exactly         = $true
			Scope           = 'It'
			ParameterFilter = { $PSBoundParameters.ClassName -eq 'Win32_OperatingSystem' }
		}

		Assert-MockCalled @assMParams
	}

	it 'should query the Win32_LogicalDisk CIM class on each computer provided' {
		$computers = 'FOO1', 'FOO2'
		$result = Get-MachineInfo -ComputerName $computers
		$assMParams = @{
			CommandName     = 'Get-CimInstance'
			Times           = @($computers).Count
			Exactly         = $true
			Scope           = 'It'
			ParameterFilter = { $PSBoundParameters.ClassName -eq 'Win32_LogicalDisk' }
		}

		Assert-MockCalled @assMParams
	}

	it 'should query the Win32_Processor CIM class on each computer provided' {
		$computers = 'FOO1', 'FOO2'
		$result = Get-MachineInfo -ComputerName $computers
		$assMParams = @{
			CommandName     = 'Get-CimInstance'
			Times           = @($computers).Count
			Exactly         = $true
			Scope           = 'It'
			ParameterFilter = { $PSBoundParameters.ClassName -eq 'Win32_Processor' }
		}
		Assert-MockCalled @assMParams
	}

	it 'should only return the first instance of the Win32_Processor CIM class on each computer provided' {
		$computers = 'FOO1', 'FOO2'
		$result = Get-MachineInfo -ComputerName $computers
		$result[0].Arch | should be 'Addrwidth'
		$result[1].Arch | should be 'Addrwidth'
	}

	context 'When the function calls itself' {

		it 'when an exception is thrown when querying a computer, and ProtocolFallBack is used, and WSMAN is used as the Protocol, it should call itself using the DCOM protocol' {
			mock 'New-CimSession' { throw }

			mock 'Get-MachineInfo' { } -ParameterFilter { $Protocol -eq 'DCOM' }

			$result = Get-MachineInfo -ComputerName FOO -Protocol WSMAN -ProtocolFallBack
			$assMParams = @{
				CommandName = 'Get-MachineInfo'
				Times       = 1
				Exactly     = $true
				Scope       = 'It'
			}
			Assert-MockCalled @assMParams
		}

		it 'when an exception is thrown when querying a computer, and ProtocolFallBack is used, and DCOM is used as the Protocol, it should call itself using the WSMAN protocol' {

			mock 'Get-MachineInfo' { } -ParameterFilter { $Protocol -eq 'WSMAN' }

			$result = Get-MachineInfo -ComputerName FOO -Protocol DCOM -ProtocolFallBack
			$assMParams = @{
				CommandName = 'Get-MachineInfo'
				Times       = 1
				Exactly     = $true
				Scope       = 'It'
			}
			Assert-MockCalled @assMParams
		}

		it 'when an exception is thrown when querying a computer, and ProtocolFallBack and LogFailuresToPath are used, it should call itself using the LogFailuresToPath parameter' {

			mock 'Get-MachineInfo' { } -ParameterFilter { $LogFailuresToPath -eq 'C:\Path' }

			$result = Get-MachineInfo -ComputerName FOO -ProtocolFallBack -LogFailuresToPath 'C:\Path'

			$assMParams = @{
				CommandName = 'Get-MachineInfo'
				Times       = 1
				Exactly     = $true
				Scope       = 'It'
			}
			Assert-MockCalled @assMParams
		}
	}

	context 'When the function throws an exception' {

		mock 'New-CimSession' { throw }

		it 'when an exception is thrown when querying a computer, and ProtocolFallBack is not used, and LogFailuresToPath is used, it writes the computer name to a file' {
			$result = Get-MachineInfo -ComputerName FOO -LogFailuresToPath 'C:\Path'
			$assMParams = @{
				CommandName     = 'Out-File'
				Times           = 1
				Exactly         = $true
				Scope           = 'It'
				ParameterFilter = {
					$PSBoundParameters.FilePath -eq 'C:\Path' -and
					$PSBoundParameters.InputObject -eq 'FOO'
				}
			}
			Assert-MockCalled @assMParams
		}
	}

	it 'should return a single pscustomobject for each computer provided' {
		$computers = 'FOO1', 'FOO2'
		$result = Get-MachineInfo -ComputerName $computers
		@($result).Count | should be @($computers).Count
	}

	it 'should return a pscustomobject with expected property names for each computer provided' {
		$computers = 'FOO1', 'FOO2'
		$result = Get-MachineInfo -ComputerName $computers
		foreach ($obj in $result) {
			$obj.OSVersion | should be 'ver'
			$obj.SPVersion | should be 'spver'
			$obj.OSBuild | should be 'buildnum'
			$obj.Manufacturer | should be 'manhere'
			$obj.Model | should be 'modelhere'
			$obj.Procs | should be 'numberofprocshere'
			$obj.Cores | should be 'numlogprocshere'
			$obj.RAM | should be '9.31322574615479E-07'
			$obj.Arch | should be 'Addrwidth'
			$obj.SysDriveFreeSpace | should be 'freespacehere'
		}
	}
}

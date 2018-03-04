<#
.SYNOPSIS
Tests of the private logging functions in the Prog module.

.DESCRIPTION
Pester tests of the private functions in the Prog module that are called by the public 
logging functions.
#>

# PowerShell allows multiple modules of the same name to be imported from different locations.  
# This would confuse Pester.  So, to be sure there are not multiple Prog modules imported, 
# remove all Prog modules and re-import only one.
Get-Module Prog | Remove-Module -Force
# Use $PSScriptRoot so this script will always import the Prog module in the Modules folder 
# adjacent to the folder containing this script, regardless of the location that Pester is 
# invoked from:
#                                     {parent folder}
#                                             |
#                   -----------------------------------------------------
#                   |                                                   |
#     {folder containing this script}                                Modules folder
#                   \                                                   |
#                    ------------------> imports                     Prog module folder
#                                                \                      |
#                                                 -----------------> Prog.psd1 module script
Import-Module (Join-Path $PSScriptRoot ..\Modules\Prog\Prog.psd1 -Resolve) -Force

InModuleScope Prog {

    Describe 'GetCallingFunctionName' {     

        Context 'Get-PSCallStack mocked to return $Null' {
            Mock Get-PSCallStack { return $Null }

            It 'returns "[UNKNOWN CALLER]"' {
                Private_GetCallerName | Should -Be "[UNKNOWN CALLER]"          
            } 
        }    

        Context 'Get-PSCallStack mocked to return empty collection' {
            Mock Get-PSCallStack { return @() }

            It 'returns "[UNKNOWN CALLER]"' {
                Private_GetCallerName | Should -Be "[UNKNOWN CALLER]"          
            } 
        }  

        Context 'Get-PSCallStack mocked to return single stack frame' {

            Mock Get-PSCallStack { 
                $callStack = @()
                $stackFrame = New-Object PSObject -Property @{ ScriptName='C:\Test\Prog.psd1'; FunctionName='Private_GetCallerName' }
                $callStack += $stackFrame
                return $callStack
            }

            It 'returns "----"' {
                Private_GetCallerName | Should -Be "----"
            } 
        }  

        Context 'Get-PSCallStack mocked so second stack frame has no file name' {

            Mock Get-PSCallStack { 
                $callStack = @()
                $stackFrame = New-Object PSObject -Property @{ ScriptName='C:\Test\Prog.psd1'; FunctionName='Private_GetCallerName' }
                $callStack += $stackFrame
                $stackFrame = New-Object PSObject -Property @{ ScriptName=$Null; FunctionName=$Null }
                $callStack += $stackFrame
                return $callStack
            }

            It 'returns "[CONSOLE]"' {
                Private_GetCallerName | Should -Be "[CONSOLE]"          
            } 
        }   

        Context 'Get-PSCallStack mocked so second stack frame has no script name' {

            Mock Get-PSCallStack { 
                $callStack = @()
                $stackFrame = New-Object PSObject -Property @{ ScriptName='C:\Test\Prog.psd1'; FunctionName='Private_GetCallerName' }
                $callStack += $stackFrame
                $stackFrame = New-Object PSObject -Property @{ ScriptName=$Null; FunctionName='<ScriptBlock>' }
                $callStack += $stackFrame
                return $callStack
            }

            It 'returns "[CONSOLE]"' {
                Private_GetCallerName | Should -Be "[CONSOLE]"          
            } 
        }  

        Context 'Get-PSCallStack mocked so second stack frame function name is <ScriptBlock>' {

            Mock Get-PSCallStack { 
                $callStack = @()
                $stackFrame = New-Object PSObject -Property @{ ScriptName='C:\Test\Prog.psd1'; FunctionName='Private_GetCallerName' }
                $callStack += $stackFrame
                $stackFrame = New-Object PSObject -Property @{ ScriptName='C:\Test\Test.ps1'; FunctionName='<ScriptBlock>' }
                $callStack += $stackFrame
                return $callStack
            }

            It 'returns "Script <script name>"' {
                Private_GetCallerName | Should -Be "Script Test.ps1"
            } 
        } 

        Context 'Get-PSCallStack mocked so second stack frame has both script name and function name' {

            Mock Get-PSCallStack { 
                $callStack = @()
                $stackFrame = New-Object PSObject -Property @{ ScriptName='C:\Test\Prog.psd1'; FunctionName='Private_GetCallerName' }
                $callStack += $stackFrame
                $stackFrame = New-Object PSObject -Property @{ ScriptName='C:\Test\Test.ps1'; FunctionName='TestFunction' }
                $callStack += $stackFrame
                return $callStack
            }

            It 'returns "<function name>"' {
                Private_GetCallerName | Should -Be "TestFunction"
            } 
        }
    }
}

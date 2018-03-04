<#
.SYNOPSIS
Tests of the exported Prog functions in the Prog module.

.DESCRIPTION
Pester tests of the logging functions exported from the Prog module.
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

<#
.SYNOPSIS
Test function with no arguments that throws an exception.
#>
function NoArgsException
{
    throw [ArgumentException] "This is the message"
}

InModuleScope Prog {

    # Need to dot source the helper file within the InModuleScope block to be able to use its 
    # functions within a test.
    . (Join-Path $PSScriptRoot .\AssertExceptionThrown.ps1 -Resolve)

    # Gets the MessageFormatInfo hashtable that matches the default configuration.
    function GetDefaultMessageFormatInfo ()
    {
        $messageFormatInfo = @{
                                RawFormat = '{Timestamp:yyyy-MM-dd hh:mm:ss.fff} | {CallerName} | {MessageType} | {Message}'
                                WorkingFormat = '$($Timestamp.ToString(''yyyy-MM-dd hh:mm:ss.fff'')) | ${CallerName} | ${MessageType} | ${Message}'
                                FieldsPresent = @('Message', 'Timestamp', 'CallerName', 'MessageType')
                            }
        return $messageFormatInfo
    }

    function GetCallingDirectoryPath ()
    {
        $callStack = Get-PSCallStack
        $stackFrame = $callStack[0]
        # Skip this function in the call stack as we've already read it.
	    $i = 1
	    while ($stackFrame.ScriptName -ne $Null -and $i -lt $callStack.Count)
	    {
		    $stackFrame = $callStack[$i]
            if ($stackFrame.ScriptName -ne $Null)
		    {
                $stackFrameFileName = $stackFrame.ScriptName
            }
		    $i++
	    }
        $pathOfCallerDirectory = Split-Path -Path $stackFrameFileName -Parent
        return $pathOfCallerDirectory
    }

    function GetResetLogFilePath ()
    {
        $dateString = Get-Date -Format "_yyyyMMdd"
        $path = "$TestDrive\Results${dateString}.log"
        return $path
    }

    # Sets the Prog configuration to its defaults, apart from LogFileName and LogFilePath.
    function ResetConfiguration ()
    {
        $script:_logConfiguration = Private_DeepCopyHashTable $script:_defaultLogConfiguration
        $script:_logConfiguration.LogFileName = "$TestDrive\Results.log"
        $script:_messageFormatInfo = GetDefaultMessageFormatInfo
        $script:_logFilePath = GetResetLogFilePath
        $script:_logFileOverwritten = $False
    }

    function MockHostAndStreamWriters ()
    {
        Mock Write-Host
        Mock Write-Error
        Mock Write-Warning
        Mock Write-Information
        Mock Write-Debug
        Mock Write-Verbose
    }

    function AssertCorrectWriteCommandCalled (
        [switch]$WriteToHost, 
        [switch]$WriteToStreams,
        [string]$messageType
        )
    {
        $timesWriteHostCalled = 0
        $timesWriteErrorCalled = 0
        $timesWriteWarningCalled = 0
        $timesWriteInformationCalled = 0
        $timesWriteDebugCalled = 0
        $timesWriteVerboseCalled = 0

        if ($WriteToHost.IsPresent)
        {
            $timesWriteHostCalled = 1
        }
        elseif ($WriteToStreams.IsPresent -or 
                (-not $WriteToHost.IsPresent -and -not $WriteToStreams.IsPresent))
        {
            switch ($messageType)
            {
                ERROR				{ $timesWriteErrorCalled = 1; break }
                WARNING   			{ $timesWriteWarningCalled = 1; break }
                INFORMATION			{ $timesWriteInformationCalled = 1; break }
                DEBUG				{ $timesWriteDebugCalled = 1; break }
                VERBOSE				{ $timesWriteVerboseCalled = 1; break } 
                SUCCESS				{ $timesWriteInformationCalled = 1; break }
                FAILURE				{ $timesWriteInformationCalled = 1; break }
                PARTIAL_FAILURE		{ $timesWriteInformationCalled = 1; break } 
                default				{ $timesWriteInformationCalled = 1 }                                                             
            } 
        }
        
        Assert-MockCalled -CommandName Write-Host -Scope It -Times $timesWriteHostCalled
        Assert-MockCalled -CommandName Write-Error -Scope It -Times $timesWriteErrorCalled
        Assert-MockCalled -CommandName Write-Warning -Scope It -Times $timesWriteWarningCalled
        Assert-MockCalled -CommandName Write-Information -Scope It -Times $timesWriteInformationCalled
        Assert-MockCalled -CommandName Write-Debug -Scope It -Times $timesWriteDebugCalled
        Assert-MockCalled -CommandName Write-Verbose -Scope It -Times $timesWriteVerboseCalled             
    }

    function AssertWriteHostCalled ([string]$WithTextColor)
    {
        Assert-MockCalled -CommandName Write-Host `
            -ParameterFilter { $ForegroundColor -eq $WithTextColor } -Scope It -Times 1
    }

    function MockFileWriter ()
    {
        Mock Set-Content
        Mock Add-Content
    }

    function AssertFileWriterCalled 
    (
        [string]$LogFilePath,
        [bool]$OverwriteLogFile, 
        [bool]$LogFileOverwritten
    )
    {
        $commandName = 'Set-Content'

        if (-not $OverwriteLogFile -or $LogFileOverwritten)
        {
            $commandName = 'Add-Content'
        }
        
        Assert-MockCalled -CommandName $commandName -Scope It -Times 1 `
            -ParameterFilter { $Path -eq $LogFilePath }
    }

    function AssertFileWriterNotCalled ()
    {
        Assert-MockCalled -CommandName Add-Content -Scope It -Times 0 
        Assert-MockCalled -CommandName Set-Content -Scope It -Times 0
    }

    function RemoveLogFile ([string]$Path)
    {
        if (Test-Path $Path)
        {
            Remove-Item $Path
        }
    }

    function NewLogFile ([string]$Path)
    {
        'Original content line 1', 'Original content line 2' | Set-Content -Path $Path

        if (-not (Test-Path $Path))
        {
            throw [Exception] "Test log file '$Path' was not created during test set up."
        }

        $originalContent = (Get-Content -Path $Path)
        if ($originalContent.Count -lt 2)
        {
            throw [Exception] `
                "Contents of test log file '$Path' were not created during test set up."
        }

        return $originalContent
    }

    function TestLogLevelWithMessageTypeSwitch
    (
        [string]$LogLevel, 
        [string]$MessageType, 
        [switch]$ShouldWrite
    )
    {
        $writeText = 'does not write'
        $numberTimesShouldWrite = 0
        if ($ShouldWrite.IsPresent)
        {
            $writeText = 'writes'
            $numberTimesShouldWrite = 1
        }

        $isError = $False
        $isWarning = $False
        $isInformation = $False
        $isDebug = $False
        $isVerbose = $False
        $isSuccess = $False
        $isFailure = $False
        $isPartialFailure = $False

        $switchName = ''

        switch ($MessageType)
        {
            ERROR { 
                $isError = $True 
                $switchName = '-IsError'
                break 
            }
            WARNING	{ 
                $isWarning = $True 
                $switchName = '-IsWarning'
                break 
            }
            INFORMATION	{ 
                $isInformation = $True 
                $switchName = '-IsInformation'
                break 
            }
            DEBUG { 
                $isDebug = $True 
                $switchName = '-IsDebug'
                break 
            }
            VERBOSE { 
                $isVerbose = $True 
                $switchName = '-IsVerbose'
                break 
            }
            SUCCESS { 
                $isSuccess = $True 
                $switchName = '-IsSuccessResult'
                break 
            }
            FAILURE	{ 
                $isFailure = $True 
                $switchName = '-IsFailureResult'
                break 
            }
            PARTIAL_FAILURE { 
                $isPartialFailure = $True 
                $switchName = '-IsPartialFailureResult'
                break 
            }
        }

        It "$writeText message when configuration LogLevel is $LogLevel and $switchName switch is set" {

                Write-LogMessage -Message 'hello world' -WriteToHost `
                    -IsError:$isError -IsWarning:$isWarning -IsInformation:$isInformation `
                    -IsDebug:$isDebug -IsVerbose:$isVerbose -IsSuccessResult:$isSuccess `
                    -IsFailureResult:$isFailure -IsPartialFailureResult:$isPartialFailure

                Assert-MockCalled -CommandName Write-Host -Scope It -Times $numberTimesShouldWrite
            }
    }

    function TestLogLevelWithMessageTypeText
    (
        [string]$LogLevel, 
        [string]$MessageType, 
        [switch]$ShouldWrite
    )
    {
        $writeText = 'does not write'
        $numberTimesShouldWrite = 0
        if ($ShouldWrite.IsPresent)
        {
            $writeText = 'writes'
            $numberTimesShouldWrite = 1
        }

        It "$writeText message when configuration LogLevel is $LogLevel and message type is $MessageType" {

                Write-LogMessage -Message 'hello world' -WriteToHost -MessageType $MessageType

                Assert-MockCalled -CommandName Write-Host -Scope It -Times $numberTimesShouldWrite
            }
    }

    function TestMessageFormat
    (
        [scriptblock]$FunctionUnderTest, 
        [string]$ExpectedLoggedText,
        [switch]$DoRegexMatch
    )
    {
        Invoke-Command $FunctionUnderTest

        Assert-MockCalled -CommandName Write-Host -Scope It -Times 1 `
            -ParameterFilter {
                # It's messy throwing exceptions inside a parameter filter but we get 
                # more informative error messages which include expected and actual text, 
                # rather than unhelpful
                #   "Expected Write-Host in module Prog to be called at least 1 times but was called 0 times"
                if ($DoRegexMatch.IsPresent)
                {
                    $Object | Should -Match $ExpectedLoggedText
                    # Should never reach here if $Object doesn't match the regex expression. 
                    # Should throw an exception instead.
                    $True
                }
                else
                {
                    $Object | Should -Be $ExpectedLoggedText
                    # Should never reach here if $Object doesn't equal the expected text. 
                    # Should throw an exception instead.
                    $True
                }
            }
    }

    Describe 'Write-LogMessage' {             

        BeforeEach {
            ResetConfiguration
        }

        Context 'No message supplied' {

            It 'throws no error when no Message supplied' {
                # Only want the message field logged, so Prog isn't logging any text at all.
                Private_SetMessageFormat '{Message}'

                { Write-LogMessage } | Should -Not -Throw
            }

            It 'writes to log when no Message supplied' {
                # Only want the message field logged, so Prog isn't logging any text at all.
                Private_SetMessageFormat '{Message}'
                Mock Write-Host

                Write-LogMessage

                Assert-MockCalled -CommandName Write-Host -Scope It -Times 1
            }
        }
            
        Context 'Parameter validation' {
            # Any mocks declared in a Context block, even if they are declared inside an It block, 
            # remain until the end of the Context block, affecting subsequent It blocks within 
            # the same Context.
            Mock Write-Host

            It 'does not throw exception when -Message is $Null' {
                
                { Write-LogMessage -Message $Null } | 
                    Assert-ExceptionThrown -Not
            }

            It 'writes to log when -Message is $Null' {
                # Only want the message field logged, so Prog isn't logging any text at all.
                Private_SetMessageFormat '{Message}'

                Write-LogMessage -Message $Null

                Assert-MockCalled -CommandName Write-Host -Scope It -Times 1
            }

            It 'does not throw exception when -Message is empty string' {
                
                { Write-LogMessage -Message '' } | 
                    Assert-ExceptionThrown -Not
            }

            It 'writes to log when -Message is empty string' {
                # Only want the message field logged, so Prog isn't logging any text at all.
                Private_SetMessageFormat '{Message}'

                Write-LogMessage -Message ''

                Assert-MockCalled -CommandName Write-Host -Scope It -Times 1
            }

            It 'does not throw exception when Message passed by position' {
                { Write-LogMessage 'hello world' } | 
                    Assert-ExceptionThrown -Not                                     
            }

            It 'writes to log when Message passed by position' {
                # Only want the message field logged, so Prog isn't logging any text at all.
                Private_SetMessageFormat '{Message}'

                Write-LogMessage 'hello world'

                Assert-MockCalled -CommandName Write-Host -Scope It -Times 1
            }

            It 'throws exception when an invalid -HostTextColor is specified' {
                { Write-LogMessage -Message 'hello world' -HostTextColor DeepPurple } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingValidationException `
                        -WithMessage "'DeepPurple' is not a valid text color"                                       
            }

            It 'does not throw exception when no -HostTextColor is specified' {
                
                { Write-LogMessage -Message 'hello world' } | 
                    Assert-ExceptionThrown -Not
            }

            It 'does not throw exception when valid -HostTextColor is specified' {
                
                { Write-LogMessage -Message 'hello world' -HostTextColor Cyan } | 
                    Assert-ExceptionThrown -Not
            }

            It 'does not throw exception when neither -MessageType nor a message type switch are specified' {
                { Write-LogMessage 'hello world' } | 
                    Assert-ExceptionThrown -Not
            }

            It 'throws exception when an invalid -MessageType is specified' {
                { Write-LogMessage 'hello world' -MessageType INVALID } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingValidationException `
                        -WithMessage "Cannot validate argument on parameter 'MessageType'"                                       
            }

            It 'does not throw exception when valid -MessageType is specified' {
                { Write-LogMessage 'hello world' -MessageType ERROR } | 
                    Assert-ExceptionThrown -Not
            }

            It 'throws exception when both -MessageType and -IsError are specified' {
                { Write-LogMessage 'hello world' -MessageType ERROR -IsError } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingException `
                        -WithMessage 'Parameter set cannot be resolved'
            }

            It 'throws exception when both -MessageType and -IsWarning are specified' {
                { Write-LogMessage 'hello world' -MessageType ERROR -IsWarning } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingException `
                        -WithMessage 'Parameter set cannot be resolved'
            }

            It 'throws exception when both -MessageType and -IsInformation are specified' {
                { Write-LogMessage 'hello world' -MessageType ERROR -IsInformation } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingException `
                        -WithMessage 'Parameter set cannot be resolved'
            }

            It 'throws exception when both -MessageType and -IsDebug are specified' {
                { Write-LogMessage 'hello world' -MessageType ERROR -IsDebug } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingException `
                        -WithMessage 'Parameter set cannot be resolved'
            }

            It 'throws exception when both -MessageType and -IsVerbose are specified' {
                { Write-LogMessage 'hello world' -MessageType ERROR -IsVerbose } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingException `
                        -WithMessage 'Parameter set cannot be resolved'
            }

            It 'throws exception when both -MessageType and -IsSuccessResult are specified' {
                { Write-LogMessage 'hello world' -MessageType ERROR -IsSuccessResult } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingException `
                        -WithMessage 'Parameter set cannot be resolved'
            }

            It 'throws exception when both -MessageType and -IsFailureResult are specified' {
                { Write-LogMessage 'hello world' -MessageType ERROR -IsFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingException `
                        -WithMessage 'Parameter set cannot be resolved'
            }

            It 'throws exception when both -MessageType and -IsPartialFailureResult are specified' {
                { Write-LogMessage 'hello world' -MessageType ERROR -IsPartialFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ParameterBindingException `
                        -WithMessage 'Parameter set cannot be resolved'
            }

            It 'throws exception when both -IsError and -IsWarning switches set' {
                { Write-LogMessage -Message 'hello world' -IsError -IsWarning } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsError and -IsInformation switches set' {
                { Write-LogMessage -Message 'hello world' -IsError -IsInformation } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsError and -IsDebug switches set' {
                { Write-LogMessage -Message 'hello world' -IsError -IsDebug } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsError and -IsVerbose switches set' {
                { Write-LogMessage -Message 'hello world' -IsError -IsVerbose } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsError and -IsSuccessResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsError -IsSuccessResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsError and -IsFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsError -IsFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsError and -IsPartialFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsError -IsPartialFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsWarning and -IsInformation switches set' {
                { Write-LogMessage -Message 'hello world' -IsWarning -IsInformation } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsWarning and -IsDebug switches set' {
                { Write-LogMessage -Message 'hello world' -IsWarning -IsDebug } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsWarning and -IsVerbose switches set' {
                { Write-LogMessage -Message 'hello world' -IsWarning -IsVerbose } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsWarning and -IsSuccessResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsWarning -IsSuccessResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsWarning and -IsFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsWarning -IsFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsWarning and -IsPartialFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsWarning -IsPartialFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsInformation and -IsDebug switches set' {
                { Write-LogMessage -Message 'hello world' -IsInformation -IsDebug } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsInformation and -IsVerbose switches set' {
                { Write-LogMessage -Message 'hello world' -IsInformation -IsVerbose } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsInformation and -IsSuccessResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsInformation -IsSuccessResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsInformation and -IsFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsInformation -IsFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsInformation and -IsPartialFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsInformation -IsPartialFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsDebug and -IsVerbose switches set' {
                { Write-LogMessage -Message 'hello world' -IsDebug -IsVerbose } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsDebug and -IsSuccessResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsDebug -IsSuccessResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsDebug and -IsFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsDebug -IsFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsDebug and -IsPartialFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsDebug -IsPartialFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsVerbose and -IsSuccessResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsVerbose -IsSuccessResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsVerbose and -IsFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsVerbose -IsFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsVerbose and -IsPartialFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsVerbose -IsPartialFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsSuccessResult and -IsFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsSuccessResult -IsFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsSuccessResult and -IsPartialFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsSuccessResult -IsPartialFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -IsFailureResult and -IsPartialFailureResult switches set' {
                { Write-LogMessage -Message 'hello world' -IsFailureResult -IsPartialFailureResult } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Message Type switch parameter may be set'                                        
            }

            It 'throws exception when both -WriteToHost and -WriteToStreams switches set' {
                { Write-LogMessage -Message 'hello world' -WriteToHost -WriteToStreams } | 
                    Assert-ExceptionThrown -WithTypeName ArgumentException `
                        -WithMessage 'Only one Destination switch parameter may be set'                                        
            }
        }

        Context 'Logging to host and PowerShell streams' {
            MockHostAndStreamWriters

            It 'writes to host when -WriteToHost switch set' {
                
                Write-LogMessage -Message 'hello world' -WriteToHost

                AssertCorrectWriteCommandCalled -WriteToHost                          
            }

            It 'writes to stream when -WriteToStreams switch set' {
                
                Write-LogMessage -Message 'hello world' -WriteToStreams

                AssertCorrectWriteCommandCalled -WriteToStreams -MessageType 'INFORMATION'                          
            }

            It 'writes to host when neither -WriteToHost nor -WriteToStreams switches set and configuration.WriteToHost set' {
                $script:_logConfiguration.WriteToHost = $True
                
                Write-LogMessage -Message 'hello world'

                AssertCorrectWriteCommandCalled -WriteToHost
            }

            It 'writes to stream when neither -WriteToHost nor -WriteToStreams switches set and configuration.WriteToHost cleared' {
                $script:_logConfiguration.WriteToHost = $False
                
                Write-LogMessage -Message 'hello world'

                AssertCorrectWriteCommandCalled -WriteToStreams -MessageType 'INFORMATION'
            }

            It 'writes to host in colour specified via -HostTextColor' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.Information = 'White'
                
                Write-LogMessage -Message 'hello world' -WriteToHost -HostTextColor $textColour

                AssertWriteHostCalled -WithTextColor $textColour
            }

            It 'writes to host in Error text colour when -WriteToHost and -IsError switches set, and -HostTextColor not specified' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.Error = $textColour
                
                Write-LogMessage -Message 'hello world' -WriteToHost -IsError 

                AssertWriteHostCalled -WithTextColor $textColour
            }

            It 'writes to host in Warning text colour when -WriteToHost and -IsWarning switches set, and -HostTextColor not specified' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.Warning = $textColour
                
                Write-LogMessage -Message 'hello world' -WriteToHost -IsWarning 

                AssertWriteHostCalled -WithTextColor $textColour
            }

            It 'writes to host in Debug text colour when -WriteToHost and -IsDebug switches set, and -HostTextColor not specified' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.Debug = $textColour
                
                Write-LogMessage -Message 'hello world' -WriteToHost -IsDebug 

                AssertWriteHostCalled -WithTextColor $textColour
            }

            It 'writes to host in Information text colour when -WriteToHost and -IsInformation switches set, and -HostTextColor not specified' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.Information = $textColour
                
                Write-LogMessage -Message 'hello world' -WriteToHost -IsInformation 

                AssertWriteHostCalled -WithTextColor $textColour
            }

            It 'writes to host in Verbose text colour when -WriteToHost and -IsVerbose switches set, and -HostTextColor not specified' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.Verbose = $textColour
                $script:_logConfiguration.LogLevel = 'Verbose'
                
                Write-LogMessage -Message 'hello world' -WriteToHost -IsVerbose 

                AssertWriteHostCalled -WithTextColor $textColour
            }

            It 'writes to host in Success text colour when -WriteToHost and -IsSuccessResult switches set, and -HostTextColor not specified' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.Success = $textColour
                
                Write-LogMessage -Message 'hello world' -WriteToHost -IsSuccessResult 

                AssertWriteHostCalled -WithTextColor $textColour
            }

            It 'writes to host in Failure text colour when -WriteToHost and -IsFailureResult switches set, and -HostTextColor not specified' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.Failure = $textColour
                
                Write-LogMessage -Message 'hello world' -WriteToHost -IsFailureResult 

                AssertWriteHostCalled -WithTextColor $textColour
            }

            It 'writes to host in PartialFailure text colour when -WriteToHost and -IsPartialFailureResult switches set, and -HostTextColor not specified' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.PartialFailure = $textColour
                
                Write-LogMessage -Message 'hello world' -WriteToHost -IsPartialFailureResult 

                AssertWriteHostCalled -WithTextColor $textColour
            }

            It '-HostTextColor overrides the colour determined by a Message Type switch' {
                $textColour = 'DarkRed'
                $script:_logConfiguration.HostTextColor.Error = 'DarkMagenta'
                
                Write-LogMessage -Message 'hello world' -WriteToHost -IsError -HostTextColor $textColour

                AssertWriteHostCalled -WithTextColor $textColour
            }
        }

        Context 'Logging to file with mocked file writer' {
            Mock Write-Host
            MockFileWriter

            It 'does not attempt to write to a log file when configuration LogFileName blank' {
                $script:_logConfiguration.LogFileName = ''
                Private_SetLogFilePath

                Write-LogMessage -Message 'hello world' -WriteToHost

                AssertFileWriterNotCalled
            }

            It 'does not attempt to write to a log file when configuration LogFileName empty string' {
                $script:_logConfiguration.LogFileName = ' '
                Private_SetLogFilePath

                Write-LogMessage -Message 'hello world' -WriteToHost

                AssertFileWriterNotCalled
            }

            It 'does not attempt to write to a log file when configuration LogFileName $Null' {
                $script:_logConfiguration.LogFileName = $Null
                Private_SetLogFilePath

                Write-LogMessage -Message 'hello world' -WriteToHost

                AssertFileWriterNotCalled
            }

            It 'does not attempt to write to a log file when configuration LogFileName not a valid path' {
                $logFileName = 'CC:\Test\Test.log'
                # This scenario should never occur.  Prog should throw an exception when setting 
                # LogFileName to an invalid path via Set-LogConfiguration.
                $script:_logConfiguration.LogFileName = $logFileName
                $script:_logFilePath = $logFileName
                
                Write-LogMessage -Message 'hello world' -WriteToHost

                AssertFileWriterNotCalled
            }

            It 'does not add date to log file name when IncludeDateInFileName cleared' {
                $script:_logConfiguration.IncludeDateInFileName = $False
                Private_SetLogFilePath
                $logFileAlreadyOverwritten = $script:_logFileOverwritten
                
                Write-LogMessage -Message 'hello world' -WriteToHost
                
                $logFileName = $script:_logConfiguration.LogFileName
                AssertFileWriterCalled -LogFilePath $logFileName `
                    -OverwriteLogFile $script:_logConfiguration.OverwriteLogFile `
                    -LogFileOverwritten $logFileAlreadyOverwritten
            }

            It 'adds date to log file name when IncludeDateInFileName set' {
                $script:_logConfiguration.IncludeDateInFileName = $True
                Private_SetLogFilePath
                $logFileAlreadyOverwritten = $script:_logFileOverwritten
                
                Write-LogMessage -Message 'hello world' -WriteToHost
                
                $logFileName = GetResetLogFilePath
                AssertFileWriterCalled -LogFilePath $logFileName `
                    -OverwriteLogFile $script:_logConfiguration.OverwriteLogFile `
                    -LogFileOverwritten $logFileAlreadyOverwritten
            }
        }

        Context 'Logging to file with actual file writer' {
            
            BeforeEach {
                RemoveLogFile -Path $script:_logFilePath
            }

            Mock Write-Host

            It 'creates a log file when configuration LogFileName set and OverwriteLogFile cleared, and log file does not exist' {
                $script:_logConfiguration.OverwriteLogFile = $False
                
                Write-LogMessage -Message 'hello world' -WriteToHost

                $script:_logFilePath | Should -Exist
            }

            It 'creates a log file when configuration LogFileName and OverwriteLogFile set, and log file does not exist' {
                $script:_logConfiguration.OverwriteLogFile = $True                
                
                Write-LogMessage -Message 'hello world' -WriteToHost

                $script:_logFilePath | Should -Exist
            }

            It 'appends to existing log file when configuration OverwriteLogFile cleared' {
                $script:_logConfiguration.OverwriteLogFile = $False

                $originalContent = NewLogFile -Path $script:_logFilePath                
                
                Write-LogMessage -Message 'hello world' -WriteToHost

                $script:_logFilePath | Should -Exist
                $newContent = (Get-Content -Path $script:_logFilePath)
                $newContent.Count | Should -Be 3
                $newContent[2] | Should -BeLike '*hello world*'               
                
                Write-LogMessage -Message 'second message' -WriteToHost

                $newContent = (Get-Content -Path $script:_logFilePath)
                $newContent.Count | Should -Be 4
                $newContent[3] | Should -BeLike '*second message*'
            }

            It 'overwrites an existing log file with first logged message when configuration OverwriteLogFile set' {
                $script:_logConfiguration.OverwriteLogFile = $True

                $originalContent = NewLogFile -Path $script:_logFilePath                
                
                Write-LogMessage -Message 'hello world' -WriteToHost

                $script:_logFilePath | Should -Exist
                $newContent = ,(Get-Content -Path $script:_logFilePath)
                $newContent.Count | Should -Be 1
                $newContent[0] | Should -BeLike '*hello world*'
            }

            It 'appends subsequent messages to log file when configuration OverwriteLogFile set' {
                $script:_logConfiguration.OverwriteLogFile = $True

                $originalContent = NewLogFile -Path $script:_logFilePath                
                
                Write-LogMessage -Message 'hello world' -WriteToHost

                $script:_logFilePath | Should -Exist
                $newContent = ,(Get-Content -Path $script:_logFilePath)
                $newContent.Count | Should -Be 1
                $newContent[0] | Should -BeLike '*hello world*'               
                
                Write-LogMessage -Message 'second message' -WriteToHost

                $newContent = (Get-Content -Path $script:_logFilePath)
                $newContent.Count | Should -Be 2
                $newContent[1] | Should -BeLike '*second message*'               
                
                Write-LogMessage -Message 'third message' -WriteToHost

                $newContent = (Get-Content -Path $script:_logFilePath)
                $newContent.Count | Should -Be 3
                $newContent[2] | Should -BeLike '*third message*'
            }
        }        

        Context 'Log level Off' {
            BeforeEach {
                $script:_logConfiguration.LogLevel = 'Off'
            }

            Mock Write-Host
            $logLevel = 'Off'

            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType ERROR
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType WARNING
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType INFORMATION
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType DEBUG
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType SUCCESS
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType FAILURE
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType PARTIAL_FAILURE
            
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType ERROR
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType WARNING
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType INFORMATION
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType DEBUG
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType SUCCESS
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType FAILURE
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType PARTIAL_FAILURE
        }

        Context 'Log level Error' {
            BeforeEach {
                $script:_logConfiguration.LogLevel = 'Error'
            }

            Mock Write-Host
            $logLevel = 'Error'
            
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType WARNING
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType INFORMATION
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType DEBUG
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType SUCCESS
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType FAILURE
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType PARTIAL_FAILURE

            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType WARNING
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType INFORMATION
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType DEBUG
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType SUCCESS
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType FAILURE
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType PARTIAL_FAILURE
        }

        Context 'Log level Warning' {
            BeforeEach {
                $script:_logConfiguration.LogLevel = 'Warning'
            }

            Mock Write-Host
            $logLevel = 'Warning'
            
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType WARNING -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType INFORMATION
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType DEBUG
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType SUCCESS
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType FAILURE
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType PARTIAL_FAILURE

            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType WARNING -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType INFORMATION
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType DEBUG
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType SUCCESS
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType FAILURE
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType PARTIAL_FAILURE
        }

        Context 'Log level Information' {
            BeforeEach {
                $script:_logConfiguration.LogLevel = 'Information'
            }

            Mock Write-Host
            $logLevel = 'Information'
            
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType WARNING -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType INFORMATION -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType DEBUG
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType SUCCESS -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType FAILURE -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType PARTIAL_FAILURE -ShouldWrite

            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType WARNING -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType INFORMATION -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType DEBUG
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType SUCCESS -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType FAILURE -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType PARTIAL_FAILURE -ShouldWrite
        }

        Context 'Log level Debug' {
            BeforeEach {
                $script:_logConfiguration.LogLevel = 'Debug'
            }

            Mock Write-Host
            $logLevel = 'Debug'
            
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType WARNING -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType INFORMATION -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType DEBUG -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType SUCCESS -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType FAILURE -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType PARTIAL_FAILURE -ShouldWrite

            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType WARNING -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType INFORMATION -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType DEBUG -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType VERBOSE
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType SUCCESS -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType FAILURE -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType PARTIAL_FAILURE -ShouldWrite
        }

        Context 'Log level Verbose' {
            BeforeEach {
                $script:_logConfiguration.LogLevel = 'Verbose'
            }

            Mock Write-Host
            $logLevel = 'Verbose'
            
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType WARNING -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType INFORMATION -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType DEBUG -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType VERBOSE -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType SUCCESS -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType FAILURE -ShouldWrite
            TestLogLevelWithMessageTypeSwitch -LogLevel $logLevel -MessageType PARTIAL_FAILURE -ShouldWrite
            
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType ERROR -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType WARNING -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType INFORMATION -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType DEBUG -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType VERBOSE -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType SUCCESS -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType FAILURE -ShouldWrite
            TestLogLevelWithMessageTypeText -LogLevel $logLevel -MessageType PARTIAL_FAILURE -ShouldWrite
        }

        Context 'Message Format' {
            
            Mock Write-Host
            
            It 'writes only message text when -MessageFormat contains only {Message} field' {
                TestMessageFormat `
                    -ExpectedLoggedText 'hello world' `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{message}' `
                                            -WriteToHost 
                        }
            }
            
            It 'writes only timestamp with default formatting when -MessageFormat contains only {Timestamp} field' {
                TestMessageFormat `
                    -ExpectedLoggedText '^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d\d$' -DoRegexMatch `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{Timestamp}' `
                                            -WriteToHost 
                        }
            }
            
            It 'formats timestamp with specified format string when -MessageFormat contains formatted {Timestamp} field' {
                TestMessageFormat `
                    -ExpectedLoggedText '^\d\d:\d\d:\d\d$' -DoRegexMatch `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{Timestamp:hh:mm:ss}' `
                                            -WriteToHost 
                        }
            }
            
            It 'writes only calling object name when -MessageFormat contains only {CallerName} field' {
                TestMessageFormat `
                    -ExpectedLoggedText 'Script ExportedLoggingFunctions.Tests.ps1' `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{CallerName}' `
                                            -WriteToHost 
                        }
            }
            
            It 'writes only log level when -MessageFormat contains only {LogLevel} field' {
                TestMessageFormat `
                    -ExpectedLoggedText 'INFORMATION' `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{LogLevel}' `
                                            -WriteToHost 
                        }
            }
            
            It 'writes only SUCCESS when -MessageFormat contains only {Result} field and -IsSuccessResult set' {
                TestMessageFormat `
                    -ExpectedLoggedText 'SUCCESS' `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{Result}' `
                                            -WriteToHost `
                                            -IsSuccessResult
                        }
            }
            
            It 'writes only FAILURE when -MessageFormat contains only {Result} field and -IsFailureResult set' {
                TestMessageFormat `
                    -ExpectedLoggedText 'FAILURE' `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{Result}' `
                                            -WriteToHost `
                                            -IsFailureResult
                        }
            }
            
            It 'writes only PARTIAL FAILURE when -MessageFormat contains only {Result} field and -IsPartialFailureResult set' {
                TestMessageFormat `
                    -ExpectedLoggedText 'PARTIAL_FAILURE' `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{Result}' `
                                            -WriteToHost `
                                            -IsPartialFailureResult
                        }
            }
            
            It 'writes only message type when -MessageFormat contains only {MessageType} field' {
                TestMessageFormat `
                    -ExpectedLoggedText 'INFORMATION' `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{MessageType}' `
                                            -WriteToHost
                        }
            }            
            
            It 'writes text to match all fields when -MessageFormat contains multiple fields' {
                TestMessageFormat `
                    -ExpectedLoggedText '^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d\d | INFORMATION | hello world$' `
                    -DoRegexMatch `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -MessageFormat '{Timestamp} | {LogLevel} | {Message}' `
                                            -WriteToHost 
                        }
            }           
            
            It 'uses configuration MessageFormat when -MessageFormat parameter not specified' {
                Private_SetMessageFormat '{Timestamp:hh:mm:ss.fff} | {Message}'
                TestMessageFormat `
                    -ExpectedLoggedText '^\d\d:\d\d:\d\d\.\d\d\d | hello world$' `
                    -DoRegexMatch `
                    -FunctionUnderTest `
                        { 
                            Write-LogMessage -Message 'hello world' `
                                            -WriteToHost 
                        }
            }
        }
    }
}

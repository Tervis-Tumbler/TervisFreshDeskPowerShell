function Set-TervisFreshDeskAPIKey {
    $APIKey = Get-PasswordstatePassword -ID 5470 | Select-Object -ExpandProperty Password
    Set-FreshDeskAPIKey -APIKey $APIKey
}

function Set-TervisFreshDeskEnvironment {
    Set-TervisFreshDeskAPIKey
    Set-FreshDeskDomain -Domain Tervis
}

function New-WarrantyRequest {
    param (
        [Parameter(ValueFromPipelineByPropertyName)]$FirstName,
        [Parameter(ValueFromPipelineByPropertyName)]$LastName,
        [Parameter(ValueFromPipelineByPropertyName)]$BusinessName,
        [Parameter(ValueFromPipelineByPropertyName)]$Address1,
        [Parameter(ValueFromPipelineByPropertyName)]$Address2,
        [Parameter(ValueFromPipelineByPropertyName)]$City,
        [Parameter(ValueFromPipelineByPropertyName)]$State,
        [Parameter(ValueFromPipelineByPropertyName)][String]$PostalCode,
        [Parameter(ValueFromPipelineByPropertyName)][ValidateSet("Residence","Business")]$ResidentialOrBusinessAddress,
        [Parameter(ValueFromPipelineByPropertyName)]$PhoneNumber,
        [Parameter(ValueFromPipelineByPropertyName)]$Email,
        [Parameter(ValueFromPipelineByPropertyName)]$WarrantyLines
    )
    $PSBoundParameters | ConvertFrom-PSBoundParameters
}

function ConvertFrom-FreshDeskTicketToWarrantyRequest {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$Ticket
    )
    process {
        $WarrantyRequestParameters = @{
            FirstName = $Ticket.custom_fields.cf_first_name
            LastName = $Ticket.custom_fields.cf_last_name
            BusinessName = $Ticket.custom_fields.cf_business_name
            Address1 = $Ticket.custom_fields.cf_address1
            Address2 = $Ticket.custom_fields.cf_address2
            City = $Ticket.custom_fields.cf_city
            State = $Ticket.custom_fields.cf_state
            PostalCode = $Ticket.custom_fields.cf_postalcode
            ResidentialOrBusinessAddress = $Ticket.custom_fields.cf_residenceorbusiness
            PhoneNumber = $Ticket.custom_fields.cf_phonenumber
            Email = $Ticket.custom_fields.cf_email
        } | Remove-HashtableKeysWithEmptyOrNullValues
        New-WarrantyRequest @WarrantyRequestParameters
    }
}

function New-WarrantyRequestLine {
    param (
        [Parameter(ValueFromPipelineByPropertyName)]$DesignName,
        [ValidateSet(
            "10oz (5 1/2)",
            "12oz (4 1/4)",
            "wavy (5 1/2)",
            "wine glass (8 1/2)",
            "My First Tervis Sippy Cup (5 1/5)",
            "16oz (6)",
            "mug (5)",
            "stemless wine glass (4 4/5)",
            "24oz (7 7/8)",
            "water bottle (10.4)",
            "8oz (4)",
            "goblet (7 7/8)",
            "collectible (2 3/4)",
            "tall (6 1/4)",
            "stout (3 1/2)",
            "20oz Stainless Steel (6 3/4)",
            "30oz Stainless Steel (8)",
            "12oz stainless (4.85)",
            "stainless water bottle (10.75)"
        )]
        [Parameter(ValueFromPipelineByPropertyName)]$Size,

        [ValidateSet(1,2,3,4,5,6,7,8,9,10)][Parameter(ValueFromPipelineByPropertyName)][String]$Quantity,
        [ValidateSet(
            "Before 2004",2004,2005,2006,2007,2008,2009,2010,2011,2012,2013,2014,2015,2016,2017,2018,"NA","Non Tervis"
        )][Parameter(ValueFromPipelineByPropertyName)][String]$ManufactureYear,

        [ValidateSet(
            "cracked",
            "cracked not at weld",
            "cracked stress cracks",
            "decoration fail",
            "film",
            "heat distortion",
            "stainless defect",
            "seal failure",
            "sunscreen"
        )]
        [Parameter(ValueFromPipelineByPropertyName)]$ReturnReason
    )
    $PSBoundParameters | ConvertFrom-PSBoundParameters
}

function ConvertFrom-FreshDeskTicketToWarrantyRequestLine {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$Ticket
    )
    process {
        $ReturnReason = $ReturnReasonToIssueTypeMapping.keys |
        Where-Object {
            $ReturnReasonToIssueTypeMapping.$_.cf_issue_description -eq $Ticket.custom_fields.cf_issue_description
        } |
        Where-Object {
            $ReturnReasonToIssueTypeMapping.$_.cf_issue_subcode -eq $Ticket.custom_fields.cf_issue_subcode
        }
        
        $WarrantyRequestLineParameters = @{
            DesignName = $Ticket.custom_fields.cf_design_name
            Size = $Ticket.custom_fields.cf_size
            Quantity = $Ticket.custom_fields.cf_quantity
            ManufactureYear = $Ticket.custom_fields.cf_mfd_year
            ReturnReason = $ReturnReason
        } | Remove-HashtableKeysWithEmptyOrNullValues
        New-WarrantyRequestLine @WarrantyRequestLineParameters
    }
}

function New-WarrantyParentTicket {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$WarrantyRequest
    )
    process {
        $RequestorIDParameter = if (-not $WarrantyRequest.Email -and -not $WarrantyRequest.PhoneNumber) {
            $FreshDeskContact = New-FreshDeskContact -name "$FirstName $LastName" -phone "555-555-5555"
            @{requester_id = $FreshDeskContact.ID}
        } else {
            @{}
        }

        $WarrantyParentFreshDeskTicketParameter = $WarrantyRequest |
        New-WarrantyParentFreshDeskTicketParameter
        
        $WarrantyParentTicket = New-FreshDeskTicket @WarrantyParentFreshDeskTicketParameter @RequestorIDParameter
        $WarrantyParentTicket
        if ($WarrantyRequest.WarrantyLines) {
            $WarrantyRequest.WarrantyLines | 
            New-WarrantyChildTicket -WarrantyParentTicket $WarrantyParentTicket
        }
    }
}

function New-WarrantyChildTicket {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$WarrantyLine,
        [Parameter(Mandatory,ParameterSetName="WarrantyParentTicketID")]$WarrantyParentTicketID,
        [Parameter(Mandatory,ParameterSetName="WarrantyParentTicket")]$WarrantyParentTicket
    )
    process {
        if (-not $WarrantyParentTicket) {
            $WarrantyParentTicket = Get-FreshDeskTicket -ID $WarrantyParentTicketID
        } 

        $WarrantyRequest = $WarrantyParentTicket | 
        ConvertFrom-FreshDeskTicketToWarrantyRequest

        $ParametersFromWarantyParent = $WarrantyRequest | 
        Select-Object -Property Email, FirstName, LastName | 
        ConvertTo-HashTable |
        Remove-HashtableKeysWithEmptyOrNullValues

        $WarrantyChildFreshDeskTicketParameter = $WarrantyLine |
        New-WarrantyChildFreshDeskTicketParameter @ParametersFromWarantyParent -ParentID $WarrantyParentTicketID

        New-FreshDeskTicket @WarrantyChildFreshDeskTicketParameter -requester_id $WarrantyParentTicket.requester_id
    }
}

function New-WarrantyParentFreshDeskTicketParameter {
    param (
        [Parameter(ValueFromPipelineByPropertyName)]$FirstName,
        [Parameter(ValueFromPipelineByPropertyName)]$LastName,
        [Parameter(ValueFromPipelineByPropertyName)]$BusinessName,
        [Parameter(ValueFromPipelineByPropertyName)]$Address1,
        [Parameter(ValueFromPipelineByPropertyName)]$Address2,
        [Parameter(ValueFromPipelineByPropertyName)]$City,
        [Parameter(ValueFromPipelineByPropertyName)]$State,
        [Parameter(ValueFromPipelineByPropertyName)]$PostalCode,
        [Parameter(ValueFromPipelineByPropertyName)][ValidateSet("Residence","Business")]$ResidentialOrBusinessAddress,
        [Parameter(ValueFromPipelineByPropertyName)]$PhoneNumber,
        [Parameter(ValueFromPipelineByPropertyName)]$Email,
        [Parameter(ValueFromPipelineByPropertyName)]$WarrantyLines
    )
    process {
        @{
            priority = 1
            email = $Email
            phone = $PhoneNumber
            name = "$FirstName $LastName"
		    source = 2
		    status = 2
		    type = "Warranty Parent"
		    subject = "MFL for " + $FirstName + " " + $LastName + " " + (get-date).tostring("G")
		    description = "Warranty Request"
		    custom_fields = @{
		    	cf_first_name = $FirstName
                cf_last_name = $LastName
                cf_business_name = $BusinessName
		        cf_address1 = $Address1
		        cf_address2 = $Address2
                cf_city = $City
		        cf_state = $State
		        cf_postalcode = $PostalCode
		        cf_residenceorbusiness = $ResidentialOrBusinessAddress
                cf_phonenumber = $PhoneNumber
                cf_email = $Email
                cf_source = "Warranty Return Form Internal"
		    } | Remove-HashtableKeysWithEmptyOrNullValues
        } | Remove-HashtableKeysWithEmptyOrNullValues
    }
}

$ReturnReasonToIssueTypeMapping = @{
    "cracked" = @{ #"02.110.01"
        cf_issue_type = "02-Product"
        cf_issue_description = ".110 Cracked"
        cf_issue_subcode = ".01-Cracked at Weld"
    }
    "cracked not at weld" = @{ #"02.110.03"
        cf_issue_type = "02-Product"
        cf_issue_description = ".110 Cracked"
        cf_issue_subcode = ".03-No at weld"
    }
    "cracked stress cracks" = @{ #"02.110.02"
        cf_issue_type = "02-Product"
        cf_issue_description = ".110 Cracked"
        cf_issue_subcode = ".02-Stress Cracks"
    }
    "decoration fail" = @{ #"02.600.01"
        cf_issue_type = "02-Product"
        cf_issue_description = ".600 Decoration"
        cf_issue_subcode = ".01-Damaged"
    }
    "film" = @{ #"02.200.02"
        cf_issue_type = "02-Product"
        cf_issue_description = ".200 Surface"
        cf_issue_subcode = ".02-Film/Stains"
    }
    "heat distortion" = @{ #"02.900.00"
        cf_issue_type = "02-Product"
        cf_issue_description = ".900 Deformed"
        cf_issue_subcode = ".01-Deformed"
    }
    "stainless defect" = @{ #"02.090.95"
        cf_issue_type = "02-Product"
        cf_issue_description = ".090 Supplier"
        cf_issue_subcode = ".95-Poor Thermal Performance"
    }
    "seal failure" = @{ #"02.100.01"
        cf_issue_type = "02-Product"
        cf_issue_description = ".100 - Weld/Seal"
        cf_issue_subcode = ".01-Tumbler in two pieces"
    }
    "sunscreen" = @{ #"02.200.03"
        cf_issue_type = "02-Product"
        cf_issue_description = ".200 Surface"
        cf_issue_subcode = ".03-Sunscreen"
    }
}

function New-WarrantyChildFreshDeskTicketParameter {
    param (
        [Parameter(ValueFromPipelineByPropertyName)]$DesignName,
        [Parameter(ValueFromPipelineByPropertyName)]$Size,
        [Parameter(ValueFromPipelineByPropertyName)]$Quantity,
        [Parameter(ValueFromPipelineByPropertyName)]$ManufactureYear,
        [Parameter(ValueFromPipelineByPropertyName)]$ReturnReason,
        $Email,
        $FirstName,
        $LastName,
        [Int]$ParentID
    )
    process {
        $IssueTypeFields = $ReturnReasonToIssueTypeMapping.$ReturnReason
        @{
            priority = 1
            email = $Email
            source = 2
            status = 5
            type = "Warranty Child"
            subject = "$DesignName $Size for $FirstName $LastName"
            description = "Warranty Child Request for Parent Ticket : $ParentID"
            parent_id = $ParentID
            custom_fields = (
                @{
                    cf_size = $Size
                    cf_quantity = $Quantity
                    cf_design_name = $DesignName
                    cf_mfd_year = $ManufactureYear
                    cf_source = "Warranty Return Form Internal"
                } + $IssueTypeFields
            ) | Remove-HashtableKeysWithEmptyOrNullValues
        } | Remove-HashtableKeysWithEmptyOrNullValues
    }
}

function Invoke-NewUDInputWarrantyParentInput {
    param (
        $Parameters
    )
    $WarrantyRequest = New-WarrantyRequest @Parameters
    $WarrantyParentTicket = $WarrantyRequest | New-WarrantyParentTicket
    $Session:WarrantyParentTicketID = $WarrantyParentTicket.ID
    $Session:WarrantyChildTicketID = New-Object System.Collections.ArrayList

    New-UDInputAction -RedirectUrl "/WarrantyChild"	
}

function Invoke-NewUDInputWarrantyChildInput {
    param (
        $Parameters
    )
    $WarrantyRequestLine = New-WarrantyRequestLine @Parameters

    $WarrantyChildTicket = $WarrantyRequestLine | 
    New-WarrantyChildTicket -WarrantyParentTicketID $Session:WarrantyParentTicketID

    if ($WarrantyChildTicket) {
        $Session:WarrantyChildTicketID.Add($WarrantyChildTicket.ID)

        Add-UDElement -ParentId "RedirectParent" -Content {
            New-UDHtml -Markup @"
            <meta http-equiv="refresh" content="0; URL='/WarrantyChild'" />
"@
        }
    #New-UDInputAction -ClearInput -Toast "Warranty Line Created" #Given we are redirecting the whole page below I don't know that we need this
    }    
}

function New-UDTableWarrantyParent {
    New-UDTable -Title "Warranty Parent" -Id "WarrantyParentTable" -Headers ID, FirstName, LastName, BusinessName, Address1, Address2, City, State, PostalCode, ResidentialOrBusinessAddress, PhoneNumber, Email, Action -Endpoint {
        $WarrantyRequest = Get-FreshDeskTicket -ID $Session:WarrantyParentTicketID |
        Where-Object {-Not $_.Deleted} |
        ConvertFrom-FreshDeskTicketToWarrantyRequest |
        Add-Member -MemberType NoteProperty -PassThru -Name ID -Value $Session:WarrantyParentTicketID |
        Add-Member -MemberType NoteProperty -PassThru -Name Remove -Value (
            New-UDElement -Tag "a" -Attributes @{
                className = "btn"
                onClick = {
                    Remove-FreshDeskTicket -ID $Session:WarrantyParentTicketID
                    $Session:WarrantyChildTicketID | ForEach-Object { Remove-FreshDeskTicket -ID $_ }
                    Remove-Item -Path Session:WarrantyParentTicketID
                    Remove-Item -Path Session:WarrantyChildTicketID
                    Add-UDElement -ParentId "RedirectParent" -Content {
                        New-UDHtml -Markup @"
                            <meta http-equiv="refresh" content="0; URL='/'" />
"@
                    }
                }
            } -Content {
                "Remove" 
            }
        )

        $WarrantyRequest | 
        Out-UDTableData -Property ID, FirstName, LastName, BusinessName, Address1, Address2, City, State, PostalCode, ResidentialOrBusinessAddress, PhoneNumber, Email, Remove
    }
}

function New-UDTableWarrantyChild {
    New-UDTable -Title "Warranty Child" -Id "WarrantyChildTable" -Headers ID, DesignName, Size, Quantity, ManufactureYear, ReturnReason, Action -Endpoint {
        $Session:WarrantyChildTicketID | 
        ForEach-Object {
            Get-FreshDeskTicket -ID $_ |
            Where-Object {-Not $_.Deleted} |
            ConvertFrom-FreshDeskTicketToWarrantyRequestLine |
            Add-Member -MemberType NoteProperty -Name ID -Value $_ -PassThru |                        
            Select-Object -Property *, @{
                Name = "Remove"
                Expression = {
                    New-UDElement -Tag "a" -Attributes @{
                        className = "btn"
                        onClick = {
                            Remove-FreshDeskTicket -ID $_.ID
                            $Session:WarrantyChildTicketID.Remove($_.ID)

                            Add-UDElement -ParentId "RedirectParent" -Content {
                                New-UDHtml -Markup @"
                                    <meta http-equiv="refresh" content="0; URL='/WarrantyChild'" />
"@  
                            }
                        }
                    } -Content {
                        "Remove"
                    }
                }
            }
        } |
        Out-UDTableData -Property ID, DesignName, Size, Quantity, ManufactureYear, ReturnReason, Remove
    } #-AutoRefresh -RefreshInterval 2  
}

function New-TervisWarrantyFormDashboard {
    $Port = 10001
	Get-UDDashboard | Where port -eq $Port | Stop-UDDashboard

	$NewWarrantyParentPage = New-UDPage -Name "NewWarrantyParentPage" -Icon home -Content {
        #New-UDRow {
            #New-UDColumn -Size 6 {
                New-UDInput -Title "New Warranty Parent" -Endpoint {
                    param (
                        $FirstName,
                        $LastName,
                        $BusinessName,
                        $Address1,
                        $Address2,
                        $City,
                        [ValidateSet(
                            "AL","AK","AZ","AR","CA","CO","CT","DC","DE","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY","GU","PR","VI","AE","AA","AP"
                        )]
                        $State,
                        [String]$PostalCode,
                        [ValidateSet("Residence","Business")]$ResidentialOrBusinessAddress,
                        $PhoneNumber,
                        $Email
                    )
                    Invoke-NewUDInputWarrantyParentInput -Parameters $PSBoundParameters
                }
            #}
        #}
	}


    
	$NewWarrantyChildPage = New-UDPage -Url "/WarrantyChild" -Icon link -Endpoint {
        New-UDElement -Tag div -Id RedirectParent
        New-UDRow {
            New-UDColumn -Size 12 {
                New-UDTableWarrantyParent              
            }
        
            New-UDLayout -Columns 2 -Content {
                New-UDInput -Title "New Warranty Child" -Id "NewWarrantyChildInput" -Endpoint {
                    param (
                        $DesignName,
                        [ValidateSet(
                            "10oz (5 1/2)",
                            "12oz (4 1/4)",
                            "wavy (5 1/2)",
                            "wine glass (8 1/2)",
                            "My First Tervis Sippy Cup (5 1/5)",
                            "16oz (6)",
                            "mug (5)",
                            "stemless wine glass (4 4/5)",
                            "24oz (7 7/8)",
                            "water bottle (10.4)",
                            "8oz (4)",
                            "goblet (7 7/8)",
                            "collectible (2 3/4)",
                            "tall (6 1/4)",
                            "stout (3 1/2)",
                            "20oz stainless Steel (6 3/4)",
                            "30oz stainless Steel (8)",
                            "12oz stainless (4.85)",
                            "stainless water bottle (10.75)"
                        )]
                        [String]$Size,
                
                        [ValidateSet("1","2","3","4","5","6","7","8","9","10")][String]$Quantity,
                        [ValidateSet(
                            "Before 2004","2004","2005","2006","2007","2008","2009","2010","2011","2012","2013","2014","2015","2016","2017","2018","NA","Non Tervis"
                        )][String]$ManufactureYear,
                
                        [ValidateSet(
                            "cracked",
                            "cracked not at weld",
                            "cracked stress cracks",
                            "decoration fail",
                            "film",
                            "heat distortion",
                            "stainless defect",
                            "seal failure",
                            "sunscreen"
                        )]
                        [String]$ReturnReason
                    )
                    Invoke-NewUDInputWarrantyChildInput -Parameters $PSBoundParameters
                }

                New-UDTableWarrantyChild
                
                New-UDElement -Tag "a" -Attributes @{
                    className = "btn"
                    onClick = {
                        Add-UDElement -ParentId "RedirectParent" -Content {
                            New-UDHtml -Markup @"
                                <meta http-equiv="refresh" content="0; URL='/'" />
"@
                        }
                    }
                } -Content {
                    "Done" 
                }
            }
        }
    }   
	
	$Dashboard = New-UDDashboard -Pages @($NewWarrantyParentPage, $NewWarrantyChildPage) -Title "Warranty Request Form" -EndpointInitializationScript {
        #Get-ChildItem -Path C:\ProgramData\PowerShellApplication\TervisFreshDeskPowerShell -File -Recurse -Filter *.psm1 -Depth 2 |
        #ForEach-Object {
        #    Import-Module -Name $_.FullName -Force
        #}
        
        Set-TervisFreshDeskEnvironment
	}

	Start-UDDashboard -Dashboard $Dashboard -Port $Port -AllowHttpForLogin
}

function Install-TervisFreshDeskWarrantyForm {
	param (
		$ComputerName
	)
	Install-PowerShellApplicationUniversalDashboard -ComputerName $ComputerName -ModuleName TervisFreshDeskPowerShell -TervisModuleDependencies PasswordstatePowerShell,
		TervisMicrosoft.PowerShell.Utility,
        FreshDeskPowerShell,
        WebServicesPowerShellProxyBuilder -PowerShellGalleryDependencies UniversalDashboard -CommandString "New-TervisWarrantyFormDashboard"

	$PowerShellApplicationInstallDirectory = Get-PowerShellApplicationInstallDirectory -ComputerName $ComputerName -ModuleName TervisFreshDeskPowerShell
	Invoke-Command -ComputerName $ComputerName -ScriptBlock {
		New-NetFirewallRule -Name TervisWarrantyFormDashboard -DisplayName TervisWarrantyFormDashboard -Profile Any -Direction Inbound -Action Allow -LocalPort 10001 -Protocol TCP
		#. $Using:PowerShellApplicationInstallDirectory\Import-ApplicationModules.ps1
		#Set-PSRepository -Trusted -Name PowerShellGallery
		#Install-Module -Name UniversalDashboard -Scopoe CurrentUser
		#$PSModulePathCurrentUser = Get-UserPSModulePath
		#Copy-Item -Path $PSModulePathCurrentUser -Destination $Using:PowerShellApplicationInstallDirectory\. -Recurse
		#Publish-UDDashboard -DashboardFile $Using:PowerShellApplicationInstallDirectory\Script.ps1
	}
}
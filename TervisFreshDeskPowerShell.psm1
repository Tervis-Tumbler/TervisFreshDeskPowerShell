function Set-TervisFreshDeskAPIKey {
    $APIKey = Get-PasswordstatePassword -ID 5452 | Select-Object -ExpandProperty Password
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
            "30oz Stainless Steel (8)"
        )]
        [Parameter(ValueFromPipelineByPropertyName)]$Size,

        [ValidateSet(1,2,3,4,5,6,7,8,9,10)][Parameter(ValueFromPipelineByPropertyName)][String]$Quantity,
        [ValidateSet(
            "Before 2004",2004,2005,2006,2007,2008,2009,2010,2011,2012,2013,2014,2015,2016,2017,2018,"NA"
        )][Parameter(ValueFromPipelineByPropertyName)][String]$ManufactureYear,

        [ValidateSet("cracked","decoration fail","film","heat distortion","stainless defect","seal failure")][Parameter(ValueFromPipelineByPropertyName)]$ReturnReason
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
        $WarrantyParentFreshDeskTicketParameter = $WarrantyRequest | 
        New-WarrantyParentFreshDeskTicketParameter |
        ConvertTo-HashTable

        $WarrantyParentTicket = New-FreshDeskTicket @WarrantyParentFreshDeskTicketParameter
        $WarrantyParentTicket
        if ($WarrantyRequest.WarrantyLines) {
            $WarrantyRequest.WarrantyLines | 
            New-WarrantyChildTicket -WarrantyRequest $WarrantyRequest -WarrantyParentTicket $WarrantyParentTicket
        }
    }
}

function New-WarrantyChildTicket {
    param (
        [Parameter(Mandatory)]$WarrantyRequest,
        [Parameter(Mandatory,ValueFromPipeline)]$WarrantyLine,
        [Parameter(Mandatory)]$WarrantyParentTicket
    )
    process {
        $ParametersFromWarantyParent = $WarrantyRequest | 
        Select-Object -Property Email, FirstName, LastName | 
        ConvertTo-HashTable

        $WarrantyChildFreshDeskTicketParameter = $WarrantyLine |
        New-WarrantyChildFreshDeskTicketParameter @ParametersFromWarantyParent -ParentID $WarrantyParentTicket.id |
        ConvertTo-HashTable

        New-FreshDeskTicket @WarrantyChildFreshDeskTicketParameter
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
        [PSCustomObject][Ordered]@{
            priority = 1
		    email = $Email
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
		    } | Remove-HashtableKeysWithEmptyOrNullValues
        }
    }
}

$ReturnReasonToIssueTypeMapping = @{
    "cracked" = @{ #"02.110.01"
        cf_issue_type = "02-Product"
        cf_issue_description = ".110 Cracked"
        cf_issue_subcode = ".01-Cracked at Weld"
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
        [PSCustomObject][Ordered]@{
            priority = 1
            email = $Email
            source = 2
            status = 2
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
                } + $IssueTypeFields
            ) | Remove-HashtableKeysWithEmptyOrNullValues
        }
    }
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
                        $State,
                        [String]$PostalCode,
                        [ValidateSet("Residence","Business")]$ResidentialOrBusinessAddress,
                        $PhoneNumber,
                        $Email
                    )
                    $WarrantyRequest = New-WarrantyRequest @PSBoundParameters
                    $WarrantyParentTicket = $WarrantyRequest | New-WarrantyParentTicket
                    $GUID = New-Guid | Select-Object -ExpandProperty GUID
                    Set-Item -Path Cache:$GUID -Value (
                        [PSCustomObject][Ordered]@{
                            WarrantyParentParameters = $PSBoundParameters |
                            ConvertFrom-PSBoundParameters -AsHashTable |
                            Remove-HashtableKeysWithEmptyOrNullValues

                            WarrantyRequest = $WarrantyRequest |
                            Add-Member -MemberType NoteProperty -Name Ticket -Value $WarrantyParentTicket -PassThru
                            WarrantyRequestLine = New-Object System.Collections.ArrayList
                        }
                    )
                    New-UDInputAction -RedirectUrl "/WarrantyChild/$GUID"			
                }
            #}
        #}
	}

	$NewWarrantyChildPage = New-UDPage -Url "/WarrantyChild/:GUID" -Icon link -Endpoint {
		param(
			$GUID
        )
        $CachedData = Get-Item Cache:$GUID
        New-UDRow {
            New-UDColumn -Size 12 {
                New-UDTable -Title "Warranty Parent" -Id "WarrantyParentTable" -Headers ID, FirstName, LastName, BusinessName, Address1, Address2, City, State, PostalCode, ResidentialOrBusinessAddress, PhoneNumber, Email, Action -Endpoint {
                    $CachedData = Get-Item Cache:$GUID
                    $CachedData.WarrantyRequest |
                    Select-Object -Property @{
                        Name = "ID"
                        Expression = {$CachedData.WarrantyRequest.Ticket.ID}
                    }, *, 
                    @{
                        Name = "Remove"
                        Expression = {
                            New-UDElement -Tag "a" -Attributes @{
                                className = "btn"
                                onClick = {
                                    $CachedData = Get-Item Cache:$GUID
                                    $CachedData.WarrantyRequestLine.Ticket | Remove-FreshDeskTicket
                                    $CachedData.WarrantyRequest.Ticket | Remove-FreshDeskTicket
                                    Remove-Item -Path Cache:$GUID
                                    Add-UDElement -ParentId "RedirectParent" -Content {
                                        New-UDHtml -Markup @"
                                            <meta http-equiv="refresh" content="0; URL='/'" />
"@
                                    }
                                }
                            } -Content {
                                "Remove" 
                            } 
                        }
                    } |
                    Out-UDTableData -Property ID, FirstName, LastName, BusinessName, Address1, Address2, City, State, PostalCode, ResidentialOrBusinessAddress, PhoneNumber, Email, Remove
                }
                New-UDElement -Tag div -Id RedirectParent
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
                            "20oz Stainless Steel (6 3/4)",
                            "30oz Stainless Steel (8)"
                        )]
                        [String]$Size,
                
                        [ValidateSet("1","2","3","4","5","6","7","8","9","10","error")][String]$Quantity,
                        [ValidateSet(
                            "Before 2004","2004","2005","2006","2007","2008","2009","2010","2011","2012","2013","2014","2015","2016","2017","2018","NA"
                        )][String]$ManufactureYear,
                
                        [ValidateSet("cracked","decoration fail","film","heat distortion","stainless defect","seal failure")][String]$ReturnReason
                    )
                    $CachedData = Get-Item Cache:$GUID
                    $WarrantyRequestLine = New-WarrantyRequestLine @PSBoundParameters

                    try {
                        $WarrantyChildTicket = $WarrantyRequestLine | 
                        New-WarrantyChildTicket -WarrantyRequest $CachedData.WarrantyRequest -WarrantyParentTicket $CachedData.WarrantyRequest.Ticket

                        $CachedData.WarrantyRequestLine.Add(
                            $(
                                $WarrantyRequestLine |
                                Add-Member -MemberType NoteProperty -Name Ticket -Value $WarrantyChildTicket -PassThru
                            )
                        )
                        Add-UDElement -ParentId "RedirectParent" -Content {
                            New-UDHtml -Markup @"
                            <meta http-equiv="refresh" content="0; URL='/WarrantyChild/$GUID'" />
"@  
                        #New-UDInputAction -ClearInput -Toast "Warranty Line Created" #Given we are redirecting the whole page below I don't know that we need this
                        }
                    } catch {
                        New-UDInputAction -Toast $_.Exception.Response
                    }
                }

                New-UDTable -Title "Warranty Child" -Id "WarrantyChildTable" -Headers DesignName, Size, Quantity, ManufactureYear, ReturnReason, Action -Endpoint {
                    $CachedData = Get-Item Cache:$GUID
                    $CachedData.WarrantyRequestLine |
                    ForEach-Object {
                        $_ | Select-Object -Property @{
                            Name = "ID"
                            Expression = {$CachedData.WarrantyParentTicket.ID}
                        }, *, 
                        @{
                            Name = "Remove"
                            Expression = {
                                New-UDElement -Tag "a" -Attributes @{
                                    className = "btn"
                                    onClick = {
                                        $CachedData = Get-Item Cache:$GUID
                                        $_.Ticket | Remove-FreshDeskTicket

                                        $CachedData.WarrantyRequestLine.Remove($_)

                                        Add-UDElement -ParentId "RedirectParent" -Content {
                                            New-UDHtml -Markup @"
                                                <meta http-equiv="refresh" content="0; URL='/WarrantyChild/$GUID'" />
"@  
                                        }
                                    }
                                } -Content {
                                    "Remove" 
                                } 
                            }
                        }
                    } |
                    Out-UDTableData -Property DesignName, Size, Quantity, ManufactureYear, ReturnReason, Remove
                } #-AutoRefresh -RefreshInterval 2  
            }
        }
    }   
	
	$Dashboard = New-UDDashboard -Pages @($NewWarrantyParentPage, $NewWarrantyChildPage) -Title "Warranty Request Form" -EndpointInitializationScript {
        Set-TervisFreshDeskEnvironment
	}

	Start-UDDashboard -Dashboard $Dashboard -Port $Port -AllowHttpForLogin
}
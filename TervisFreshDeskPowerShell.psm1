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
        $Email,
        $WarrantyLines
    )
    $PSBoundParameters | ConvertFrom-PSBoundParameters
}

function New-WarrantyRequestLine {
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
        $Size,

        [ValidateSet(1,2,3,4,5,6,7,8,9,10)][String]$Quantity,
        [ValidateSet(
            "Before 2004",2004,2005,2006,2007,2008,2009,2010,2011,2012,2013,2014,2015,2016,2017,2018,"NA"
        )][String]$ManufactureYear,

        [ValidateSet("cracked","decoration fail","film","heat distortion","stainless defect","seal failure")]$ReturnReason
    )
    $PSBoundParameters | ConvertFrom-PSBoundParameters
}

function New-WarrantyParentTicket {
    param (
        [Parameter(ValueFromPipeline)]$WarrantyRequest
    )
    process {
        $WarrantyParentFreshDeskTicketParameter = $WarrantyRequest | 
        New-WarrantyParentFreshDeskTicketParameter |
        ConvertTo-HashTable

        $WarrantyParentTicket = New-FreshDeskTicket @WarrantyParentFreshDeskTicketParameter

        $WarrantyRequest.WarrantyLines | New-WarrantyChildTicket -WarrantyRequest $WarrantyRequest -WarrantyParentTicket $WarrantyParentTicket
        foreach ($WarrantyLine in $WarrantyRequest.WarrantyLines) {
            
        }
    }
}

function New-WarrantyChildTicket {
    param (
        $WarrantyRequest,
        [Parameter(ValueFromPipeline)]$WarrantyLine,
        $WarrantyParentTicket
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
            $WarrantyRequest = $PSBoundParameters | New-WarrantyRequest
            $WarrantyParentTicket = $WarrantyRequest | New-WarrantyParentTicket
			$GUID = New-Guid | Select-Object -ExpandProperty GUID
			Set-Item -Path Cache:$GUID -Value (
                [PSCustomObject][Ordered]@{
                    $WarrantyParentParameters = $PSBoundParameters |
                    ConvertFrom-PSBoundParameters -AsHashTable |
                    Remove-HashtableKeysWithEmptyOrNullValues
                    WarrantyParentTicket = $WarrantyParentTicket
                    WarrantyRequest = $WarrantyRequest
                    WarrantyChildTicket = @()
                    WarrantyRequestLine = @()
                }
			)
			New-UDInputAction -RedirectUrl "/WarrantyChild/$GUID"			
		}
	}

	$NewWarrantyChildPage = New-UDPage -Url "/WarrantyChild/:GUID" -Icon link -Endpoint {
		param(
			$GUID
		)		
        $CachedData = Get-Item Cache:$GUID
        New-UDCard -Title "Warranty Parent" -Text ($CachedData.WarrantyRequest | Out-String)
        if ($CachedData.WarrantyRequestLine) {
            New-UDCard -Title "Warranty Parent" -Text ($CachedData.WarrantyRequestLine | Out-String)
        }

        New-UDInput -Title "New Warranty Child" -Endpoint {
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
                $Size,
        
                [ValidateSet(1,2,3,4,5,6,7,8,9,10)][String]$Quantity,
                [ValidateSet(
                    "Before 2004",2004,2005,2006,2007,2008,2009,2010,2011,2012,2013,2014,2015,2016,2017,2018,"NA"
                )][String]$ManufactureYear,
        
                [ValidateSet("cracked","decoration fail","film","heat distortion","stainless defect","seal failure")]$ReturnReason
            )
            $WarrantyRequestLine = $PSBoundParameters | New-WarrantyRequestLine
            $WarrantyChildTicket = $WarrantyRequestLine | New-WarrantyChildTicket -WarrantyRequest $CachedData.WarrantyRequest -WarrantyParentTicket $CachedData.WarrantyParentTicket
			
            $CachedData.WarrantyChildTicket += $WarrantyChildTicket
            $CachedData.WarrantyRequestLine += $WarrantyRequestLine
            $Cache:GUID = $CachedData

			New-UDInputAction -RedirectUrl "/WarrantyChild/$GUID"
        }

		#$AccountNumber = Find-TervisCustomer @BoundParameters
		#
		#if ($AccountNumber) {
		#	New-UDCard -Title "Account Number(s)" -Text ($AccountNumber | Out-String)
#
		#	New-UDGrid -Title "Customers" -Headers AccountNumber, PARTY_NAME, ADDRESS1, CITY, STATE, POSTAL_CODE -Properties AccountNumber, PARTY_NAME, ADDRESS1, CITY, STATE, POSTAL_CODE -Endpoint {
		#		$AccountNumber | 
		#		% { 
		#			$Account = Get-EBSTradingCommunityArchitectureCustomerAccount -Account_Number $_
		#			$Organization = Get-EBSTradingCommunityArchitectureOrganizationObject -Party_ID $Account.Party_ID
		#			$Organization | 
		#			Select-Object -Property PARTY_NAME, ADDRESS1, CITY, STATE, POSTAL_CODE, @{
		#				Name = "AccountNumber"
		#				Expression = {New-UDLink -Text $Account.ACCOUNT_NUMBER -Url "/AccountDetails/$($Account.ACCOUNT_NUMBER)"}
		#			}
		#		} |
		#		Out-UDGridData
		#	}
		#} else {
		#	New-UDCard -Title "No Account Number(s) found that match your criteria"
		#}
		#New-UDCard -Title "Query" -Content {
		#	New-UDLink -Text Query -Url /CustomerSearchSQLQuery/$GUID
		#}		
	}
	
	$Dashboard = New-UDDashboard -Pages @($NewWarrantyParentPage, $NewWarrantyChildPage) -Title "Warranty Request Form" -EndpointInitializationScript {
        Set-TervisFreshDeskEnvironment
	}

	Start-UDDashboard -Dashboard $Dashboard -Port $Port -AllowHttpForLogin
}
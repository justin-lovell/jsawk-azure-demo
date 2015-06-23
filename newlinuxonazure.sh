#!/bin/sh

# Set variable values based on parameters passed
azureloginuname="$1"
azureloginpass="$2"
azuresubname="$3"
azureregion="$4"
azureprefix="$5"
azurevmuname="$6"
azurevmpass="$7"
azurevmtotal="$8"
azurecloudinit="$9"


##############################
# Sign-in to Azure account with Azure AD credentials
 
azure login --username "$azureloginuname" --password "$azureloginpass"
 
# Confirm that Azure account sign-in was successful
 
if [ "$?" != "0" ]; then
    echo "Error: login to Azure account failed"
    exit 1
fi

################################
# Select Azure subscription
 
azure account set "$azuresubname"
 
# Confirm that subscription is now default
 
#azuresubdefault=$(azure account show --json "$azuresubname" | jsawk 'return this.isDefault')
#if [ "$azuresubdefault" != "true" ]; then
#    echo "Error: Azure subscription ${azuresubdefault} not found as default subscription"
#    exit 1
#fi


#################################
# Define Azure affinity group
 
azureagname="${azureprefix}ag"
azure account affinity-group create --location "$azureregion" --label "$azureagname" "$azureagname"
 
# Confirm that Azure affinity group exists
 
azureagexist=$(azure account affinity-group list --json | jsawk 'return true' -q "[?name=\"$azureagname\"]")
if [ $azureagexist != [true] ]; then 
    echo "Error: Azure affinity group ${azureagname} not found"
    exit 1
fi


##############################
# Create Azure storage account
 
azurestoragename="${azureprefix}stor"
azure storage account create --affinity-group "$azureagname" --label "$azurestoragename" --type GRS "$azurestoragename"
 
# Confirm that Azure storage account exists
 
azurestorageexist=$(azure storage account list --json | jsawk 'return true' -q "[?name=\"$azurestoragename\"]")
if [ $azurestorageexist != [true] ]; then 
    echo "Error: Azure storage account ${azurestoragename} not found"
    exit 1
fi



##############################
# Create Azure virtual network
 
azurevnetname="${azureprefix}net"
azure network vnet create --affinity-group "$azureagname" "$azurevnetname"
 
# Confirm that Azure virtual network exists
 
azurevnetexist=$(azure network vnet list --json | jsawk 'return true' -q "[?name=\"$azurevnetname\"]")
if [ $azurevnetexist != [true] ]; then 
    echo "Error: Azure virtual network ${azurevnetname} not found"
    exit 1
fi


##############################
# Select Linux VM image 
 
azurevmimage=$(azure vm image list --json | jsawk -n 'out(this.name)' -q "[?name=\"*Ubuntu-14_04_2-LTS-amd64-server*\"]" | sort | tail -n 1)
azurevmimage="${azurevmimage#OUT:  }"

# Confirm that valid Linux VM Image is selected
 
if [ "$azurevmimage" = "" ]; then
    echo "Error: Azure VM image not found"
    exit 1
fi


##############################
# Set variables for provisioning Linux VMs
 
azurednsname="${azureprefix}app"
azurevmsize='Small'
azureavailabilityset="${azureprefix}as"
azureendpointport='80'
azureendpointprot='tcp'
azureendpointdsr='false'
azureloadbalanceset="${azureprefix}lb"



##############################
# Provision Linux VMs
 
# Initialize Azure VM counter 
azurevmcount=1
 
# Loop through provisioning each VM
while [ $azurevmcount -le $azurevmtotal ]
do
 
   # Set Linux VM hostname
    azurevmname="${azureprefix}app${azurevmcount}"
 
    # Create Linux VM - if first VM, also create Azure Cloud Service
    if [ $azurevmcount -eq 1 ]; then
        azure vm create --vm-name "$azurevmname" --affinity-group "$azureagname" --virtual-network-name "$azurevnetname" --availability-set "$azureavailabilityset" --ssh 22 --custom-data "$azurecloudinit" --vm-size "$azurevmsize" "$azurednsname" "$azurevmimage" "$azurevmuname" "$azurevmpass"
    else
        azure vm create --vm-name "$azurevmname" --affinity-group "$azureagname" --virtual-network-name "$azurevnetname" --availability-set "$azureavailabilityset" --ssh $((22+($azurevmcount-1))) --custom-data "$azurecloudinit" --vm-size "$azurevmsize" --connect "$azurednsname" "$azurevmimage" "$azurevmuname" "$azurevmpass"
    fi
 
    # Confirm that VM creation was successfully submitted
    if [ "$?" != "0" ]; then
        echo "Error: provisioning VM ${azurevmname} failed"
        exit 1
    fi
 
    # Define load-balancing for incoming web traffic on each VM
    azure vm endpoint create-multiple "$azurevmname" $azureendpointport:$azureendpointport:$azureendpointprot:$azureendpointdsr:$azureloadbalanceset:$azureendpointprot:$azureendpointport
 
    # Confirm that load-balancing config was successfully submitted
    if [ "$?" != "0" ]; then
        echo "Error: provisioning endpoints for VM ${azurevmname} failed"
        exit 1
    fi
 
    # Wait until new VM is in a Running state
    azurevmstatus='None'
    while [ "$azurevmstatus" != "ReadyRole" ]
    do
        sleep 30s
        azurevmstatus=$(azure vm show --json --dns-name "$azurednsname" "$azurevmname" | jsawk 'return this.InstanceStatus')
        azurevmstatus="${azurevmstatus#OUT:  }"
        echo "Provisioning: ${azurevmname} status is ${azurevmstatus}"
    done
 
    # Increment VM counter for next VM
    azurevmcount=$((azurevmcount+1))
 
done

##########################
# End of script
 
echo "Success: Azure provisioning for ${azurednsname} completed"
azure logout "$azureloginuname"

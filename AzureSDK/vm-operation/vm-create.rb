#!/usr/bin/env ruby

require 'azure_mgmt_resources'
require 'azure_mgmt_network'
require 'azure_mgmt_storage'
require 'azure_mgmt_compute'

SOUTH_CENTRAL_US = 'southcentralus'
GROUP_NAME = 'azure-sample-compute-group'

StorageModels = Azure::ARM::Storage::Models
NetworkModels = Azure::ARM::Network::Models
ComputeModels = Azure::ARM::Compute::Models
ResourceModels = Azure::ARM::Resources::Models

# This sample shows how to manage a Azure virtual machines using using the Azure Resource Manager APIs for Ruby.
#
# This script expects that the following environment vars are set:
#
# AZURE_TENANT_ID: with your Azure Active Directory tenant id or domain
# AZURE_CLIENT_ID: with your Azure Active Directory Application Client ID
# AZURE_CLIENT_SECRET: with your Azure Active Directory Application Secret
# AZURE_SUBSCRIPTION_ID: with your Azure Subscription Id
#
def run_example
  #
  # Create the Resource Manager Client with an Application (service principal) token provider
  #
  subscription_id = ENV['AZURE_SUBSCRIPTION_ID'] || '11111111-1111-1111-1111-111111111111' # your Azure Subscription Id
  provider = MsRestAzure::ApplicationTokenProvider.new(
      ENV['AZURE_TENANT_ID'],
      ENV['AZURE_CLIENT_ID'],
      ENV['AZURE_CLIENT_SECRET'])
  credentials = MsRest::TokenCredentials.new(provider)
  resource_client = Azure::ARM::Resources::ResourceManagementClient.new(credentials)
  resource_client.subscription_id = subscription_id
  network_client = Azure::ARM::Network::NetworkManagementClient.new(credentials)
  network_client.subscription_id = subscription_id
  storage_client = Azure::ARM::Storage::StorageManagementClient.new(credentials)
  storage_client.subscription_id = subscription_id
  compute_client = Azure::ARM::Compute::ComputeManagementClient.new(credentials)
  compute_client.subscription_id = subscription_id
  
  postfix = rand(1000)
  storage_account_name = "rubystor#{postfix}"
  puts "Creating a premium storage account with encryption off named #{storage_account_name} in resource group #{GROUP_NAME}"
  storage_create_params = StorageModels::StorageAccountCreateParameters.new.tap do |account|
    account.location = SOUTH_CENTRAL_US
    account.sku = StorageModels::Sku.new.tap do |sku|
      sku.name = StorageModels::SkuName::PremiumLRS
      sku.tier = StorageModels::SkuTier::Premium
    end
    account.kind = StorageModels::Kind::Storage
    account.encryption = StorageModels::Encryption.new.tap do |encrypt|
      encrypt.services = StorageModels::EncryptionServices.new.tap do |services|
        services.blob = StorageModels::EncryptionService.new.tap do |service|
          service.enabled = false
        end
      end
    end
  end
  print_item storage_account = storage_client.storage_accounts.create(GROUP_NAME, storage_account_name, storage_create_params)

  puts 'Creating a virtual network for the VM'
  vnet_create_params = NetworkModels::VirtualNetwork.new.tap do |vnet|
    vnet.location = SOUTH_CENTRAL_US
    vnet.address_space = NetworkModels::AddressSpace.new.tap do |addr_space|
      addr_space.address_prefixes = ['10.0.0.0/16']
    end
    vnet.dhcp_options = NetworkModels::DhcpOptions.new.tap do |dhcp|
      dhcp.dns_servers = ['8.8.8.8']
    end
    vnet.subnets = [
        NetworkModels::Subnet.new.tap do |subnet|
          subnet.name = 'rubySampleSubnet'
          subnet.address_prefix = '10.0.0.0/24'
        end
    ]
  end
  print_item vnet = network_client.virtual_networks.create_or_update(GROUP_NAME, 'vm2-vnet', vnet_create_params)

  puts 'Creating a public IP address for the VM'
  public_ip_params = NetworkModels::PublicIPAddress.new.tap do |ip|
    ip.location = SOUTH_CENTRAL_US
    ip.public_ipallocation_method = NetworkModels::IPAllocationMethod::Dynamic
    # ip.dns_settings = NetworkModels::PublicIPAddressDnsSettings.new.tap do |dns|
    #   dns.domain_name_label = 'sample-ruby-domain-name-label'
    # end
  end
  print_item public_ip = network_client.public_ipaddresses.create_or_update(GROUP_NAME, 'vm2-pubip', public_ip_params)

  vm = create_vm(compute_client, network_client, SOUTH_CENTRAL_US, 'vm2', storage_account, vnet.subnets[0], public_ip)
  # vm = create_vm(compute_client, network_client, SOUTH_CENTRAL_US, 'vm2', nil, vnet.subnets[0], public_ip)  
end

def print_item(resource)
  resource.instance_variables.sort.each do |ivar|
    str = ivar.to_s.gsub /^@/, ''
    if resource.respond_to? str.to_sym
      puts "\t\t#{str}: #{resource.send(str.to_sym)}"
    end
  end
  puts "\n\n"
end

# Create a Virtual Machine and return it
def create_vm(compute_client, network_client, location, vm_name, storage_acct, subnet, public_ip)
  puts "Creating a network interface for the VM #{vm_name}"
  print_item nic = network_client.network_interfaces.create_or_update(
      GROUP_NAME,
      "nic-#{vm_name}",
      NetworkModels::NetworkInterface.new.tap do |interface|
        interface.location = SOUTH_CENTRAL_US
        interface.ip_configurations = [
            NetworkModels::NetworkInterfaceIPConfiguration.new.tap do |nic_conf|
              nic_conf.name = "nic-#{vm_name}"
              nic_conf.private_ipallocation_method = NetworkModels::IPAllocationMethod::Dynamic
              nic_conf.subnet = subnet
              nic_conf.public_ipaddress = public_ip
            end
        ]
      end
  )

  puts 'Creating a Ubuntu 16.04.0-LTS Standard DS2 V2 virtual machine w/ a public IP'
  vm_create_params = ComputeModels::VirtualMachine.new.tap do |vm|
    # location => 'southcentralus'
    vm.location = location
    vm.os_profile = ComputeModels::OSProfile.new.tap do |os_profile|
      os_profile.computer_name = vm_name
      os_profile.admin_username = 'notAdmin'
      os_profile.admin_password = 'Pa$$w0rd92'
    end

    vm.storage_profile = ComputeModels::StorageProfile.new.tap do |store_profile|
      store_profile.image_reference = ComputeModels::ImageReference.new.tap do |ref|
        ref.publisher = 'canonical'
        ref.offer = 'UbuntuServer'
        ref.sku = '16.04.0-LTS'
        ref.version = 'latest'
      end
      store_profile.os_disk = ComputeModels::OSDisk.new.tap do |os_disk|
        os_disk.name = "os-disk-#{vm_name}"
        os_disk.caching = ComputeModels::CachingTypes::None
        os_disk.create_option = ComputeModels::DiskCreateOptionTypes::FromImage
        # os_disk.vhd = ComputeModels::VirtualHardDisk.new.tap do |vhd|
        #   vhd.uri = "https://#{storage_acct.name}.blob.core.windows.net/rubycontainer/#{vm_name}.vhd"
        # end
      end
    end

    vm.hardware_profile = ComputeModels::HardwareProfile.new.tap do |hardware|
      # vm_size => 'Standard_DS2_v2'
      hardware.vm_size = ComputeModels::VirtualMachineSizeTypes::StandardDS2V2
    end

    vm.network_profile = ComputeModels::NetworkProfile.new.tap do |net_profile|
      net_profile.network_interfaces = [
          ComputeModels::NetworkInterfaceReference.new.tap do |ref|
            ref.id = nic.id
            ref.primary = true
          end
      ]
    end
  end

  print_item vm = compute_client.virtual_machines.create_or_update(GROUP_NAME, "vm-#{vm_name}", vm_create_params)
  vm
end

if $0 == __FILE__
  run_example
end

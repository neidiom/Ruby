require 'azure_mgmt_resources'

class Deployer

  # Initialize the deployer class with subscription, resource group and resource group location. The class will raise an
  # ArgumentError if there are empty values for Tenant Id, Client Id or Client Secret environment variables.
  #
  # @param [String] subscription_id the subscription to deploy the template
  # @param [String] resource_group the resource group to create or update and then deploy the template
  # @param [String] resource_group_location the location of the resource group
  def initialize(subscription_id, resource_group, resource_group_location)
    raise ArgumentError.new("Missing template file 'template.json' in current directory.") unless File.exist?('template.json')
    raise ArgumentError.new("Missing parameters file 'parameters.json' in current directory.") unless File.exist?('parameters.json')
    @resource_group = resource_group
    @subscription_id = subscription_id
	@resource_group_location = resource_group_location
    provider = MsRestAzure::ApplicationTokenProvider.new(
        ENV['AZURE_TENANT_ID'],
        ENV['AZURE_CLIENT_ID'],
        ENV['AZURE_CLIENT_SECRET'])
    credentials = MsRest::TokenCredentials.new(provider)
    @client = Azure::ARM::Resources::ResourceManagementClient.new(credentials)
    @client.subscription_id = @subscription_id
  end

  # Deploy the template to a resource group
  def deploy
    # ensure the resource group is created
    params = Azure::ARM::Resources::Models::ResourceGroup.new.tap do |rg|
      rg.location = @resource_group_location
    end
    @client.resource_groups.create_or_update(@resource_group, params)

    # build the deployment from a json file template from parameters
    template = File.read(File.expand_path(File.join(__dir__, 'template.json')))
    deployment = Azure::ARM::Resources::Models::Deployment.new
    deployment.properties = Azure::ARM::Resources::Models::DeploymentProperties.new
    deployment.properties.template = JSON.parse(template)
    deployment.properties.mode = Azure::ARM::Resources::Models::DeploymentMode::Incremental

    # build the deployment template parameters from Hash to {key: {value: value}} format
    deploy_params = File.read(File.expand_path(File.join(__dir__, 'parameters.json')))
    
    param_json = JSON.parse(deploy_params)
    param_json["parameters"]["location"]["value"] = "#{@resource_group_location}"
    param_json["parameters"]["resourceGroup"]["value"] = "#{@resource_group}"
    param_json["parameters"]["virtualMachineName"]["value"] = "#{@resource_group}-vm"
    param_json["parameters"]["virtualNetworkName"]["value"] = "#{@resource_group}-vnet"
    param_json["parameters"]["networkInterfaceName"]["value"] = "#{@resource_group}-nic"
    param_json["parameters"]["networkSecurityGroupName"]["value"] = "#{@resource_group}-nsg"
    param_json["parameters"]["publicIpAddressName"]["value"] = "#{@resource_group}-ip"
    #TODO: get imageId from DB, by location & image created date
    param_json["parameters"]["imageId"]["value"] = "/subscriptions/802136ca-e0a8-447c-b138-fa22e3db978f/resourceGroups/south_central/providers/Microsoft.Compute/images/GameHost-image-20170814174158"
    puts param_json["parameters"]

    # deployment.properties.parameters = JSON.parse(deploy_params)["parameters"]
    deployment.properties.parameters = param_json["parameters"]

    # put the deployment to the resource group
    @client.deployments.create_or_update(@resource_group, "#{@resource_group}-deploy", deployment)
  end
end

# Get user inputs and execute the script
if(ARGV.empty?)
  puts "Please specify subscriptionId resourceGroupName resourceGroupLocation as command line arguments"
  exit
end

subscription_id = ARGV[0]             # Azure Subscription Id
resource_group = ARGV[1]              # The resource group for deployment
resource_group_location = ARGV[2]     # The resource group location

msg = "\nInitializing the Deployer class with subscription id: #{subscription_id}, resource group: #{resource_group}"
msg += "\nand resource group location: #{resource_group_location}...\n\n"
puts msg

# Initialize the deployer class
deployer = Deployer.new(subscription_id, resource_group, resource_group_location)

puts "Beginning the deployment... \n\n"
# Deploy the template
deployment = deployer.deploy

puts "Done deploying!!"
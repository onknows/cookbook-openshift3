#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_node37
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

Chef::Log.error("Upgrade will be skipped. Could not find the flag: #{node['cookbook-openshift3']['control_upgrade_flag']}") unless ::File.file?(node['cookbook-openshift3']['control_upgrade_flag'])

if ::File.file?(node['cookbook-openshift3']['control_upgrade_flag'])

  node.force_override['cookbook-openshift3']['upgrade'] = true
  node.force_override['cookbook-openshift3']['ose_major_version'] = node['cookbook-openshift3']['upgrade_ose_major_version']
  node.force_override['cookbook-openshift3']['ose_version'] = node['cookbook-openshift3']['upgrade_ose_version']
  node.force_override['cookbook-openshift3']['openshift_docker_image_version'] = node['cookbook-openshift3']['upgrade_openshift_docker_image_version']

  server_info = OpenShiftHelper::NodeHelper.new(node)
  is_node_server = server_info.on_node_server?

  if defined? node['cookbook-openshift3']['upgrade_repos']
    node.force_override['cookbook-openshift3']['yum_repositories'] = node['cookbook-openshift3']['upgrade_repos']
  end

  include_recipe 'yum::default'
  include_recipe 'cookbook-openshift3::packages'

  if is_node_server
    log 'Upgrade for NODE [STARTED]' do
      level :info
    end

    %w(excluder docker-excluder).each do |pkg|
      execute "Disable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}" do
        command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} enable"
      end
    end

    include_recipe 'cookbook-openshift3::services'
    include_recipe 'cookbook-openshift3::node'
    include_recipe 'cookbook-openshift3::docker'
    include_recipe 'cookbook-openshift3::excluder'

    log 'Node services' do
      level :info
      notifies :restart, 'service[openvswitch]', :immediately
    end

    log 'Upgrade for NODE [COMPLETED]' do
      level :info
    end
  end
end

#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_certificate_server
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

  if defined? node['cookbook-openshift3']['upgrade_repos']
    node.force_override['cookbook-openshift3']['yum_repositories'] = node['cookbook-openshift3']['upgrade_repos']
  end

  log 'Upgrade for CERTIFICATE SERVER [STARTED]' do
    level :info
  end

  %w(excluder docker-excluder).each do |pkg|
    execute "Disable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}" do
      command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} enable"
      only_if "rpm -q #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}"
    end
  end

  include_recipe 'cookbook-openshift3::packages'
  include_recipe 'cookbook-openshift3::master_packages'
  include_recipe 'cookbook-openshift3::etcd_packages'
  include_recipe 'cookbook-openshift3::excluder'

  log 'Upgrade for CERTIFICATE SERVER [COMPLETED]' do
    level :info
  end
end

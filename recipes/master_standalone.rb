#
# Cookbook Name:: cookbook-openshift3
# Recipe:: master_standalone
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

helper = OpenShiftHelper::NodeHelper.new(node)

ose_major_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : node['cookbook-openshift3']['ose_major_version']

if node['cookbook-openshift3']['openshift_master_ca_certificate']['data_bag_name'] && node['cookbook-openshift3']['openshift_master_ca_certificate']['data_bag_item_name']
  secret_file = node['cookbook-openshift3']['openshift_master_ca_certificate']['secret_file'] || nil
  ca_vars = data_bag_item(node['cookbook-openshift3']['openshift_master_ca_certificate']['data_bag_name'], node['cookbook-openshift3']['openshift_master_ca_certificate']['data_bag_item_name'], secret_file)

  file "#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.key" do
    content Base64.decode64(ca_vars['key_base64'])
    mode '0600'
    action :create_if_missing
  end

  file "#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.crt" do
    content Base64.decode64(ca_vars['cert_base64'])
    mode '0644'
    action :create_if_missing
  end
end

package "#{node['cookbook-openshift3']['openshift_service_type']}-master" do
  action :install
  version node['cookbook-openshift3']['ose_version'] unless node['cookbook-openshift3']['ose_version'].nil?
  notifies :run, 'execute[daemon-reload]', :immediately
  not_if { node['cookbook-openshift3']['deploy_containerized'] }
  retries 3
end

ruby_block 'Duplicate Master directory' do
  block do
    helper.backup_dir("#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/.", node['cookbook-openshift3']['openshift_master_config_dir'])
  end
end

template "/etc/systemd/system/#{node['cookbook-openshift3']['openshift_service_type']}-master.service" do
  source 'service_master-containerized.service.erb'
  notifies :run, 'execute[daemon-reload]', :immediately
  only_if { node['cookbook-openshift3']['deploy_containerized'] }
end

sysconfig_vars = {}

if node['cookbook-openshift3']['openshift_cloud_provider'] == 'aws'
  if node['cookbook-openshift3']['openshift_cloud_providers']['aws']['data_bag_name'] && node['cookbook-openshift3']['openshift_cloud_providers']['aws']['data_bag_item_name']
    secret_file = node['cookbook-openshift3']['openshift_cloud_providers']['aws']['secret_file'] || nil
    aws_vars = data_bag_item(node['cookbook-openshift3']['openshift_cloud_providers']['aws']['data_bag_name'], node['cookbook-openshift3']['openshift_cloud_providers']['aws']['data_bag_item_name'], secret_file)
    sysconfig_vars['aws_access_key_id'] = aws_vars['access_key_id']
    sysconfig_vars['aws_secret_access_key'] = aws_vars['secret_access_key']
  end
end

template "/etc/sysconfig/#{node['cookbook-openshift3']['openshift_service_type']}-master" do
  source 'service_master.sysconfig.erb'
  variables(sysconfig_vars)
  notifies :restart, 'service[Restart Master]', :immediately
end

execute 'Create the policy file' do
  command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} create-bootstrap-policy-file --filename=#{node['cookbook-openshift3']['openshift_master_policy']}"
  creates node['cookbook-openshift3']['openshift_master_policy']
  notifies :restart, 'service[Restart Master]', :immediately
end

template node['cookbook-openshift3']['openshift_master_scheduler_conf'] do
  source 'scheduler.json.erb'
  variables ose_major_version: node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : node['cookbook-openshift3']['ose_major_version']
  notifies :restart, 'service[Restart Master]', :immediately
end

if node['cookbook-openshift3']['oauth_Identities'].include? 'HTPasswdPasswordIdentityProvider'
  package 'httpd-tools' do
    retries 3
  end

  template node['cookbook-openshift3']['openshift_master_identity_provider']['HTPasswdPasswordIdentityProvider']['filename'] do
    source 'htpasswd.erb'
    mode '600'
  end
end

include_recipe 'cookbook-openshift3::wire_aggregator' if ose_major_version.split('.')[1].to_i >= 7

openshift_create_master 'Create master configuration file' do
  named_certificate node['cookbook-openshift3']['openshift_master_named_certificates']
  origins node['cookbook-openshift3']['erb_corsAllowedOrigins'].uniq
  standalone_registry node['cookbook-openshift3']['deploy_standalone_registry']
  master_file node['cookbook-openshift3']['openshift_master_config_file']
  openshift_service_type node['cookbook-openshift3']['openshift_service_type']
end

service "#{node['cookbook-openshift3']['openshift_service_type']}-master" do
  action %i(start enable)
end

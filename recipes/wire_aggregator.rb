#
# Cookbook Name:: cookbook-openshift3
# Recipe:: wire_aggregator
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

execute 'Creating Master Aggregator signer certs' do
  command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} adm ca create-signer-cert \
          --cert=#{node['cookbook-openshift3']['openshift_master_config_dir']}/front-proxy-ca.crt \
          --key=#{node['cookbook-openshift3']['openshift_master_config_dir']}/front-proxy-ca.key \
          --serial=#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.serial.txt"
  creates "#{node['cookbook-openshift3']['openshift_master_config_dir']}/front-proxy-ca.crt"
end

# create-api-client-config generates a ca.crt file which will
# overwrite the OpenShift CA certificate.  
# Generate the aggregator kubeconfig in a temporary directory and then copy files into the
# master config dir to avoid overwriting ca.crt

execute 'Create temp directory for aggregator files' do
  command "mkdir -p #{Chef::Config[:file_cache_path]}/certtemp"
  creates "#{node['cookbook-openshift3']['openshift_master_config_dir']}/aggregator-front-proxy.kubeconfig"
end

execute 'Create Master api-client config for Aggregator' do
  command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} adm ca create-api-client-config \
          --certificate-authority=#{node['cookbook-openshift3']['openshift_master_config_dir']}/front-proxy-ca.crt \
          --signer-cert=#{node['cookbook-openshift3']['openshift_master_config_dir']}/front-proxy-ca.crt \
          --signer-key=#{node['cookbook-openshift3']['openshift_master_config_dir']}/front-proxy-ca.key \
          --user aggregator-front-proxy \
          --client-dir=#{Chef::Config[:file_cache_path]}/certtemp \
          --signer-serial=#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.serial.txt"
  creates "#{node['cookbook-openshift3']['openshift_master_config_dir']}/aggregator-front-proxy.kubeconfig"
end

%w(aggregator-front-proxy.crt aggregator-front-proxy.key aggregator-front-proxy.kubeconfig).each do |aggregator_file|
  remote_file "#{node['cookbook-openshift3']['openshift_master_config_dir']}/#{aggregator_file}" do
    source "file://#{Chef::Config[:file_cache_path]}/certtemp/#{aggregator_file}"
    not_if { ::File.file?("#{node['cookbook-openshift3']['openshift_master_config_dir']}/#{aggregator_file}") }
  end
end

directory 'Delete temp directory for aggregator files' do
  path "#{Chef::Config[:file_cache_path]}/certtemp"
  recursive true
  action :delete
end

file "#{node['cookbook-openshift3']['openshift_master_config_dir']}/openshift-ansible-catalog-console.js" do
  content 'window.OPENSHIFT_CONSTANTS.TEMPLATE_SERVICE_BROKER_ENABLED=false'
  mode '0644'
  owner 'root'
  group 'root'
end

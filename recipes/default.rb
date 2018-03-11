#
# Cookbook Name:: cookbook-openshift3
# Recipe:: default
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
is_etcd_server = server_info.on_etcd_server?
is_master_server = server_info.on_master_server?
is_node_server = server_info.on_node_server?

service "#{node['cookbook-openshift3']['openshift_service_type']}-master"

service "#{node['cookbook-openshift3']['openshift_service_type']}-master-api" do
  retries 5
  retry_delay 5
end

service "#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers" do
  retries 5
  retry_delay 5
end

execute 'daemon-reload' do
  command 'systemctl daemon-reload'
  action :nothing
end

service 'httpd'

service 'docker'

service 'NetworkManager'

service 'openvswitch'

service 'haproxy'

service 'Restart Master' do
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master"
  action :nothing
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master"
end

service 'Restart API' do
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master-api"
  action :nothing
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master-api"
end

service 'Restart Controller' do
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master-controller"
  action :nothing
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master-controller"
end

service 'Restart Node' do
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-node"
  action :nothing
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-node"
end

service 'etcd-service' do
  service_name node['cookbook-openshift3']['etcd_service_name']
  action :nothing
end

if node['cookbook-openshift3']['control_upgrade']
  begin
    include_recipe "cookbook-openshift3::upgrade_control_plane#{node['cookbook-openshift3']['control_upgrade_version']}" if is_master_server || is_etcd_server
    include_recipe "cookbook-openshift3::upgrade_control_plane#{node['cookbook-openshift3']['control_upgrade_version']}" if is_node_server
  rescue Chef::Exceptions::RecipeNotFound
    log "['cookbook-openshift3']['control_upgrade_version']: '#{node['cookbook-openshift3']['control_upgrade_version']}' not valid (14,15,36,37)" do
      level :warn
    end
  end
end

include_recipe 'cookbook-openshift3::validate' unless node['cookbook-openshift3']['upgrade']

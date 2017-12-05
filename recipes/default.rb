#
# Cookbook Name:: cookbook-openshift3
# Recipe:: default
#
# Copyright (c) 2015 The Authors, All Rights Reserved.
server_info = OpenShiftHelper::NodeHelper.new(node)
is_first_master = server_info.on_first_master?

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

include_recipe 'cookbook-openshift3::validate'
include_recipe 'cookbook-openshift3::common'
include_recipe 'cookbook-openshift3::master'
include_recipe 'cookbook-openshift3::node'

include_recipe 'cookbook-openshift3::master_config_post' if is_first_master

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

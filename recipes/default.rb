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

# Use ruby_block for restarting master
service 'Restart Master'
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master" do
  action :restart
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master"
end

service 'Restart API'
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master-api" do
  action :restart
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master-api"
end

service 'Restart Controller'
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master-controller" do
  action :restart
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master-controller"
end

service 'Restart Node'
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-node" do
  action :restart
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-node"
end

## Use ruby_block for restarting master
#ruby_block 'Restart Master' do
#  block do
#    Mixlib::ShellOut.new("systemctl restart #{node['cookbook-openshift3']['openshift_service_type']}-master").run_command
#    only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master"
#  end
#  action :nothing
#end

## Use ruby_block for restarting master api
#ruby_block 'Restart API' do
#  block do
#    Mixlib::ShellOut.new("systemctl restart #{node['cookbook-openshift3']['openshift_service_type']}-master-api").run_command
#    only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master-api"
#  end
#  action :nothing
#end

## Use ruby_block for restarting master controller
#ruby_block 'Restart Controller' do
#  block do
#    Mixlib::ShellOut.new("systemctl restart #{node['cookbook-openshift3']['openshift_service_type']}-master-controller").run_command
#    only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master-controller"
#  end
#  action :nothing
#end

## Use ruby_block for restarting node
#ruby_block 'Restart Node' do
#  block do
#    Mixlib::ShellOut.new("systemctl restart #{node['cookbook-openshift3']['openshift_service_type']}-node").run_command
#    only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-node"
#  end
#  action :nothing
#end

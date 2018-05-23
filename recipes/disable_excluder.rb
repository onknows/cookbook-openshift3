#
# Cookbook Name:: cookbook-openshift3
# Recipe:: disable_excluder
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
is_master_server = server_info.on_master_server?
is_node_server = server_info.on_node_server?

if is_master_server || is_node_server
  %w(excluder docker-excluder).each do |pkg|
    execute "Disable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} (Best effort < 3.5)" do
      command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} enable"
      only_if "rpm -q #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}"
    end
  end
end

#
# Cookbook Name:: cookbook-openshift3
# Recipe:: excluder
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

ose_major_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : node['cookbook-openshift3']['ose_major_version']

%w(excluder docker-excluder).each do |pkg|
  yum_package "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}" do
    action :upgrade if node['cookbook-openshift3']['upgrade']
    version node['cookbook-openshift3']['excluder_version'] unless node['cookbook-openshift3']['excluder_version'].nil?
    not_if { ose_major_version.split('.')[1].to_i < 5 && node['cookbook-openshift3']['openshift_deployment_type'] != 'enterprise' }
  end

  execute "Enable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}" do
    command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} disable"
    not_if { ose_major_version.split('.')[1].to_i < 5 && node['cookbook-openshift3']['openshift_deployment_type'] != 'enterprise' }
  end
end

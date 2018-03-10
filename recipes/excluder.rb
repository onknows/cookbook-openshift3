#
# Cookbook Name:: cookbook-openshift3
# Recipe:: excluder
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

ose_major_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'].reverse.chop.reverse : node['cookbook-openshift3']['ose_major_version']

if node['cookbook-openshift3']['upgrade']
  %w(excluder docker-excluder).each do |pkg|
    execute "Disable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}" do
      command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} disable"
    end
  end
else
  %w(excluder docker-excluder).each do |pkg|
    yum_package "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} = #{ose_major_version}"
    execute "Enable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}" do
      command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} enable"
    end
  end
end

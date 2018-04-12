#
# Cookbook Name:: cookbook-openshift3
# Recipe:: master_packages
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
is_certificate_server = server_info.on_certificate_server?
first_master = server_info.first_master
docker_version = node['cookbook-openshift3']['openshift_docker_image_version']

if node['cookbook-openshift3']['deploy_containerized']
  docker_image node['cookbook-openshift3']['openshift_docker_master_image'] do
    tag docker_version
    action :pull_if_missing
  end

  bash 'Add CLI to master(s)' do
    code <<-BASH
      docker create --name temp-cli ${DOCKER_IMAGE}:${DOCKER_TAG}
      docker cp temp-cli:/usr/bin/openshift /usr/local/bin/openshift
      docker rm temp-cli
      BASH
    environment(
      'DOCKER_IMAGE' => node['cookbook-openshift3']['openshift_docker_master_image'],
      'DOCKER_TAG' => node['cookbook-openshift3']['openshift_docker_image_version']
    )
    not_if { ::File.exist?('/usr/local/bin/openshift') && !node['cookbook-openshift3']['upgrade'] }
  end

  %w(oadm oc kubectl).each do |client_symlink|
    link "/usr/local/bin/#{client_symlink}" do
      to '/usr/local/bin/openshift'
      link_type :hard
    end
  end

  execute 'Add bash completion for oc' do
    command '/usr/local/bin/oc completion bash > /etc/bash_completion.d/oc'
    not_if { ::File.exist?('/etc/bash_completion.d/oc') && !node['cookbook-openshift3']['upgrade'] }
  end
end

package "#{node['cookbook-openshift3']['openshift_service_type']}-master" do
  action :install
  version node['cookbook-openshift3']['ose_version'] unless node['cookbook-openshift3']['ose_version'].nil?
  options node['cookbook-openshift3']['yum_options'] unless node['cookbook-openshift3']['yum_options'].nil?
  notifies :run, 'execute[daemon-reload]', :immediately
  not_if { node['cookbook-openshift3']['deploy_containerized'] || (is_certificate_server && node['fqdn'] != first_master['fqdn']) }
  retries 3
end

package "#{node['cookbook-openshift3']['openshift_service_type']}-clients" do
  action :install
  version node['cookbook-openshift3']['ose_version'] unless node['cookbook-openshift3']['ose_version'].nil?
  options node['cookbook-openshift3']['yum_options'] unless node['cookbook-openshift3']['yum_options'].nil?
  not_if { node['cookbook-openshift3']['deploy_containerized'] }
  retries 3
end

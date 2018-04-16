#
# Cookbook Name:: is_apaas_openshift_cookbook
# Recipe:: docker
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
is_node_server = server_info.on_node_server?

if is_node_server || node['is_apaas_openshift_cookbook']['deploy_containerized']
  yum_package 'docker' do
    action :upgrade if node['is_apaas_openshift_cookbook']['upgrade']
    version node['is_apaas_openshift_cookbook']['docker_version'] unless node['is_apaas_openshift_cookbook']['docker_version'].nil?
    options node['is_apaas_openshift_cookbook']['docker_yum_options'] unless node['is_apaas_openshift_cookbook']['docker_yum_options'].nil?
    retries 3
    notifies :restart, 'service[docker]', :immediately if node['is_apaas_openshift_cookbook']['upgrade']
  end

  bash "Configure Docker to use the default FS type for #{node['fqdn']}" do
    code <<-BASH
      correct_fs=$(df -T /var | egrep -o 'xfs|ext4')
      sed -i "s/xfs/$correct_fs/" /usr/bin/docker-storage-setup
    BASH
    not_if "grep $(df -T /var | egrep -o 'xfs|ext4') /usr/bin/docker-storage-setup"
    timeout 60
  end

  template '/etc/sysconfig/docker-storage-setup' do
    source 'docker-storage.erb'
  end

  template '/etc/sysconfig/docker' do
    source 'service_docker.sysconfig.erb'
    notifies :restart, 'service[docker]', :immediately
    notifies :enable, 'service[docker]', :immediately
  end
end

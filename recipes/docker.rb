#
# Cookbook Name:: cookbook-openshift3
# Recipe:: docker
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
is_node_server = server_info.on_node_server?

if is_node_server || node['cookbook-openshift3']['deploy_containerized']
  yum_package 'docker' do
    action :install
    version node['cookbook-openshift3']['upgrade'] ? (node['cookbook-openshift3']['upgrade_docker_version'] unless node['cookbook-openshift3']['upgrade_docker_version'].nil?) : (node['cookbook-openshift3']['docker_version'] unless node['cookbook-openshift3']['docker_version'].nil?)
    retries 3
    options node['cookbook-openshift3']['docker_yum_options'] unless node['cookbook-openshift3']['docker_yum_options'].nil?
    notifies :restart, 'service[docker]', :immediately if node['cookbook-openshift3']['upgrade']
    only_if do
      ::Mixlib::ShellOut.new('rpm -q docker').run_command.error? || node['cookbook-openshift3']['upgrade']
    end
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

  if node['cookbook-openshift3']['openshift_docker_secure']
    node['cookbook-openshift3']['openshift_docker_add_registry_arg'].each do |registry|
      directory "/etc/docker/certs.d/#{registry}" do
        owner 'root'
        group 'root'
        mode '0755'
        action :create
        recursive true
      end

      ruby_block "Update Docker trusted certificates for #{node['fqdn']}" do
        block do
          fqdn, port = registry.split(':')
          uri = port.nil? ? "#{fqdn}:443" : "#{fqdn}:#{port}"
          crt = Mixlib::ShellOut.new("echo | timeout 5 openssl s_client -servername #{fqdn} -connect #{uri} 2>/dev/null | openssl x509").run_command.stdout.strip
          open("/etc/docker/certs.d/#{registry}/registry.crt", 'w') { |f| f << crt.to_s } unless crt.empty?
        end
        not_if { ::File.file?("/etc/docker/certs.d/#{registry}/registry.crt") }
      end
    end
  end
end

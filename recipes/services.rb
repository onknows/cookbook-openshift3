#
# Cookbook Name:: cookbook-openshift3
# Recipe:: services
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
helper = OpenShiftHelper::UtilHelper
etcd_servers = server_info.etcd_servers
master_servers = server_info.master_servers
certificate_server = server_info.certificate_server

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
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers"
  action :nothing
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master-controllers"
end

service 'Restart Node' do
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-node"
  action :nothing
  only_if "systemctl is-enabled #{node['cookbook-openshift3']['openshift_service_type']}-node"
  retries 4
  retry_delay 5
end

systemd_unit "#{node['cookbook-openshift3']['openshift_service_type']}-node" do
  action :nothing
end

if node['cookbook-openshift3']['deploy_containerized']
  service 'etcd-service' do
    service_name 'etcd_container'
    action :nothing
  end
else
  service 'etcd-service' do
    service_name 'etcd'
    action :nothing
  end
end

ruby_block 'Change HTTPD port xfer' do
  block do
    http_addresses = [etcd_servers, master_servers, [certificate_server]].each_with_object([]) do |candidate_servers, memo|
      this_server = candidate_servers.find { |server_candidate| server_candidate['fqdn'] == node['fqdn'] }
      memo << this_server['ipaddress'] if this_server
    end.sort.uniq

    openshift_settings = helper.new('/etc/httpd/conf/httpd.conf')
    openshift_settings.search_file_replace_line(
      /(^Listen.*?\n)+/m,
      http_addresses.map { |addr| "Listen #{addr}:#{node['cookbook-openshift3']['httpd_xfer_port']}\n" }.join
    )
    openshift_settings.write_file
  end
  action :nothing
  notifies :restart, 'service[httpd]', :immediately
end

ruby_block 'Modify the AllowOverride options' do
  block do
    openshift_settings = helper.new('/etc/httpd/conf/httpd.conf')
    openshift_settings.search_file_replace_line(
      /AllowOverride None/,
      'AllowOverride All'
    )
    openshift_settings.write_file
  end
  action :nothing
  notifies :reload, 'service[httpd]', :immediately
end

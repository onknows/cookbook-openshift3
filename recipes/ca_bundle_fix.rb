#
# Cookbook Name:: cookbook-openshift3
# Recipe:: ca_bundle_fix
#
# If the original deployment was on <3.3/<1.3 then ca-bundle may not have been
# created on the masters. This ensures it exists to avoid failures to startup
# when it is not there by copying it over from ca.crt
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
is_master_server = server_info.on_master_server?

ruby_block 'Create ca-bundle if it is not there' do
  block do
    require 'fileutils'
    FileUtils.cp("#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.crt", "#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca-bundle.crt")
  end
  only_if { is_master_server && ::File.file?("#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.crt") && !::File.file?("#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca-bundle.crt") }
end

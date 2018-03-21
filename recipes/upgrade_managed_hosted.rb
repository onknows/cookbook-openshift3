#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_managed_hosted
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

hosted_upgrade_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : 'v' + node['cookbook-openshift3']['ose_version'].to_s.split('-')[0]

log 'Update hosted deployment(s) to current version [STARTED]' do
  level :info
end

template "#{Chef::Config[:file_cache_path]}/router-patch" do
  source 'patch-router.json.erb'
  variables(
    lazy do
      {
        router_image: Mixlib::ShellOut.new("#{node['cookbook-openshift3']['openshift_common_client_binary']} get dc/router -n #{node['cookbook-openshift3']['openshift_hosted_router_namespace']} -o jsonpath='{.spec.template.spec.containers[0].image}'").run_command.stdout.strip.gsub(/:v.+/, ":#{hosted_upgrade_version}")
      }
    end
  )
end

template "#{Chef::Config[:file_cache_path]}/registry-patch" do
  source 'patch-registry.json.erb'
  variables(
    lazy do
      {
        registry_image: Mixlib::ShellOut.new("#{node['cookbook-openshift3']['openshift_common_client_binary']} get dc/docker-registry -n #{node['cookbook-openshift3']['openshift_hosted_registry_namespace']} -o jsonpath='{.spec.template.spec.containers[0].image}'").run_command.stdout.strip.gsub(/:v.+/, ":#{hosted_upgrade_version}")
      }
    end
  )
end

execute "Update router image to current version \"#{hosted_upgrade_version}\"" do
  command "#{node['cookbook-openshift3']['openshift_common_client_binary']} \
    --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
    patch dc/router -n #{node['cookbook-openshift3']['openshift_hosted_router_namespace']} -p \"$(cat #{Chef::Config[:file_cache_path]}/router-patch)\""
  only_if do
    node['cookbook-openshift3']['openshift_hosted_manage_router']
  end
end

execute "Update registry image to current version \"#{hosted_upgrade_version}\"" do
  command "#{node['cookbook-openshift3']['openshift_common_client_binary']} \
    --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
    patch dc/docker-registry -n #{node['cookbook-openshift3']['openshift_hosted_registry_namespace']} -p \"$(cat #{Chef::Config[:file_cache_path]}/registry-patch)\""
  only_if do
    node['cookbook-openshift3']['openshift_hosted_manage_registry']
  end
end

log 'Update hosted deployment(s) to current version [COMPLETED]' do
  level :info
end

#
# Cookbook Name:: is_apaas_openshift_cookbook
# Recipe:: packages
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

if node['is_apaas_openshift_cookbook']['install_method'].eql? 'yum'
  node['is_apaas_openshift_cookbook']['yum_repositories'].each do |repo|
    yum_repository repo['name'] do
      description "#{repo['name'].capitalize} aPaaS Repository"
      baseurl repo['baseurl']
      gpgcheck repo['gpgcheck'] if repo.key?(:gpgcheck) && !repo['gpgcheck'].nil?
      gpgkey repo['gpgkey'] if repo.key?(:gpgkey) && !repo['gpgkey'].nil?
      sslverify repo['sslverify'] if repo.key?(:sslverify) && !repo['sslverify'].nil?
      exclude repo['exclude'] if repo.key?(:exclude) && !repo['exclude'].nil?
      enabled repo['enabled'] if repo.key?(:enabled) && !repo['enabled'].nil?
      action :create
    end
  end
end

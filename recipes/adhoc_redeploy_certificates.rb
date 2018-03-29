#
# Cookbook Name:: cookbook-openshift3
# Recipe:: adhoc_redeploy_certificates
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

include_recipe 'cookbook-openshift3::services'
include_recipe 'cookbook-openshift3::adhoc_redeploy_etcd_ca' if node['cookbook-openshift3']['adhoc_redeploy_etcd_ca']
include_recipe 'cookbook-openshift3::adhoc_redeploy_etcd_certs' if node['cookbook-openshift3']['adhoc_redeploy_etcd_certs']

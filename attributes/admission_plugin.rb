ose_major_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : node['cookbook-openshift3']['ose_major_version']

default['cookbook-openshift3']['admission_plugin'] = case ose_major_version.split('.')[1].to_i
                                                     when '5,6,7'
                                                       "{'openshift.io/ImagePolicy':{'configuration':{'kind':'ImagePolicyConfig','apiVersion':'v1','executionRules':[{'name':'execution-denied','onResources':[{'resource':'pods'},{'resource':'builds'}],'reject':true,'matchImageAnnotations':[{'key':'images.openshift.io/deny-execution','value':'true'}],'skipOnResolutionFailure':true}]}}}"
                                                     else
                                                       ''
                                                     end

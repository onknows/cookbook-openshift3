# Redeploy Platform Certificates Process

### Overview

You can use the `cookbook-openshift3::adhoc_redeploy_certificates` recipe to automate the OpenShift cluster certifciates
renewal.

#### Certificate renewal

The following table is a guide for renewing the certificates:

| PURPOSE | Supported | Variable |
| ------------------------------- | ------------------ | ---------- |
| Redeploying a New etcd CA Only | `Fully`    | `adhoc_redeploy_etcd_ca` |
| Redeploying etcd Certificates Only | `Fully` |`adhoc_redeploy_etcd_certs` |
| Redeploying Master Certificates Only | `Not yet`  | `N/A` |
| Redeploying Node Certificates Only | `Not yet` | `N/A` |
| Redeploying Registry Certificates Only | `Not yet` | `N/A` |
| Redeploying Router Certificates Only | `Not yet` | `N/A` |

#### Control Renewal of certificates

When renewing the certificates in separate phases (CA/CERTS), the control phase includes:

* The `adhoc_redeploy_etcd_ca` redeploys the etcd CA certificate by generating a new CA certificate and distributing an updated bundle containing old and new to all etcd peers and master clients. This also includes serial restarts of the etcd service.

* The `adhoc_redeploy_etcd_certs` redeploys new etcd certificates signed by CA certificate and distributing to all etcd peers and master clients. This also includes serial restarts of the etcd service and Openshift services (API/Controllers)


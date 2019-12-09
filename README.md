# Shell to configure:
1. A microservices aplications
2. Setup Red Hat Service Mesh to into a project
3. Configure Service Mesh Gateways, Policies, Destination Rules, Virtual Services, Routes

Before you start, make sure you have the following installed Operators in your OpenShift v4 platform:

1. Elasticsearch Operator
2. Jaeger Operator
3. Kiali Operator


This script is responsable for performing the Installation of the Red Hat Service Mesh Operator, make sure you have the following data from your OpenShift platform:

```
WILDCARD=apps.cluster-40b3.40b3.sandbox1154.opentlc.com
PROJECT=bookinfo
PROJECT_ISTIO=bookretail-istio-system
```

# OpenShift Cluster
```
Console: https://console-openshift-console.apps.cluster-40b3.40b3.sandbox1154.opentlc.com
API: https://api.cluster-40b3.40b3.sandbox1154.opentlc.com:6443
Username: admin
Password: << default pw >>
```

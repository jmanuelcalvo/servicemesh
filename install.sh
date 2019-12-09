#! /bin/bash

# Setear las variables
WILDCARD=apps.cluster-40b3.40b3.sandbox1154.opentlc.com
PROJECT=bookinfo
PROJECT_ISTIO=bookretail-istio-system

# Script de instalacion de Istio y app
oc login -u admin -p r3dh4t1!

# Crear la aplicacion y el proyecto bookinfo


oc new-project bookinfo
if [ "$?" = "0" ]
then
   oc apply -f https://raw.githubusercontent.com/istio/istio/1.4.0/samples/bookinfo/platform/kube/bookinfo.yaml -n $PROJECT
   sleep 10
   oc expose service productpage
   echo "In your browser, navigate to the bookinfo productpage at the following URL:"
   echo -en "\nhttp://$(oc get route productpage --template '{{ .spec.host }}')\n"
else
   echo "el proyecto ya existe"
   echo "In your browser, navigate to the bookinfo productpage at the following URL:"
   echo -en "\nhttp://$(oc get route productpage --template '{{ .spec.host }}')\n"
fi

# Creando un nuevo proyecto de Service para incluir el service Mesh ( kiali, prometheus, jaeger, citadel, pilot ) entre otros
oc adm new-project $PROJECT_ISTIO --display-name="Bookretail Service Mesh System"

# Pasar al nuevo proyecto
oc project $PROJECT_ISTIO

# Creando el Service Mesh Control Plane
cat <<EOF > service-mesh.yaml
---
apiVersion: maistra.io/v1
kind: ServiceMeshControlPlane
metadata:
  name: service-mesh-installation
spec:
  threeScale:
    enabled: false

  istio:
    global:
      mtls: false
      disablePolicyChecks: false
      proxy:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 128Mi

    gateways:
      istio-egressgateway:
        autoscaleEnabled: false
      istio-ingressgateway:
        autoscaleEnabled: false
        ior_enabled: false

    mixer:
      policy:
        autoscaleEnabled: false

      telemetry:
        autoscaleEnabled: false
        resources:
          requests:
            cpu: 100m
            memory: 1G
          limits:
            cpu: 500m
            memory: 4G

    pilot:
      autoscaleEnabled: false
      traceSampling: 100.0

    kiali:
      dashboard:
        user: admin
        passphrase: redhat
    tracing:
      enabled: true
EOF

oc apply -f service-mesh.yaml -n $PROJECT_ISTIO

# Habiliatndo el ServiceMeshMemberRoll en el proyecto bookinfo
cat <<EOF > service-mesh-roll.yaml
---
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
  namespace: $PROJECT_ISTIO
spec:
  members:
  - bookinfo
EOF

oc apply -f service-mesh-roll.yaml -n $PROJECT_ISTIO

# Esperar a que suban todos los pods del service Mesh
sleep 180

# Adicionando Sidecar a los contenedores
for i in $(oc get deployment -n $PROJECT | grep -v NAME | awk '{print $1}') ; do oc patch deployment $i -p "{\"spec\": { \"template\": { \"metadata\": { \"annotations\": { \"sidecar.istio.io/inject\": \"true\"}}}}}" -n $PROJECT; done


# Esperar a que suban todos los pods se RE generen
sleep 120
# crear el archivo de configuracion para los certificados y su Wildcard
cat <<EOF | tee ./cert.cfg
[ req ]
req_extensions     = req_ext
distinguished_name = req_distinguished_name
prompt             = no

[req_distinguished_name]
commonName=$WILDCARD

[req_ext]
subjectAltName   = @alt_names

[alt_names]
DNS.1  = $WILDCARD
DNS.2  = *.$WILDCARD
EOF

# Crear certificado autofirmado y llave privada
openssl req -x509 -config cert.cfg -extensions req_ext -nodes -days 730 -newkey rsa:2048 -sha256 -keyout tls.key -out tls.crt

# Crear el Secret 
oc create secret tls istio-ingressgateway-certs --cert tls.crt --key tls.key -n $PROJECT_ISTIO

##################################################################

# Poner las anotaciones para el Istio Ingress Gateway pod
oc patch deployment istio-ingressgateway -p '{"spec":{"template":{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt": "'`date -Iseconds`'"}}}}}' -n $PROJECT_ISTIO

# Definir un  wildcard Gateway

cat <<EOF > wildcard-gateway.yml
---
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: bookinfo-wildcard-gateway
spec:
  selector:
    istio: ingressgateway # use istio default controller
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      privateKey: /etc/istio/ingressgateway-certs/tls.key
      serverCertificate: /etc/istio/ingressgateway-certs/tls.crt
    hosts:
    - "*.$WILDCARD"
EOF

oc apply -f wildcard-gateway.yml -n $PROJECT_ISTIO

####################################################
# Definir las politicas para las aplicaciones      #
####################################################

for i in details productpage ratings reviews
do
cat <<EOF > $i-policy.yml
---
apiVersion: authentication.istio.io/v1alpha1
kind: Policy
metadata:
  name: $i-policy
spec:
  peers:
  - mtls:
      mode: STRICT
  targets:
  - name: reviews
EOF
oc apply -f $i-policy.yml -n $PROJECT
done

####################################################
# Definir las reglas al destino                    #
####################################################

for i in details productpage ratings reviews
do
cat <<EOF > $i-destination-rule.yml
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: $i-destination-rule
spec:
  host: $i.bookinfo.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF
oc apply -f  $i-destination-rule.yml -n $PROJECT
done


####################################################
# Definicio del virtual service
####################################################

cat <<EOF > virtualservice.yml
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: productpage-virtualservice
spec:
  hosts:
  - productpage.bookinfo.$WILDCARD
  gateways:
  - bookinfo-wildcard-gateway.bookretail-istio-system.svc.cluster.local
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        port:
          number: 9080
        host: productpage.bookinfo.svc.cluster.local
EOF

oc apply -f virtualservice.yml -n $PROJECT

####################################################
# Creacion de la ruta en el proyecrto de ISTIO     #
####################################################

cat <<EOF > service-gateway.yml
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  annotations:
    openshift.io/host.generated: 'true'
  labels:
    app: productpage
  name: productpage-route
spec:
  host: productpage.bookinfo.$WILDCARD
  port:
    targetPort: https
  tls:
    termination: passthrough
  to:
    kind: Service
    name: istio-ingressgateway
    weight: 100
  wildcardPolicy: None
EOF

oc apply -f service-gateway.yml -n $PROJECT_ISTIO


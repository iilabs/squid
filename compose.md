# How to run

These vars need to be set and exported:

export PODMAN_COMPOSE_PROVIDER=/usr/sbin/podman-compose
export PODMAN_COMPOSE_WARNING_LOGS=false

podman compose up

Once your CA is created, install it.

sudo ./install-ca.sh config/ca/CA.pem 
installed CA at /etc/pki/ca-trust/source/anchors/squid-ssl-proxy.pem (update-ca-trust extract)

You'll need this CA installed in the ca-trust source of any https clients.


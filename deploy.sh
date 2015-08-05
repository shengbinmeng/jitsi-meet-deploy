#!/bin/bash

#Configure

DOMAIN_NAME=jitsi.shengbin.vbox
YOURSECRET1=yoursecret1
YOURSECRET2=yoursecret2
YOURSECRET3=yoursecret3

# Prosody

apt-get install prosody

cat > $DOMAIN_NAME.cfg.lua <<EndOfText
VirtualHost "$DOMAIN_NAME"
        -- enabled = false -- Remove this line to enable this host
        authentication = "anonymous"
        -- Assign this host a certificate for TLS, otherwise it would use the one
        -- set in the global section (if any).
        -- Note that old-style SSL on port 5223 only supports one certificate, and will always
        -- use the global one.
        -- we need bosh
        modules_enabled = {
            "bosh";
            "pubsub";
        }

Component "conference.$DOMAIN_NAME" "muc"
admins = { "focus@auth.$DOMAIN_NAME" }

Component "jitsi-videobridge.$DOMAIN_NAME"
    component_secret = "$YOURSECRET1"

VirtualHost "auth.$DOMAIN_NAME"
        authentication = "internal_plain"

Component "focus.$DOMAIN_NAME"
    component_secret = "$YOURSECRET2"
EndOfText

mkdir -p /etc/prosody/conf.d && cp $DOMAIN_NAME.cfg.lua /etc/prosody/conf.d/

prosodyctl register focus auth.$DOMAIN_NAME $YOURSECRET3
prosodyctl restart

err=$?
if [ "${err}" -ne 0 ]; then exit "${err}"; fi

# Nginx

apt-get install nginx

cat > $DOMAIN_NAME <<EndOfText
server {
    listen 80;
    server_name $DOMAIN_NAME;
    # set the root
    root /srv/$DOMAIN_NAME;
    index index.html;
    location ~ ^/([a-zA-Z0-9=\?]+)$ {
        rewrite ^/(.*)$ / break;
    }
    location / {
        ssi on;
    }
    # BOSH
    location /http-bind {
        proxy_pass      http://localhost:5280/http-bind;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$http_host;
    }
}
EndOfText

mkdir -p /etc/nginx/sites-available && cp $DOMAIN_NAME /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/$DOMAIN_NAME

mkdir -p /srv && cp -r jitsi-meet /srv/$DOMAIN_NAME
invoke-rc.d nginx restart

err=$?
if [ "${err}" -ne 0 ]; then exit "${err}"; fi

# Videobridge & jicofo

apt-get install default-jre

mkdir -p /opt && cp -r jitsi-videobridge /opt/ && cp -r jicofo /opt/

echo org.jitsi.impl.neomedia.transform.srtp.SRTPCryptoContext.checkReplay=false > sip-communicator.properties
mkdir -p ~/.sip-communicator && cp sip-communicator.properties ~/.sip-communicator/

# Clean up

rm $DOMAIN_NAME.cfg.lua $DOMAIN_NAME sip-communicator.properties

# Run

/opt/jitsi-videobridge/jvb.sh --host=localhost --domain=$DOMAIN_NAME --port=5347 --secret=$YOURSECRET1 &
/opt/jicofo/jicofo.sh --domain=$DOMAIN_NAME --secret=$YOURSECRET2 --user_domain=auth.$DOMAIN_NAME --user_name=focus --user_password=$YOURSECRET3 &

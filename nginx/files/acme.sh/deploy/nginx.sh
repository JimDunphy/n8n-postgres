#!/usr/bin/bash

#Here is a script to deploy cert to nginx server.
HTTPS_DIR="/etc/nginx/ssl"

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
nginx_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  cp -f "$_ckey" $HTTPS_DIR/$_cdomain/key.pem
  cp -f "$_ccert" $HTTPS_DIR/$_cdomain/cert.pem
  cp -f "$_cfullchain" $HTTPS_DIR/$_cdomain/fullchain.pem

  /bin/logger -p local2.info NETWORK "Certificate has been Renewed for $_cdomain"
  sudo systemctl reload nginx

  return 0

}

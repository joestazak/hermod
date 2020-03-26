#!/usr/bin/env bash
#
# Created by Connor O'Leary (Coleary05)
#
# Script to deploy both a front end and back end to a MUT.
#
# DETAILS:
# This script file takes care of everything. You do not need to rsync, edit files, or restart any services.
# It will do several commands over ssh which is why a password is needed.
#
# OPTIONS (** indicates required option):
# first: Indicates that this is a new MUT and requires a completely fresh deployment. Defaults to false.
# nofe: Turns OFF the front end deployment.
# nobe: Turns OFF the back end deployment.
# rflf: Folder location for remote front end. Defaults to /hart. You can also perma change it below.
# rflb: Folder location for remote back end. Defaults to /ada. You can also perma change it below. 
# lflf: Folder location for local front end. Defaults to /hart. You can also perma change it below.
# lflb: Folder location for local back end. Defaults to /ada. You can also perma change it below. 
# ** mut: MUT IP address to use. You can enter just the final octet (Ex: "255" will make 10.70.0.255)
#         or you can enter the full IP address (Ex: "10.70.0.255" will make 10.70.0.255)
# ** p: Password for sudo commands on whatever MUT you are accessing.
#
# UPCOMING:
# -- Looking into more auto-deployment and error handling for this script. Things to auto-detect if something is wrong.
# -- Git integration to pull latest develop of both and put that on a MUT.
# -- Slack integration to let the user know when the MUT is ready (although it only takes like 5 minutes to fully run)
# -- Auth0 integration to do what the /addmut command does in Slack
#

# !!! Set the following to your AWS user name before running! You can set the password here or through the p option.
USER="joe"
PASS=""

# Default variables
MUT_IP="null"
RFLF="hart"
RFLB="ada"
LFLF="ahalogy-repos/hart"
LFLB="ahalogy-repos/ada"
FE=true
BE=true
FIRST=false
CMS=false

# While loop to gather options and values
while [ -n "$1" ]; do

	case "$1" in

  -p)
    PASS="$2"
    shift
    ;;

  -first)
    FIRST=true
    ;;

  -cms)
    CMS=true
    ;;

	-nofe)
    FE=false
    ;;

	-nobe)
		BE=false
		;;

  -rflf)
    RFLF="$2"
    shift
    ;;

	-rflb)
    RFLB="$2"
    shift
    ;;

  -lflf)
    LFLF="$2"
    shift
    ;;

  -lflb)
    LFLB="$2"
    shift
    ;;

  -mut)
    MUT_IP="$2"
    shift
    ;;

	*)
    echo "Option $1 not recognized"
    ;;

	esac
	shift

done

# Check if password has been given.
if [ "$PASS" == "null" ] ; then
  echo "Password not set. Exiting..."
fi

# Set the MUT IP address.
if [ "$MUT_IP" == "null" ] ; then
  echo "MUT IP address was not set. Exiting..."
  exit 1
elif [ ${#MUT_IP} -lt 4 ] ; then
  MUT_IP="10.70.0.$MUT_IP"
fi
echo "MUT IP has been set to $MUT_IP"

# Deletes a big log file that can become a problem on first MUT deployment.
if [ "$FIRST" = true ] ; then
  echo $PASS | ssh -tt $USER@$MUT_IP "sudo rm -rf /var/log/mysql/import-ahalogy.log"
fi

# Prep and deploy the back end.
if [ "$BE" = true ] ; then
  echo "Deploying back end to $MUT_IP"

  echo "Removing old ada on MUT..."
  echo $PASS | ssh -tt $USER@$MUT_IP "sudo -u $USER bash -c rm -rf ada"
  echo "Old ada removed."

  echo "Syncing new ada and deploying..."
  cd "$HOME/$LFLB"
  mvn clean
  rsync -avz --exclude '.git' "$HOME/$LFLB" $USER@$MUT_IP:
  ECHO $PASS | ssh -tt $USER@$MUT_IP "sudo -u $USER bash -c ~/ada/deploy/deploybe.sh"

  echo "Back end deployed!"
fi

# Prep and deploy the front end.
if [ "$FE" = true ] ; then
  echo "Deploying front end to $MUT_IP"

  cd "$HOME/$LFLF"
  sed -i '' "s/10.70.0.*/$MUT_IP:8080';/" config/environment.js
  ember build --environment=mut
  rsync -avz dist $USER@$MUT_IP:

  echo $PASS | ssh -tt $USER@$MUT_IP "sudo sed -i '166 s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf && sudo rm -rf /var/www/html && sudo mv ~/dist /var/www/html && sudo service apache2 restart"

  ssh -t $USER@$MUT_IP 'cat > /var/www/html/.htaccess <<- "EOF"
  # place in [app]/public so it gets compiled into the dist folder
  Options FollowSymLinks
  <IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteRule ^index\.html$ - [L]
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule (.*) index.html [L]
  </IfModule>
  <filesMatch "\.(html|htm|js|css)$">
    FileETag None
    <ifModule mod_headers.c>
      Header unset ETag
      Header set Cache-Control "max-age=0, no-cache, no-store, must-revalidate"
      Header set Pragma "no-cache"
      Header set Expires "Wed, 11 Jan 1984 05:00:00 GMT"
    </ifModule>
  </filesMatch>
EOF
    '

  echo "Front end deployed!"
fi


# Prep and deploy the CMS command file.
if [ "$CMS" = true ] ; then
  echo "Deploying CMS command to $MUT_IP"
  cd "$HOME/$LFLB"

  mvn clean
  mvn package -DskipTests
  rsync -avz cms-common/target/cms-common-1.0-SNAPSHOT-jar-with-dependencies.jar $USER@$MUT_IP:
  echo "CMS command file is ready on MUT $MUT_IP!"
fi

echo "Script complete! Be sure to use the /addmut command in Slack to add the MUT to Auth0."

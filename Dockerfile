############################################################
# Dockerfile to build Nginx Installed Containers
# Based on Debian 9 (Stretch)
############################################################

FROM debian:stretch

# File Author / Maintainer
MAINTAINER Cam

# Copy hello world script
COPY helloworld.sh /tmp/

# Default container command
ENTRYPOINT ["/tmp/helloworld.sh"]


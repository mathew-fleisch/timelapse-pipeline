FROM ubuntu:18.04

LABEL maintainer="Mathew Fleisch <mathew.fleisch@gmail.com>"
RUN rm /bin/sh && ln -s /bin/bash /bin/sh
RUN mkdir -p /usr/timelapse

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y zip wget iputils-ping curl jq build-essential libssl-dev python python-pip python3 python3-pip file libgcrypt-dev git sudo build-essential libssl-dev awscli vim ffmpeg sqlite3
# Get newest version of awscli
RUN pip3 install awscli --upgrade --user

WORKDIR /usr/timelapse
COPY . .

RUN cat /usr/timelapse/.env >> ~/.bashrc
RUN source ~/.bashrc

CMD ["/bin/bash"]

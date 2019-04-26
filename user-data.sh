#!/bin/bash

# set agent log level to WARN
cat << EOF >> /etc/ecs/ecs.config
ECS_LOGLEVEL=warn
EOF

cat << EOF > /home/ec2-user/runtests.sh
cd /home/ec2-user/go/src/github.com/aws/amazon-ecs-agent
sudo systemctl stop ecs
make test-registry
make release
docker tag amazon/amazon-ecs-agent:latest amazon/amazon-ecs-agent:make

make test # unit tests
make run-integ-tests
# Setup functional tests
sudo sysctl -w net.ipv4.conf.all.route_localnet=1
sudo iptables -t nat -A PREROUTING -p tcp -d 169.254.170.2 --dport 80 -j DNAT --to-destination 127.0.0.1:51679
sudo iptables -t nat -A OUTPUT -d 169.254.170.2 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 51679
export TASK_IAM_ROLE_ARN="arn:aws:iam::039193556298:role/TaskIAMRoleArn"
export ECS_FTS_EXECUTION_ROLE="arn:aws:iam::039193556298:role/ecsTaskExecutionRole"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
# Run functional tests -- note: your ec2 instance will need access to your personal AWS account for these tests
make run-functional-tests
EOF

yum update -y
yum install -y wget vim git jq aws-cli zsh gcc

# change default shell to zsh and write zshrc
usermod --shell /bin/zsh ec2-user
cat << \EOF > /home/ec2-user/.zshrc
autoload -Uz compinit colors add-zsh-hook
compinit -u     # autocomplete
colors          # colors
typeset -U PATH # no dupes in PATH

gstat () {
    if test -d ".git"; then
        psvar[1]=" `git rev-parse --abbrev-ref HEAD`"
        psvar[2]=`git diff-index --quiet HEAD -- || echo "*"`
    else
        psvar[1]=""
        psvar[2]=""
    fi
}
# get git meta-information periodically, every 1s
PERIOD=1
add-zsh-hook periodic gstat
# prompt format
PROMPT="CONTAINER INST %{$fg[blue]%}%4d%{$fg[green]%}%1v%{$fg[red]%}%2v%{$fg_bold[red]%} %# %{$reset_color%}"

setopt APPEND_HISTORY SHARE_HISTORY BANG_HIST NO_BEEP INTERACTIVECOMMENTS NO_COMPLETE_ALIASES

# completion
zstyle ':completion:*' menu select
# oh-my-zsh style history completion
bindkey '\e[A' history-beginning-search-backward
bindkey '\e[B' history-beginning-search-forward
bindkey '\e[3~' delete-char # 'forward' delete key

alias gd='git diff'
alias gc='git checkout'
alias gs='git status --short'
alias gu='git fetch --all --prune &&
          git checkout master &&
          git pull origin master --tags &&
          git checkout -'
EOF

# install tig
wget -O "/tmp/tig.rpm" "http://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/t/tig-2.4.0-1.el7.x86_64.rpm"
yum install -y /tmp/tig.rpm

# install go
wget -O "/tmp/go.tar.gz" "https://dl.google.com/go/go1.12.4.linux-amd64.tar.gz"
tar -C /usr/local -xzf /tmp/go.tar.gz
echo export GOPATH="/home/ec2-user/go"  >> /home/ec2-user/.zshrc
echo export PATH=$PATH:/usr/local/go/bin >> /home/ec2-user/.zshrc

# clone amazon-ecs-agent
mkdir -p /home/ec2-user/go/src/github.com/aws
cd /home/ec2-user/go/src/github.com/aws
git clone https://github.com/sparrc/amazon-ecs-agent.git
cd amazon-ecs-agent
git config --global pull.rebase true
git config --global branch.autosetuprebase always
git remote add upstream https://github.com/aws/amazon-ecs-agent.git
git fetch --all

# chown and chgrp any files/directories created with root ownership
chown -R ec2-user /home/ec2-user
chgrp -R ec2-user /home/ec2-user


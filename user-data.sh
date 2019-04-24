#!/bin/bash

# set agent log level to WARN
cat << EOF >> /etc/ecs/ecs.config
ECS_LOGLEVEL=warn
EOF

yum update -y

# install tools
yum install -y wget vim git jq aws-cli zsh

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

HISTFILE=~/.zsh_history                            # where to store zsh config
HISTSIZE=7500                                      # lines of history to keep in mem
SAVEHIST=30000                                     # lines of history to save to file
HISTORY_IGNORE="(history|ls|pwd|exit|ll|la|clear)" # commands history ignores

setopt APPEND_HISTORY           # append
setopt HIST_IGNORE_DUPS         # no duplicate
setopt HIST_IGNORE_ALL_DUPS     # no duplicate
setopt HIST_REDUCE_BLANKS       # trim blanks
setopt SHARE_HISTORY            # share hist between sessions
setopt HIST_IGNORE_SPACE        # ignore commands prefixed by a space
setopt HIST_NO_STORE            # dont store dupes
setopt BANG_HIST                # !keyword
setopt NO_BEEP                  # no terminal beeps
setopt HIST_SAVE_NO_DUPS        # more de-duping
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS
setopt INTERACTIVECOMMENTS      # recognize comments on cli
setopt NO_COMPLETE_ALIASES      # autocomplete aliases, this seems to do the opposite of what it sounds like

# completion
zstyle ':completion:*' menu select
# oh-my-zsh style history completion
bindkey '\e[A' history-beginning-search-backward
bindkey '\e[B' history-beginning-search-forward
bindkey '\e[3~' delete-char # 'forward' delete key

# git aliases
alias gd='git diff'
alias gc='git checkout'
alias gs='git status --short'
# displays the current HEAD commit
alias gv='git rev-parse HEAD'
# show all branches
alias gb='git rev-parse --abbrev-ref HEAD'
# update remotes, checkout master, pull origin onto the master branch
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
# make a release in background
nohup make release > /home/ec2-user/make-release.out &

# chown and chgrp any files/directories created with root ownership
chown -R ec2-user /home/ec2-user
chgrp -R ec2-user /home/ec2-user


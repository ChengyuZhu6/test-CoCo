#!/usr/bin/env bash

sudo -E PATH="$PATH" bash -c './Install/operator.sh' uninstall
sudo -E PATH="$PATH" bash -c './Install/cluster/down.sh'
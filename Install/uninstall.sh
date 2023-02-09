#!/usr/bin/env bash

sudo -E PATH="$PATH" bash -c './operator.sh' uninstall
sudo -E PATH="$PATH" bash -c './cluster/down.sh'
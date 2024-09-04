#!/bin/bash

VENV_DIR='.mmai-venvs'

alias lvenv="ls $VENV_DIR"
alias dvenv="deactivate"

cvenv() {
  if (( $# == 1 )); then
    venvpath=$VENV_DIR/$1
    if [[ ! -d $venvpath && ! -f $venvpath ]]; then
      python -m venv $venvpath
    else
      echo "Cannot create venv: name already exists"
    fi
  else
    echo "Cannot create venv: 1 argument expected, $# received"
  fi
}

avenv() {
  if (( $# == 1 )); then
    activatevenvpath=$VENV_DIR/$1/bin/activate
    if [[ -f $activatevenvpath ]]; then
      source $activatevenvpath
    else
      echo "Cannot activate venv: venv does not exist"
    fi
  else
    echo "Cannot activate venv: 1 argument expected, $# received"
  fi
}

rvenv() {
  if (( $# == 1 )); then
    venvpath=$VENV_DIR/$1
    if [[ -d $venvpath ]]; then
      rm -rf $venvpath
    else
      echo "Cannot remove venv: venv does not exist"
    fi
  else
    echo "Cannot remove venv: 1 argument expected, $# received"
  fi
}

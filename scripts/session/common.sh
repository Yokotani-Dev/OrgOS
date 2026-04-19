#!/usr/bin/env bash

export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-$LC_ALL}"

trim_whitespace() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

ruby_utf8() {
  LC_ALL="${LC_ALL:-en_US.UTF-8}" LANG="${LANG:-${LC_ALL:-en_US.UTF-8}}" ruby "$@"
}

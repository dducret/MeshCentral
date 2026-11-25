#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

release=$(CDPATH= cd "$(dirname "$0")" && pwd)
exec "${MC_NODE:-node}" "$release/update.cjs" "$@"

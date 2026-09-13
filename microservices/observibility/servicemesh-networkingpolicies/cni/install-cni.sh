#!/bin/bash
# Deprecated: Calico replaced by Cilium + Hubble. Delegates to install-cilium.sh.
exec "$(dirname "$0")/install-cilium.sh" "$@"

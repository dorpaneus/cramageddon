#!/usr/bin/env bash
# SRE Pre-Flight & Day-2 Health Audit for OpenShift (OCP 4.18+)
set -euo pipefail

echo "=== 1. CLUSTER VERSION & UPGRADE CHANNEL ==="
oc get clusterversion -o custom-columns=NAME:.metadata.name,VERSION:.status.desired.version,CHANNEL:.spec.channel,PROGRESSING:.status.conditions[?(@.type==\"Progressing\")].status

echo -e "\n=== 2. DEGRADED OR UNAVAILABLE CLUSTER OPERATORS ==="
UNHEALTHY_CO=$(oc get co -o jsonpath='{range .items[*]}{.metadata.name}{" Available="}{.status.conditions[?(@.type=="Available")].status}{" Degraded="}{.status.conditions[?(@.type=="Degraded")].status}{"\n"}{end}' | grep -Ev 'Available=True Degraded=False' || true)
if [[ -z "$UNHEALTHY_CO" ]]; then
  echo "OK: All ClusterOperators are Available and not Degraded."
else
  echo "ALERT: Unhealthy ClusterOperators detected:"
  echo "$UNHEALTHY_CO"
fi

echo -e "\n=== 3. MACHINE CONFIG POOL (MCP) STATUS ==="
oc get mcp -o custom-columns=POOL:.metadata.name,UPDATED:.status.conditions[?(@.type==\"Updated\")].status,UPDATING:.status.conditions[?(@.type==\"Updating\")].status,DEGRADED:.status.conditions[?(@.type==\"Degraded\")].status,PAUSED:.spec.paused

echo -e "\n=== 4. NON-RUNNING / CRASHING PODS CLUSTER-WIDE ==="
oc get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName

echo -e "\n=== 5. RECENT CLUSTER WARNING EVENTS (LAST 10) ==="
oc get events -A --field-selector=type=Warning --sort-by=.lastTimestamp | tail -n 10

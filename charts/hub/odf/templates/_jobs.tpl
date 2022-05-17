{{- define "odf.nodeLabels" -}}
oc get nodes --show-labels | grep ocs > /dev/null
if [ $? -eq 1 ]; then
  oc label nodes -l node-role.kubernetes.io/worker= cluster.ocs.openshift.io/openshift-storage=
else
  echo "storage nodes are already labeled"
fi
{{- end -}}

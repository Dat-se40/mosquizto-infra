# EBS storage for the Mosquizto EKS lab

Coordinate this installation with the cluster/add-on owners. Do not install
alongside another EBS CSI installation. `Install-Storage.ps1` rejects an existing
managed EBS CSI add-on. It renders upstream Helm chart 2.67.1 (driver 1.67.1),
applies the tracked network patch, validates on the server and installs with
kubectl. It is not a Helm-managed release. Re-run the same script for updates.

This lab uses the existing worker `LabRole` through IMDSv2. Node metadata has hop
limit 1, so the controller and CSI node Pods use host networking. No AWS static
keys or ECR tokens are stored in Kubernetes. If the Lab denies EBS operations,
stop and request the required permissions from the Lab administrator; attaching
an IAM policy cannot override an SCP. A dedicated workload identity is the
production replacement for this lab configuration.

```powershell
./kubernetes/storage/Install-Storage.ps1 -Context mosquizto-eks -Helm helm
kubectl --context=mosquizto-eks create namespace mosquizto-storage-check
kubectl --context=mosquizto-eks -n mosquizto-storage-check apply -f kubernetes/storage/check-pvc.yaml
kubectl --context=mosquizto-eks -n mosquizto-storage-check wait pod/storage-check --for=condition=Ready --timeout=180s
kubectl --context=mosquizto-eks -n mosquizto-storage-check logs storage-check
kubectl --context=mosquizto-eks -n mosquizto-storage-check delete pod storage-check
kubectl --context=mosquizto-eks -n mosquizto-storage-check apply -f kubernetes/storage/read-pvc.yaml
kubectl --context=mosquizto-eks -n mosquizto-storage-check wait pod/storage-check --for=condition=Ready --timeout=180s
kubectl --context=mosquizto-eks -n mosquizto-storage-check logs storage-check
```

The second Pod must read `mosquizto-storage-ok` from the same Bound claim.
Before removing the test namespace, record the test PV and its EBS volume ID.
Retain intentionally leaves the EBS volume after PVC deletion. Clean up only
the recorded disposable test volume/PV after the test, never application data.

`mosquizto-gp3` explicitly selects encrypted gp3, ext4, WaitForFirstConsumer,
expansion and Retain. It is not the cluster's default StorageClass. Application
PVCs select it explicitly. This test and the application create billable EBS
volumes; they are part of the approved lab deployment, not a backup service.

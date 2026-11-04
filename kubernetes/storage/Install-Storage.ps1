[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Context,
    [string]$Helm = 'helm'
)
$ErrorActionPreference = 'Stop'
$existingAddon = & aws eks list-addons --region us-east-1 --cluster-name project11-eks-cluster --output json
if ($LASTEXITCODE -ne 0) { throw 'Cannot check managed EKS add-ons' }
if (($existingAddon | ConvertFrom-Json).addons -contains 'aws-ebs-csi-driver') {
    throw 'EBS CSI managed add-on already exists; coordinate ownership instead of installing a second driver.'
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('mosquizto-ebs-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    # Render the pinned upstream chart, then apply the controller network patch.
    # This is a kubectl-managed installation, not an additional Helm release.
    $yaml = & $Helm template aws-ebs-csi-driver aws-ebs-csi-driver `
        --repo https://kubernetes-sigs.github.io/aws-ebs-csi-driver --version 2.67.1 `
        --namespace kube-system --skip-tests --values (Join-Path $PSScriptRoot 'ebs-csi-values.yaml')
    if ($LASTEXITCODE -ne 0) { throw 'EBS CSI rendering failed' }
    [IO.File]::WriteAllLines((Join-Path $temp 'upstream.yaml'), $yaml, [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'controller-network.yaml') -Destination $temp
    $kustomization = "apiVersion: kustomize.config.k8s.io/v1beta1`nkind: Kustomization`nnamespace: kube-system`nresources: [upstream.yaml]`npatches:`n  - path: controller-network.yaml`n"
    [IO.File]::WriteAllText((Join-Path $temp 'kustomization.yaml'), $kustomization)
    & kubectl --context=$Context apply --dry-run=server -k $temp
    if ($LASTEXITCODE -ne 0) { throw 'EBS CSI server validation failed' }
    & kubectl --context=$Context apply -k $temp
    if ($LASTEXITCODE -ne 0) { throw 'EBS CSI installation failed' }
    & kubectl --context=$Context -n kube-system rollout status deployment/ebs-csi-controller --timeout=180s
    if ($LASTEXITCODE -ne 0) { throw 'EBS controller not ready' }
    & kubectl --context=$Context -n kube-system rollout status daemonset/ebs-csi-node --timeout=180s
    if ($LASTEXITCODE -ne 0) { throw 'EBS node driver not ready' }
} finally {
    # Delete only the three known generated files inside this invocation's temp folder.
    foreach ($name in @('upstream.yaml','controller-network.yaml','kustomization.yaml')) {
        $path = Join-Path $temp $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    Remove-Item -LiteralPath $temp
}
& kubectl --context=$Context apply -f (Join-Path $PSScriptRoot 'mosquizto-gp3.yaml')
if ($LASTEXITCODE -ne 0) { throw 'StorageClass creation failed' }

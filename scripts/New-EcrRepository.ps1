[CmdletBinding()]
param([string]$Region = 'us-east-1', [string]$Name = 'mosquizto-backend')
$ErrorActionPreference = 'Stop'
$all = & aws ecr describe-repositories --region $Region --output json
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect ECR repositories' }
$repository = ($all | ConvertFrom-Json).repositories | Where-Object repositoryName -eq $Name
if (-not $repository) {
    $created = & aws ecr create-repository --region $Region --repository-name $Name `
        --image-tag-mutability IMMUTABLE --encryption-configuration encryptionType=AES256 --output json
    if ($LASTEXITCODE -ne 0) { throw 'ECR repository creation failed' }
    $repository = ($created | ConvertFrom-Json).repository
}
if ($repository.imageTagMutability -ne 'IMMUTABLE') { throw 'Existing ECR repository must use immutable tags; do not change it silently.' }
Write-Output $repository.repositoryUri

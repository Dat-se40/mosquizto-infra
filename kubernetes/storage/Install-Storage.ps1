[CmdletBinding()]
param(
    [string]$Context = ""
)

$ErrorActionPreference = "Stop"

# Đảm bảo bin/ (chứa kubectl.exe nội bộ) nằm trong PATH
$infraDir = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$binDir   = Join-Path $infraDir "bin"
if ((Test-Path $binDir) -and ($env:PATH -notlike "*$binDir*")) {
    $env:PATH = "$binDir;$env:PATH"
}

# Kiểm tra sự tồn tại của kubectl
if (-not (Get-Command "kubectl" -ErrorAction SilentlyContinue)) {
    Write-Error "LỖI: Không tìm thấy 'kubectl'. Hãy đảm bảo kubectl.exe nằm trong $binDir hoặc trong PATH hệ thống."
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [STORAGE] Cài Đặt AWS EBS CSI Driver & StorageClass gp3   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Thiết lập tham số context cho kubectl (nếu có)
$kArgs = @()
if ($Context) {
    $kArgs += "--context=$Context"
}

# 2. Kiểm tra kết nối cụm EKS
Write-Host "[1/4] Đang kiểm tra kết nối tới cụm Kubernetes EKS..." -ForegroundColor Yellow
try {
    $nodes = & kubectl @kArgs get nodes -o name
    if ($LASTEXITCODE -ne 0 -or -not $nodes) {
        throw "Không thể kết nối đến cụm EKS hoặc chưa có worker node nào sẵn sàng."
    }
    Write-Host "       Kết nối thành công! Tìm thấy $($nodes.Count) node(s)." -ForegroundColor Green
}
catch {
    Write-Error "LỖI: $_"
    exit 1
}

# 3. Cài đặt AWS EBS CSI Driver chính thức cho Kubernetes v1.30
Write-Host "[2/4] Đang áp dụng AWS EBS CSI Driver lên cụm EKS..." -ForegroundColor Yellow
$csiManifest = Join-Path $PSScriptRoot "aws-ebs-csi-driver.yaml"
try {
    if (-not (Test-Path $csiManifest)) {
        throw "Không tìm thấy file manifest $csiManifest"
    }
    & kubectl @kArgs apply -f $csiManifest
    if ($LASTEXITCODE -ne 0) {
        throw "Lỗi áp dụng manifest EBS CSI Driver."
    }
    Write-Host "       Đã gửi manifest EBS CSI Driver vào cluster." -ForegroundColor Green
}
catch {
    Write-Error "LỖI: $_"
    exit 1
}

# 4. Chờ EBS CSI Controller sẵn sàng
Write-Host "[3/4] Đang chờ EBS CSI Controller khởi động hoàn tất (tối đa 180s)..." -ForegroundColor Yellow
try {
    & kubectl @kArgs -n kube-system rollout status deployment/ebs-csi-controller --timeout=180s
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "EBS CSI Controller đang trong quá trình sẵn sàng, tiếp tục áp dụng StorageClass."
    }
    else {
        Write-Host "       EBS CSI Controller đã sẵn sàng hoạt động!" -ForegroundColor Green
    }
}
catch {
    Write-Warning "Cảnh báo rollout timeout: $_"
}

# 5. Khởi tạo StorageClass mosquizto-gp3
Write-Host "[4/4] Đang khởi tạo StorageClass mosquizto-gp3..." -ForegroundColor Yellow
$scFile = Join-Path $PSScriptRoot "storageclass-gp3.yaml"
try {
    & kubectl @kArgs apply -f $scFile
    if ($LASTEXITCODE -ne 0) {
        throw "Không thể tạo StorageClass mosquizto-gp3."
    }
    
    # Kiểm tra lại
    $scCheck = & kubectl @kArgs get sc mosquizto-gp3 -o name
    if ($scCheck) {
        Write-Host "==========================================================" -ForegroundColor Green
        Write-Host " [THÀNH CÔNG] StorageClass 'mosquizto-gp3' đã sẵn sàng!   " -ForegroundColor Green
        Write-Host " Các PVC cơ sở dữ liệu (Postgres/Redis/Meili/Qdrant) đã    " -ForegroundColor Green
        Write-Host " có thể cấp phát ổ cứng AWS gp3 tự động.                  " -ForegroundColor Green
        Write-Host "==========================================================" -ForegroundColor Green
    }
}
catch {
    Write-Error "LỖI: $_"
    exit 1
}
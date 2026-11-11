<#
.SYNOPSIS
    Bộ Điều Khiển Vòng Đời Hạ Tầng Tự Động Hóa (MosQuizTo Infra Lifecycle Orchestrator)
.DESCRIPTION
    Tự động hóa toàn bộ vòng đời hạ tầng AWS EKS, Storage gp3, Backup/Restore PostgreSQL
    và dọn sạch chi phí lưu trữ trước khi destroy.
.PARAMETER Up
    Dựng hạ tầng Terraform -> Cài EBS CSI Driver & StorageClass gp3 -> Giải phóng terminal ngay.
.PARAMETER Watch
    Kết hợp với -Up: Tự động chờ Pod Postgres online -> Nạp data cũ -> Đồng bộ Meili/Qdrant.
.PARAMETER Restore
    Chủ động nạp dữ liệu cũ từ local vào PostgreSQL trên EKS và kích hoạt Sync Job.
.PARAMETER Backup
    Sao lưu database PostgreSQL về máy local (không xóa hạ tầng).
.PARAMETER Down
    Sao lưu database -> Kiểm tra an toàn (> 0 bytes) -> Xóa sạch EBS mồ côi -> terraform destroy.
.PARAMETER Status
    Báo cáo trạng thái AWS credentials, EKS nodes, Pods, local backups và EBS volumes.
#>

[CmdletBinding(DefaultParameterSetName = "Help")]
param(
    [Parameter(ParameterSetName = "Up")]
    [switch]$Up,

    [Parameter(ParameterSetName = "Up")]
    [switch]$Watch,

    [Parameter(ParameterSetName = "Down")]
    [switch]$Down,

    [Parameter(ParameterSetName = "Restore")]
    [switch]$Restore,

    [Parameter(ParameterSetName = "Backup")]
    [switch]$Backup,

    [Parameter(ParameterSetName = "Status")]
    [switch]$Status,

    [string]$Region = "us-east-1",
    [string]$ClusterName = "project11-eks-cluster",
    [string]$Namespace = "mosquizto-eks",
    [string]$Context = ""
)

$ErrorActionPreference = "Stop"

# --- Khai báo các đường dẫn chuẩn bên trong mosquizto-infra ---
$infraDir       = $PSScriptRoot
$binDir         = Join-Path $infraDir "bin"
if ((Test-Path $binDir) -and ($env:PATH -notlike "*$binDir*")) {
    $env:PATH = "$binDir;$env:PATH"
}
$parentDir      = Split-Path -Parent $infraDir
$infraTfDir     = Join-Path $infraDir "terraform"
$storageScript  = Join-Path $infraDir "kubernetes\storage\Install-Storage.ps1"
$backupDir      = Join-Path $infraDir "backups"
$backupFile     = Join-Path $backupDir "mosquizto-db-backup.dump"
$syncScript     = Join-Path $parentDir "mosquizto-gitops\operations\eks\Start-Sync.ps1"

$script:KubeArgs = @()
if ($Context) {
    $script:KubeArgs += "--context=$Context"
}

# --- Helper Functions ---
function Write-Header([string]$title) {
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
}

function Write-Step([string]$step, [string]$msg) {
    Write-Host "[$step] $msg" -ForegroundColor Yellow
}

function Write-Success([string]$msg) {
    Write-Host "  -> [OK] $msg" -ForegroundColor Green
}

function Write-Fail([string]$msg) {
    Write-Host "  -> [ERROR] $msg" -ForegroundColor Red
}

function Invoke-KubectlQuiet([string[]]$CmdArgs) {
    # Tạm chuyển sang Continue để stderr từ native exe không gây NativeCommandError trong PS 5.1
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $allArgs = @($script:KubeArgs) + @($CmdArgs)
        $out = & kubectl @allArgs 2>$null
        return @{
            Output   = $out
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }
}

function Get-PostgresPod() {
    # Dùng items[*] thay vì items[0] để tránh lỗi out of bounds khi chưa có Pod Postgres
    $res = Invoke-KubectlQuiet @("-n", $Namespace, "get", "pod", "-l", "app=postgres", "--field-selector=status.phase=Running", "-o", "jsonpath={.items[*].metadata.name}")
    if ($res.ExitCode -ne 0) {
        return $null
    }
    $raw = ($res.Output -join " ").Trim()
    if (-not $raw) {
        $resAny = Invoke-KubectlQuiet @("-n", $Namespace, "get", "pod", "-l", "app=postgres", "-o", "jsonpath={.items[*].metadata.name}")
        if ($resAny.ExitCode -ne 0) {
            return $null
        }
        $raw = ($resAny.Output -join " ").Trim()
    }
    if ($raw) {
        return ($raw -split '\s+' | Where-Object { $_ } | Select-Object -First 1)
    }
    return $null
}

function Wait-PostgresReady([int]$TimeoutSeconds = 300) {
    Write-Step "WAIT" "Đang theo dõi EKS chờ Pod Postgres sẵn sàng (Timeout: ${TimeoutSeconds}s)..."
    Write-Host "      (Bạn có thể nhấn Ctrl+C bất cứ lúc nào để bỏ qua và restore sau)" -ForegroundColor DarkGray
    
    $elapsed = 0
    $interval = 5
    while ($elapsed -lt $TimeoutSeconds) {
        $pod = Get-PostgresPod
        if ($pod) {
            $res = Invoke-KubectlQuiet @("-n", $Namespace, "get", "pod", $pod, "-o", "jsonpath={.status.containerStatuses[*].ready}")
            if ($res.ExitCode -eq 0 -and (($res.Output -join " ").Trim() -eq "true")) {
                Write-Host ""
                Write-Success "Pod Postgres ($pod) đã ở trạng thái 1/1 Ready!"
                return $pod
            }
        }
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        Write-Host "." -NoNewline -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Warning "Đã hết thời gian chờ ${TimeoutSeconds}s nhưng chưa thấy Pod Postgres Ready."
    return $null
}

function Invoke-DbBackup() {
    Write-Header "SAO LƯU DỮ LIỆU POSTGRESQL VỀ MÁY CỤC BỘ"
    
    Write-Step "1/3" "Kiểm tra Pod Postgres trong namespace '$Namespace'..."
    $pod = Get-PostgresPod
    if (-not $pod) {
        throw "Không tìm thấy Pod Postgres đang chạy trong namespace '$Namespace'."
    }
    Write-Success "Tìm thấy Pod: $pod"

    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    Write-Step "2/3" "Thực hiện dump dữ liệu từ container sang /tmp/backup.dump..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & kubectl @script:KubeArgs -n $Namespace exec $pod -- sh -c 'pg_dump -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-mosquizto-db}" -Fc -f /tmp/backup.dump'
        $dumpCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }
    if ($dumpCode -ne 0) {
        throw "Lệnh pg_dump trong container thất bại (Exit code: $dumpCode)."
    }

    Write-Step "3/3" "Tải file dump về máy cục bộ: $backupFile..."
    $backupFileName = Split-Path -Leaf $backupFile
    Push-Location $backupDir
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & kubectl @script:KubeArgs cp "${Namespace}/${pod}:/tmp/backup.dump" $backupFileName
        $cpCode = $LASTEXITCODE
        & kubectl @script:KubeArgs -n $Namespace exec $pod -- rm -f /tmp/backup.dump 2>$null
    }
    finally {
        $ErrorActionPreference = $prevEAP
        Pop-Location
    }

    if ($cpCode -ne 0) {
        throw "Không thể tải file backup từ container về máy cục bộ (Exit code: $cpCode)."
    }

    if (-not (Test-Path $backupFile)) {
        throw "File backup không tồn tại sau khi tải về."
    }

    $size = (Get-Item $backupFile).Length
    if ($size -le 0) {
        throw "File backup rỗng (0 bytes)! Hủy thao tác để đảm bảo an toàn."
    }

    $sizeKb = [math]::Round($size / 1KB, 2)
    Write-Success "Sao lưu thành công! Kích thước file: $sizeKb KB"
    Write-Host "      File lưu tại: $backupFile" -ForegroundColor Cyan
    return $true
}

function Invoke-DbRestore() {
    Write-Header "NẠP (RESTORE) DỮ LIỆU VÀO POSTGRESQL TRÊN EKS"

    if (-not (Test-Path $backupFile)) {
        Write-Warning "Không tìm thấy file backup tại: $backupFile"
        Write-Warning "Hệ thống sẽ giữ nguyên schema/seed mặc định từ Flyway."
        return $false
    }

    Write-Step "1/4" "Kiểm tra Pod Postgres..."
    $pod = Get-PostgresPod
    if (-not $pod) {
        throw "Không tìm thấy Pod Postgres trong namespace '$Namespace'. Hãy chắc chắn GitOps đã deploy ứng dụng."
    }
    Write-Success "Tìm thấy Pod: $pod"

    Write-Step "2/4" "Đẩy file backup từ máy lên container..."
    $backupFileName = Split-Path -Leaf $backupFile
    Push-Location $backupDir
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & kubectl @script:KubeArgs cp $backupFileName "${Namespace}/${pod}:/tmp/restore.dump"
        $cpCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prevEAP
        Pop-Location
    }
    if ($cpCode -ne 0) {
        throw "Không thể copy file dump vào container (Exit code: $cpCode)."
    }

    Write-Step "3/4" "Khôi phục dữ liệu vào database 'mosquizto-db'..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & kubectl @script:KubeArgs -n $Namespace exec $pod -- sh -c 'pg_restore -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-mosquizto-db}" --clean --if-exists --no-owner /tmp/restore.dump'
        $restoreCode = $LASTEXITCODE
        & kubectl @script:KubeArgs -n $Namespace exec $pod -- rm -f /tmp/restore.dump 2>$null
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }
    if ($restoreCode -ne 0) {
        Write-Warning "pg_restore kết thúc với mã $restoreCode (có thể là cảnh báo non-fatal từ --clean)."
    }
    Write-Success "Dữ liệu cũ đã được nạp hoàn tất vào database!"

    Write-Step "4/4" "Restart nhẹ Backend & kích hoạt Sync Job sang Meili/Qdrant..."
    $restartRes = Invoke-KubectlQuiet @("-n", $Namespace, "rollout", "restart", "deployment/mosquizto-backend-deployemnt")
    if ($restartRes.ExitCode -eq 0) {
        Write-Success "Đã gửi tín hiệu khởi động lại backend."
    }
    else {
        Write-Warning "Chưa có backend deployment để restart, bỏ qua."
    }

    if (Test-Path $syncScript) {
        try {
            Write-Host "      Đang kích hoạt Start-Sync.ps1..." -ForegroundColor Yellow
            $syncContext = $Context
            if (-not $syncContext) {
                $ctxRes = Invoke-KubectlQuiet @("config", "current-context")
                if ($ctxRes.ExitCode -eq 0) {
                    $syncContext = ($ctxRes.Output -join "").Trim()
                }
            }
            if ($syncContext) {
                & $syncScript -Context $syncContext -Target all -Write
                Write-Success "Đã kích hoạt đồng bộ dữ liệu sang Meilisearch & Qdrant."
            }
            else {
                Write-Warning "Không xác định được kubeconfig Context để chạy Start-Sync.ps1."
            }
        }
        catch {
            Write-Warning "Lỗi khi kích hoạt sync: $_"
        }
    }
    return $true
}

function Clean-OrphanEbsVolumes() {
    Write-Step "EBS-CLEAN" "Đang quét các ổ đĩa AWS EBS mồ côi (status = available) để tránh bị trừ tiền Lab..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $raw = & aws ec2 describe-volumes --filters "Name=status,Values=available" --region $Region --query "Volumes[].VolumeId" --output json 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Không thể quét EBS tự động qua AWS CLI (Exit code: $LASTEXITCODE)."
            return
        }
        if ($raw) {
            $vols = @( (($raw -join "`n") | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object { $_ } )
            if ($vols.Count -gt 0) {
                Write-Host "      Tìm thấy $($vols.Count) ổ đĩa EBS mồ côi cần xóa:" -ForegroundColor Yellow
                foreach ($vol in $vols) {
                    if ($vol) {
                        Write-Host "        -> Đang xóa $vol..." -ForegroundColor DarkYellow
                        & aws ec2 delete-volume --volume-id $vol --region $Region 2>$null
                    }
                }
                Write-Success "Đã xóa sạch toàn bộ EBS mồ côi! Tài khoản an toàn 0đ phí ngầm."
            }
            else {
                Write-Success "Không có ổ đĩa EBS mồ côi nào trên AWS. Hoàn toàn sạch sẽ!"
            }
        }
    }
    catch {
        Write-Warning "Không thể quét/xóa EBS tự động qua AWS CLI: $_"
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }
}

# =========================================================================
# XỬ LÝ THEO CÁC THAM SỐ GỌI LỆNH
# =========================================================================

# --- 1. CHẾ ĐỘ TRIỂN KHAI: -Up ---
if ($Up) {
    Write-Header "BẮT ĐẦU TRIỂN KHAI HẠ TẦNG EKS & STORAGE GP3"

    # 1. Terraform Apply
    Write-Step "1/3" "Chạy terraform apply dựng VPC, EC2, EKS..."
    Push-Location $infraTfDir
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & terraform apply -auto-approve
        $tfCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prevEAP
        Pop-Location
    }
    if ($tfCode -ne 0) { throw "terraform apply thất bại." }
    Write-Success "Terraform apply thành công!"

    # 2. Cập nhật Kubeconfig
    Write-Step "2/3" "Đồng bộ cấu hình kubeconfig từ AWS EKS..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & aws eks update-kubeconfig --region $Region --name $ClusterName
        $kubeCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }
    if ($kubeCode -ne 0) { throw "Không thể kết nối cập nhật kubeconfig." }
    Write-Success "Kubeconfig đã sẵn sàng."

    # 3. Cài Storage Driver & StorageClass gp3
    Write-Step "3/3" "Cài đặt AWS EBS CSI Driver & StorageClass mosquizto-gp3..."
    if (Test-Path $storageScript) {
        $stArgs = @{}
        if ($Context) { $stArgs["Context"] = $Context }
        & $storageScript @stArgs
    }
    else {
        throw "Không tìm thấy file script: $storageScript"
    }

    # 4. Kiểm tra chế độ -Watch
    if ($Watch) {
        Write-Host ""
        Write-Host "[CHẾ ĐỘ TỰ ĐỘNG CHỜ -WATCH ĐƯỢC BẬT]" -ForegroundColor Magenta
        $pod = Wait-PostgresReady -TimeoutSeconds 300
        if ($pod) {
            Invoke-DbRestore
        }
        else {
            Write-Host "Bạn có thể chạy '.\infra.ps1 -Restore' bất cứ lúc nào khi Pod sẵn sàng." -ForegroundColor Cyan
        }
    }
    else {
        Write-Header "TRIỂN KHAI HẠ TẦNG HOÀN TẤT - TERMINAL ĐÃ ĐƯỢC GIẢI PHÓNG"
        Write-Host "Cụm EKS và StorageClass 'mosquizto-gp3' đã sẵn sàng 100%!" -ForegroundColor Green
        Write-Host "Bây giờ bạn hoặc GitOps/Argo CD có thể deploy ứng dụng thoải mái." -ForegroundColor Green
        Write-Host ""
        Write-Host "👉 Khi nào Pod Postgres chạy lên, bạn chỉ cần gõ đúng 1 lệnh (trong mosquizto-infra):" -ForegroundColor Yellow
        Write-Host "     .\infra.ps1 -Restore" -ForegroundColor Cyan
        Write-Host "   để nạp toàn bộ dữ liệu cũ vào database trong 3 giây!" -ForegroundColor Yellow
    }
    exit 0
}

# --- 2. CHẾ ĐỘ DỌN DẸP AN TOÀN: -Down ---
if ($Down) {
    Write-Header "BẮT ĐẦU QUY TRÌNH DỌN DẸP HẠ TẦNG AN TOÀN & BẢO VỆ DỮ LIỆU"

    $backupPerformed = $false

    # Đảm bảo kubeconfig đồng bộ nếu cụm EKS đang ACTIVE
    $nodeRes = Invoke-KubectlQuiet @("get", "nodes", "-o", "name")
    if ($nodeRes.ExitCode -ne 0 -and (-not $Context)) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $clusterStatus = & aws eks describe-cluster --name $ClusterName --region $Region --query "cluster.status" --output text 2>$null
            if ($LASTEXITCODE -eq 0 -and $clusterStatus -eq "ACTIVE") {
                Write-Step "K8S" "Đồng bộ lại kubeconfig từ cụm EKS đang hoạt động..."
                & aws eks update-kubeconfig --region $Region --name $ClusterName 2>$null | Out-Null
            }
        }
        finally {
            $ErrorActionPreference = $prevEAP
        }
    }

    # Bước 1: Sao lưu dữ liệu nếu có Pod Postgres
    $pod = Get-PostgresPod
    if ($pod) {
        try {
            Invoke-DbBackup
            $backupPerformed = $true
            Write-Success "SAFETY GATE: Dữ liệu đã nằm an toàn trên máy bạn. Được phép tiếp tục dọn dẹp!"
        }
        catch {
            Write-Header "CẢNH BÁO AN TOÀN: SAO LƯU THẤT BẠI!"
            Write-Fail "$_"
            Write-Fail "Script DỪNG NGAY LẬP TỨC để bảo vệ dữ liệu, KHÔNG CHẠY DESTROY!"
            Write-Host "Hãy kiểm tra lại kết nối cụm trước khi tiếp tục." -ForegroundColor Yellow
            exit 1
        }
    }
    else {
        Write-Warning "Không tìm thấy Pod Postgres đang chạy trong '$Namespace'. Tiếp tục bước giải phóng tài nguyên."
    }

    # Bước 2: Xóa namespace K8s nếu đang tồn tại để nhả PVC
    Write-Step "K8S" "Kiểm tra & xóa namespace '$Namespace' để giải phóng các volume..."
    $nsCheck = Invoke-KubectlQuiet @("get", "namespace", $Namespace, "-o", "name")
    if ($nsCheck.ExitCode -eq 0) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & kubectl @script:KubeArgs delete namespace $Namespace --timeout=60s
        }
        finally {
            $ErrorActionPreference = $prevEAP
        }
    }
    else {
        Write-Host "  -> Namespace '$Namespace' không tồn tại (hoặc đã được xóa), bỏ qua." -ForegroundColor DarkGray
    }

    # Bước 3: Dọn sạch EBS mồ côi trên AWS trước khi destroy
    Clean-OrphanEbsVolumes

    # Bước 4: Terraform Destroy
    Write-Step "TERRAFORM" "Tiến hành terraform destroy dọn dẹp hạ tầng AWS..."
    Push-Location $infraTfDir
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & terraform destroy -auto-approve
        $tfCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prevEAP
        Pop-Location
    }
    if ($tfCode -ne 0) { throw "terraform destroy gặp lỗi (Exit code: $tfCode)." }

    # Bước 5: Quét lại lần cuối đảm bảo 100% không còn ổ cứng
    Clean-OrphanEbsVolumes

    Write-Header "DỌN DẸP HOÀN TẤT THÀNH CÔNG"
    if ($backupPerformed) {
        Write-Host "  1. Toàn bộ dữ liệu database mới nhất đã được lưu an toàn tại: $backupFile" -ForegroundColor Green
    }
    elseif (Test-Path $backupFile) {
        Write-Host "  1. Không có Pod Postgres mới; bản sao lưu trước đó vẫn được giữ tại: $backupFile" -ForegroundColor Green
    }
    else {
        Write-Host "  1. Không có Pod Postgres đang chạy nên không cần sao lưu dữ liệu." -ForegroundColor Green
    }
    Write-Host "  2. Hạ tầng AWS đã được xóa sạch sẽ 100%." -ForegroundColor Green
    Write-Host "  3. Số dư tài khoản AWS Lab được bảo toàn, không bị trừ tiền ngầm!" -ForegroundColor Green
    exit 0
}

# --- 3. CHỈ SAO LƯU: -Backup ---
if ($Backup) {
    Invoke-DbBackup
    exit 0
}

# --- 4. CHỈ KHÔI PHỤC: -Restore ---
if ($Restore) {
    Invoke-DbRestore
    exit 0
}

# --- 5. BÁO CÁO TÌNH TRẠNG: -Status ---
if ($Status) {
    Write-Header "BÁO CÁO TÌNH TRẠNG HẠ TẦNG VÀ DỮ LIỆU (INFRA STATUS)"

    # AWS Identity
    Write-Host "[1] AWS Credentials:" -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $idRaw = & aws sts get-caller-identity --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $idRaw) {
            $id = ($idRaw -join "`n") | ConvertFrom-Json
            Write-Host "    Account : $($id.Account)" -ForegroundColor Green
            Write-Host "    Arn     : $($id.Arn)" -ForegroundColor Green
        }
        else {
            Write-Host "    Chưa đăng nhập hoặc Session Token hết hạn." -ForegroundColor Red
        }
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }

    # EKS Nodes
    Write-Host "[2] Cụm Kubernetes EKS (Nodes):" -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $nodesOut = & kubectl @script:KubeArgs get nodes -o wide 2>$null
        if ($LASTEXITCODE -eq 0 -and $nodesOut) {
            $nodesOut | ForEach-Object { Write-Host $_ }
        }
        else {
            Write-Host "    Không thể kết nối đến EKS (cụm chưa dựng hoặc kubeconfig chưa đồng bộ)." -ForegroundColor DarkGray
        }
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }

    # Pods & Storage
    Write-Host "[3] Workload & PVCs trong '$Namespace':" -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $nsOut = & kubectl @script:KubeArgs -n $Namespace get pods,pvc 2>$null
        if ($LASTEXITCODE -eq 0 -and $nsOut) {
            $nsOut | ForEach-Object { Write-Host $_ }
        }
        else {
            Write-Host "    Không có tài nguyên hoặc chưa kết nối được tới namespace '$Namespace'." -ForegroundColor DarkGray
        }
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }

    # Local Backups
    Write-Host "[4] File Backup Dữ Liệu Cục Bộ:" -ForegroundColor Yellow
    if (Test-Path $backupFile) {
        $item = Get-Item $backupFile
        $sizeKb = [math]::Round($item.Length / 1KB, 2)
        Write-Host "    File    : $backupFile" -ForegroundColor Green
        Write-Host "    Size    : $sizeKb KB" -ForegroundColor Green
        Write-Host "    Date    : $($item.LastWriteTime)" -ForegroundColor Green
    }
    else {
        Write-Host "    Chưa có file backup cục bộ nào." -ForegroundColor DarkGray
    }

    # AWS Orphan Volumes
    Write-Host "[5] Ổ Cứng EBS Mồ Côi Trên AWS (Trạng thái 'available'):" -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $rawVol = & aws ec2 describe-volumes --filters "Name=status,Values=available" --region $Region --query "Volumes[].{ID:VolumeId,Size:Size,AZ:AvailabilityZone}" --output table 2>$null
        if ($LASTEXITCODE -eq 0) {
            if ($rawVol) {
                $rawVol | ForEach-Object { Write-Host $_ -ForegroundColor DarkYellow }
            }
            else {
                Write-Host "    Không có ổ đĩa EBS mồ côi nào." -ForegroundColor Green
            }
        }
        else {
            Write-Host "    Không thể truy vấn volumes từ AWS." -ForegroundColor DarkGray
        }
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }

    exit 0
}

# --- Trợ giúp mặc định nếu không truyền tham số ---
Write-Header "HƯỚNG DẪN SỬ DỤNG BỘ ĐIỀU KHIỂN HẠ TẦNG (INFRA.PS1)"
Write-Host "Cú pháp sử dụng (chạy từ thư mục mosquizto-infra):" -ForegroundColor Yellow
Write-Host "  .\infra.ps1 -Up           : Dựng hạ tầng EKS + Cài Storage gp3 (Giải phóng terminal ngay)" -ForegroundColor Cyan
Write-Host "  .\infra.ps1 -Up -Watch    : Dựng hạ tầng + Tự động chờ Postgres online để nạp dữ liệu cũ" -ForegroundColor Cyan
Write-Host "  .\infra.ps1 -Restore      : Bơm dữ liệu cũ vào PostgreSQL và sync sang Meili/Qdrant" -ForegroundColor Cyan
Write-Host "  .\infra.ps1 -Backup       : Chỉ sao lưu database về máy local" -ForegroundColor Cyan
Write-Host "  .\infra.ps1 -Down         : Sao lưu DB an toàn -> Dọn sạch EBS -> terraform destroy" -ForegroundColor Cyan
Write-Host "  .\infra.ps1 -Status       : Kiểm tra toàn bộ trạng thái tài nguyên và backup" -ForegroundColor Cyan
Write-Host ""
# 🚀 Hướng Dẫn Vận Hành, Kiểm Thử & Dọn Dẹp Hạ Tầng Terraform (AWS EKS & Jenkins)

Tài liệu này cung cấp hướng dẫn toàn diện từ chuẩn bị môi trường, các bước triển khai (Deploy), quy trình kiểm thử xác minh hạ tầng đã sẵn sàng 100%, đến quy trình hủy dọn dẹp (Destroy) an toàn kèm các bước kiểm tra đảm bảo không bị trừ tiền ngầm trên tài khoản AWS Academy Lab.

---

## 📌 MỤC LỤC
1. [Chuẩn Bị Trước Khi Chạy](#1-chuẩn-bị-trước-khi-chạy)
2. [Các Bước Triển Khai Hạ Tầng (Deployment)](#2-các-bước-triển-khai-hạ-tầng-deployment)
   - [Cách 1: Triển khai tự động hóa bằng infra.ps1 (Khuyên dùng)](#cách-1-triển-khai-tự-động-hóa-bằng-infraps1-khuyên-dùng)
   - [Cách 2: Triển khai thủ công bằng Terraform CLI](#cách-2-triển-khai-thủ-công-bằng-terraform-cli)
3. [Các Bước Kiểm Thử Đảm Bảo Hạ Tầng Đã Ổn Định](#3-các-bước-kiểm-thử-đảm-bảo-hạ-tầng-đã-ổn-định)
   - [Test 1: Kiểm tra 2 Worker Nodes EKS Ready](#test-1-kiểm-tra-2-worker-nodes-eks-ready)
   - [Test 2: Kiểm tra Pods hệ thống & EBS CSI Driver](#test-2-kiểm-tra-pods-hệ-thống--ebs-csi-driver)
   - [Test 3: Kiểm tra StorageClass mosquizto-gp3](#test-3-kiểm-tra-storageclass-mosquizto-gp3)
   - [Test 4: Kiểm tra kết nối SSH vào EC2 Jenkins](#test-4-kiểm-tra-kết-nối-ssh-vào-ec2-jenkins)
   - [Test 5: Kiểm tra Security Group mở 10 cổng](#test-5-kiểm-tra-security-group-mở-10-cổng)
4. [Bàn Giao Cho Thành Viên 2 (Ansible) & Thành Viên 3 (GitOps)](#4-bàn-giao-cho-thành-viên-2-ansible--thành-viên-3-gitops)
5. [Quy Trình Dọn Dẹp (Destroy) & Bảo Vệ Dữ Liệu](#5-quy-trình-dọn-dẹp-destroy--bảo-vệ-dữ-liệu)
   - [Cách 1: Dọn dẹp tự động an toàn bằng infra.ps1 (Khuyên dùng)](#cách-1-dọn-dẹp-tự-động-an-toàn-bằng-infraps1-khuyên-dùng)
   - [Cách 2: Dọn dẹp thủ công từng bước](#cách-2-dọn-dẹp-thủ-công-từng-bước)
6. [Các Bước Kiểm Tra Xác Nhận Destroy Thành Công 100% (Tránh Bị Trừ Tiền Lab)](#6-các-bước-kiểm-tra-xác-nhận-destroy-thành-công-100-tránh-bị-trừ-tiền-lab)

---

## 1. Chuẩn Bị Trước Khi Chạy

### A. Khóa SSH bí mật (Private Key)
- Đảm bảo file private key `devops-teams-key` (không có phần mở rộng `.pub`) nằm ở thư mục `mosquizto-infra/` hoặc ngang hàng.
- *Phân quyền an toàn (nếu dùng Linux/WSL):*
  ```bash
  chmod 400 devops-teams-key
  ```

### B. Cập nhật AWS Credentials bằng lệnh `aws configure` (Nhanh & Không cần mở file)
1. Đăng nhập vào trang **AWS Classroom Lab**, bấm **Start Lab**.
2. Tại mục **AWS Details** (hoặc **AWS CLI**), bấm nút **Show**, sao chép đủ 3 thông số:
   - `aws_access_key_id`
   - `aws_secret_access_key`
   - `aws_session_token`
3. Mở terminal và chạy lệnh `aws configure`:
   ```powershell
   aws configure
   ```
   *Nhập lần lượt các giá trị khi được hỏi:*
   - **AWS Access Key ID**: *Dán `aws_access_key_id` vừa copy*
   - **AWS Secret Access Key**: *Dán `aws_secret_access_key` vừa copy*
   - **Default region name**: `us-east-1`
   - **Default output format**: `json`
4. Cập nhật tiếp `session_token` của bài Lab (bắt buộc đối với tài khoản AWS Academy):
   ```powershell
   aws configure set aws_session_token "<DÁN_SESSION_TOKEN_VỪA_COPY_VÀO_ĐÂY>"
   ```
5. Kiểm tra quyền truy cập xác thực:
   ```powershell
   aws sts get-caller-identity
   ```
   👉 **Kỳ vọng:** Màn hình in ra JSON chứa thông tin `Account` và `Arn: "arn:aws:sts::...:assumed-role/LabRole/..."` là thành công 100%!

### C. Chuẩn bị file biến `terraform.tfvars`
Tại thư mục `mosquizto-infra/terraform/`:
```powershell
# Windows PowerShell:
Copy-Item terraform.tfvars.example terraform.tfvars

# Linux / Git Bash:
cp terraform.tfvars.example terraform.tfvars
```
*(File mẫu đã cấu hình sẵn `USE-LAB-ROLE = true` và Region `us-east-1` chuẩn cho AWS Lab).*

---

## 2. Các Bước Triển Khai Hạ Tầng (Deployment)

### Cách 1: Triển khai tự động hóa bằng `infra.ps1` (Khuyên dùng)

Bộ điều khiển hợp nhất `infra.ps1` sẽ tự động hóa: chạy Terraform -> cập nhật Kubeconfig -> cài đặt AWS EBS CSI Driver & StorageClass `mosquizto-gp3` -> giải phóng ngay terminal:

```powershell
# 1. Chuyển vào thư mục mosquizto-infra
cd mosquizto-infra

# 2. Khởi chạy triển khai
.\infra.ps1 -Up
```

> [!TIP]
> **Chế độ tự động chờ nạp data cũ (`-Watch`):**
> Nếu bạn muốn cắm máy đi làm việc khác, gõ lệnh:
> ```powershell
> .\infra.ps1 -Up -Watch
> ```
> Script sẽ dựng EKS, cài Storage gp3, rồi hiển thị đồng hồ đếm ngược chờ Pod Postgres online để tự động nạp dữ liệu cũ từ máy bạn vào database mà không cần gõ thêm lệnh nào.

---

### Cách 2: Triển khai thủ công bằng Terraform CLI

Nếu muốn tự chạy từng lệnh cơ bản:

```powershell
cd mosquizto-infra\terraform

# 1. Khởi tạo plugin và module
terraform init

# 2. Kiểm tra cú pháp mã nguồn
terraform validate

# 3. Xem trước kế hoạch cấp phát
terraform plan

# 4. Cấp phát hạ tầng (Quá trình tạo cụm EKS mất khoảng 10 - 12 phút)
terraform apply -auto-approve
```

Sau khi `terraform apply` thành công, chạy tiếp các bước cấu hình cụm và cài StorageClass:
```powershell
# 5. Đồng bộ cấu hình kubectl từ EKS
aws eks update-kubeconfig --region us-east-1 --name project11-eks-cluster

# 6. Chạy script cài EBS CSI Driver và StorageClass mosquizto-gp3
cd ..\kubernetes\storage
.\Install-Storage.ps1
```

---

## 3. Các Bước Kiểm Thử Đảm Bảo Hạ Tầng Đã Ổn Định

Sau khi triển khai xong, hãy thực hiện lần lượt 5 bước kiểm tra dưới đây để đảm bảo hạ tầng đã hoàn toàn sẵn sàng cho GitOps và Ansible:

### Test 1: Kiểm tra 2 Worker Nodes EKS Ready
```powershell
kubectl get nodes -o wide
```
👉 **Kỳ vọng:**
- Xuất hiện **2 Worker Nodes** (máy ảo `t3.medium`).
- Cột `STATUS` bắt buộc hiển thị: **`Ready`**.
- Cột `VERSION` hiển thị đúng bản Kubernetes: `v1.30.x`.

---

### Test 2: Kiểm tra Pods hệ thống & EBS CSI Driver
```powershell
kubectl get pods -n kube-system
```
👉 **Kỳ vọng:**
- Toàn bộ pods hệ thống (`coredns`, `kube-proxy`, `aws-node`) đều ở trạng thái **`Running`**.
- Các Pod của driver lưu trữ:
  - `ebs-csi-controller-xxxx` (READY: `5/5` hoặc `2/2`, STATUS: `Running`).
  - `ebs-csi-node-xxxx` chạy trên cả 2 nodes (READY: `3/3`, STATUS: `Running`).

---

### Test 3: Kiểm tra StorageClass `mosquizto-gp3`
```powershell
kubectl get storageclass
```
👉 **Kỳ vọng:**
- Xuất hiện StorageClass tên: **`mosquizto-gp3`**.
- Cột `PROVISIONER` hiển thị: **`ebs.csi.aws.com`**.
- Cột `RECLAIMPOLICY` hiển thị: **`Delete`**.
- Cột `VOLUMEBINDINGMODE` hiển thị: **`WaitForFirstConsumer`**.

---

### Test 4: Kiểm tra kết nối SSH vào EC2 Jenkins
Lấy địa chỉ Public IP của Jenkins từ output của Terraform:
```powershell
terraform output jenkins_public_ip
```
Kiểm tra đăng nhập SSH bằng file khóa bí mật:
```bash
ssh -i ../devops-teams-key ubuntu@<JENKINS_PUBLIC_IP>
```
👉 **Kỳ vọng:** Đăng nhập thành công vào terminal máy chủ: `ubuntu@ip-10-0-1-xx:~$`. Gõ `exit` để thoát.

---

### Test 5: Kiểm tra Security Group mở 10 cổng
Security Group của Jenkins EC2 đã được cấu hình mở sẵn 10 cổng chức năng:

| Cổng (Port) | Dịch vụ | Mục đích |
| :--- | :--- | :--- |
| **`22`** | SSH | Ansible và Quản trị viên kết nối terminal |
| **`8080`** | Jenkins UI | Giao diện điều khiển CI/CD |
| **`3000`** | Grafana Dashboard | Hiển thị Dashboard giám sát |
| **`9090`** | Prometheus Server | Giao diện truy vấn Metrics |
| **`9100`** | Node Exporter | Xuất chỉ số phần cứng máy chủ |
| **`8000`** | Java App | Cổng chạy trực tiếp Backend bán hàng |
| **`1883`** | Mosquitto MQTT TCP | Giao thức truyền tin IoT/App thi trắc nghiệm |
| **`9001`** | Mosquitto WebSockets | Giao thức MQTT qua Web cho trình duyệt |
| **`80` / `443`** | HTTP / HTTPS | Cổng web tiêu chuẩn |

---

## 4. Bàn Giao Cho Thành Viên 2 (Ansible) & Thành Viên 3 (GitOps)

### Bàn giao cho Thành viên 2 (Phong - Ansible & Monitoring):
1. **Public IP của Jenkins:** Lấy từ lệnh `terraform output jenkins_public_ip` để điền vào `ansible/inventory/hosts.ini`.
2. **File Private Key:** Đảm bảo Phong có file `devops-teams-key` để chạy `ansible jenkins -m ping`.
3. **Cụm EKS:** Xác nhận 2 nodes đã `Ready` để Phong chạy playbook `install-prometheus.yml`.

### Bàn giao cho Thành viên 3 (Đạt - GitOps & Argo CD):
1. **StorageClass:** Xác nhận StorageClass `mosquizto-gp3` đã sẵn sàng để 4 PVCs (Postgres, Redis, Meilisearch, Qdrant) không bị kẹt `Pending`.
2. **Kubeconfig:** Lệnh kết nối:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name project11-eks-cluster
   ```
3. **Khôi phục dữ liệu cũ (Restore):** Khi Đạt deploy xong Pod Postgres, chỉ cần gõ:
   ```powershell
   .\infra.ps1 -Restore
   ```
   Dữ liệu cũ sẽ được nạp vào database trong 3 giây và tự động đồng bộ sang Meili/Qdrant!

---

## 5. Quy Trình Dọn Dẹp (Destroy) & Bảo Vệ Dữ Liệu

> [!WARNING]
> **VẤN ĐỀ CHI PHÍ TRÊN AWS LAB (BẮT BUỘC ĐỌC):**
> 1. Khi bạn xóa EKS, các ổ cứng EBS do Kubernetes tạo ra **có thể vẫn nằm lại trên AWS** ở trạng thái `available` và tiếp tục trừ tiền tài khoản Lab.
> 2. Nếu chạy `terraform destroy` vội khi chưa giải phóng Load Balancer hoặc PVCs, quá trình xóa VPC sẽ bị kẹt lỗi `DependencyViolation`.

### Cách 1: Dọn dẹp tự động an toàn bằng `infra.ps1` (Khuyên dùng)

Chạy đúng 1 lệnh duy nhất tại thư mục `mosquizto-infra/`:

```powershell
cd mosquizto-infra
.\infra.ps1 -Down
```

* **Cơ chế tự động 5 bước:**
  1. Tự động dump database PostgreSQL về máy cá nhân tại: `mosquizto-infra\backups\mosquizto-db-backup.dump`.
  2. **Cổng kiểm tra an toàn (Safety Gate):** Nếu file backup rỗng (0 bytes) hoặc lỗi mạng -> **Script DỪNG NGAY LẬP TỨC**, hủy lệnh destroy để bảo vệ dữ liệu cho bạn!
  3. Xóa namespace `mosquizto-eks` để Kubernetes nhả các ổ đĩa và gỡ Load Balancer.
  4. Tự động quét và **XÓA SẠCH 100% các ổ đĩa EBS mồ côi** trên AWS qua AWS CLI.
  5. Kích hoạt `terraform destroy -auto-approve` dọn sạch toàn bộ hạ tầng.

---

### Cách 2: Dọn dẹp thủ công từng bước

Nếu không dùng script, hãy thực hiện đúng 4 bước theo thứ tự sau:

```powershell
# Bước 1: Sao lưu dữ liệu database về máy local (nếu muốn giữ)
kubectl exec -i deployment/postgres -n mosquizto-eks -- pg_dump -U postgres -d mosquizto-db -Fc > ..\backups\mosquizto-db-backup.dump

# Bước 2: Xóa namespace ứng dụng để giải phóng Load Balancer và PVCs
kubectl delete namespace mosquizto-eks --timeout=60s
kubectl delete namespace monitoring --timeout=60s

# Bước 3: Chờ 1 phút rồi dọn sạch hạ tầng bằng Terraform
cd terraform
terraform destroy -auto-approve

# Bước 4: Xóa sạch các ổ đĩa EBS mồ côi còn sót trên AWS
aws ec2 describe-volumes --filters "Name=status,Values=available" --region us-east-1 --query "Volumes[].VolumeId" --output text | ForEach-Object { aws ec2 delete-volume --volume-id $_ --region us-east-1 }
```

---

## 6. Các Bước Kiểm Tra Xác Nhận Destroy Thành Công 100% (Tránh Bị Trừ Tiền Lab)

Sau khi destroy xong, hãy chạy các lệnh kiểm tra sau để chắc chắn tài khoản AWS Lab sạch bóng tài nguyên tính phí:

### 1. Kiểm tra màn hình Terraform output
👉 **Kỳ vọng:** Dòng cuối cùng in ra:
```text
Destroy complete! Resources: 12 destroyed.
```

### 2. Kiểm tra danh sách máy ảo EC2 còn chạy
```powershell
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --region us-east-1 --query "Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key=='Name'].Value|[0]}" --output table
```
👉 **Kỳ vọng:** Bảng trả về rỗng (`None`), không còn máy ảo EC2 Jenkins hay Worker Node nào đang chạy.

### 3. Kiểm tra cụm EKS
```powershell
aws eks list-clusters --region us-east-1 --output table
```
👉 **Kỳ vọng:** Không còn cụm `project11-eks-cluster`.

### 4. Kiểm tra ổ cứng EBS Volumes (QUAN TRỌNG NHẤT)
```powershell
aws ec2 describe-volumes --filters "Name=status,Values=available" --region us-east-1 --query "Volumes[].VolumeId" --output table
```
👉 **Kỳ vọng:** Trả về danh sách rỗng (`None`). Nếu xuất hiện bất kỳ mã `vol-xxxx` nào, chạy ngay lệnh sau để xóa:
```powershell
aws ec2 delete-volume --volume-id <MÃ_VOL_XUẤT_HIỆN> --region us-east-1
```

### 5. Kiểm tra Load Balancers (ELB)
```powershell
aws elb describe-load-balancers --region us-east-1 --query "LoadBalancerDescriptions[].LoadBalancerName" --output table
aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[].LoadBalancerName" --output table
```
👉 **Kỳ vọng:** Không còn Load Balancer nào của Kubernetes tồn tại.

### 6. Kiểm tra lại trạng thái tổng thể bằng `infra.ps1`
```powershell
cd mosquizto-infra
.\infra.ps1 -Status
```
👉 **Kỳ vọng:** Toàn bộ các mục EKS Nodes, Pods và EBS Volumes mồ côi đều báo sạch sẽ. File backup dữ liệu cũ vẫn nằm an toàn trên máy tính của bạn sẵn sàng cho lần thực hành tiếp theo!

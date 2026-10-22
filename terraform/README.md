# 🚀 Hướng Dẫn Vận Hành & Kiểm Thử Hạ Tầng (Dành Cho Thành Viên 2 - Ansible & Monitoring)

Tài liệu này hướng dẫn Thành viên 2 (Phong) tiếp nhận mã nguồn hạ tầng Terraform từ Thành viên 1 (Tuấn) để tự khởi tạo, kiểm tra máy chủ EC2 (Jenkins), cụm Kubernetes (EKS), và chuẩn bị môi trường chạy Ansible & Monitoring.

---

## 📌 1. Chuẩn Bị Trước Khi Chạy

### A. Nhận file Private Key từ Tuấn
- Nhận file private key `devops-teams-key` (file không có đuôi mở rộng, được gửi riêng qua Zalo/Telegram, **tuyệt đối không commit lên Git**).
- Đặt file `devops-teams-key` ở thư mục cha hoặc ngang hàng với thư mục `terraform/` (đúng đường dẫn trong cấu hình).
- *Lưu ý phân quyền (nếu dùng Linux/macOS/WSL):*
  ```bash
  chmod 400 devops-teams-key
  ```

### B. Cấu hình AWS Credentials (Từ phiên Lab của Phong)
1. Đăng nhập vào trang AWS Classroom Lab, bấm **Start Lab**.
2. Tại mục **AWS CLI**, bấm nút **Show**, copy toàn bộ nội dung gồm 3 dòng:
   - `aws_access_key_id`
   - `aws_secret_access_key`
   - `aws_session_token`
3. Mở file `~/.aws/credentials` (Windows: `C:\Users\<User>\.aws\credentials`), dán đè nội dung vừa copy vào rồi lưu lại.

### C. Tạo file biến cấu hình
Mở terminal tại thư mục `terraform/` và chạy:
```bash
# Windows PowerShell:
Copy-Item terraform.tfvars.example terraform.tfvars

# Linux / macOS / Git Bash:
cp terraform.tfvars.example terraform.tfvars
```
*(File `terraform.tfvars` đã được cấu hình sẵn cho tài khoản Lab với `USE-LAB-ROLE = true` và Region `us-east-1`).*

---

## 🛠️ 2. Khởi Tạo Hạ Tầng (Terraform)

Chạy các lệnh sau tại thư mục `terraform/`:

```bash
# 1. Khởi tạo plugin và module
terraform init

# 2. Kiểm tra cú pháp
terraform validate

# 3. Triển khai hạ tầng (Quá trình tạo EKS mất khoảng 10 - 12 phút)
terraform apply -auto-approve
```

Khi lệnh hoàn tất, màn hình sẽ in ra bảng **Outputs**. Hãy lưu lại 2 thông số quan trọng nhất:
- `jenkins_public_ip`: IP của máy chủ EC2 Jenkins.
- `eks_kubeconfig_command`: Lệnh kết nối đến cụm EKS.

---

## 🔍 3. Kiểm Thử Hạ Tầng & Cài Đặt kubectl

### A. Cài đặt `kubectl` (Nếu máy chưa có)

* **Cách 1: Tải nhanh file `kubectl.exe` chạy trực tiếp (Windows - Khuyên dùng):**
  ```powershell
  curl.exe -LO "https://dl.k8s.io/release/v1.30.0/bin/windows/amd64/kubectl.exe"
  ```
  *(Dùng lệnh `.\kubectl.exe` để thao tác).*

* **Cách 2: Cài đặt chính thức qua Winget (Windows):**
  ```powershell
  winget install -e --id Kubernetes.kubectl
  ```

* **Cách 3: Cài đặt trên Linux / Ubuntu:**
  ```bash
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  ```

---

### B. Kiểm tra cụm EKS
1. Đồng bộ cấu hình cụm về máy:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name project11-eks-cluster
   ```
2. Kiểm tra trạng thái các Worker Node:
   ```bash
   kubectl get nodes -o wide
   ```
   👉 **Kỳ vọng:** Xuất hiện **2 nodes** với trạng thái `STATUS` là **`Ready`**.
3. Kiểm tra các pods hệ thống:
   ```bash
   kubectl get pods -A
   ```
   👉 **Kỳ vọng:** Toàn bộ pods trong namespace `kube-system` đều ở trạng thái `Running`.

---

### C. Kiểm tra kết nối SSH vào EC2 Jenkins
Kiểm tra xem máy chủ EC2 đã mở cửa và sẵn sàng cho Ansible chưa:

```bash
ssh -i ../devops-teams-key ubuntu@<JENKINS_PUBLIC_IP>
```
👉 **Kỳ vọng:** Đăng nhập thành công vào giao diện dòng lệnh `ubuntu@ip-10-0-1-...:~$`. Gõ `exit` để thoát.

---

## 📋 4. Bàn Giao Cấu Hình Cho Ansible & Monitoring

### A. Mẫu file `inventory.ini` cho Ansible
Thành viên 2 tạo file `inventory.ini` trong repo `infra` hoặc thư mục làm việc của Ansible:

```ini
[jenkins]
<JENKINS_PUBLIC_IP> ansible_user=ubuntu ansible_ssh_private_key_file=./devops-teams-key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

Kiểm tra kết nối Ansible:
```bash
ansible jenkins -m ping -i inventory.ini
```

---

### B. Bảng Port Security Group Đã Mở Sẵn Trên EC2
Security Group (`sg-xxxx`) đã mở sẵn 10 cổng phục vụ toàn bộ dịch vụ của đồ án:

| Cổng (Port) | Dịch vụ tương ứng | Mục đích sử dụng |
| :--- | :--- | :--- |
| **`22`** | SSH | Ansible và Thành viên kết nối điều khiển |
| **`8080`** | Jenkins UI | Giao diện quản lý CI/CD Pipeline |
| **`3000`** | Grafana Dashboard | Hiển thị Dashboard giám sát hệ thống |
| **`9090`** | Prometheus Server | Thu thập và truy vấn Metrics |
| **`9100`** | Node Exporter | Thu thập chỉ số tài nguyên máy chủ EC2 |
| **`8000`** | Java App | Cổng chạy trực tiếp Backend bán hàng |
| **`1883`** | Mosquitto MQTT | Giao thức truyền nhận thông điệp qua TCP |
| **`9001`** | Mosquitto WebSockets | Giao thức truyền nhận MQTT qua Web |
| **`80` / `443`** | HTTP / HTTPS | Truy cập Web thông thường qua tên miền |

---

## 🧹 5. Dọn Dẹp Tài Nguyên Sau Khi Thực Hành (RẤT QUAN TRỌNG)

Khi kết thúc buổi làm việc hoặc trước khi hết phiên Lab, **bắt buộc** phải hủy toàn bộ tài nguyên để tránh bị khóa bài Lab hoặc trừ hết ngân sách:

```bash
terraform destroy -auto-approve
```

👉 **Kỳ vọng:** Màn hình in ra `Destroy complete! Resources: 12 destroyed.`
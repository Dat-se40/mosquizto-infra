# Triển khai Jenkins EC2 và Prometheus/Grafana bằng Ansible

Hướng dẫn chạy trên **Ubuntu Linux hoặc Ubuntu trong WSL**, dùng Bash. Jenkins được cài trên EC2; Prometheus/Grafana được triển khai lên EKS bằng Helm thông qua Ansible.

## 1. Cấu trúc dự án

```text
mosquizto-infra/
├── terraform/
└── ansible/
    ├── ansible.cfg
    ├── .gitignore
    ├── inventory/
    │   ├── hosts.ini
    │   └── group_vars/
    │       ├── jenkins.yml
    │       └── monitoring.yml
    ├── playbooks/
    │   ├── install-jenkin.yml
    │   └── install-prometheus.yml
    └── roles/
        ├── jenkins/
        └── prometheus/
            ├── defaults/
            ├── tasks/
            └── templates/
                └── monitoring.yml.j2
```

Terraform tạo hạ tầng trước. Các bước sau giả định EC2 Jenkins và EKS đã tồn tại. Không cần chạy lại Terraform để cài phần mềm bằng Ansible.

## 2. Cài package trên máy Linux chạy Ansible

Các lệnh bên dưới chạy trong **Bash trên Ubuntu Linux/WSL**.

### 2.1. Package nền và Ansible

```bash
sudo apt update
sudo apt install -y curl unzip ca-certificates openssh-client python3 ansible python3-kubernetes python3-yaml
```

Đứng trong thư mục `ansible/` chứa `requirements.yml`, cài các collection:

```bash
ansible-galaxy collection install -r requirements.yml
```

Kiểm tra:

```bash
ansible --version
ansible-galaxy collection list
/usr/bin/python3 -c "import kubernetes, yaml; print('Python dependencies: OK')"
```

### 2.2. AWS CLI v2

Chọn kiến trúc và cài AWS CLI v2:

```bash
case "$(uname -m)" in x86_64) AWS_ARCH=x86_64 ;; aarch64|arm64) AWS_ARCH=aarch64 ;; *) echo 'Kiến trúc chưa được hỗ trợ'; return 1 2>/dev/null || exit 1 ;; esac
AWS_INSTALL_DIR=$(mktemp -d)
curl -fL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "$AWS_INSTALL_DIR/awscliv2.zip"
unzip -q "$AWS_INSTALL_DIR/awscliv2.zip" -d "$AWS_INSTALL_DIR"
sudo "$AWS_INSTALL_DIR/aws/install" --update
aws --version
```

Cấu hình tài khoản AWS:

```bash
aws configure
```

Nhập:

- AWS Access Key ID.
- AWS Secret Access Key.
- Default region name: `us-east-1`.
- Default output format: `json`.

Nếu dùng AWS Academy/Learner Lab, cấu hình thêm session token của phiên lab hiện tại:

```bash
read -r -s -p 'AWS session token: ' LAB_SESSION_TOKEN; echo
aws configure set aws_session_token "$LAB_SESSION_TOKEN"
unset LAB_SESSION_TOKEN
```

Kiểm tra xác thực:

```bash
aws sts get-caller-identity
```

Credential phải được cấu hình trong **Linux/WSL đang chạy Ansible**. Credential trên Windows không tự áp dụng cho WSL.

Nếu máy điều khiển là EC2 đã gắn IAM role có đủ quyền, không cần nhập access key thủ công.

### 2.3. Cài kubectl và kết nối EKS

Các lệnh dưới dành cho Linux **x86_64/amd64**, sau khi đã cài AWS CLI và cấu hình credential.

Cài kubectl theo phiên bản EKS đã khai báo trong `roles/prometheus/defaults/main.yml` (`us-east-1`, `project11-eks-cluster`):

```bash
EKS_VERSION=$(aws eks describe-cluster --region us-east-1 --name project11-eks-cluster --query 'cluster.version' --output text)
KUBECTL_VERSION=$(curl -fsSL "https://dl.k8s.io/release/stable-${EKS_VERSION}.txt")
curl -fLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

Kết nối và kiểm tra cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name project11-eks-cluster
kubectl get nodes -o wide
```

Nếu đổi region hoặc tên cluster trong file cấu hình, sửa tương ứng trong các lệnh trên. IAM principal đang dùng phải có quyền truy cập EKS.

### 2.4. Helm

Cài Helm 3:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o get-helm-3.sh
bash get-helm-3.sh
helm version
```

## 3. Cấu hình inventory cho EC2 Jenkins

Các lệnh dưới chạy trong thư mục `ansible/`.

Cấp quyền cho file PEM hiện có, ví dụ:

```bash
chmod 400 /home/ubuntu/jenkins-key.pem
```

Trong `inventory/hosts.ini`, sửa `ansible_host` thành Public IP của EC2 Jenkins và `ansible_ssh_private_key_file` thành đường dẫn file PEM:

```ini
[jenkins]
jenkins-server ansible_host=PUBLIC_IP_EC2_JENKINS ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/jenkins-key.pem
```

Giữ nguyên các group khác trong inventory.

Kiểm tra kết nối:

```bash
ansible jenkins -i inventory/hosts.ini -m ping
```

Kết quả mong đợi: `"ping": "pong"`.

## 4. Chạy playbook cài Jenkins EC2

```bash
ansible-playbook -i inventory/hosts.ini playbooks/install-jenkin.yml
```

Kiểm tra dịch vụ Jenkins:

```bash
ansible jenkins -i inventory/hosts.ini -b -m command -a 'systemctl is-active jenkins'
```

Kết quả mong đợi: `active`.

### Truy cập Jenkins

Trong Security Group của EC2 Jenkins, cho phép inbound **TCP 8080** từ IP public của máy truy cập. Sau đó mở trình duyệt:

```text
http://PUBLIC_IP_EC2_JENKINS:8080
```

Nếu Jenkins hiện màn hình Unlock Jenkins, lấy mật khẩu khởi tạo:

```bash
ansible jenkins -i inventory/hosts.ini -b -m command -a 'cat /var/lib/jenkins/secrets/initialAdminPassword'
```

Dùng chuỗi mật khẩu ở kết quả lệnh để mở khóa, cài plugin và tạo tài khoản quản trị theo giao diện. Nếu dự án đã tự cấu hình tài khoản bằng Ansible/JCasC, dùng tài khoản được cấu hình; có thể không xuất hiện màn hình mở khóa.

## 5. Chạy playbook cài Prometheus/Grafana lên EKS

### 5.1. Kết nối EKS

Chạy trên máy Linux điều khiển, cùng user sẽ chạy Ansible:

### 5.2. Chạy playbook

```bash
ansible-playbook -i inventory/hosts.ini playbooks/install-prometheus.yml --syntax-check
ansible-playbook -i inventory/hosts.ini playbooks/install-prometheus.yml
```

Kiểm tra kết quả:

```bash
helm list -n monitoring
kubectl get pods -n monitoring -o wide
kubectl get svc -n monitoring
```

Pod cần ở trạng thái `Running`, cột `READY` đầy đủ. Các tên Service bên dưới tương ứng release `prometheus` đã triển khai trong dự án.

## 6. Truy cập Prometheus và Grafana qua AWS Load Balancer

Đã cấu hình `service.type: LoadBalancer` cho Grafana và Prometheus trong template. Sau khi chạy playbook, kiểm tra địa chỉ:

```bash
kubectl get svc -n monitoring -w
```

Đợi `EXTERNAL-IP` của hai Service chuyển từ `<pending>` thành hostname AWS, rồi nhấn **Ctrl+C**.

### 6.1. Lấy URL truy cập

```bash
kubectl get svc prometheus-grafana -n monitoring -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}{"\n"}'
kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}:9090{"\n"}'
```

Mở URL tương ứng trên trình duyệt:

| Dịch vụ | URL |
|---|---|
| Grafana | `http://HOSTNAME_LB_GRAFANA` |
| Prometheus | `http://HOSTNAME_LB_PROMETHEUS:9090` |

Dùng `http://`, không dùng `https://` vì chưa cấu hình TLS.

### 6.2. Đăng nhập Grafana

Đăng nhập Grafana với tên tài khoản **admin** và mật khẩu khi nhập ở bước chạy playbook, vào **Dashboards**, tìm `Kubernetes / Compute Resources / Cluster` để xem CPU/RAM. Chọn dashboard namespace hoặc pod để xem chi tiết.

### 6.3. Kiểm tra Prometheus

Mở URL Prometheus, vào **Status → Targets** để kiểm tra trạng thái các target.

Chạy truy vấn:

```promql
up
```

Giá trị `1` là scrape thành công, `0` là thất bại.

Xem CPU worker đang sử dụng (% trung bình trong 5 phút):

```promql
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

### 6.4. Nếu không truy cập được

Chờ Load Balancer hoàn tất khởi tạo và health check, sau đó kiểm tra:

```bash
kubectl get pods -n monitoring
kubectl describe svc prometheus-grafana -n monitoring
kubectl describe svc prometheus-kube-prometheus-prometheus -n monitoring
```

Trong AWS, kiểm tra Load Balancer có scheme `internet-facing`, target healthy và security group cho phép truy cập đúng port.

## Tài liệu cài đặt chính thức

- [AWS CLI v2 trên Linux](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [kubectl trên Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
- [Helm 3](https://helm.sh/docs/v3/intro/install/)

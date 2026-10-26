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

Nội dung `requirements.yml`:

```yaml
---
collections:
  - name: ansible.posix
  - name: kubernetes.core
```

Trong `inventory/hosts.ini`, thêm:

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

Nếu đã khai báo `ansible_python_interpreter` ở host hoặc group khác, sửa về `/usr/bin/python3` hoặc bỏ khai báo đó để tránh ghi đè.

Nếu đang ở trong virtual environment, thoát bằng:

```bash
deactivate
```

Bỏ biến interpreter đã export trước đó, nếu có:

```bash
unset ANSIBLE_PYTHON_INTERPRETER
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

### 2.3. kubectl

Chọn region và nhập tên cluster:

```bash
export AWS_DEFAULT_REGION=us-east-1
read -r -p 'Tên EKS cluster: ' EKS_CLUSTER_NAME
aws eks describe-cluster --region "$AWS_DEFAULT_REGION" --name "$EKS_CLUSTER_NAME" --query 'cluster.version' --output text
```

Chỉ tiếp tục khi lệnh trên trả về phiên bản EKS thành công.

Cài kubectl cùng minor version với cluster và kiểm tra checksum:

```bash
case "$(uname -m)" in x86_64) KUBECTL_ARCH=amd64 ;; aarch64|arm64) KUBECTL_ARCH=arm64 ;; *) echo 'Kiến trúc chưa được hỗ trợ'; return 1 2>/dev/null || exit 1 ;; esac
EKS_VERSION=$(aws eks describe-cluster --region "$AWS_DEFAULT_REGION" --name "$EKS_CLUSTER_NAME" --query 'cluster.version' --output text)
KUBECTL_VERSION=$(curl -fsSL "https://dl.k8s.io/release/stable-${EKS_VERSION}.txt")
KUBECTL_INSTALL_DIR=$(mktemp -d)
curl -fL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl" -o "$KUBECTL_INSTALL_DIR/kubectl"
curl -fL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl.sha256" -o "$KUBECTL_INSTALL_DIR/kubectl.sha256"
(cd "$KUBECTL_INSTALL_DIR" && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check) && sudo install -m 0755 "$KUBECTL_INSTALL_DIR/kubectl" /usr/local/bin/kubectl
kubectl version --client
```

Checksum phải báo `kubectl: OK`.

Cập nhật kubeconfig và kiểm tra kết nối:

```bash
aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name "$EKS_CLUSTER_NAME"
kubectl get nodes -o wide
```

IAM principal đang sử dụng phải được cấp quyền truy cập cluster. Lệnh `update-kubeconfig` không tự cấp quyền.

### 2.4. Helm

Cài Helm 3:

```bash
HELM_INSTALL_DIR=$(mktemp -d)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "$HELM_INSTALL_DIR/get-helm-3"
bash "$HELM_INSTALL_DIR/get-helm-3"
helm version
```

## 3. Cấu hình inventory cho EC2 Jenkins và khóa PEM

### 3.1. Vào thư mục Ansible

Nếu đang đứng trong `mosquizto-infra/tf/`:

```bash
cd ../ansible
```

Nếu đang dùng WSL theo đường dẫn hiện tại của dự án:

```bash
cd /mnt/d/UIT/NT548/mosquizto-infra/ansible
```

`../ansible/inventory/hosts.ini` khi đứng trong `tf/` chính là `inventory/hosts.ini` khi đã đứng trong `ansible/`.

### 3.2. Chép khóa vào filesystem Linux và chmod

Thay đường dẫn nguồn dưới đây bằng vị trí file PEM thực tế của bạn:

```bash
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
cp /mnt/d/duong-dan/jenkins-key.pem "$HOME/.ssh/jenkins-key.pem"
chmod 400 "$HOME/.ssh/jenkins-key.pem"
ls -l "$HOME/.ssh/jenkins-key.pem"
realpath "$HOME/.ssh/jenkins-key.pem"
```

Quyền mong đợi là `-r--------`. Trên WSL, dùng bản key trong thư mục Linux `$HOME/.ssh`, tránh lỗi quyền SSH với key đặt trực tiếp dưới `/mnt/d`.

### 3.3. Sửa hosts.ini

Mở file:

```bash
nano inventory/hosts.ini
```

Cập nhật block Jenkins, giữ lại các group khác đang có:

```ini
[jenkins]
jenkins-server ansible_host=PUBLIC_IP_EC2_JENKINS ansible_user=ubuntu ansible_ssh_private_key_file=/DUONG_DAN_TUYET_DOI/.ssh/jenkins-key.pem

[jenkins:vars]
ansible_python_interpreter=/usr/bin/python3
```

Thay `PUBLIC_IP_EC2_JENKINS` bằng Public IPv4 hiện tại của EC2. Thay đường dẫn key bằng kết quả `realpath` ở trên. Ví dụ, nếu chạy bằng root trong WSL thì thường là `/root/.ssh/jenkins-key.pem`; nếu chạy bằng user khác, dùng home của user đó.

`ansible_user=ubuntu` áp dụng cho EC2 Ubuntu. Nếu EC2 dùng AMI khác, đặt đúng SSH user của AMI đó.

Monitoring chạy trên máy Linux điều khiển, không SSH vào worker EKS. Nếu playbook dùng group `control`, inventory cần có:

```ini
[control]
localhost ansible_connection=local
```

Nếu playbook dùng group `monitoring` thay vì `control`, giữ đúng tên group đó. Kiểm tra trường `hosts:` trong `playbooks/install-prometheus.yml`; file `inventory/group_vars/monitoring.yml` tự áp dụng cho group `monitoring`, không tự áp dụng cho group `control` nếu không có quan hệ group hoặc nạp vars riêng.

### 3.4. Kiểm tra cấu hình và SSH

Đứng trong `ansible/`, sử dụng cấu hình của dự án và inventory đã sửa:

```bash
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
export ANSIBLE_ROLES_PATH="$PWD/roles"
export ANSIBLE_PYTHON_INTERPRETER="$(command -v python)"
ansible --version
ansible-inventory -i inventory/hosts.ini --graph
```

Các biến export trên chỉ áp dụng trong terminal hiện tại, không chỉnh `.bashrc`. Đặt `ANSIBLE_CONFIG` tường minh cũng tránh việc Ansible bỏ qua tự nạp cấu hình ở thư mục WSL có quyền world-writable.

Kiểm tra SSH bằng đúng IP và key đã cấu hình:

```bash
ssh -i "$HOME/.ssh/jenkins-key.pem" ubuntu@PUBLIC_IP_EC2_JENKINS
```

Xác minh host fingerprint khi kết nối lần đầu; sau khi vào được EC2, chạy `exit` để quay về máy điều khiển. Security Group EC2 phải cho phép SSH TCP `22` từ IP public của máy đang chạy Ansible.

```bash
ansible jenkins -i inventory/hosts.ini -m ping
```

Kết quả mong đợi: `jenkins-server | SUCCESS` và `"ping": "pong"`.

## 4. Chạy playbook cài Jenkins EC2

Tất cả lệnh Ansible sau chạy từ thư mục `ansible/`, trong virtual environment đã kích hoạt:

```bash
ansible-playbook -i inventory/hosts.ini playbooks/install-jenkin.yml --syntax-check
ansible-playbook -i inventory/hosts.ini playbooks/install-jenkin.yml
```

Nếu playbook cần sudo và user SSH yêu cầu mật khẩu sudo, thêm `--ask-become-pass`. EC2 Ubuntu thông thường cho user `ubuntu` sudo không cần mật khẩu.

Kiểm tra dịch vụ sau khi playbook hoàn tất:

```bash
ansible jenkins -i inventory/hosts.ini -b -m command -a 'systemctl is-active jenkins'
```

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

```bash
aws sts get-caller-identity
aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name "$EKS_CLUSTER_NAME"
kubectl config current-context
kubectl get nodes -o wide
```

Nếu mở terminal mới, khai báo lại `AWS_DEFAULT_REGION`, `EKS_CLUSTER_NAME`, kích hoạt virtual environment và các biến Ansible ở mục 3.4. IAM principal cần được cấp quyền truy cập EKS; `update-kubeconfig` không tự cấp quyền. Máy điều khiển cũng phải có đường mạng tới API endpoint EKS.

Kiểm tra region, tên cluster và biến monitoring trong `inventory/group_vars/monitoring.yml` trước khi chạy. Đảm bảo tên template được task tham chiếu khớp với `roles/prometheus/templates/monitoring.yml.j2`.

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

### 6.1. Chuyển Service sang LoadBalancer

```bash
kubectl patch svc prometheus-grafana -n monitoring -p '{"spec":{"type":"LoadBalancer"}}'
kubectl patch svc prometheus-kube-prometheus-prometheus -n monitoring -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc -n monitoring -w
```

Đợi `EXTERNAL-IP` của hai Service chuyển từ `<pending>` thành hostname `...us-east-1.elb.amazonaws.com`, rồi nhấn **Ctrl+C**. Trên AWS, đây thường là hostname Load Balancer, không phải IP public EC2 Jenkins.

### 6.2. Lấy URL truy cập

```bash
kubectl get svc prometheus-grafana -n monitoring -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}{"\n"}'
kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}:9090{"\n"}'
```

| Dịch vụ | URL |
|---|---|
| Grafana | `http://HOSTNAME_LB_GRAFANA` |
| Prometheus | `http://HOSTNAME_LB_PROMETHEUS:9090` |

Nhấn **Ctrl+L** trong trình duyệt rồi dán đầy đủ URL. Dùng `http://`; cấu hình này chưa thiết lập HTTPS. Không dùng NodePort xuất hiện sau dấu `:` trong cột `PORT(S)` để truy cập hostname LB.

### 6.3. Đăng nhập và kiểm tra Grafana

Lấy user và mật khẩu:

```bash
kubectl get secret prometheus-grafana -n monitoring -o jsonpath='{.data.admin-user}' | base64 --decode; echo
kubectl get secret prometheus-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 --decode; echo
```

Mở URL Grafana và đăng nhập bằng thông tin trên. Nếu dùng Secret tùy chỉnh hoặc đã đổi mật khẩu trong UI, dùng thông tin tương ứng.

Trong **Dashboards**, tìm `Kubernetes / Compute Resources / Cluster` hoặc dashboard tương tự, chọn datasource Prometheus, khoảng thời gian `Last 15 minutes` để kiểm tra CPU/RAM. Có thể chọn dashboard namespace/pod để xem chi tiết.

### 6.4. Kiểm tra Prometheus

Mở URL Prometheus, vào **Status → Targets** để xem target đang `UP` hay `DOWN`. Chạy truy vấn:

```promql
up
```

Giá trị `1` nghĩa là lần scrape gần nhất thành công, `0` là thất bại. Muốn kiểm tra CPU worker (% trung bình trong 5 phút):

```promql
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

Prometheus mặc định chưa có đăng nhập trong cấu hình này. Load Balancer công khai có thể cho người ngoài truy cập metrics và phát sinh phí AWS; giới hạn nguồn truy cập theo nhu cầu sử dụng.

### 6.5. Giữ cấu hình LoadBalancer khi chạy lại playbook

Hai lệnh patch chỉ thay đổi Service đang chạy. Để Helm/Ansible tiếp tục quản lý cấu hình này, hợp nhất vào `roles/prometheus/templates/monitoring.yml.j2`:

```yaml
grafana:
  service:
    type: LoadBalancer

prometheus:
  service:
    type: LoadBalancer
```

Nếu đã có các block `grafana:` hoặc `prometheus:`, thêm/sửa `service.type` bên trong; không tạo khóa YAML trùng và không ghi đè các thiết lập hiện có. Sau đó chạy lại:

```bash
ansible-playbook -i inventory/hosts.ini playbooks/install-prometheus.yml
```

Nếu có hostname nhưng chưa vào được, chờ LB hoàn tất health check rồi kiểm tra:

```bash
kubectl describe svc prometheus-grafana -n monitoring
kubectl describe svc prometheus-kube-prometheus-prometheus -n monitoring
kubectl get endpointslices -n monitoring
```

Kiểm tra thêm scheme internet-facing, listener, target health và security group của LB trong AWS. Không mở port Grafana/Prometheus trên EC2 Jenkins: hai dịch vụ này chạy trong EKS và được truy cập qua LB của chúng.

## Tài liệu cài đặt chính thức

- [AWS CLI v2 trên Linux](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [kubectl trên Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
- [Helm 3](https://helm.sh/docs/v3/intro/install/)

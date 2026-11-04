# Lưu trữ EBS cho Mosquizto trên EKS lab

Phối hợp người quản lý cluster/add-on trước khi cài. Không cài chồng một bản EBS CSI khác. `Install-Storage.ps1` từ chối nếu cluster đã có EBS CSI managed add-on. Script render Helm chart chính thức phiên bản 2.67.1, driver 1.67.1; áp dụng bản vá network được lưu trong repo, kiểm tra phía server rồi cài bằng kubectl. Đây không phải bản cài do Helm quản lý. Dùng lại script để cập nhật cấu hình.

Lab dùng `LabRole` sẵn có của worker qua IMDSv2. Metadata của node có hop limit bằng 1, nên controller và CSI node Pod dùng host network. Controller dùng cổng health 9811 để tránh trùng cổng 9808 của node plugin. Không lưu AWS access key hoặc ECR token tĩnh trong Kubernetes. Nếu Lab từ chối thao tác EBS, cần quản trị Lab cấp quyền phù hợp; thêm IAM policy không vượt được SCP. Khi triển khai production, thay cách dùng chung role node bằng danh tính IAM riêng cho workload.

Chạy các lệnh sau từ thư mục gốc `mosquizto-infra`, sau khi cấu hình AWS credentials và kubeconfig:

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

Pod thứ hai phải đọc được `mosquizto-storage-ok` từ cùng PVC đã Bound. Trước khi xóa namespace kiểm thử, ghi lại tên PV và ID EBS volume của bài test. Chính sách `Retain` giữ lại volume sau khi PVC bị xóa. Sau kiểm thử, chỉ dọn PV/volume tạm có ID đã đối chiếu, giữ nguyên dữ liệu ứng dụng.

StorageClass `mosquizto-gp3` chọn rõ gp3 được mã hóa, ext4, `WaitForFirstConsumer`, cho mở rộng dung lượng và `Retain`. Class này không được đặt làm mặc định của cluster; các PVC ứng dụng tham chiếu trực tiếp bằng tên. Bài kiểm thử và ứng dụng tạo EBS volume có tính phí trong phạm vi lab đã được duyệt; chúng chưa cung cấp chức năng backup.

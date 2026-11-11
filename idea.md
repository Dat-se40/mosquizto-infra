# 💡 Ý Tưởng & Giải Pháp Nâng Cấp Hạ Tầng (MosQuizTo Infra)

Tài liệu tóm tắt ngắn gọn giải pháp nâng cấp tự động hóa vòng đời hạ tầng, tối ưu chi phí và bảo toàn dữ liệu cho đồ án.

---

## 1. Vấn Đề Thực Tế Trước Khi Nâng Cấp

1. **Thao tác rời rạc:** Phải chạy nhiều lệnh thủ công riêng biệt giữa Terraform, Kubernetes Storage và GitOps.
2. **Nguy cơ mất tiền AWS Lab:** Khi chạy `terraform destroy`, các ổ cứng EBS và Load Balancers do Kubernetes tạo ra **không bị xóa theo**, âm thầm tồn tại ở trạng thái mồ côi (`available`) và tiếp tục trừ tiền tài khoản học tập (gây mất ~$22.80/tháng).
3. **Mất dữ liệu mỗi phiên Lab:** Mỗi lần dựng lại EKS phải chạy seed lại dữ liệu ban đầu, mất toàn bộ câu hỏi trắc nghiệm và tài khoản người dùng đã tạo trong các phiên trước.
4. **Rủi ro xóa nhầm máy chủ:** Terraform lấy động AMI Ubuntu mới nhất (`most_recent = true`), khi Canonical cập nhật bản vá thì `terraform apply` sẽ tự xóa và tạo lại máy chủ Jenkins, làm mất toàn bộ cấu hình CI/CD.

---

## 2. Giải Pháp Nâng Cấp Hợp Nhất (`infra.ps1`)

Đóng gói toàn bộ quy trình vào **1 tệp điều khiển duy nhất** tại `mosquizto-infra/infra.ps1`:

### A. Triển khai thông minh không treo máy (`.\infra.ps1 -Up`)
* Tự động chạy `terraform apply -auto-approve`.
* Tự động cấu hình Kubeconfig và cài đặt **AWS EBS CSI Driver + StorageClass `mosquizto-gp3`**.
* **Giải phóng ngay terminal** để người dùng thoải mái làm việc tiếp (không bị kẹt màn hình chờ đợi). Có thêm tùy chọn `.\infra.ps1 -Up -Watch` nếu muốn máy tự động chờ nạp data.

### B. Khôi phục dữ liệu 1 chạm (`.\infra.ps1 -Restore`)
* Khi PostgreSQL online, chỉ cần gõ lệnh để nạp toàn bộ dữ liệu cũ từ máy cá nhân (`backups/`) vào database trong **3 giây**.
* Tự động kích hoạt đồng bộ dữ liệu sang Meilisearch và Qdrant (`Start-Sync.ps1`). Không cần seed lại từ đầu.

### C. Dọn dẹp an toàn & Triệt tiêu chi phí ngầm (`.\infra.ps1 -Down`)
* **Cổng an toàn (Safety Gate):** Tự động dump database về máy cá nhân -> Kiểm tra file hợp lệ (> 0 bytes) thành công thì mới cho phép xóa hạ tầng (chống mất dữ liệu).
* **Quét dọn sạch 100% chi phí:** Tự động gọi AWS CLI tìm và xóa sạch các ổ cứng EBS mồ côi trên AWS trước khi destroy.
* Chạy `terraform destroy -auto-approve`. Đảm bảo tài khoản Lab không bị trừ 1 xu phí ngầm.

### D. Bảo vệ máy chủ Jenkins trong Terraform
* Bổ sung `lifecycle { ignore_changes = [ami] }` vào `modules/aws-ec2/main.tf` để máy chủ Jenkins không bao giờ bị xóa ngoài ý muốn.

---

## 3. Giá Trị Mang Lại Cho Đồ Án
* **Tự động hóa chuẩn DevOps:** Chuyển đổi từ vận hành thủ công sang tự động hóa toàn diện từ A -> Z.
* **Bảo vệ ngân sách:** Giải quyết triệt để vấn đề trừ tiền oan trên AWS Academy.
* **Chứng minh năng lực Disaster Recovery:** Dữ liệu có khả năng sao lưu, sống sót và phục hồi nguyên vẹn dù cụm Kubernetes bị xóa sổ hoàn toàn.


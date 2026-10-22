terraform {
  # Ghi chú: Trong Project 11 gốc sử dụng S3 backend ("my-ews-baket1").
  # Đã lược bỏ hardcode S3 bucket của tác giả để sử dụng local state khi chạy nhóm.
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}